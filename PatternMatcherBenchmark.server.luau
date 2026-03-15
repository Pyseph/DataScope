--!strict
--[[
	PatternMatcher Benchmark — PM vs native string.find
	500K iters short strings, 100K iters long strings.
]]

local PatternMatcher = require(game:GetService("ReplicatedStorage").PatternMatcher)

local function bench(label: string, fn: () -> (), iterations: number): number
	for _ = 1, math.min(iterations // 10, 3_000) do fn() end
	local t0 = os.clock()
	for _ = 1, iterations do fn() end
	local elapsed = os.clock() - t0
	print(string.format("  %-42s  %7.3f s   %6.2f M/s", label, elapsed, (iterations / elapsed) / 1e6))
	return elapsed
end

local function section(title: string)
	print("\n" .. string.rep("─", 76) .. "\n  " .. title .. "\n" .. string.rep("─", 76))
end

-- ── Pools ────────────────────────────────────────────────────────────────────

local N = 500_000
local POOL_SIZE = 10_000
local pool: { string } = table.create(POOL_SIZE)

local templates = {
	"player_%d", "userId_%d", "score_%d_points", "level%d",
	"item_sword_%d", "quest_complete_%d", "achievement_%d_unlocked",
	"zone_forest_%d", "npc_merchant_%d", "session_%d_data",
	"coins=%d", "xp=%d", "health=100", "mana=%d", "stamina=%d",
	"inventory_slot_%d", "weapon_damage_%d", "armor_defense_%d",
	"magic_power_%d", "speed_boost_%d", "UID_ABCDEF%d",
	"FLAG_TRUE", "FLAG_FALSE", "value_3.14159",
	"base64_SGVsbG8gV29ybGQ=", "hex_0xFF%d", "timestamp_1700000%d",
	"ratio_0.%d", "empty_", "CamelCaseKey%d",
}
do
	local ti = 1
	for i = 1, POOL_SIZE do
		pool[i] = string.format(templates[ti], i)
		ti = ti % #templates + 1
	end
end

local LONG_N = 100_000
local LONG_POOL_SIZE = 5_000
local longPool: { string } = table.create(LONG_POOL_SIZE)
do
	local ti = 1
	for i = 1, LONG_POOL_SIZE do
		local parts = {}
		for j = 1, 4 + (i % 3) do
			parts[j] = string.format(templates[ti], i * 100 + j)
			ti = ti % #templates + 1
		end
		longPool[i] = table.concat(parts, "/")
	end
end

-- ── Cases ────────────────────────────────────────────────────────────────────

type Case = { pattern: string, desc: string }

local cases: { Case } = {
	-- Literals
	{ pattern = "player",      desc = "plain literal (short)" },
	{ pattern = "achievement", desc = "plain literal (long)" },
	-- Anchors
	{ pattern = "^player",     desc = "^ anchor + literal" },
	{ pattern = "data$",       desc = "literal + $ anchor" },
	-- Classes
	{ pattern = "%d+",         desc = "%d+" },
	{ pattern = "%a+",         desc = "%a+" },
	{ pattern = "_%d+$",       desc = "_ then %d+ then $" },
	{ pattern = "%u%u%u",      desc = "3 uppercase" },
	{ pattern = "%x+",         desc = "hex digits" },
	-- Greedy
	{ pattern = "player_%d+",  desc = "literal + %d+ (greedy)" },
	{ pattern = "%a+_%d+",     desc = "%a+ _ %d+ (greedy)" },
	{ pattern = "score_%d+_",  desc = "literal %d+ literal" },
	{ pattern = "%w+=%d+",     desc = "%w+ = %d+" },
	-- Lazy
	{ pattern = "_%d-_",       desc = "_%d-_ (lazy)" },
	{ pattern = "%a-%d",       desc = "%a-%d (lazy class)" },
	-- Charsets
	{ pattern = "[0-9]+",      desc = "[0-9]+ charset range" },
	{ pattern = "[a-z_]+",     desc = "[a-z_]+ charset" },
	{ pattern = "[aeiou]",     desc = "[aeiou] vowel charset" },
	{ pattern = "[^_]+",       desc = "[^_]+ negated charset" },
	{ pattern = "[0-9a-f]+",   desc = "[0-9a-f]+ hex charset" },
	-- Mixed
	{ pattern = "^%a+_%d+$",   desc = "^%a+_%d+$ full-string" },
	{ pattern = "%u%l+%u%l+",  desc = "CamelCase detector" },
	{ pattern = "%d+%.%d+",    desc = "float number" },
	{ pattern = "0x%x+",       desc = "hex literal 0x…" },
	{ pattern = "=%d+$",       desc = "=digits at end" },
	-- No-match
	{ pattern = "^never_gonna_match_this_pattern$", desc = "no-match long anchor" },
	{ pattern = "zzz",         desc = "no-match plain literal" },
	{ pattern = "%d%d%d%d%d%d%d%d", desc = "no-match 8 digits" },
	-- Multi-quantifier backtracking
	{ pattern = "%a+_%a+_%d+",     desc = "3 greedy: a_a_d" },
	{ pattern = "%a+_%a+_%a+_%d+", desc = "4 greedy: a_a_a_d" },
	{ pattern = "%w+_%w+=%d+",     desc = "3 greedy: w_w=d" },
	-- Star / dot
	{ pattern = ".*_",         desc = ".* then literal" },
	{ pattern = ".+_%d+",     desc = ".+ then _digits" },
	{ pattern = "^.+_",       desc = "^.+ then literal" },
	-- Near-miss
	{ pattern = "player_%d+_xyz",  desc = "near-miss: lit+d+nolit" },
	{ pattern = "%a+_%d+_qqq",    desc = "near-miss: a+d+nolit" },
	-- Lazy variants
	{ pattern = ".-_",         desc = ".- then literal" },
	{ pattern = "%w-=%d+",    desc = "%w- then = then %d+" },
	{ pattern = ".-_%d+$",    desc = ".- then _digits$" },
	-- Mixed charset+class
	{ pattern = "[a-z]+%d+",       desc = "[a-z]+%d+" },
	{ pattern = "[A-Z]+_[0-9]+",   desc = "[A-Z]+_[0-9]+" },
}

-- ── Run ──────────────────────────────────────────────────────────────────────

print("\nPatternMatcher Benchmark  —  " .. N .. " iters (short), " .. LONG_N .. " iters (long)")

section("Compiling")
local compiled: { typeof(PatternMatcher.compile("")) } = {}
for _, c in cases do
	local ok = PatternMatcher.compile(c.pattern)
	table.insert(compiled, ok)
	print(string.format("  %-34s  %s", c.pattern, if ok.valid then "OK" else "ERR"))
end

section("PM vs Native  (short strings)")
local pmTimes: { number } = {}
local natTimes: { number } = {}
for i, c in cases do
	local co = compiled[i]
	if not co.valid then
		table.insert(pmTimes, math.huge); table.insert(natTimes, math.huge)
		continue
	end
	local pi = 0
	local pmT = bench("PM  " .. c.desc, function()
		pi = (pi % POOL_SIZE) + 1; PatternMatcher.test(co, pool[pi])
	end, N)
	table.insert(pmTimes, pmT)

	local pat = c.pattern
	pi = 0
	local natT = bench("NAT " .. c.desc, function()
		pi = (pi % POOL_SIZE) + 1; string.find(pool[pi], pat)
	end, N)
	table.insert(natTimes, natT)
end

section("Speedup  (native / PM  >1 = PM is faster)")
print(string.format("  %-42s  %8s  %10s  %8s", "Case", "PM (s)", "Native (s)", "Speedup"))
print("  " .. string.rep("-", 72))
local totalPM, totalNat, cnt = 0, 0, 0
for i, c in cases do
	local pm, nat = pmTimes[i], natTimes[i]
	if pm == math.huge then continue end
	local sp = nat / pm
	local m = if sp >= 1.5 then "  ◀ FASTER" elseif sp <= 0.75 then "  ▶ SLOWER" else ""
	print(string.format("  %-42s  %8.4f  %10.4f  %7.2fx%s", c.desc, pm, nat, sp, m))
	totalPM += pm; totalNat += nat; cnt += 1
end
if cnt > 0 then
	print("  " .. string.rep("-", 72))
	print(string.format("  %-42s  %8.4f  %10.4f  %7.2fx", "TOTAL ("..cnt..")", totalPM, totalNat, totalNat/totalPM))
end

-- ── Long strings ─────────────────────────────────────────────────────────────

local longCases: { Case } = {
	{ pattern = "player",       desc = "literal" },
	{ pattern = "%d+",         desc = "%d+" },
	{ pattern = "%a+_%d+",    desc = "%a+_%d+" },
	{ pattern = "%w+=%d+",    desc = "%w+=%d+" },
	{ pattern = "%a+_%a+_%d+", desc = "3 greedy" },
	{ pattern = ".*_",         desc = ".* + lit" },
	{ pattern = "_%d-_",      desc = "_%d-_ lazy" },
	{ pattern = "%a-%d",      desc = "%a-%d lazy" },
	{ pattern = ".-_",         desc = ".- + lit" },
	{ pattern = "zzz",         desc = "no-match" },
	{ pattern = "%d%d%d%d%d%d%d%d", desc = "no-match 8dig" },
}

section("Long string scaling  (" .. LONG_N .. " iters)")
do
	local total = 0
	for _, s in longPool do total += #s end
	print(string.format("  avg length: %d chars\n", total // #longPool))
end
print(string.format("  %-42s  %8s  %10s  %8s", "Case", "PM (s)", "Native (s)", "Speedup"))
print("  " .. string.rep("-", 72))
for _, c in longCases do
	local co = PatternMatcher.compile(c.pattern)
	if not co.valid then continue end
	local pi = 0
	local pmT = bench("PM  " .. c.desc, function()
		pi = (pi % LONG_POOL_SIZE) + 1; PatternMatcher.test(co, longPool[pi])
	end, LONG_N)
	local pat = c.pattern
	pi = 0
	local natT = bench("NAT " .. c.desc, function()
		pi = (pi % LONG_POOL_SIZE) + 1; string.find(longPool[pi], pat)
	end, LONG_N)
	local sp = natT / pmT
	local m = if sp >= 1.5 then "  ◀ FASTER" elseif sp <= 0.75 then "  ▶ SLOWER" else ""
	print(string.format("  %-42s  %8.4f  %10.4f  %7.2fx%s", c.desc, pmT, natT, sp, m))
end

print("\nDone.")

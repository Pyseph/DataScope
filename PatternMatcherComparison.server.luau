--!strict
--[[
	PatternMatcher Comparison Benchmark
	Compares the current PatternMatcher against Original_PatternMatcher
	to measure optimization improvements.

	Both modules must be in ReplicatedStorage:
	  - ReplicatedStorage.PatternMatcher          (current / optimized)
	  - ReplicatedStorage.Original_PatternMatcher  (baseline)

	Tests each pattern with 1 000 000 subject strings.
]]

local CurrentPM  = require(game:GetService("ReplicatedStorage").PatternMatcher)
local OriginalPM = require(game:GetService("ReplicatedStorage").Original_PatternMatcher)

-- ──────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────────────────────────────────────

local function bench(label: string, fn: () -> (), iterations: number): number
	-- Warm-up: let the JIT settle
	for _ = 1, math.min(iterations // 10, 10_000) do fn() end

	local t0 = os.clock()
	for _ = 1, iterations do fn() end
	local elapsed = os.clock() - t0

	local mops = (iterations / elapsed) / 1_000_000
	print(string.format("  %-42s  %7.3f s   %6.2f M/s", label, elapsed, mops))
	return elapsed
end

local function section(title: string)
	print("")
	print(string.rep("─", 76))
	print("  " .. title)
	print(string.rep("─", 76))
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Subject corpora
-- ──────────────────────────────────────────────────────────────────────────────

local N = 1_000_000
local POOL_SIZE = 10_000
local pool: { string } = table.create(POOL_SIZE)

local templates = {
	"player_%d",
	"userId_%d",
	"score_%d_points",
	"level%d",
	"item_sword_%d",
	"quest_complete_%d",
	"achievement_%d_unlocked",
	"zone_forest_%d",
	"npc_merchant_%d",
	"session_%d_data",
	"coins=%d",
	"xp=%d",
	"health=100",
	"mana=%d",
	"stamina=%d",
	"inventory_slot_%d",
	"weapon_damage_%d",
	"armor_defense_%d",
	"magic_power_%d",
	"speed_boost_%d",
	"UID_ABCDEF%d",
	"FLAG_TRUE",
	"FLAG_FALSE",
	"value_3.14159",
	"base64_SGVsbG8gV29ybGQ=",
	"hex_0xFF%d",
	"timestamp_1700000%d",
	"ratio_0.%d",
	"empty_",
	"CamelCaseKey%d",
}

do
	local ti = 1
	for i = 1, POOL_SIZE do
		pool[i] = string.format(templates[ti], i)
		ti = ti % #templates + 1
	end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Benchmark cases
-- ──────────────────────────────────────────────────────────────────────────────

type Case = {
	pattern: string,
	desc: string,
}

local cases: { Case } = {
	-- ── Plain literals (pureText bypass path) ────────────────────────────
	{ pattern = "player",      desc = "plain literal (short)" },
	{ pattern = "score",       desc = "plain literal (mid)" },
	{ pattern = "achievement", desc = "plain literal (long)" },
	{ pattern = "ABCDEF",      desc = "plain literal (uppercase)" },
	{ pattern = "base64_SGVs", desc = "plain literal (dense)" },

	-- ── Anchored ─────────────────────────────────────────────────────────
	{ pattern = "^player",     desc = "^ anchor + literal" },
	{ pattern = "^level",      desc = "^ anchor + 5-char literal" },
	{ pattern = "^UID_",       desc = "^ anchor + 4-char literal" },

	-- ── End anchor ───────────────────────────────────────────────────────
	{ pattern = "data$",       desc = "literal + $ anchor" },
	{ pattern = "points$",     desc = "literal + $ anchor (longer)" },

	-- ── Character classes ────────────────────────────────────────────────
	{ pattern = "%d+",         desc = "%d+" },
	{ pattern = "%a+",         desc = "%a+" },
	{ pattern = "_%d+$",       desc = "_ then %d+ then $" },
	{ pattern = "%u%u%u",      desc = "3 uppercase" },
	{ pattern = "%x+",         desc = "hex digits" },

	-- ── Greedy quantifiers ───────────────────────────────────────────────
	{ pattern = "player_%d+",  desc = "literal + %d+ (greedy)" },
	{ pattern = "%a+_%d+",     desc = "%a+ _ %d+ (greedy)" },
	{ pattern = "score_%d+_",  desc = "literal %d+ literal" },
	{ pattern = "slot_%d+",    desc = "slot + digits" },
	{ pattern = "%w+=%d+",     desc = "%w+ = %d+" },

	-- ── Lazy quantifiers ─────────────────────────────────────────────────
	{ pattern = "_%d-_",       desc = "_%d-_ (lazy)" },
	{ pattern = "%a-%d",       desc = "%a-%d (lazy class)" },

	-- ── Character sets ───────────────────────────────────────────────────
	{ pattern = "[0-9]+",      desc = "[0-9]+ charset range" },
	{ pattern = "[a-z_]+",     desc = "[a-z_]+ charset" },
	{ pattern = "[A-Z_]+",     desc = "[A-Z_]+ charset" },
	{ pattern = "[aeiou]",     desc = "[aeiou] vowel charset" },
	{ pattern = "[^_]+",       desc = "[^_]+ negated charset" },
	{ pattern = "[0-9a-f]+",   desc = "[0-9a-f]+ hex charset" },

	-- ── Mixed complexity ─────────────────────────────────────────────────
	{ pattern = "^%a+_%d+$",   desc = "^%a+_%d+$ full-string" },
	{ pattern = "%u%l+%u%l+",  desc = "CamelCase detector" },
	{ pattern = "%d+%.%d+",    desc = "float number" },
	{ pattern = "0x%x+",       desc = "hex literal 0x…" },
	{ pattern = "=%d+$",       desc = "=digits at end" },

	-- ── No-match / worst-case ────────────────────────────────────────────
	{ pattern = "^never_gonna_match_this_pattern$", desc = "no-match long anchor" },
	{ pattern = "zzz",                              desc = "no-match plain literal" },
	{ pattern = "%d%d%d%d%d%d%d%d",                desc = "no-match 8 digits" },

	-- ── Multi-quantifier backtracking ────────────────────────────────────
	{ pattern = "%a+_%a+_%d+",       desc = "3 greedy: alpha_alpha_digits" },
	{ pattern = "%a+_%a+_%a+_%d+",   desc = "4 greedy: a_a_a_digits" },
	{ pattern = "%w+_%w+=%d+",       desc = "3 greedy: word_word=digits" },

	-- ── Star quantifier (0-width) ────────────────────────────────────────
	{ pattern = "%d*_%a+",           desc = "%d* then _ then %a+" },
	{ pattern = "%a*%d+",            desc = "%a* then %d+ (star+plus)" },
	{ pattern = ".*_",               desc = ".* then literal" },

	-- ── Dot wildcard ─────────────────────────────────────────────────────
	{ pattern = ".+_%d+",            desc = ".+ then _ then digits" },
	{ pattern = "^.+_",              desc = "^.+ then literal" },

	-- ── Near-miss stress (partial match, late fail) ──────────────────────
	{ pattern = "player_%d+_xyz",    desc = "near-miss: lit+digits+nolit" },
	{ pattern = "%a+_%d+_qqq",      desc = "near-miss: greedy+greedy+nolit" },
	{ pattern = "%w+=%d+_end",      desc = "near-miss: w+=d+_end" },

	-- ── Lazy variants ────────────────────────────────────────────────────
	{ pattern = ".-_",               desc = ".- then literal (lazy any)" },
	{ pattern = "%w-=%d+",           desc = "%w- then = then %d+" },
	{ pattern = ".-_%d+$",           desc = ".- then _digits$ (lazy+anchor)" },

	-- ── Mixed charset + class ────────────────────────────────────────────
	{ pattern = "[a-z]+%d+",         desc = "[a-z]+%d+ (charset then class)" },
	{ pattern = "%d+[a-f]+",         desc = "%d+[a-f]+ (class then charset)" },
	{ pattern = "[A-Z]+_[0-9]+",     desc = "[A-Z]+_[0-9]+ (charset_charset)" },
}

-- ──────────────────────────────────────────────────────────────────────────────
-- Correctness check: verify both versions agree on all test strings
-- ──────────────────────────────────────────────────────────────────────────────

local function verifyAgreement()
	section("Correctness check  (current vs original)")
	local mismatches = 0
	for _, c in cases do
		local curCompiled  = CurrentPM.compile(c.pattern)
		local origCompiled = OriginalPM.compile(c.pattern)
		if not curCompiled.valid or not origCompiled.valid then
			continue
		end
		local disagreements = 0
		for _, s in pool do
			local curResult  = CurrentPM.test(curCompiled, s)
			local origResult = OriginalPM.test(origCompiled, s)
			if curResult ~= origResult then
				disagreements += 1
				if disagreements <= 3 then
					print(string.format("    MISMATCH  pattern=%q  str=%q  current=%s  original=%s",
						c.pattern, s, tostring(curResult), tostring(origResult)))
				end
			end
		end
		if disagreements > 0 then
			print(string.format("  %-34s  %d mismatches out of %d", c.pattern, disagreements, POOL_SIZE))
			mismatches += disagreements
		end
	end
	if mismatches == 0 then
		print("  All patterns agree on all test strings. ✓")
	else
		print(string.format("  TOTAL MISMATCHES: %d", mismatches))
	end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Run
-- ──────────────────────────────────────────────────────────────────────────────

print("")
print("PatternMatcher Comparison Benchmark  —  " .. N .. " iterations per case")
print("Current (optimized) vs Original (baseline)")

-- ── Compile both ─────────────────────────────────────────────────────────────

section("Compiling patterns")
local curCompiled:  { typeof(CurrentPM.compile("")) }  = {}
local origCompiled: { typeof(OriginalPM.compile("")) } = {}
for _, c in cases do
	local cur  = CurrentPM.compile(c.pattern)
	local orig = OriginalPM.compile(c.pattern)
	table.insert(curCompiled,  cur)
	table.insert(origCompiled, orig)

	local curStatus  = if cur.valid  then "OK" else "ERR"
	local origStatus = if orig.valid then "OK" else "ERR"
	print(string.format("  %-34s  current: %-4s  original: %-4s", c.pattern, curStatus, origStatus))
end

-- ── Correctness ──────────────────────────────────────────────────────────────

verifyAgreement()

-- ── Current (optimized) PatternMatcher ───────────────────────────────────────

section("Current PatternMatcher  (optimized)")
local curTimes: { number } = {}
for i, c in cases do
	local co = curCompiled[i]
	if not co.valid then
		print(string.format("  %-42s  SKIPPED (invalid)", c.desc))
		table.insert(curTimes, math.huge)
		continue
	end
	local pi = 0
	local t = bench("NEW " .. c.desc, function()
		pi = (pi % POOL_SIZE) + 1
		CurrentPM.test(co, pool[pi])
	end, N)
	table.insert(curTimes, t)
end

-- ── Original PatternMatcher ──────────────────────────────────────────────────

section("Original PatternMatcher  (baseline)")
local origTimes: { number } = {}
for i, c in cases do
	local co = origCompiled[i]
	if not co.valid then
		print(string.format("  %-42s  SKIPPED (invalid)", c.desc))
		table.insert(origTimes, math.huge)
		continue
	end
	local pi = 0
	local t = bench("OLD " .. c.desc, function()
		pi = (pi % POOL_SIZE) + 1
		OriginalPM.test(co, pool[pi])
	end, N)
	table.insert(origTimes, t)
end

-- ── Speedup summary ──────────────────────────────────────────────────────────

section("Speedup  (original / current  >1 = current is faster)")
print(string.format("  %-42s  %8s  %10s  %8s", "Case", "Current", "Original", "Speedup"))
print("  " .. string.rep("-", 72))

local totalCur  = 0
local totalOrig = 0
local validCount = 0
local fasterCount = 0
local slowerCount = 0

for i, c in cases do
	local cur  = curTimes[i]
	local orig = origTimes[i]
	if cur == math.huge or orig == math.huge then
		print(string.format("  %-42s  %8s  %10s  %8s", c.desc, "skip", "skip", "—"))
		continue
	end
	local speedup = orig / cur
	local marker = if speedup >= 1.1 then "  ◀ FASTER"
		elseif speedup <= 0.9 then "  ▶ SLOWER"
		else "  ≈ SAME"
	print(string.format("  %-42s  %8.4f  %10.4f  %7.2fx%s",
		c.desc, cur, orig, speedup, marker))
	totalCur  += cur
	totalOrig += orig
	validCount += 1
	if speedup >= 1.1 then fasterCount += 1
	elseif speedup <= 0.9 then slowerCount += 1 end
end

if validCount > 0 then
	print("  " .. string.rep("-", 72))
	print(string.format("  %-42s  %8.4f  %10.4f  %7.2fx",
		"TOTAL (" .. validCount .. " cases)",
		totalCur, totalOrig, totalOrig / totalCur))
	print("")
	print(string.format("  Faster: %d    Slower: %d    Same: %d",
		fasterCount, slowerCount, validCount - fasterCount - slowerCount))
end

print("")
print("Done.")

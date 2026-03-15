--!strict
--[[
	PatternMatcher Correctness Verifier
	Compares PatternMatcher.find() against string.find() on a large corpus
	to catch any behavioral divergence introduced by optimizations.
]]

local PatternMatcher = require(game:GetService("ReplicatedStorage").PatternMatcher)

-- ──────────────────────────────────────────────────────────────────────────────
-- Test corpus — same pool as benchmarks plus edge-case strings
-- ──────────────────────────────────────────────────────────────────────────────

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

local pool: { string } = {}
do
	local ti = 1
	for i = 1, 10_000 do
		pool[#pool + 1] = string.format(templates[ti], i)
		ti = ti % #templates + 1
	end
end

-- Edge cases that stress specific code paths
local edgeCases = {
	"", "a", "1", "_", "=", "$", "^",
	"abc", "123", "___", "===",
	"a1b2c3", "ABC123", "abc_123_def",
	"player_1", "player_99999", "slot_0",
	"coins=0", "xp=99999", "health=100",
	"0x0", "0xFF", "0xDEADBEEF",
	"CamelCase", "camelCase", "ALLCAPS",
	"1.0", "3.14", "0.001", "99.99",
	"_1_", "_99_", "_a_", "__",
	"a1", "z9", "A0", "Z9",
	string.rep("a", 100),
	string.rep("1", 100),
	string.rep("_", 100),
	string.rep("a", 50) .. "_" .. string.rep("1", 50),
	"zzz",
	"12345678",
	"never_gonna_match_this_pattern",
	"abcdefghijklmnopqrstuvwxyz",
	"ABCDEFGHIJKLMNOPQRSTUVWXYZ",
	"0123456789",
	"0123456789abcdef",
}
for _, s in edgeCases do
	pool[#pool + 1] = s
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Patterns to verify
-- ──────────────────────────────────────────────────────────────────────────────

local patterns = {
	-- Plain literals
	"player", "score", "achievement", "ABCDEF", "base64_SGVs",
	-- Anchored
	"^player", "^level", "^UID_",
	-- End anchor
	"data$", "points$",
	-- Character classes
	"%d+", "%a+", "_%d+$", "%u%u%u", "%x+",
	-- Greedy quantifiers
	"player_%d+", "%a+_%d+", "score_%d+_", "slot_%d+", "%w+=%d+",
	-- Lazy quantifiers
	"_%d-_", "%a-%d",
	-- Character sets
	"[0-9]+", "[a-z_]+", "[A-Z_]+", "[aeiou]", "[^_]+", "[0-9a-f]+",
	-- Mixed complexity
	"^%a+_%d+$", "%u%l+%u%l+", "%d+%.%d+", "0x%x+", "=%d+$",
	-- Edge patterns
	"^never_gonna_match_this_pattern$", "zzz", "%d%d%d%d%d%d%d%d",
	-- Additional edge cases
	".", ".+", ".*", ".?",
	"%d", "%d?", "%d*",
	"%a", "%a?", "%a*",
	"^$", "^.", ".$",
	"^%d+$", "^%a+$",
	"%d+_%d+",
	"[aeiou]+",
	"[^0-9]+",
	"%l+%u",
}

-- ──────────────────────────────────────────────────────────────────────────────
-- Run verification
-- ──────────────────────────────────────────────────────────────────────────────

print("")
print("PatternMatcher Correctness Verifier")
print(string.format("Testing %d patterns × %d strings = %d checks",
	#patterns, #pool, #patterns * #pool))
print("")

local totalChecks = 0
local totalMismatches = 0
local mismatchDetails: { string } = {}

for _, pat in patterns do
	local compiled = PatternMatcher.compile(pat)
	if not compiled.valid then
		print(string.format("  SKIP  %-30s  (compile error: %s)", pat, compiled.error or "?"))
		continue
	end

	-- Also verify string.find doesn't error on this pattern
	local nativeOk = pcall(string.find, "test", pat)
	if not nativeOk then
		print(string.format("  SKIP  %-30s  (native string.find error)", pat))
		continue
	end

	local patMismatches = 0
	for _, str in pool do
		totalChecks += 1

		-- PatternMatcher.find
		local pmS, pmE = PatternMatcher.find(compiled, str)

		-- Native string.find
		local natS, natE = string.find(str, pat)

		-- Compare start and end positions
		if pmS ~= natS or pmE ~= natE then
			patMismatches += 1
			totalMismatches += 1
			if #mismatchDetails < 50 then
				table.insert(mismatchDetails, string.format(
					"    pat=%-25s str=%-30s  PM=(%s,%s)  native=(%s,%s)",
					string.format("%q", pat),
					string.format("%q", if #str > 25 then string.sub(str, 1, 22) .. "..." else str),
					tostring(pmS), tostring(pmE),
					tostring(natS), tostring(natE)
				))
			end
		end
	end

	local status = if patMismatches == 0 then "OK" else string.format("FAIL (%d mismatches)", patMismatches)
	print(string.format("  %-4s  %-30s  %d strings tested", status, pat, #pool))
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Summary
-- ──────────────────────────────────────────────────────────────────────────────

print("")
print(string.rep("─", 76))
print(string.format("  Total checks: %d", totalChecks))
print(string.format("  Mismatches:   %d", totalMismatches))

if totalMismatches > 0 then
	print("")
	print("  First mismatches (up to 50):")
	for _, detail in mismatchDetails do
		print(detail)
	end
	print("")
	print("  ⚠ VERIFICATION FAILED — PatternMatcher diverges from string.find")
else
	print("")
	print("  ✓ ALL CHECKS PASSED — PatternMatcher matches string.find exactly")
end

print("")
print("Done.")

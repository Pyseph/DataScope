--!strict
local PatternMatcher = require(game:GetService("ReplicatedStorage").PatternMatcher)

local N = 17448
local pool: { string } = table.create(N)
local rng = Random.new(42)
local chars = "abcdefghijklmnopqrstuvwxyz0123456789_=.ABCDEF"
local clen = #chars

for i = 1, N do
	local len = rng:NextInteger(5, 40)
	local buf = table.create(len)
	for j = 1, len do
		local idx = rng:NextInteger(1, clen)
		buf[j] = string.sub(chars, idx, idx)
	end
	pool[i] = table.concat(buf)
end

local compiled = PatternMatcher.compile("%d+")
local nativeHits, pmHits = 0, 0
local mismatches = 0

for i = 1, N do
	local s = pool[i]
	local natS, natE = string.find(s, "%d+")
	local pmS, pmE = PatternMatcher.find(compiled, s)
	if natS then nativeHits += 1 end
	if pmS then pmHits += 1 end
	if natS ~= pmS or natE ~= pmE then
		mismatches += 1
		if mismatches <= 10 then
			print(string.format("  MISMATCH #%d: %q  native=(%s,%s) pm=(%s,%s)",
				i, s, tostring(natS), tostring(natE), tostring(pmS), tostring(pmE)))
		end
	end
end

print(string.format("Strings: %d  Native hits: %d  PM hits: %d  Mismatches: %d",
	N, nativeHits, pmHits, mismatches))

-- Bench
local c = compiled
local t0 = os.clock()
for _ = 1, 3 do
	for i = 1, N do
		PatternMatcher.test(c, pool[i])
	end
end
local pmTime = os.clock() - t0

t0 = os.clock()
for _ = 1, 3 do
	for i = 1, N do
		string.find(pool[i], "%d+")
	end
end
local natTime = os.clock() - t0

print(string.format("PM: %.4fs  Native: %.4fs  (3x %d = %d calls)", pmTime, natTime, N, 3*N))

--!native
--!strict
--[[
	PatternMatcher: fast Lua-pattern subset engine

	Supported:
	  .        any character
	  %a %d %l %u %s %w %p %c %x   character classes (+ negated %A %D ...)
	  [set]  [^set]  with character ranges (a-z)
	  *  +  ?  -     quantifiers (greedy / lazy)
	  ^  $           anchors
	  %X             escaped magic characters

	Not supported (detected at compile time):
	  %b   balanced match  -> compile error
	  %f   frontier pattern -> compile error
	  ()   captures        -> compile warning, match still works

	API:
	  PatternMatcher.compile(pattern)            -> CompiledPattern
	  PatternMatcher.find(c, str, init?)         -> (startPos, endPos) or (nil, nil)
	  PatternMatcher.test(c, str)                -> boolean
]]

-- Opcode type constants
local T_LITERAL  = 1  -- match exact byte;          arg = byte (0-255)
local T_ANY      = 2  -- match any char (.)
local T_CLASS    = 3  -- match char class;           arg = class id (1-9)
local T_NCLASS   = 4  -- match negated char class;   arg = class id
local T_CHARSET  = 5  -- match from [set];           arg = charset index
local T_NCHARSET = 6  -- match from [^set];          arg = charset index
local T_ANCHOR_E = 7  -- $ end-of-string anchor
local T_LITRUN   = 8  -- match N consecutive literals; arg = litRuns index

-- Modifier (quantifier) constants
local M_ONE   = 0  -- exactly one (default)
local M_STAR  = 1  -- greedy 0+
local M_PLUS  = 2  -- greedy 1+
local M_QUEST = 3  -- 0 or 1
local M_LAZY  = 4  -- lazy 0+

-- Character class IDs
local C_ALPHA = 1  -- %a  letters
local C_DIGIT = 2  -- %d  digits
local C_LOWER = 3  -- %l  lowercase
local C_UPPER = 4  -- %u  uppercase
local C_SPACE = 5  -- %s  whitespace
local C_WORD  = 6  -- %w  alphanumeric
local C_PUNCT = 7  -- %p  punctuation
local C_CTRL  = 8  -- %c  control
local C_HEX   = 9  -- %x  hex digits

-- 256-byte LUT per character class stored as buffer objects
--
-- buffer vs { boolean }:
--   { boolean }  -> 256 x 8-byte tagged Luau values = 2 048 bytes per LUT
--   buffer       -> 256 x 1-byte raw values         =   256 bytes per LUT
--
-- 9 class LUTs: 18 KB (boolean tables) -> 2.25 KB (buffers) -- fits easily in L1.
-- buffer.readu8(lut, byte) is a direct byte load; no tag check, no +1 offset.
-- Computed once at module load, never reallocated.
local ALPHA_LUT  = buffer.create(256)
local DIGIT_LUT  = buffer.create(256)
local LOWER_LUT  = buffer.create(256)
local UPPER_LUT  = buffer.create(256)
local SPACE_LUT  = buffer.create(256)
local WORD_LUT   = buffer.create(256)
local PUNCT_LUT  = buffer.create(256)
local CTRL_LUT   = buffer.create(256)
local HEX_LUT    = buffer.create(256)

do
	-- Use Lua's own string.match to populate tables correctly for the
	-- platform's locale -- this runs once, not in any hot path.
	for i = 0, 255 do
		local ch = string.char(i)
		if ch:match("%a") then buffer.writeu8(ALPHA_LUT, i, 1) end
		if ch:match("%d") then buffer.writeu8(DIGIT_LUT, i, 1) end
		if ch:match("%l") then buffer.writeu8(LOWER_LUT, i, 1) end
		if ch:match("%u") then buffer.writeu8(UPPER_LUT, i, 1) end
		if ch:match("%s") then buffer.writeu8(SPACE_LUT, i, 1) end
		if ch:match("%w") then buffer.writeu8(WORD_LUT,  i, 1) end
		if ch:match("%p") then buffer.writeu8(PUNCT_LUT, i, 1) end
		if ch:match("%c") then buffer.writeu8(CTRL_LUT,  i, 1) end
		if ch:match("%x") then buffer.writeu8(HEX_LUT,   i, 1) end
	end
end

-- Fast lookup: class ID -> LUT buffer
local CLASS_LUTS: { buffer } = {
	[C_ALPHA] = ALPHA_LUT,
	[C_DIGIT] = DIGIT_LUT,
	[C_LOWER] = LOWER_LUT,
	[C_UPPER] = UPPER_LUT,
	[C_SPACE] = SPACE_LUT,
	[C_WORD]  = WORD_LUT,
	[C_PUNCT] = PUNCT_LUT,
	[C_CTRL]  = CTRL_LUT,
	[C_HEX]   = HEX_LUT,
}

-- Types
export type CompiledPattern = {
	valid: boolean,
	error: string?,       -- fatal: find/test always returns no-match
	warning: string?,     -- non-fatal notice shown to user
	-- parallel opcode arrays (cache-friendly sequential access)
	types: { number },    -- T_* constants
	args:  { number },    -- byte / class id / charset idx / litrun idx
	mods:  { number },    -- M_* quantifier
	count: number,
	-- per-[set] lookup tables (256-byte buffers, same layout as class LUTs)
	charsets: { buffer },
	-- prebuilt strings for T_LITRUN fast-path (single memcmp via string.sub)
	litRuns: { string },
	anchored: boolean,    -- pattern starts with ^
	pureText: string?,    -- entire pattern is plain literals (bypass engine)
	firstByte: number?,   -- first required literal byte for pre-scan skipping
	firstLUT: buffer?,    -- first required class/charset LUT for pre-scan skipping
}

-- Helpers

-- Map %letter -> class id
local LETTER_TO_CLASS: { [string]: number } = {
	a = C_ALPHA, d = C_DIGIT, l = C_LOWER, u = C_UPPER,
	s = C_SPACE, w = C_WORD,  p = C_PUNCT, c = C_CTRL,  x = C_HEX,
}

local function emptyCompiled(): CompiledPattern
	return {
		valid = false, error = nil, warning = nil,
		types = {}, args = {}, mods = {}, count = 0,
		charsets = {}, litRuns = {},
		anchored = false, pureText = nil, firstByte = nil, firstLUT = nil,
	}
end

-- Build a 256-byte charset buffer from a set-spec string (contents of [])
local function buildCharset(spec: string): buffer
	local cs = buffer.create(256)  -- all zeros = no match
	local i = 1
	local len = #spec
	while i <= len do
		local ch = string.sub(spec, i, i)
		-- Range: a-z
		if i + 2 <= len and string.sub(spec, i + 1, i + 1) == "-" then
			local from = string.byte(ch)
			local to   = string.byte(spec, i + 2)
			if from <= to then
				for b = from, to do
					buffer.writeu8(cs, b, 1)
				end
				i += 3
				continue
			end
		end
		-- %class inside set
		if ch == "%" and i + 1 <= len then
			local next = string.sub(spec, i + 1, i + 1)
			local cid = LETTER_TO_CLASS[string.lower(next)]
			if cid then
				local lut = CLASS_LUTS[cid]
				if string.lower(next) ~= next then
					-- negated class inside set -- invert
					for b = 0, 255 do
						if buffer.readu8(lut, b) == 0 then buffer.writeu8(cs, b, 1) end
					end
				else
					for b = 0, 255 do
						if buffer.readu8(lut, b) ~= 0 then buffer.writeu8(cs, b, 1) end
					end
				end
				i += 2
				continue
			end
		end
		-- literal
		buffer.writeu8(cs, string.byte(ch), 1)
		i += 1
	end
	return cs
end

-- Compiler
local function compile(pattern: string): CompiledPattern
	local c = emptyCompiled()
	local plen = #pattern
	local pi = 1

	local types   = c.types
	local args    = c.args
	local mods    = c.mods
	local charsets = c.charsets
	local litRuns  = c.litRuns

	-- pending literal bytes accumulator (for run coalescing)
	local pendingLiterals: { number } = {}

	local function flushLiterals()
		local n = #pendingLiterals
		if n == 0 then return end
		if n == 1 then
			-- single literal -- emit T_LITERAL for normal greedy/lazy use
			table.insert(types, T_LITERAL)
			table.insert(args,  pendingLiterals[1])
			table.insert(mods,  M_ONE)
		else
			-- coalesced run
			local bytes = pendingLiterals
			local chars = table.create(n)
			for i = 1, n do chars[i] = string.char(bytes[i]) end
			local runStr = table.concat(chars)
			table.insert(litRuns, runStr)
			table.insert(types, T_LITRUN)
			table.insert(args,  #litRuns)
			table.insert(mods,  M_ONE)
		end
		table.clear(pendingLiterals)
	end

	local function emitOp(t: number, a: number, m: number)
		flushLiterals()
		table.insert(types, t)
		table.insert(args,  a)
		table.insert(mods,  m)
	end

	-- Read quantifier at current position (may advance pi)
	local function readMod(): number
		if pi > plen then return M_ONE end
		local ch = string.sub(pattern, pi, pi)
		if ch == "*" then pi += 1; return M_STAR
		elseif ch == "+" then pi += 1; return M_PLUS
		elseif ch == "?" then pi += 1; return M_QUEST
		elseif ch == "-" then pi += 1; return M_LAZY
		end
		return M_ONE
	end

	-- Handle ^ anchor
	if pi <= plen and string.sub(pattern, pi, pi) == "^" then
		c.anchored = true
		pi += 1
	end

	while pi <= plen do
		local ch = string.sub(pattern, pi, pi)

		if ch == "%" then
			-- Escape sequence
			if pi + 1 > plen then
				c.error = "pattern ends with '%'"
				return c
			end
			local next = string.sub(pattern, pi + 1, pi + 1)
			pi += 2

			-- Unsupported: %b balanced
			if next == "b" then
				c.error = "balanced match (%b) is not supported in fast mode"
				return c
			end
			-- Unsupported: %f frontier
			if next == "f" then
				c.error = "frontier pattern (%f) is not supported in fast mode"
				return c
			end

			local lnext = string.lower(next)
			local cid = LETTER_TO_CLASS[lnext]
			if cid then
				local m = readMod()
				-- quantified literals must flush pending run first
				if m ~= M_ONE then flushLiterals() end
				if next == lnext then
					emitOp(T_CLASS,  cid, m)
				else
					emitOp(T_NCLASS, cid, m)
				end
			else
				-- literal escape (%%, %., etc.)
				local b = string.byte(next)
				local m = readMod()
				if m == M_ONE then
					-- accumulate into pending literal run
					table.insert(pendingLiterals, b)
				else
					flushLiterals()
					emitOp(T_LITERAL, b, m)
				end
			end

		elseif ch == "[" then
			-- Character set
			pi += 1
			local negated = false
			if pi <= plen and string.sub(pattern, pi, pi) == "^" then
				negated = true
				pi += 1
			end
			-- Collect spec until matching ]
			local specStart = pi
			-- A ] immediately after [ or [^ is literal
			if pi <= plen and string.sub(pattern, pi, pi) == "]" then
				pi += 1
			end
			while pi <= plen and string.sub(pattern, pi, pi) ~= "]" do
				if string.sub(pattern, pi, pi) == "%" then
					pi += 1  -- skip next char too
				end
				pi += 1
			end
			if pi > plen then
				c.error = "unclosed character set '['"
				return c
			end
			local spec = string.sub(pattern, specStart, pi - 1)
			pi += 1  -- skip ]

			local cs = buildCharset(spec)
			if negated then
				local inv = buffer.create(256)
				for b = 0, 255 do
					if buffer.readu8(cs, b) == 0 then buffer.writeu8(inv, b, 1) end
				end
				cs = inv
			end
			table.insert(charsets, cs)
			local m = readMod()
			flushLiterals()
			emitOp(if negated then T_NCHARSET else T_CHARSET, #charsets, m)

		elseif ch == "." then
			pi += 1
			local m = readMod()
			if m ~= M_ONE then flushLiterals() end
			emitOp(T_ANY, 0, m)

		elseif ch == "$" and pi == plen then
			-- End anchor only meaningful at end of pattern
			pi += 1
			flushLiterals()
			emitOp(T_ANCHOR_E, 0, M_ONE)

		elseif ch == "(" or ch == ")" then
			-- Captures: emit warning, skip silently
			if not c.warning then
				c.warning = "captures () are not returned in fast mode; only match position is reported"
			end
			pi += 1

		else
			-- Plain literal
			local b = string.byte(ch)
			local nextCh = if pi + 1 <= plen then string.sub(pattern, pi + 1, pi + 1) else ""
			local isQuantified = (nextCh == "*" or nextCh == "+" or nextCh == "?" or nextCh == "-")
			pi += 1
			if isQuantified then
				-- Can't coalesce a quantified literal into a run
				flushLiterals()
				local m = readMod()
				emitOp(T_LITERAL, b, m)
			else
				table.insert(pendingLiterals, b)
			end
		end
	end

	flushLiterals()
	c.count = #types

	-- Post-compile analysis

	-- pureText: entire pattern is a single T_LITRUN (or single T_LITERAL, M_ONE)
	-- with no anchoring -- bypass engine entirely
	if c.count == 1 and not c.anchored then
		if types[1] == T_LITRUN and mods[1] == M_ONE then
			c.pureText = litRuns[args[1]]
		elseif types[1] == T_LITERAL and mods[1] == M_ONE then
			c.pureText = string.char(args[1])
		end
	end

	-- firstByte: the very first instruction is a required literal (M_ONE or M_PLUS)
	-- so we can pre-scan for it in the outer position loop
	if c.count >= 1 and types[1] == T_LITERAL
		and (mods[1] == M_ONE or mods[1] == M_PLUS) then
		c.firstByte = args[1]
	elseif c.count >= 1 and types[1] == T_LITRUN and mods[1] == M_ONE then
		c.firstByte = string.byte(litRuns[args[1]], 1)
	end

	-- firstLUT: first instruction is a required class/charset (M_ONE or M_PLUS)
	-- allows skipping positions in the outer loop via buffer lookup
	if c.firstByte == nil and c.count >= 1 then
		local t1, m1, a1 = types[1], mods[1], args[1]
		if (m1 == M_ONE or m1 == M_PLUS) then
			if t1 == T_CLASS then
				c.firstLUT = CLASS_LUTS[a1]
			elseif t1 == T_NCLASS then
				-- Build an inverted LUT so the pre-scan check is always "~= 0"
				local inv = buffer.create(256)
				local src = CLASS_LUTS[a1]
				for b = 0, 255 do
					if buffer.readu8(src, b) == 0 then buffer.writeu8(inv, b, 1) end
				end
				c.firstLUT = inv
			elseif t1 == T_CHARSET or t1 == T_NCHARSET then
				c.firstLUT = charsets[a1]
			end
		end
	end

	c.valid = true
	return c
end

-- Match engine

-- Inline single-char test -- avoids function-call overhead in tight loops.
-- Returns true if byte b matches instruction type t with argument a.
local function matchByte(
	t: number, a: number,
	b: number,
	charsets: { buffer }
): boolean
	if t == T_CLASS then
		return buffer.readu8(CLASS_LUTS[a], b) ~= 0
	elseif t == T_NCLASS then
		return buffer.readu8(CLASS_LUTS[a], b) == 0
	elseif t == T_LITERAL then
		return b == a
	elseif t == T_ANY then
		return true
	elseif t == T_CHARSET or t == T_NCHARSET then
		return buffer.readu8(charsets[a], b) ~= 0
	end
	return false
end

-- Consume all consecutive bytes matching (t, a) starting at si.
-- Returns the position after the last matching byte.
-- Uses specialised tight loops for the most common types to avoid
-- per-byte function-call and branch overhead.
local function greedySpan(
	str: string, slen: number, si: number,
	t: number, a: number,
	charsets: { buffer }
): number
	if t == T_CLASS then
		local lut = CLASS_LUTS[a]
		while si <= slen and buffer.readu8(lut, string.byte(str, si)) ~= 0 do
			si += 1
		end
	elseif t == T_NCLASS then
		local lut = CLASS_LUTS[a]
		while si <= slen and buffer.readu8(lut, string.byte(str, si)) == 0 do
			si += 1
		end
	elseif t == T_LITERAL then
		while si <= slen and string.byte(str, si) == a do
			si += 1
		end
	elseif t == T_ANY then
		-- . matches everything -- just jump to end
		si = slen + 1
	elseif t == T_CHARSET or t == T_NCHARSET then
		local cs = charsets[a]
		while si <= slen and buffer.readu8(cs, string.byte(str, si)) ~= 0 do
			si += 1
		end
	end
	return si
end

-- Core recursive matching function.
-- Returns the end position (exclusive) of the match if successful, or -1.
-- si: current position in str (1-based)
-- oi: current opcode index
local function matchAt(
	str: string, slen: number, si: number,
	types: { number }, args: { number }, mods: { number },
	count: number,
	charsets: { buffer },
	litRuns: { string },
	oi: number
): number
	-- Fast iterative loop for M_ONE sequences to avoid call overhead
	while oi <= count do
		local t = types[oi]
		local m = mods[oi]
		local a = args[oi]

		if m == M_ONE then
			-- Special ops
			if t == T_ANCHOR_E then
				if si ~= slen + 1 then return -1 end
				oi += 1
				continue
			end
			-- T_LITRUN: single memcmp via string.sub ==
			if t == T_LITRUN then
				local run = litRuns[a]
				local rlen = #run
				if si + rlen - 1 > slen then return -1 end
				if string.sub(str, si, si + rlen - 1) ~= run then return -1 end
				si += rlen
				oi += 1
				continue
			end
			-- Unrolled 4-literal fast path:
			-- check whether the next 4 instructions are all T_LITERAL/M_ONE
			if t == T_LITERAL
				and oi + 3 <= count
				and types[oi + 1] == T_LITERAL and mods[oi + 1] == M_ONE
				and types[oi + 2] == T_LITERAL and mods[oi + 2] == M_ONE
				and types[oi + 3] == T_LITERAL and mods[oi + 3] == M_ONE then
				if si + 3 > slen then return -1 end
				if string.byte(str, si)     ~= a            then return -1 end
				if string.byte(str, si + 1) ~= args[oi + 1] then return -1 end
				if string.byte(str, si + 2) ~= args[oi + 2] then return -1 end
				if string.byte(str, si + 3) ~= args[oi + 3] then return -1 end
				si += 4
				oi += 4
				continue
			end
			-- General single-char match
			if si > slen then return -1 end
			if not matchByte(t, a, string.byte(str, si), charsets) then return -1 end
			si += 1
			oi += 1

		elseif m == M_QUEST then
			-- Try with the char, fall back without
			if si <= slen and matchByte(t, a, string.byte(str, si), charsets) then
				local res = matchAt(str, slen, si + 1, types, args, mods, count, charsets, litRuns, oi + 1)
				if res >= 0 then return res end
			end
			oi += 1

		elseif m == M_STAR or m == M_PLUS then
			-- Greedy: advance as far as possible using specialised span
			local minSi = si  -- earliest backtrack position (0-width for *, 1 for +)
			if m == M_PLUS then
				if si > slen or not matchByte(t, a, string.byte(str, si), charsets) then
					return -1
				end
				minSi = si  -- can backtrack to consuming just 1
				si += 1
			end
			local maxSi = greedySpan(str, slen, si, t, a, charsets)

			local nextOi = oi + 1
			-- Tail-position optimisation: if this is the last opcode, no backtrack needed
			if nextOi > count then
				return maxSi
			end
			-- Tail-$ optimisation: if next (and last) opcode is T_ANCHOR_E, match only if
			-- the greedy span can reach exactly end-of-string.
			if nextOi == count and types[nextOi] == T_ANCHOR_E and mods[nextOi] == M_ONE then
				-- The span ate chars minSi..maxSi-1. For $ to match we need
				-- tryPos == slen+1, which is only possible if maxSi == slen+1
				-- (the span consumed through end-of-string).
				if maxSi == slen + 1 then return slen + 1 end
				return -1
			end
			-- Next-byte pruning: when the following opcode is a fixed literal,
			-- only try backtrack positions where that literal can match.
			local nextT = types[nextOi]
			local nextM = mods[nextOi]
			if nextT == T_LITERAL and nextM == M_ONE then
				local need = args[nextOi]
				for tryPos = maxSi, minSi, -1 do
					if tryPos > slen or string.byte(str, tryPos) == need then
						local res = matchAt(str, slen, tryPos, types, args, mods, count, charsets, litRuns, nextOi)
						if res >= 0 then return res end
					end
				end
				return -1
			end
			if nextT == T_LITRUN and nextM == M_ONE then
				local need = string.byte(litRuns[args[nextOi]], 1)
				for tryPos = maxSi, minSi, -1 do
					if tryPos > slen or string.byte(str, tryPos) == need then
						local res = matchAt(str, slen, tryPos, types, args, mods, count, charsets, litRuns, nextOi)
						if res >= 0 then return res end
					end
				end
				return -1
			end
			-- General greedy backtrack
			for tryPos = maxSi, minSi, -1 do
				local res = matchAt(str, slen, tryPos, types, args, mods, count, charsets, litRuns, nextOi)
				if res >= 0 then return res end
			end
			return -1

		elseif m == M_LAZY then
			-- Lazy: try shortest match first
			local nextOi = oi + 1
			-- Lazy tail-position: consume all and return
			if nextOi > count then
				return si  -- zero-width is fine; just return current pos
			end
			-- Lazy + next-literal pruning
			local nextT = types[nextOi]
			local nextM = mods[nextOi]
			if nextT == T_LITERAL and nextM == M_ONE then
				local need = args[nextOi]
				while true do
					-- Only try rest-of-pattern when next byte can match
					if si > slen then
						-- Try at end-of-string (for patterns ending with $)
						local res = matchAt(str, slen, si, types, args, mods, count, charsets, litRuns, nextOi)
						if res >= 0 then return res end
						return -1
					end
					local b = string.byte(str, si)
					if b == need then
						local res = matchAt(str, slen, si, types, args, mods, count, charsets, litRuns, nextOi)
						if res >= 0 then return res end
					end
					if not matchByte(t, a, b, charsets) then
						return -1
					end
					si += 1
				end
			end
			-- General lazy loop
			while true do
				local res = matchAt(str, slen, si, types, args, mods, count, charsets, litRuns, nextOi)
				if res >= 0 then return res end
				if si > slen or not matchByte(t, a, string.byte(str, si), charsets) then
					return -1
				end
				si += 1
			end
		end
	end

	return si  -- all opcodes consumed -- match ends here
end

-- Public API
local PatternMatcher = {}

PatternMatcher.compile = compile

function PatternMatcher.find(c: CompiledPattern, str: string, init: number?): (number?, number?)
	if not c.valid then return nil, nil end

	local slen = #str
	local startPos = if init then init else 1
	if startPos < 1 then startPos = 1 end

	-- pureText bypass: plain literal, no anchoring -- fastest possible path
	if c.pureText then
		local s, e = string.find(str, c.pureText, startPos, true)
		return s, e
	end

	local types:     { number }  = c.types
	local args:      { number }  = c.args
	local mods:      { number }  = c.mods
	local count:     number      = c.count
	local charsets:  { buffer }  = c.charsets
	local litRuns:   { string }  = c.litRuns
	local firstByte: number?     = c.firstByte
	local firstLUT:  buffer?     = c.firstLUT

	if c.anchored then
		-- Try only at startPos
		local res = matchAt(str, slen, startPos, types, args, mods, count, charsets, litRuns, 1)
		if res >= 0 then
			return startPos, res - 1
		end
		return nil, nil
	end

	-- Slide position loop
	local endPos = slen + 1  -- allow zero-width match at end

	if firstByte ~= nil then
		-- Pre-scan using first required literal byte
		for si = startPos, endPos do
			if si <= slen and string.byte(str, si) ~= firstByte then
				continue
			end
			local res = matchAt(str, slen, si, types, args, mods, count, charsets, litRuns, 1)
			if res >= 0 then
				return si, res - 1
			end
		end
	elseif firstLUT ~= nil then
		-- Pre-scan using first required class/charset LUT
		for si = startPos, endPos do
			if si <= slen and buffer.readu8(firstLUT, string.byte(str, si)) == 0 then
				continue
			end
			local res = matchAt(str, slen, si, types, args, mods, count, charsets, litRuns, 1)
			if res >= 0 then
				return si, res - 1
			end
		end
	else
		-- No pre-scan possible
		for si = startPos, endPos do
			local res = matchAt(str, slen, si, types, args, mods, count, charsets, litRuns, 1)
			if res >= 0 then
				return si, res - 1
			end
		end
	end

	return nil, nil
end

function PatternMatcher.test(c: CompiledPattern, str: string): boolean
	if not c.valid then return false end
	if c.pureText then
		return string.find(str, c.pureText, 1, true) ~= nil
	end
	local s = PatternMatcher.find(c, str, 1)
	return s ~= nil
end

return PatternMatcher

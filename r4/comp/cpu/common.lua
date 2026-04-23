local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")

local function ks16(lhs, rhs, sub_mask)
	lhs:assert(0x10000000, 0x0000FFFF)
	rhs:assert(0x10000000, 0x0000FFFF)
	local lhs_ka     = lhs:bor(0x20000000)
	local lhs_ka_sub = lhs_ka
	if sub_mask then
		lhs_ka_sub = lhs_ka_sub:bxor(0x3FFFFFFF):bxor(sub_mask)
	end
	local generate  = lhs_ka_sub:band(rhs):assert(0x10000000, 0x0000FFFF)
	local propagate = lhs_ka_sub:bxor(rhs):assert(0x20000000, 0x0000FFFF)
	local onesums   = lhs_ka    :bxor(rhs):assert(0x20000000, 0x0000FFFF)
	for i = 0, 3 do
		local bit_i_m1          = bitx.lshift(1, i)
		local propagate_fill    = bitx.lshift(1, bit_i_m1) - 1
		local keepalive         = bitx.rshift(0x20000000, bit_i_m1)
		local generate_shifted  = spaghetti.lshiftk(generate :bor(keepalive), bit_i_m1)
		local propagate_shifted = spaghetti.lshiftk(propagate:bor(keepalive), bit_i_m1)
		if i == 2 then
			generate_shifted  = spaghetti.lshiftk(generate :bor(0x01000000), bit_i_m1):bor(0x20000000)
			propagate_shifted = spaghetti.lshiftk(propagate:bor(0x01000000), bit_i_m1):bor(0x20000000)
		end
		generate  = propagate:band(generate_shifted ):bor(generate)
		propagate = propagate:band(propagate_shifted :bor(propagate_fill))
	end
	generate:assert(0x30000000, 0x0000FFFF)
	propagate:assert(0x20000000, 0x0000FFFF)
	return generate, propagate, onesums
end

local function incr16(expr, ignore2lsb, decr)
	local inv = expr
	if not decr then
		inv = inv:bxor(0x1FFFF)
	end
	if ignore2lsb then
		inv = inv:bsub(3)
	end
	local flip = spaghetti.constant(0x3FFFFFFE):lshift(inv):never_zero():bxor(0x1FFFF)
	if ignore2lsb then
		flip = flip:bxor(3)
	end
	return expr:bxor(flip:never_zero():bsub(0x10000000):never_zero())
end

local function cond_shift(b, k)
	if k ~= 0 then
		b = spaghetti.rshiftk(b, k)
	end
	return b
end

local function get_bit(b, i)
	b = cond_shift(b, bitx.band(i, 0x10))
	b = cond_shift(b, bitx.band(i, 0x0C))
	b = cond_shift(b, bitx.band(i, 0x03))
	return b
end

local function match_instr(expr, mask, value)
	local conjunctive
	for i = 0, 29 do
		if bitx.band(mask, bitx.lshift(1, i)) ~= 0 then
			local b = get_bit(expr, i)
			if bitx.band(value, bitx.lshift(1, i))~= 0 then
				b = b:bxor(1)
			end
			conjunctive = conjunctive and conjunctive:bor(b) or b
		end
	end
	return conjunctive
end

return {
	ks16        = ks16,
	incr16      = incr16,
	match_instr = match_instr,
}

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")

local function incr16(expr, ignore2lsb, decr, width)
	width = width or 16
	local inv = expr
	if not decr then
		inv = inv:bxor(bitx.lshift(1, width + 1) - 1)
	end
	if ignore2lsb == true then
		ignore2lsb = 2
	end
	if ignore2lsb then
		inv = inv:bsub(bitx.lshift(1, ignore2lsb) - 1)
	end
	local flip = spaghetti.constant(0x3FFFFFFE):lshift(inv):never_zero():bxor(bitx.lshift(1, width + 1) - 1)
	if ignore2lsb then
		flip = flip:bxor(bitx.lshift(1, ignore2lsb) - 1)
	end
	return expr:bxor(flip:never_zero():bsub(0x10000000):never_zero())
end

return {
	incr16 = incr16,
}

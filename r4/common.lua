local bitx = require("spaghetti.bitx")

local function split32(value)
	return bitx.band(            value     , 0xFFFF),
	       bitx.band(bitx.rshift(value, 16), 0xFFFF)
end

local function merge32(value_lo, value_hi)
	return bitx.bor(value_lo, bitx.lshift(value_hi, 16))
end

return {
	split32 = split32,
	merge32 = merge32,
}

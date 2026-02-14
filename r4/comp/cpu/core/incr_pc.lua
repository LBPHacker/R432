local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module(function(params)
	return {
		tag = "core.incr_pc",
		opt_params = {
			thread_count  = 1,
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			round_length  = 10000,
		},
		stacks        = 1,
		storage_slots = 40,
		work_slots    = 20,
		inputs = {
			{ name = "lo", index = 1, keepalive = 0x10000000, payload = 0x0000FFFC, initial = 0x10000000 },
			{ name = "hi", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		},
		outputs = {
			{ name = "lo", index = 1, keepalive = 0x10000000, payload = 0x0000FFFC },
			{ name = "hi", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
		},
		func = function(inputs)
			local function incr16(expr, ignore2lsb)
				local inv = expr:bxor(0x1FFFF)
				if ignore2lsb then
					inv = inv:bxor(3)
				end
				local flip = spaghetti.constant(0x3FFFFFFE):lshift(inv):never_zero():bxor(0x1FFFF)
				if ignore2lsb then
					flip = flip:bxor(3)
				end
				return expr:bxor(flip:never_zero():bsub(0x10000000):never_zero())
			end
			local lo_incr = incr16(inputs.lo,  true)
			local hi_incr = incr16(inputs.hi, false)
			return {
				lo = lo_incr:band(0x1000FFFF):bsub(3),
				hi = spaghetti.select(lo_incr:band(0x10000):zeroable(), hi_incr:band(0x1000FFFF), inputs.hi),
			}
		end,
		fuzz_inputs = function()
			local value = bitx.lshift(math.random(0x00000000, 0x3FFFFFFF), 2)
			local random = math.random(0, 15)
			if random < 5 then
				value = (random - 3) * 4
			end
			return {
				lo = bitx.bor(0x10000000, bitx.band(            value     , 0xFFFF)),
				hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(value, 16), 0xFFFF)),
			}
		end,
		fuzz_outputs = function(inputs)
			local value = bitx.bor(bitx.band(inputs.lo, 0xFFFF), bitx.lshift(bitx.band(inputs.hi, 0xFFFF), 16))
			value = (value + 4) % 0x100000000
			return {
				lo = bitx.bor(0x10000000, bitx.band(            value     , 0xFFFF)),
				hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(value, 16), 0xFFFF)),
			}
		end,
	}
end)

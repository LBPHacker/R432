local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module(function(params)
	return {
		tag = "core.alu.bitwise",
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
			{ name = "lhs_lo", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "lhs_hi", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_lo", index = 5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_hi", index = 7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		},
		outputs = {
			{ name = "and_lo", index =  1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "and_hi", index =  3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "or_lo" , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "or_hi" , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "xor_lo", index =  9, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "xor_hi", index = 11, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "eq"    , index = 13, keepalive = 0x10000000, payload = 0x00000001 },
		},
		func = function(inputs)
			local xor2_lo = inputs.lhs_lo:bxor(0x20000000):bxor(inputs.rhs_lo)
			local xor2_hi = inputs.lhs_hi:bxor(0x20000000):bxor(inputs.rhs_hi)
			return {
				and_lo = inputs.lhs_lo:band(inputs.rhs_lo),
				and_hi = inputs.lhs_hi:band(inputs.rhs_hi),
				or_lo  = inputs.lhs_lo:bor (inputs.rhs_lo),
				or_hi  = inputs.lhs_hi:bor (inputs.rhs_hi),
				xor_lo = xor2_lo:bxor(0x30000000),
				xor_hi = xor2_hi:bxor(0x30000000),
				eq     = spaghetti.select(xor2_lo:bor(xor2_hi):bsub(0x20000000):zeroable(), 0x10000000, 0x10000001)
			}
		end,
		fuzz_inputs = function()
			local lhs_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
			local lhs_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
			local rhs_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
			local rhs_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
			if math.random(0, 3) == 0 then
				rhs_lo = lhs_lo
				rhs_hi = lhs_hi
			end
			return {
				lhs_lo = lhs_lo,
				lhs_hi = lhs_hi,
				rhs_lo = rhs_lo,
				rhs_hi = rhs_hi,
			}
		end,
		fuzz_outputs = function(inputs)
			local lhs = bitx.bor(bitx.band(inputs.lhs_lo, 0xFFFF), bitx.lshift(bitx.band(inputs.lhs_hi, 0xFFFF), 16))
			local rhs = bitx.bor(bitx.band(inputs.rhs_lo, 0xFFFF), bitx.lshift(bitx.band(inputs.rhs_hi, 0xFFFF), 16))
			local band = bitx.band(lhs, rhs)
			local bor  = bitx.bor (lhs, rhs)
			local bxor = bitx.bxor(lhs, rhs)
			return {
				and_lo = bitx.bor(0x10000000, bitx.band(            band     , 0xFFFF)),
				and_hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(band, 16), 0xFFFF)),
				or_lo  = bitx.bor(0x10000000, bitx.band(            bor      , 0xFFFF)),
				or_hi  = bitx.bor(0x10000000, bitx.band(bitx.rshift(bor , 16), 0xFFFF)),
				xor_lo = bitx.bor(0x10000000, bitx.band(            bxor     , 0xFFFF)),
				xor_hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(bxor, 16), 0xFFFF)),
				eq     = lhs == rhs and 0x10000001 or 0x10000000
			}
		end,
	}
end)

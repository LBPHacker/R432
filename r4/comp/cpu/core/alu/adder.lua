local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local common    = require("r4.comp.cpu.common")

return testbed.module(function(params)
	return {
		tag = "core.alu.adder",
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
			{ name = "control", index = 1, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 },
			{ name = "lhs_lo" , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "lhs_hi" , index = 5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_lo" , index = 7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_hi" , index = 9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		},
		outputs = {
			{ name = "sum_lo", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "sum_hi", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "lt"    , index = 5, keepalive = 0x10000000, payload = 0x00000001 },
			{ name = "ltu"   , index = 7, keepalive = 0x10000000, payload = 0x00000001 },
		},
		func = function(inputs)
			local sub_mask = spaghetti.lshift(0x3FFFFFFF, inputs.control:bor(0x10000))
			local generate_lo, propagate_lo, onesums_lo = common.ks16(inputs.lhs_lo, inputs.rhs_lo, sub_mask)
			local generate_hi, propagate_hi, onesums_hi = common.ks16(inputs.lhs_hi, inputs.rhs_hi, sub_mask)
			local generate_lo_8 = spaghetti.rshiftk(generate_lo, 8):bor(0x10000000):band(0x1000FFFF)
			local half_carry = spaghetti.rshiftk(generate_lo_8, 7)
			local propagate_hi_cond = propagate_hi:band(spaghetti.lshift(0x3FFFFFFF, half_carry))
			local carries_lo = spaghetti.lshiftk(generate_lo, 1)                                       :assert(0x20000000, 0x0001FFFE)
			local carries_hi = spaghetti.lshiftk(generate_hi:bor(propagate_hi_cond), 1):bor(half_carry):assert(0x20200000, 0x0001FFFF)
			local unsigned_carry = spaghetti.rshiftk(carries_hi, 16):bor(0x10000000):band(0x10000001)
			local signed_carry = spaghetti.rshiftk(carries_hi, 16):bxor(spaghetti.rshiftk(carries_hi, 15)):bor(0x10000000):band(0x10000001)
			return {
				sum_lo = onesums_lo:bor(0x10000000):bxor(carries_lo):band(0x1000FFFF):assert(0x10000000, 0x0000FFFF),
				sum_hi = onesums_hi:bor(0x10000000):bxor(carries_hi):band(0x1000FFFF):assert(0x10000000, 0x0000FFFF),
				lt     = signed_carry,
				ltu    = unsigned_carry,
			}
		end,
		fuzz_inputs = function()
			return {
				control = bitx.bor(math.random(0x0000, 0x0001), 0x10000000),
				lhs_lo  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				lhs_hi  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_lo  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_hi  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
			}
		end,
		fuzz_outputs = function(inputs)
			local sub = bitx.band(inputs.control, 1) == 0
			local lhs = bitx.bor(bitx.band(inputs.lhs_lo, 0xFFFF), bitx.lshift(bitx.band(inputs.lhs_hi, 0xFFFF), 16))
			local rhs = bitx.bor(bitx.band(inputs.rhs_lo, 0xFFFF), bitx.lshift(bitx.band(inputs.rhs_hi, 0xFFFF), 16))
			local slhs = lhs >= 0x80000000 and lhs - 0x100000000 or lhs
			local srhs = rhs >= 0x80000000 and rhs - 0x100000000 or rhs
			local sum, ssum
			if sub then
				sum  = lhs  - rhs
				ssum = slhs - srhs
			else
				sum  = lhs  + rhs
				ssum = slhs + srhs
			end
			local lt = ssum < -0x80000000 or ssum >= 0x80000000
			local ltu = sum < 0 or sum >= 0x100000000
			sum = sum % 0x100000000
			return {
				sum_lo = bitx.bor(0x10000000, bitx.band(            sum     , 0xFFFF)),
				sum_hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(sum, 16), 0xFFFF)),
				lt     = lt and 0x10000001 or 0x10000000,
				ltu    = ltu and 0x10000001 or 0x10000000,
			}
		end,
	}
end)

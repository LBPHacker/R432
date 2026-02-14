local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module(function(params)
	return {
		tag = "alu.shifter",
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
			{ name = "control", index = 1, keepalive = 0x20000000, payload = 0x0001FFFE, initial = 0x20000000 },
			{ name = "lhs_lo" , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "lhs_hi" , index = 5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_lo" , index = 7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		},
		outputs = {
			{ name = "sl_lo", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "sl_hi", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "sr_lo", index = 5, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "sr_hi", index = 7, keepalive = 0x10000000, payload = 0x0000FFFF },
		},
		func = function(inputs)
			local shift_by = spaghetti.constant(1)
			for i = 0, 3 do
				local b = bitx.lshift(1, i)
				local bb = bitx.lshift(1, b)
				shift_by = shift_by:lshift(inputs.rhs_lo:rshift(b):bsub(0xFFFE):bxor(1):bor(bb)):never_zero()
			end
			local shift_by_inv = spaghetti.constant(0x10000):rshift(shift_by):never_zero()
			local ka_r16    = spaghetti.constant(0x10000000):rshift(shift_by):never_zero()
			local ka_l16    = spaghetti.constant(0x10000000):rshift(shift_by_inv):never_zero()
			local sl_lo_l16 = inputs.lhs_lo:bor(ka_r16):lshift(shift_by):never_zero()
			local sl_hi_l16 = inputs.lhs_hi:bor(ka_r16):lshift(shift_by):never_zero()
			local sl_lo_r16 = inputs.lhs_lo:rshift(shift_by_inv):never_zero():bxor(0x30000000):bxor(ka_l16):bxor(0x20000000)
			local sl_hi     = sl_hi_l16:bor(sl_lo_r16):band(0x1000FFFF):force(0x10000000, 0x0000FFFF)
			local sl_lo     = sl_lo_l16               :band(0x1000FFFF):force(0x10000000, 0x0000FFFF)
			local sr_hi_r16 = inputs.lhs_hi:rshift(shift_by):never_zero():bxor(0x30000000):never_zero():bxor(ka_r16):never_zero():bxor(0x20000000):never_zero()
			local sr_lo_r16 = inputs.lhs_lo:rshift(shift_by):never_zero():bxor(0x30000000):never_zero():bxor(ka_r16):never_zero():bxor(0x20000000):never_zero()
			local sr_hi_l16 = inputs.lhs_hi:bor(ka_l16):lshift(shift_by_inv):never_zero()
			local sr_hi     = sr_hi_r16                            :band(0x1000FFFF):force(0x10000000, 0x0000FFFF)
			local sr_lo     = sr_lo_r16:bor(sr_hi_l16):never_zero():band(0x1000FFFF):force(0x10000000, 0x0000FFFF)
			local sx_src    = spaghetti.select(inputs.control:bor(0x10000000):band(inputs.lhs_hi):band(0x8000):zeroable(), 0x1000FFFF, 0x10000000)
			local sx_lo_r16 = sx_src:bor(ka_l16):lshift(shift_by_inv):never_zero()
			local sx_hi     = sx_src:force(0x10000000, 0x0000FFFF)
			local sx_lo     = sx_lo_r16:band(0x1000FFFF):force(0x10000000, 0x0000FFFF)
			sl_lo, sl_hi, sr_lo, sr_hi, sx_lo, sx_hi = spaghetti.select(
				inputs.rhs_lo:band(0x10):zeroable(),
				0x10000000, sl_lo,
				sl_lo, sl_hi,
				sr_hi, sr_lo,
				0x10000000, sr_hi,
				sx_lo, 0x10000000,
				sx_hi, sx_lo
			)
			return {
				sl_lo = sl_lo,
				sl_hi = sl_hi,
				sr_lo = sr_lo:bor(sx_lo),
				sr_hi = sr_hi:bor(sx_hi),
			}
		end,
		fuzz_inputs = function()
			return {
				control = bitx.bor(bitx.lshift(math.random(0x0000, 0xFFFF), 1), 0x20000000),
				lhs_lo  = bitx.bor(            math.random(0x0000, 0xFFFF)    , 0x10000000),
				lhs_hi  = bitx.bor(            math.random(0x0000, 0xFFFF)    , 0x10000000),
				rhs_lo  = bitx.bor(            math.random(0x0000, 0xFFFF)    , 0x10000000),
			}
		end,
		fuzz_outputs = function(inputs)
			local sra = bitx.band(inputs.control, 0x8000) ~= 0
			local lhs   = bitx.bor(bitx.band(inputs.lhs_lo, 0xFFFF), bitx.lshift(bitx.band(inputs.lhs_hi, 0xFFFF), 16))
			local shamt =          bitx.band(inputs.rhs_lo, 0x1F)
			local sl = bitx.lshift(lhs, shamt)
			local sr = bitx.rshift(lhs, shamt)
			if sra then
				sr = bitx.arshift(lhs, shamt)
			end
			return {
				sl_lo = bitx.bor(0x10000000, bitx.band(            sl     , 0xFFFF)),
				sl_hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(sl, 16), 0xFFFF)),
				sr_lo = bitx.bor(0x10000000, bitx.band(            sr     , 0xFFFF)),
				sr_hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(sr, 16), 0xFFFF)),
			}
		end,
	}
end)

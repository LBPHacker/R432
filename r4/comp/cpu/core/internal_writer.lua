local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module(function(params)
	return {
		tag = "core.internal_writer",
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
			{ name = "rs"    , index =  1, keepalive = 0x10000000, payload = 0x0000001F, initial = 0x10000000 },
			{ name = "rs_lo" , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rs_hi" , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rw"    , index =  7, keepalive = 0x10000000, payload = 0x0000001F, initial = 0x10000000 },
			{ name = "rw_lo" , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rw_hi" , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "output", index = 13, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 },
		},
		outputs = {
			{ name = "rs_lo", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "rs_hi", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
		},
		func = function(inputs)
			local rw = inputs.rw:bor(0x1000):lshift(inputs.output:bor(0x10000)):never_zero()
			local rw_lo, rw_hi = spaghetti.select(
				rw:band(0x1F):zeroable(),
				inputs.rw_lo, 0x10000000,
				inputs.rw_hi, 0x10000000
			)
			local rs_lo, rs_hi = spaghetti.select(
				inputs.rs:bor(0x20000000):bxor(rw):band(0x1F):zeroable(),
				inputs.rs_lo, rw_lo,
				inputs.rs_hi, rw_hi
			)
			return {
				rs_lo = rs_lo,
				rs_hi = rs_hi,
			}
		end,
		fuzz_inputs = function()
			local rs     = math.random(0x0000, 0x001F)
			local rs_lo  = math.random(0x0000, 0xFFFF)
			local rs_hi  = math.random(0x0000, 0xFFFF)
			if rs == 0 then
				rs_lo = 0
				rs_hi = 0
			end
			return {
				rs     = bitx.bor(rs   , 0x10000000),
				rs_lo  = bitx.bor(rs_lo, 0x10000000),
				rs_hi  = bitx.bor(rs_hi, 0x10000000),
				rw     = bitx.bor(math.random(0x0000, 0x001F), 0x10000000),
				rw_lo  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rw_hi  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				output = bitx.bor(math.random(0x0000, 0x0001), 0x10000000),
			}
		end,
		fuzz_outputs = function(inputs)
			local rs_lo = inputs.rs_lo
			local rs_hi = inputs.rs_hi
			local rs = bitx.band(inputs.rs, 0x1F)
			local rw = bitx.band(inputs.rw, 0x1F)
			if bitx.band(inputs.output, 1) == 0 then
				rw = 0
			end
			if rs == rw then
				rs_lo = rw == 0 and 0x10000000 or inputs.rw_lo
				rs_hi = rw == 0 and 0x10000000 or inputs.rw_hi
			end
			return {
				rs_lo = rs_lo,
				rs_hi = rs_hi,
			}
		end,
	}
end)

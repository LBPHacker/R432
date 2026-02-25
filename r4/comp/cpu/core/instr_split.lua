local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module(function(params)
	return {
		tag = "core.instr_split",
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
			{ name = "instr", index = 1, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 },
		},
		outputs = {
			{ name = "instr_lo", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "instr_hi", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
		},
		func = function(inputs)
			local instr_lo = inputs.instr:bor(0x10000000):band(0x1000FFFF):force(0x10000000, 0x0000FFFF)
			local instr_hi = spaghetti.rshiftk(spaghetti.rshiftk(inputs.instr:bor(0x100):bsub(0xFF), 8):bor(0x10000000):bsub(0xFF), 8):bor(0x10000000):band(0x1000FFFF)
			return {
				instr_lo = instr_lo,
				instr_hi = instr_hi,
			}
		end,
		fuzz_inputs = function()
			local instr = math.random(0x00000000, 0x7FFFFFFF)
			local border = math.random(0, 31)
			if border < 5 then
				instr = border - 3
				if instr < 0 then
					instr = instr + 0x80000000
				end
			end
			return {
				instr = bitx.bor(bitx.lshift(instr, 1), 1),
			}
		end,
		fuzz_outputs = function(inputs)
			return {
				instr_lo = bitx.bor(bitx.band(            inputs.instr     , 0xFFFF), 0x10000000),
				instr_hi = bitx.bor(bitx.band(bitx.rshift(inputs.instr, 16), 0xFFFF), 0x10000000),
			}
		end,
	}
end)

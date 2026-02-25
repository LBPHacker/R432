local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module(function(params)
	return {
		tag = "core.regs",
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
			{ name = "rs1", index = 1, keepalive = 0x10000000, payload = 0x0000001F },
			{ name = "rs2", index = 3, keepalive = 0x10000000, payload = 0x0000001F },
			{ name = "rd" , index = 5, keepalive = 0x10000000, payload = 0x0000001F },
		},
		func = function(inputs)
			local instr_tame = inputs.instr:bor(0x10000000):bsub(0x80000001):force(0x10000000, 0x6FFFFFFE)
			local rs1 = spaghetti.rshiftk(instr_tame, 15):bor(0x10000000):band(0x1000001F)
			local rs2 = spaghetti.rshiftk(instr_tame, 20):bor(0x10000000):band(0x1000001F)
			local rd  = spaghetti.rshiftk(instr_tame,  7):bor(0x10000000):band(0x1000001F)
			return {
				rs1 = rs1,
				rs2 = rs2,
				rd  = spaghetti.select(inputs.instr:bxor(0x10):band(0x50):zeroable(), 0x10000000, rd),
			}
		end,
		fuzz_inputs = function()
			return {
				instr = bitx.bor(bitx.lshift(math.random(0x00000000, 0x3FFFFFFF), 2), 3),
			}
		end,
		fuzz_outputs = function(inputs)
			local writes_reg = bitx.band(inputs.instr, 0x00000050) == 0x00000010
			local rs1 = bitx.band(bitx.rshift(inputs.instr, 15), 0x1F)
			local rs2 = bitx.band(bitx.rshift(inputs.instr, 20), 0x1F)
			local rd  = bitx.band(bitx.rshift(inputs.instr,  7), 0x1F)
			return {
				rs1 = bitx.bor(0x10000000, rs1),
				rs2 = bitx.bor(0x10000000, rs2),
				rd  = bitx.bor(0x10000000, writes_reg and rd or 0),
			}
		end,
	}
end)

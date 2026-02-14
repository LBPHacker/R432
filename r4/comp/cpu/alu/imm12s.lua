local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module(function(params)
	return {
		tag = "alu.imm12s",
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
			{ name = "instr_hi", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		},
		outputs = {
			{ name = "imm12s_lo", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "imm12s_hi", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
		},
		func = function(inputs)
			local instr_imm = spaghetti.rshiftk(inputs.instr_hi, 4):assert(0x01000000, 0x00000FFF)
			local sx = spaghetti.select(inputs.instr_hi:band(0x8000):zeroable(), 0x1000FFFF, 0x10000000)
			return {
				imm12s_lo = sx:band(0x1000F000):bor(instr_imm):band(0x1000FFFF),
				imm12s_hi = sx,
			}
		end,
		fuzz_inputs = function()
			return {
				instr_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
			}
		end,
		fuzz_outputs = function(inputs)
			local imm12s = bitx.arshift(bitx.lshift(inputs.instr_hi, 16), 20)
			return {
				imm12s_lo = bitx.bor(0x10000000, bitx.band(            imm12s     , 0xFFFF)),
				imm12s_hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(imm12s, 16), 0xFFFF)),
			}
		end,
	}
end)

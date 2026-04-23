local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local util      = require("r4.comp.cpu.common")

return testbed.module(function(params)
	return {
		tag = "core.cbranch",
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
			{ name = "instr_lo", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "lt"      , index = 3, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 },
			{ name = "ltu"     , index = 5, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 },
			{ name = "eq"      , index = 7, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 },
		},
		outputs = {
			{ name = "taken", index = 1, keepalive = 0x10000000, payload = 0x00000001 },
		},
		func = function(inputs)
			local instr_branch = util.match_instr(inputs.instr_lo, 0x005C, 0x0040)
			local instr_invert = util.match_instr(inputs.instr_lo, 0x1000, 0x0000)
			local instr_lt     = util.match_instr(inputs.instr_lo, 0x2000, 0x0000)
			local instr_eq     = util.match_instr(inputs.instr_lo, 0x4000, 0x0000)
			local holds = spaghetti.select(
				instr_eq:band(1):zeroable(),
				spaghetti.select(
					instr_lt:band(1):zeroable(),
					inputs.ltu,
					inputs.lt
				),
				inputs.eq
			):bxor(instr_invert)
			return {
				taken = holds:bsub(instr_branch):bor(0x10000000):band(0x10000001)
			}
		end,
		fuzz_inputs = function()
			return {
				instr_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				lt       = bitx.bor(math.random(0x0000, 0x0001), 0x10000000),
				ltu      = bitx.bor(math.random(0x0000, 0x0001), 0x10000000),
				eq       = bitx.bor(math.random(0x0000, 0x0001), 0x10000000),
			}
		end,
		fuzz_outputs = function(inputs)
			local binstr = bitx.band(inputs.instr_lo, 0x005C) == 0x0040
			local conds = {
				[ 0 ] = inputs.eq,
				[ 1 ] = inputs.eq,
				[ 2 ] = inputs.lt,
				[ 3 ] = inputs.ltu,
			}
			local holds = bitx.band(conds[bitx.band(bitx.rshift(inputs.instr_lo, 13), 3)], 1) ~= 0
			if bitx.band(inputs.instr_lo, 0x1000) ~= 0 then
				holds = not holds
			end
			return {
				taken = binstr and holds and 0x10000001 or 0x10000000,
			}
		end,
	}
end)

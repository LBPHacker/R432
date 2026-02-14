local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

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
			local instr_2  = spaghetti.rshiftk(inputs.instr_lo, 2)
			local instr_3  = spaghetti.rshiftk(inputs.instr_lo, 3)
			local instr_4  = spaghetti.rshiftk(inputs.instr_lo, 4)
			local instr_6  = spaghetti.rshiftk(inputs.instr_lo, 6)
			local instr_6i = instr_6:bxor(1)
			local instr_12 = spaghetti.rshiftk(inputs.instr_lo, 12)
			local instr_13 = spaghetti.rshiftk(instr_12, 1)
			local instr_14 = spaghetti.rshiftk(instr_12, 2)
			local instr_branch = instr_2:bor(instr_3):bor(instr_4):bor(instr_6i)
			local holds = spaghetti.select(
				instr_14:band(1):zeroable(),
				spaghetti.select(
					instr_13:band(1):zeroable(),
					inputs.ltu,
					inputs.lt
				),
				inputs.eq
			):bxor(instr_12)
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

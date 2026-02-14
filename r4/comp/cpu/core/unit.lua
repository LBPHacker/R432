local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local alu       = require("r4.comp.cpu.alu")         .instantiate()
local cbranch   = require("r4.comp.cpu.core.cbranch").instantiate()
local incr32    = require("r4.comp.cpu.core.incr32") .instantiate()

return testbed.module(function(params)
	return {
		tag = "core.head",
		opt_params = {
			thread_count  = 1,
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			round_length  = 10000,
		},
		stacks        = 2,
		storage_slots = 70,
		work_slots    = 30,
		inputs = {
			{ name = "lhs_lo"  , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "lhs_hi"  , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_lo"  , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_hi"  , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pc_lo"   , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pc_hi"   , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "defer"   , index = 13, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 },
			{ name = "instr"   , index = 15, keepalive = 0x00000003, payload = 0xFFFFFFFC, initial = 0x00000001 },
		},
		outputs = {
			{ name = "res_lo", index =  1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "res_hi", index =  3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "pc_lo" , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "pc_hi" , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "defer" , index = 13, keepalive = 0x10000000, payload = 0x00000001 },
			{ name = "output", index = 15, keepalive = 0x10000000, payload = 0x00000001 },
		},
		func = function(inputs)
			local instr_lo = inputs.instr:bor(0x10000000):band(0x1000FFFF):force(0x10000000, 0x0000FFFF)
			local instr_hi = spaghetti.rshiftk(spaghetti.rshiftk(inputs.instr:bor(0x100):bsub(0xFF), 8):bor(0x10000000):bsub(0xFF), 8):bor(0x10000000):band(0x1000FFFF)
			local instr_2   = spaghetti.rshiftk(instr_lo, 2)
			local instr_3   = spaghetti.rshiftk(instr_lo, 3)
			local instr_4   = spaghetti.rshiftk(instr_lo, 4)
			local instr_4i  = instr_4:bxor(1)
			local instr_5   = spaghetti.rshiftk(instr_lo, 5)
			local instr_5i  = instr_5:bxor(1)
			local instr_6   = spaghetti.rshiftk(instr_lo, 6)
			local instr_6i  = instr_6:bxor(1)
			local instr_25  = spaghetti.rshiftk(instr_hi, 9)
			local instr_25i = instr_25:bxor(1)
			local instr_output = instr_4i:bor(instr_6)
			local instr_mem  = instr_4:bor(instr_6)
			local instr_mul  = instr_2:bor(instr_4i):bor(instr_5i):bor(instr_6):bor(instr_25i)
			local instr_hltj = instr_2:bor(instr_3):bor(instr_4):bxor(1):bor(instr_6i)
			local alu_outputs = alu.component({
				lhs_lo   = inputs.lhs_lo,
				lhs_hi   = inputs.lhs_hi,
				rhs_lo   = inputs.rhs_lo,
				rhs_hi   = inputs.rhs_hi,
				pc_lo    = inputs.pc_lo,
				pc_hi    = inputs.pc_hi,
				instr_lo = instr_lo,
				instr_hi = instr_hi,
			})
			local cbranch_outputs = cbranch.component({
				instr_lo = instr_lo,
				lt       = alu_outputs.lt,
				ltu      = alu_outputs.ltu,
				eq       = alu_outputs.eq,
			})
			local defer = inputs.defer:bor(cbranch_outputs.taken)
				:bor(instr_mem:bxor(1))
				:bor(instr_mul:bxor(1))
				:bor(instr_hltj:bxor(1)):band(0x10000001)
			local output = defer:bxor(1):bsub(instr_output)
			local incr32_outputs = incr32.component({
				lo = inputs.pc_lo,
				hi = inputs.pc_hi,
			})
			local pc_lo, pc_hi = spaghetti.select(
				defer:band(1):zeroable(),
				inputs.pc_lo, incr32_outputs.lo,
				inputs.pc_hi, incr32_outputs.hi
			)
			return {
				res_lo = alu_outputs.res_lo,
				res_hi = alu_outputs.res_hi,
				pc_lo  = pc_lo,
				pc_hi  = pc_hi,
				defer  = defer,
				output = output,
			}
		end,
		fuzz_inputs = function()
			return {
				lhs_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				lhs_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_lo  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_hi  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				instr  = bitx.bor(bitx.lshift(math.random(0x00000000, 0x3FFFFFFF), 2), 3),
				defer  = bitx.bor(math.random(0x0000, 0x0001), 0x10000000),
			}
		end,
		fuzz_outputs = function(inputs)
			local instr_lo = bitx.band(            inputs.instr     , 0xFFFF)
			local instr_hi = bitx.band(bitx.rshift(inputs.instr, 16), 0xFFFF)
			local instr_mem  = bitx.band(instr_lo, 0x0050) == 0x0000
			local instr_mul  = bitx.band(instr_lo, 0x0074) == 0x0030 and bitx.band(instr_hi, 0x0200) == 0x0200
			local instr_jalr = bitx.band(instr_lo, 0x005C) == 0x0044
			local instr_jal  = bitx.band(instr_lo, 0x0058) == 0x0048
			local instr_hlt  = bitx.band(instr_lo, 0x0050) == 0x0050
			local defer = bitx.band(inputs.defer, 1) ~= 0 or
			              instr_mem or
			              instr_mul or
			              instr_jalr or
			              instr_jal or
			              instr_hlt
			local output = bitx.band(instr_lo, 0x0050) == 0x0010
			local pc = bitx.bor(bitx.band(inputs.pc_lo, 0xFFFF), bitx.lshift(bitx.band(inputs.pc_hi, 0xFFFF), 16))
			local alu_outputs, err = alu.fuzz_outputs({
				lhs_lo   = inputs.lhs_lo,
				lhs_hi   = inputs.lhs_hi,
				rhs_lo   = inputs.rhs_lo,
				rhs_hi   = inputs.rhs_hi,
				pc_lo    = inputs.pc_lo,
				pc_hi    = inputs.pc_hi,
				instr_lo = bitx.bor(instr_lo, 0x10000000),
				instr_hi = bitx.bor(instr_hi, 0x10000000),
			})
			if not alu_outputs then
				return nil, "alu: " .. err
			end
			local cbranch_outputs, err = cbranch.fuzz_outputs({
				instr_lo = bitx.bor(instr_lo, 0x10000000),
				lt       = alu_outputs.lt,
				ltu      = alu_outputs.ltu,
				eq       = alu_outputs.eq,
			})
			if not cbranch_outputs then
				return nil, "cbranch: " .. err
			end
			local cbranch_taken = bitx.band(cbranch_outputs.taken, 1) ~= 0
			if cbranch_taken then
				defer = true
			end
			if not defer then
				pc = (pc + 1) % 0x100000000
			end
			if defer then
				output = false
			end
			return {
				res_lo = alu_outputs.res_lo,
				res_hi = alu_outputs.res_hi,
				pc_lo  = bitx.bor(0x10000000, bitx.band(            pc     , 0xFFFF)),
				pc_hi  = bitx.bor(0x10000000, bitx.band(bitx.rshift(pc, 16), 0xFFFF)),
				output = output and 0x10000001 or 0x10000000,
				defer  = defer and 0x10000001 or 0x10000000,
			}
		end,
	}
end)

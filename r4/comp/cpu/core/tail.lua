local spaghetti   = require("spaghetti")
local bitx        = require("spaghetti.bitx")
local testbed     = require("spaghetti.testbed")
local unit        = require("r4.comp.cpu.core.unit")
local instr_split = require("r4.comp.cpu.core.instr_split").instantiate()
local address     = require("r4.comp.cpu.core.address")    .instantiate()
local regs        = require("r4.comp.cpu.core.regs")       .instantiate()

return testbed.module(function(params)
	local unit_last = unit.instantiate({ unit_type = "l" }, "?")

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
		storage_slots = 90,
		work_slots    = 30,
		inputs = {
			{ name = "pc_lo"   , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pc_hi"   , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "shutdown", index =  5, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 },
			{ name = "start"   , index =  7, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 },
			{ name = "lhs_lo"  , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "lhs_hi"  , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_lo"  , index = 13, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_hi"  , index = 15, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "instr"   , index = 17, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 },
		},
		outputs = {
			{ name = "pc_lo"   , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "pc_hi"   , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "shutdown", index =  5, keepalive = 0x10000000, payload = 0x00000001 },
			{ name = "res_lo"  , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "res_hi"  , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "res_rd"  , index = 11, keepalive = 0x10000000, payload = 0x0000001F },
			{ name = "addr_lo" , index = 13, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "addr_hi" , index = 15, keepalive = 0x10000000, payload = 0x0000FFFF },
		},
		func = function(inputs)
			local instr_split_outputs = instr_split.component({
				instr = inputs.instr,
			})
			local regs_outputs = regs.component({
				instr = inputs.instr,
			})
			local instr_2    = spaghetti.rshiftk(instr_split_outputs.instr_lo, 2)
			local instr_2i   = instr_2:bxor(1)
			local instr_3    = spaghetti.rshiftk(instr_split_outputs.instr_lo, 3)
			local instr_3i   = instr_3:bxor(1)
			local instr_4    = spaghetti.rshiftk(instr_split_outputs.instr_lo, 4)
			local instr_4i   = instr_4:bxor(1)
			local instr_6    = spaghetti.rshiftk(instr_split_outputs.instr_lo, 6)
			local instr_6i   = instr_6:bxor(1)
			local instr_hlt  = instr_6i:bor(instr_4i)
			local instr_jal  = instr_6i:bor(instr_4):bor(instr_3i)
			local instr_jalr = instr_6i:bor(instr_4):bor(instr_3):bor(instr_2i)
			local unit_outputs = unit_last.component({
				lhs_lo   = inputs.lhs_lo,
				lhs_hi   = inputs.lhs_hi,
				rhs_lo   = inputs.rhs_lo,
				rhs_hi   = inputs.rhs_hi,
				pc_lo    = inputs.pc_lo,
				pc_hi    = inputs.pc_hi,
				defer    = inputs.shutdown,
				instr    = inputs.instr,
				instr_lo = instr_split_outputs.instr_lo,
				instr_hi = instr_split_outputs.instr_hi,
			})
			local address_outputs = address.component({
				instr_lo = instr_split_outputs.instr_lo,
				instr_hi = instr_split_outputs.instr_hi,
				lhs_lo   = inputs.lhs_lo,
				lhs_hi   = inputs.lhs_hi,
				pc_lo    = inputs.pc_lo,
				pc_hi    = inputs.pc_hi,
			})
			local pc_lo, pc_hi = spaghetti.select(
				unit_outputs.taken:bor(instr_jalr:bxor(1)):band(1):zeroable(),
				address_outputs.sum_lo, unit_outputs.pc_lo,
				address_outputs.sum_hi, unit_outputs.pc_hi
			)
			pc_lo, pc_hi = spaghetti.select(
				instr_jal:band(1):zeroable(),
				pc_lo, unit_outputs.jal_lo,
				pc_hi, unit_outputs.jal_hi
			)
			return {
				pc_lo    = pc_lo,
				pc_hi    = pc_hi,
				shutdown = inputs.shutdown:bor(instr_hlt:bxor(1)):bsub(inputs.start):bor(0x10000000):band(0x10000001),
				res_lo   = unit_outputs.res_lo,
				res_hi   = unit_outputs.res_hi,
				res_rd   = spaghetti.select(unit_outputs.output:band(1):zeroable(), regs_outputs.rd, 0x10000000),
				addr_lo  = address_outputs.sum_lo,
				addr_hi  = address_outputs.sum_hi,
			}
		end,
		fuzz_inputs = function()
			return {
				pc_lo    = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_hi    = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				shutdown = bitx.bor(math.random(0x0000, 0x0001), 0x10000000),
				start    = bitx.bor(math.random(0x0000, 0x0001), 0x10000000),
				lhs_lo   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				lhs_hi   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_lo   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_hi   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				instr    = bitx.bor(bitx.lshift(math.random(0x00000000, 0x7FFFFFFF), 1), 1),
			}
		end,
		fuzz_outputs = function(inputs)
			local instr_split_outputs, err = instr_split.fuzz_outputs({
				instr = inputs.instr,
			})
			if not instr_split_outputs then
				return nil, "instr_split: " .. err
			end
			local regs_outputs, err = regs.fuzz_outputs({
				instr = inputs.instr,
			})
			if not regs_outputs then
				return nil, "regs: " .. err
			end
			local instr_hlt  = bitx.band(instr_split_outputs.instr_lo, 0x0050) == 0x0050
			local instr_jal  = bitx.band(instr_split_outputs.instr_lo, 0x0058) == 0x0048
			local instr_jalr = bitx.band(instr_split_outputs.instr_lo, 0x005C) == 0x0044
			local defer = inputs.shutdown
			local unit_outputs, err = unit_last.fuzz_outputs({
				lhs_lo   = inputs.lhs_lo,
				lhs_hi   = inputs.lhs_hi,
				rhs_lo   = inputs.rhs_lo,
				rhs_hi   = inputs.rhs_hi,
				pc_lo    = inputs.pc_lo,
				pc_hi    = inputs.pc_hi,
				defer    = defer,
				instr    = inputs.instr,
				instr_lo = instr_split_outputs.instr_lo,
				instr_hi = instr_split_outputs.instr_hi,
			})
			if not unit_outputs then
				return nil, "unit: " .. err
			end
			local address_outputs, err = address.fuzz_outputs({
				instr_lo = instr_split_outputs.instr_lo,
				instr_hi = instr_split_outputs.instr_hi,
				lhs_lo   = inputs.lhs_lo,
				lhs_hi   = inputs.lhs_hi,
				pc_lo    = inputs.pc_lo,
				pc_hi    = inputs.pc_hi,
			})
			if not address_outputs then
				return nil, "address: " .. err
			end
			local pc_lo = unit_outputs.pc_lo
			local pc_hi = unit_outputs.pc_hi
			local branch_lo = instr_jal and unit_outputs.jal_lo or address_outputs.sum_lo
			local branch_hi = instr_jal and unit_outputs.jal_hi or address_outputs.sum_hi
			local cbranch_taken = bitx.band(unit_outputs.taken, 1) ~= 0
			if cbranch_taken or instr_jal or instr_jalr then
				pc_lo = branch_lo
				pc_hi = branch_hi
			end
			local shutdown = bitx.band(inputs.shutdown, 1) ~= 0
			if instr_hlt then
				shutdown = true
			end
			if bitx.band(inputs.start, 1) ~= 0 then
				shutdown = false
			end
			return {
				pc_lo    = pc_lo,
				pc_hi    = pc_hi,
				shutdown = shutdown and 0x10000001 or 0x10000000,
				res_lo   = unit_outputs.res_lo,
				res_hi   = unit_outputs.res_hi,
				res_rd   = bitx.band(unit_outputs.output, 1) ~= 0 and regs_outputs.rd or 0x10000000,
				addr_lo  = address_outputs.sum_lo,
				addr_hi  = address_outputs.sum_hi,
			}
		end,
	}
end)

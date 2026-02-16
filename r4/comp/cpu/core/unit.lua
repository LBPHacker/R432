local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local check     = require("spaghetti.check")
local alu       = require("r4.comp.cpu.alu")
local cbranch   = require("r4.comp.cpu.core.cbranch").instantiate()
local incr_pc   = require("r4.comp.cpu.core.incr_pc").instantiate()

return testbed.module(function(params, params_name)
	check.one_of(params_name .. ".unit_type", params.unit_type, { "f", "m", "l" })
	local has_defer_in = params.unit_type == "m"
	local has_jal      = params.unit_type == "l"

	local alu_instance = alu.instantiate(params, params_name)

	local inputs = {
		{ name = "lhs_lo"  , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "lhs_hi"  , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "rhs_lo"  , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "rhs_hi"  , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "pc_lo"   , index =  9, keepalive = 0x10000000, payload = 0x0000FFFC, initial = 0x10000000 },
		{ name = "pc_hi"   , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "instr"   , index = 15, keepalive = 0x00000003, payload = 0xFFFFFFFC, initial = 0x00000001 },
		{ name = "instr_lo", index = 27, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "instr_hi", index = 29, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	}
	local outputs = {
		{ name = "res_lo", index =  1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "res_hi", index =  3, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "pc_lo" , index =  5, keepalive = 0x10000000, payload = 0x0000FFFC },
		{ name = "pc_hi" , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "defer" , index =  9, keepalive = 0x10000000, payload = 0x00000001 },
		{ name = "output", index = 11, keepalive = 0x10000000, payload = 0x00000001 },
		{ name = "taken" , index = 23, keepalive = 0x10000000, payload = 0x00000001 },
	}
	if has_defer_in then
		table.insert(inputs, { name = "defer", index = 13, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 })
	end
	if has_jal then
		table.insert(outputs, { name = "jal_lo", index = 25, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "jal_hi", index = 27, keepalive = 0x10000000, payload = 0x0000FFFF })
	else
		table.insert(inputs, { name = "next_lhs_lo", index = 17, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs, { name = "next_lhs_hi", index = 19, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs, { name = "next_rhs_lo", index = 21, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs, { name = "next_rhs_hi", index = 23, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs, { name = "next_instr" , index = 25, keepalive = 0x00000003, payload = 0xFFFFFFFC, initial = 0x00000001 })
		table.insert(outputs, { name = "next_lhs_lo", index = 13, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "next_lhs_hi", index = 15, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "next_rhs_lo", index = 17, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "next_rhs_hi", index = 19, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "next_instr" , index = 21, keepalive = 0x00000003, payload = 0xFFFFFFFC })
	end
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
		storage_slots = 80,
		work_slots    = 30,
		inputs = inputs,
		outputs = outputs,
		func = function(inputs)
			local instr_2   = spaghetti.rshiftk(inputs.instr_lo, 2)
			local instr_3   = spaghetti.rshiftk(inputs.instr_lo, 3)
			local instr_4   = spaghetti.rshiftk(inputs.instr_lo, 4)
			local instr_4i  = instr_4:bxor(1)
			local instr_5   = spaghetti.rshiftk(inputs.instr_lo, 5)
			local instr_5i  = instr_5:bxor(1)
			local instr_6   = spaghetti.rshiftk(inputs.instr_lo, 6)
			local instr_6i  = instr_6:bxor(1)
			local instr_25  = spaghetti.rshiftk(inputs.instr_hi, 9)
			local instr_25i = instr_25:bxor(1)
			local instr_output = instr_4i:bor(instr_6)
			local instr_mem  = instr_4:bor(instr_6)
			local instr_mul  = instr_2:bor(instr_4i):bor(instr_5i):bor(instr_6):bor(instr_25i)
			local instr_hltj = instr_2:bor(instr_3):bor(instr_4):bxor(1):bor(instr_6i)
			local jaloff_lo, jaloff_hi
			if has_jal then
				local stretch_0 = inputs.instr_lo:band(0x1000F000)
				local stretch_1 = inputs.instr_hi:band(0x1000000F)
				local stretch_2 = spaghetti.lshiftk(spaghetti.rshiftk(inputs.instr_hi, 15)                          ,  4):assert(0x00020000, 0x00000010)
				local stretch_3 = spaghetti.lshiftk(spaghetti.rshiftk(inputs.instr_hi,  5):bsub(0x400 )             ,  1):assert(0x01000000, 0x000007FE)
				local stretch_4 = spaghetti.lshiftk(spaghetti.rshiftk(inputs.instr_hi,  4):bsub(0xFFFE):bor(0x10000), 11):assert(0x08000000, 0x00000800)
				jaloff_lo = stretch_0:bor(stretch_3):bor(stretch_4):band(0x1000FFFF)
				jaloff_hi = stretch_1:bor(stretch_2):band(0x1000FFFF)
				jaloff_hi = jaloff_hi:bor(spaghetti.select(jaloff_hi:band(0x10):zeroable(), 0x1000FFE0, 0x10000000))
			end
			local alu_outputs = alu_instance.component({
				lhs_lo    = inputs.lhs_lo,
				lhs_hi    = inputs.lhs_hi,
				rhs_lo    = inputs.rhs_lo,
				rhs_hi    = inputs.rhs_hi,
				pc_lo     = inputs.pc_lo,
				pc_hi     = inputs.pc_hi,
				instr_lo  = inputs.instr_lo,
				instr_hi  = inputs.instr_hi,
				jaloff_lo = jaloff_lo,
				jaloff_hi = jaloff_hi,
			})
			local cbranch_outputs = cbranch.component({
				instr_lo = inputs.instr_lo,
				lt       = alu_outputs.lt,
				ltu      = alu_outputs.ltu,
				eq       = alu_outputs.eq,
			})
			local defer = cbranch_outputs.taken
			if has_defer_in then
				defer = defer:bor(inputs.defer)
			end
			defer = defer:bor(instr_mem:bxor(1))
			             :bor(instr_mul:bxor(1))
			             :bor(instr_hltj:bxor(1)):band(0x10000001)
			local output = defer:bxor(1):bsub(instr_output)
			local incr_pc_outputs = incr_pc.component({
				lo = inputs.pc_lo,
				hi = inputs.pc_hi,
			})
			local pc_lo, pc_hi, next_instr, next_lhs_lo, next_lhs_hi, next_rhs_lo, next_rhs_hi
			if has_jal then
				pc_lo, pc_hi = spaghetti.select(
					defer:band(1):zeroable(),
					inputs.pc_lo , incr_pc_outputs.lo,
					inputs.pc_hi , incr_pc_outputs.hi
				)
			else
				pc_lo, pc_hi, next_instr, next_lhs_lo, next_lhs_hi, next_rhs_lo, next_rhs_hi = spaghetti.select(
					defer:band(1):zeroable(),
					inputs.pc_lo , incr_pc_outputs.lo,
					inputs.pc_hi , incr_pc_outputs.hi,
					inputs.instr , inputs.next_instr,
					inputs.lhs_lo, inputs.next_lhs_lo,
					inputs.lhs_hi, inputs.next_lhs_hi,
					inputs.rhs_lo, inputs.next_rhs_lo,
					inputs.rhs_hi, inputs.next_rhs_hi
				)
			end
			return {
				res_lo      = alu_outputs.res_lo,
				res_hi      = alu_outputs.res_hi,
				pc_lo       = pc_lo,
				pc_hi       = pc_hi,
				defer       = defer,
				output      = output,
				next_lhs_lo = next_lhs_lo,
				next_lhs_hi = next_lhs_hi,
				next_rhs_lo = next_rhs_lo,
				next_rhs_hi = next_rhs_hi,
				next_instr  = next_instr,
				jal_lo      = alu_outputs.jal_lo,
				jal_hi      = alu_outputs.jal_hi,
				taken       = cbranch_outputs.taken,
			}
		end,
		fuzz_inputs = function()
			local instr = bitx.bor(bitx.lshift(math.random(0x00000000, 0x3FFFFFFF), 2), 3)
			local instr_lo = bitx.band(            instr     , 0xFFFF)
			local instr_hi = bitx.band(bitx.rshift(instr, 16), 0xFFFF)
			local inputs = {
				lhs_lo      = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				lhs_hi      = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_lo      = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_hi      = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_lo       = bitx.bor(bitx.lshift(math.random(0x0000, 0x3FFF), 2), 0x10000000),
				pc_hi       = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				instr       = instr,
				instr_lo    = bitx.bor(instr_lo, 0x10000000),
				instr_hi    = bitx.bor(instr_hi, 0x10000000),
				defer       = has_defer_in and bitx.bor(math.random(0x0000, 0x0001), 0x10000000) or nil,
			}
			if not has_jal then
				inputs.next_lhs_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs.next_lhs_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs.next_rhs_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs.next_rhs_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs.next_instr  = bitx.bor(bitx.lshift(math.random(0x00000000, 0x3FFFFFFF), 2), 3)
			end
			return inputs
		end,
		fuzz_outputs = function(inputs)
			local instr_mem  = bitx.band(inputs.instr_lo, 0x0050) == 0x0000
			local instr_mul  = bitx.band(inputs.instr_lo, 0x0074) == 0x0030 and bitx.band(inputs.instr_hi, 0x0200) == 0x0200
			local instr_jalr = bitx.band(inputs.instr_lo, 0x005C) == 0x0044
			local instr_jal  = bitx.band(inputs.instr_lo, 0x0058) == 0x0048
			local instr_hlt  = bitx.band(inputs.instr_lo, 0x0050) == 0x0050
			local defer = instr_mem or
			              instr_mul or
			              instr_jalr or
			              instr_jal or
			              instr_hlt
			if has_defer_in then
				defer = defer or bitx.band(inputs.defer, 1) ~= 0
			end
			local output = bitx.band(inputs.instr_lo, 0x0050) == 0x0010
			local pc = bitx.bor(bitx.band(inputs.pc_lo, 0xFFFF), bitx.lshift(bitx.band(inputs.pc_hi, 0xFFFF), 16))
			local jaloff_lo, jaloff_hi
			if has_jal then
				local jaloff = bitx.bor(bitx.lshift(bitx.band(bitx.rshift(inputs.instr, 12), 0x000000FF), 12),
				                        bitx.lshift(bitx.band(bitx.rshift(inputs.instr, 20), 0x00000001), 11),
				                        bitx.lshift(bitx.band(bitx.rshift(inputs.instr, 21), 0x000003FF),  1),
				                        bitx.lshift(bitx.band(bitx.rshift(inputs.instr, 31), 0x00000001), 20))
				jaloff = bitx.arshift(bitx.lshift(jaloff, 11), 11)
				jaloff_lo = bitx.bor(0x10000000, bitx.band(            jaloff     , 0xFFFF))
				jaloff_hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(jaloff, 16), 0xFFFF))
			end
			local alu_outputs, err = alu_instance.fuzz_outputs({
				lhs_lo    = inputs.lhs_lo,
				lhs_hi    = inputs.lhs_hi,
				rhs_lo    = inputs.rhs_lo,
				rhs_hi    = inputs.rhs_hi,
				pc_lo     = inputs.pc_lo,
				pc_hi     = inputs.pc_hi,
				instr_lo  = bitx.bor(inputs.instr_lo, 0x10000000),
				instr_hi  = bitx.bor(inputs.instr_hi, 0x10000000),
				jaloff_lo = jaloff_lo,
				jaloff_hi = jaloff_hi,
			})
			if not alu_outputs then
				return nil, "alu: " .. err
			end
			local cbranch_outputs, err = cbranch.fuzz_outputs({
				instr_lo = bitx.bor(inputs.instr_lo, 0x10000000),
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
			local next_lhs_lo = inputs.lhs_lo
			local next_lhs_hi = inputs.lhs_hi
			local next_rhs_lo = inputs.rhs_lo
			local next_rhs_hi = inputs.rhs_hi
			local next_instr  = inputs.instr
			if not defer then
				next_lhs_lo = inputs.next_lhs_lo
				next_lhs_hi = inputs.next_lhs_hi
				next_rhs_lo = inputs.next_rhs_lo
				next_rhs_hi = inputs.next_rhs_hi
				next_instr  = inputs.next_instr
				pc = (pc + 4) % 0x100000000
			end
			if defer then
				output = false
			end
			return {
				res_lo      = alu_outputs.res_lo,
				res_hi      = alu_outputs.res_hi,
				pc_lo       = bitx.bor(0x10000000, bitx.band(            pc     , 0xFFFF)),
				pc_hi       = bitx.bor(0x10000000, bitx.band(bitx.rshift(pc, 16), 0xFFFF)),
				output      = output and 0x10000001 or 0x10000000,
				defer       = defer and 0x10000001 or 0x10000000,
				next_lhs_lo = not has_jal and next_lhs_lo or nil,
				next_lhs_hi = not has_jal and next_lhs_hi or nil,
				next_rhs_lo = not has_jal and next_rhs_lo or nil,
				next_rhs_hi = not has_jal and next_rhs_hi or nil,
				next_instr  = not has_jal and next_instr  or nil,
				jal_lo      = alu_outputs.jal_lo,
				jal_hi      = alu_outputs.jal_hi,
				taken       = cbranch_outputs.taken,
			}
		end,
	}
end)

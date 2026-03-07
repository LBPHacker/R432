local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local check     = require("spaghetti.check")
local alu       = require("r4.comp.cpu.core.alu")
local cbranch   = require("r4.comp.cpu.core.cbranch").instantiate()
local incr_pc   = require("r4.comp.cpu.core.incr_pc").instantiate()
local regs      = require("r4.comp.cpu.core.regs")   .instantiate()

return testbed.module(function(params, params_name)
	check.one_of(params_name .. ".unit_type", params.unit_type, { "f", "m", "l" })
	local has_prev_mul = params.unit_type == "f"
	local has_jal = params.unit_type == "l"

	local alu_instance = alu.instantiate(params, params_name)

	local inputs = {
		{ name = "lhs_lo"  , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "lhs_hi"  , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "rhs_lo"  , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "rhs_hi"  , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "pc_lo"   , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "pc_hi"   , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "defer"   , index = 13, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 },
		{ name = "instr_lo", index = 27, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "instr_hi", index = 29, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	}
	local outputs = {
		{ name = "res_lo", index =  1, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "res_hi", index =  3, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "pc_lo" , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "pc_hi" , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "output", index = 11, keepalive = 0x10000000, payload = 0x00000001 },
		{ name = "taken" , index = 23, keepalive = 0x10000000, payload = 0x00000001 },
	}
	if has_prev_mul then
		table.insert(inputs, { name = "instr_prev" , index = 31, keepalive = 0x00000009, payload = 0xFFFFFFF6, initial = 0x00000009 })
		table.insert(inputs, { name = "mul_prev_lo", index = 33, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs, { name = "mul_prev_hi", index = 35, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
	end
	if has_jal then
		table.insert(outputs, { name = "jal_lo"     , index = 25, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "jal_hi"     , index = 27, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "mul_control", index = 29, keepalive = 0x10000000, payload = 0x00000007 })
	else
		table.insert(inputs, { name = "instr"      , index = 15, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 })
		table.insert(inputs, { name = "next_lhs_lo", index = 17, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs, { name = "next_lhs_hi", index = 19, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs, { name = "next_rhs_lo", index = 21, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs, { name = "next_rhs_hi", index = 23, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs, { name = "next_instr" , index = 25, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 })
		table.insert(outputs, { name = "next_lhs_lo", index = 13, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "next_lhs_hi", index = 15, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "next_rhs_lo", index = 17, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "next_rhs_hi", index = 19, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "next_instr" , index = 21, keepalive = 0x00000001, payload = 0xFFFFFFFE })
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
		storage_slots = 85,
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
			local instr_26  = spaghetti.rshiftk(inputs.instr_hi, 10)
			local instr_output = instr_4i:bor(instr_6)
			local instr_mem  = instr_4:bor(instr_6)
			local instr_mul  = instr_2:bor(instr_4i):bor(instr_5i):bor(instr_6):bor(instr_25i):bor(instr_26)
			local instr_hltj = instr_2:bor(instr_3):bor(instr_4):bxor(1):bor(instr_6i)
			local instr_j    = instr_2:bor(instr_3):bxor(1):bor(instr_4):bor(instr_6i)
			local instr_l    = instr_6:bor(instr_5):bor(instr_4):bor(instr_2)
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
			local incr_pc_outputs = incr_pc.component({
				lo = inputs.pc_lo,
				hi = inputs.pc_hi,
			})
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
			local defer = inputs.defer
			local defer_mul = instr_mul
			if has_prev_mul then
				local regs_outputs_prev = regs.component({
					instr = inputs.instr_prev:bsub(8):relax_payload(0xFFFFFFFE),
				})
				local same
				do
					local instr_diff = inputs.instr:bsub(8):bxor(inputs.instr_prev)
					local same_15 = spaghetti.rshiftk(instr_diff:band(0x3FFFFFFF):bor(0x10000), 15):never_zero():bor(0x10000000) -- inverted
					local same_hi -- inverted
					do
						local shift_by = spaghetti.rshiftk(instr_diff:band(0x3FFFFFFF):bor(0x8000), 15):bxor(0x10000):bxor(1)
						same_hi = spaghetti.constant(0x1000FFFF):rshift(shift_by):never_zero():bor(0x10000000)
					end
					local same_lo -- inverted
					do
						local shift_by = instr_diff:bsub(3):bsub(0x80):band(0xFF):bxor(0x10000):bxor(8)
						same_lo = spaghetti.constant(0x1000FFFF):rshift(shift_by):never_zero():bor(0x10000000)
					end
					same = same_15:bor(same_hi):bor(same_lo) -- inverted
				end
				local lo32
				do
					local instr_12 = spaghetti.rshiftk(inputs.instr_lo, 12)
					local instr_13 = spaghetti.rshiftk(inputs.instr_lo, 13)
					lo32 = instr_12:bor(instr_13) -- inverted
				end
				local rs1_rd_diff, rs2_rd_diff
				do
					rs1_rd_diff = spaghetti.constant(0x1000FFFF):rshift(regs_outputs_prev.rd:bor(0x10000):bxor(regs_outputs_prev.rs1)):never_zero():bor(0x10000000):bxor(1) -- inverted
					rs2_rd_diff = spaghetti.constant(0x1000FFFF):rshift(regs_outputs_prev.rd:bor(0x10000):bxor(regs_outputs_prev.rs2)):never_zero():bor(0x10000000):bxor(1) -- inverted
				end
				local can_fuse = same:bor(lo32):bor(rs1_rd_diff):bor(rs2_rd_diff):bxor(1)
				same:label("same")
				lo32:label("lo32")
				rs1_rd_diff:label("rs1_rd_diff")
				rs2_rd_diff:label("rs2_rd_diff")
				can_fuse:label("can_fuse")
				defer_mul = defer_mul:bor(can_fuse)
			end
			if not has_jal then
				defer = defer:bor(cbranch_outputs.taken)
				             :bor(instr_mem:bxor(1))
				             :bor(defer_mul:bxor(1))
				             :bor(instr_hltj:bxor(1)):band(0x10000001)
			end
			if has_jal then
				instr_output = instr_output:band(instr_j):band(instr_l)
			end
			local output = defer:bxor(1):bsub(instr_output)
			local pc_lo, pc_hi, next_instr, next_lhs_lo, next_lhs_hi, next_rhs_lo, next_rhs_hi, mul_control
			local res_lo = alu_outputs.res_lo
			local res_hi = alu_outputs.res_hi
			if has_jal then
				pc_lo, pc_hi = spaghetti.select(
					defer:band(1):zeroable(),
					inputs.pc_lo, incr_pc_outputs.lo,
					inputs.pc_hi, incr_pc_outputs.hi
				)
				res_lo, res_hi = spaghetti.select(
					instr_j:band(1):zeroable(),
					res_lo, incr_pc_outputs.lo,
					res_hi, incr_pc_outputs.hi
				)
				mul_control = spaghetti.rshiftk(inputs.instr_lo, 12):bsub(8):bsub(4):bor(spaghetti.lshiftk(instr_mul:bsub(0xFFFE):bxor(1), 2)):bor(0x10000000):band(0x1000FFFF)
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
			if has_prev_mul then
				res_lo, res_hi = spaghetti.select(
					defer_mul:bsub(instr_mul):band(1):zeroable(),
					inputs.mul_prev_lo, res_lo,
					inputs.mul_prev_hi, res_hi
				)
			end
			return {
				res_lo      = res_lo,
				res_hi      = res_hi,
				pc_lo       = pc_lo,
				pc_hi       = pc_hi,
				output      = output,
				next_lhs_lo = next_lhs_lo,
				next_lhs_hi = next_lhs_hi,
				next_rhs_lo = next_rhs_lo,
				next_rhs_hi = next_rhs_hi,
				next_instr  = next_instr,
				jal_lo      = alu_outputs.jal_lo,
				jal_hi      = alu_outputs.jal_hi,
				taken       = cbranch_outputs.taken,
				mul_control = mul_control,
			}
		end,
		fuzz_inputs = function()
			local instr = bitx.bor(bitx.lshift(math.random(0x00000000, 0x7FFFFFFF), 1), 1)
			local instr_lo = bitx.band(            instr     , 0xFFFF)
			local instr_hi = bitx.band(bitx.rshift(instr, 16), 0xFFFF)
			local inputs = {
				lhs_lo      = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				lhs_hi      = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_lo      = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_hi      = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_lo       = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_hi       = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				instr       = instr,
				instr_lo    = bitx.bor(instr_lo, 0x10000000),
				instr_hi    = bitx.bor(instr_hi, 0x10000000),
				defer       = bitx.bor(math.random(0x0000, 0x0001), 0x10000000),
			}
			if has_prev_mul then
				inputs.instr_prev  = bitx.bor(bitx.lshift(math.random(0x00000000, 0x7FFFFFFF), 1), 9)
				if math.random(0, 1) == 0 then
					inputs.instr_prev = bitx.bor(instr, 8)
				end
				if math.random(0, 1) == 0 then
					inputs.instr_prev = bitx.bor(inputs.instr_prev, bitx.lshift(math.random(0, 3), 12))
				end
				if math.random(0, 1) == 0 then
					inputs.instr_prev = bitx.bor(bitx.band(inputs.instr_prev, 0xFFFFF07F), bitx.lshift(math.random(0, 31), 7))
				end
				if math.random(0, 1) == 0 then
					inputs.instr_prev = bitx.bor(bitx.band(inputs.instr_prev, 0xFFF07FFF), bitx.lshift(math.random(0, 31), 15))
				end
				if math.random(0, 1) == 0 then
					inputs.instr_prev = bitx.bor(bitx.band(inputs.instr_prev, 0xFE0FFFFF), bitx.lshift(math.random(0, 31), 20))
				end
				if math.random(0, 1) == 0 then
					inputs.instr_prev = bitx.bor(inputs.instr_prev, bitx.lshift(math.random(0, 0x7F), 25))
				end
				inputs.mul_prev_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs.mul_prev_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
			end
			if not has_jal then
				inputs.next_lhs_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs.next_lhs_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs.next_rhs_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs.next_rhs_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs.next_instr  = bitx.bor(bitx.lshift(math.random(0x00000000, 0x7FFFFFFF), 1), 1)
			end
			return inputs
		end,
		fuzz_outputs = function(inputs)
			local instr_mem  = bitx.band(inputs.instr_lo, 0x0050) == 0x0000
			local instr_mul  = bitx.band(inputs.instr_lo, 0x0074) == 0x0030 and bitx.band(inputs.instr_hi, 0x0600) == 0x0200
			local instr_jalr = bitx.band(inputs.instr_lo, 0x005C) == 0x0044
			local instr_jal  = bitx.band(inputs.instr_lo, 0x0058) == 0x0048
			local instr_hlt  = bitx.band(inputs.instr_lo, 0x0050) == 0x0050
			local instr_l    = bitx.band(inputs.instr_lo, 0x0074) == 0x0000
			local defer = bitx.band(inputs.defer, 1) ~= 0
			local defer_mul = instr_mul
			if has_prev_mul then
				local diff = bitx.bxor(inputs.instr, inputs.instr_prev)
				local same = bitx.band(diff, 0x3FFF8074) == 0
				local lo32 = bitx.band(inputs.instr_lo, 0x3000) == 0x0000
				local rs1_rd_diff = bitx.band(bitx.rshift(inputs.instr_prev, 15), 0x1F) ~= bitx.band(bitx.rshift(inputs.instr_prev, 7), 0x1F)
				local rs2_rd_diff = bitx.band(bitx.rshift(inputs.instr_prev, 20), 0x1F) ~= bitx.band(bitx.rshift(inputs.instr_prev, 7), 0x1F)
				local can_fuse = same and lo32 and rs1_rd_diff and rs2_rd_diff
				defer_mul = defer_mul and not can_fuse
			end
			if not has_jal then
				defer = defer or instr_mem or defer_mul or instr_jalr or instr_jal or instr_hlt
			end
			local output = bitx.band(inputs.instr_lo, 0x0050) == 0x0010
			if has_jal then
				output = output or instr_jalr or instr_jal or instr_l
			end
			local pc = bitx.bor(bitx.band(inputs.pc_lo, 0xFFFF), bitx.lshift(bitx.band(inputs.pc_hi, 0xFFFF), 16))
			local next_pc = (pc + 4) % 0x100000000
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
			if cbranch_taken and not has_jal then
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
				pc = next_pc
			end
			if defer then
				output = false
			end
			local res_lo = alu_outputs.res_lo
			local res_hi = alu_outputs.res_hi
			if has_jal and (instr_jalr or instr_jal) then
				res_lo = bitx.bor(0x10000000, bitx.band(            next_pc     , 0xFFFF))
				res_hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(next_pc, 16), 0xFFFF))
			end
			if has_prev_mul and instr_mul and not defer_mul then
				res_lo = inputs.mul_prev_lo
				res_hi = inputs.mul_prev_hi
			end
			local mul_control = bitx.bor(instr_mul and 4 or 0, bitx.band(bitx.rshift(inputs.instr, 12), 3))
			return {
				res_lo      = res_lo,
				res_hi      = res_hi,
				pc_lo       = bitx.bor(0x10000000, bitx.band(            pc     , 0xFFFF)),
				pc_hi       = bitx.bor(0x10000000, bitx.band(bitx.rshift(pc, 16), 0xFFFF)),
				output      = output and 0x10000001 or 0x10000000,
				next_lhs_lo = not has_jal and next_lhs_lo or nil,
				next_lhs_hi = not has_jal and next_lhs_hi or nil,
				next_rhs_lo = not has_jal and next_rhs_lo or nil,
				next_rhs_hi = not has_jal and next_rhs_hi or nil,
				next_instr  = not has_jal and next_instr  or nil,
				jal_lo      = alu_outputs.jal_lo,
				jal_hi      = alu_outputs.jal_hi,
				taken       = cbranch_outputs.taken,
				mul_control = has_jal and bitx.bor(0x10000000, mul_control) or nil,
			}
		end,
	}
end)

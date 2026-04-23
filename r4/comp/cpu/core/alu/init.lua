local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local check     = require("spaghetti.check")
local common    = require("r4.comp.cpu.common")
local adder     = require("r4.comp.cpu.core.alu.adder")  .instantiate()
local bitwise   = require("r4.comp.cpu.core.alu.bitwise").instantiate()
local shifter   = require("r4.comp.cpu.core.alu.shifter").instantiate()
local imm12s    = require("r4.comp.cpu.core.alu.imm12s") .instantiate()

return testbed.module(function(params, params_name)
	check.one_of(params_name .. ".unit_type", params.unit_type, { "f", "m", "l" })
	local has_jal = params.unit_type == "l"

	return {
		tag = "core.core.alu",
		opt_params = {
			thread_count  = 1,
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			round_length  = 10000,
		},
		stacks        = 2,
		storage_slots = 70,
		work_slots    = 20,
		inputs = {
			{ name = "lhs_lo"  , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "lhs_hi"  , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_lo"  , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_hi"  , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pc_lo"   , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pc_hi"   , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "instr_lo", index = 13, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "instr_hi", index = 15, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			has_jal and { name = "jaloff_lo", index = 17, keepalive = 0x10000000, payload = 0x0000FFFE, initial = 0x10000000 } or nil,
			has_jal and { name = "jaloff_hi", index = 19, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 } or nil,
		},
		outputs = {
			{ name = "res_lo", index =  1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "res_hi", index =  3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "lt"    , index =  5, keepalive = 0x10000000, payload = 0x00000001 },
			{ name = "ltu"   , index =  7, keepalive = 0x10000000, payload = 0x00000001 },
			{ name = "eq"    , index =  9, keepalive = 0x10000000, payload = 0x00000001 },
			has_jal and { name = "jal_lo", index = 11, keepalive = 0x10000000, payload = 0x0000FFFF } or nil,
			has_jal and { name = "jal_hi", index = 13, keepalive = 0x10000000, payload = 0x0000FFFF } or nil,
		},
		func = function(inputs)
			local instr_addx = common.match_instr(inputs.instr_lo, 0x0010, 0x0000):bor(0x10000000)
				:band(
					          common.match_instr(inputs.instr_lo, 0x7004, 0x0000)
					:bor(     common.match_instr(inputs.instr_lo, 0x0020, 0x0020)
					     :bor(common.match_instr(inputs.instr_hi, 0x4000, 0x4000)):bxor(1)):bxor(1)
					:bor(     common.match_instr(inputs.instr_lo, 0x0004, 0x0000)):bor(0x10000000)
				)
			local instr_czero = common.match_instr(inputs.instr_lo, 0x0014, 0x0014):bxor(1)
			               :bor(common.match_instr(inputs.instr_lo, 0x0020, 0x0020))
			               :bor(common.match_instr(inputs.instr_hi, 0x0600, 0x0600))
			local index = spaghetti.select(
				common.match_instr(inputs.instr_lo, 0x0004, 0x0000):band(1):zeroable(),
				0x10000,
				common.match_instr(inputs.instr_lo, 0x1000, 0x0000)
			)
			local ui_lhs_lo, ui_lhs_hi = spaghetti.select(
				common.match_instr(inputs.instr_lo, 0x0020, 0x0000):band(1):zeroable(),
				0x10000000, inputs.pc_lo,
				0x10000000, inputs.pc_hi
			)
			local imm12s_outputs = imm12s.component({
				instr_hi = inputs.instr_hi,
			})
			local rhs_lo, rhs_hi = spaghetti.select(
				inputs.instr_lo:band(0x60):zeroable(),
				inputs.rhs_lo, imm12s_outputs.imm12s_lo,
				inputs.rhs_hi, imm12s_outputs.imm12s_hi
			)
			local adder_lhs_lo, adder_lhs_hi, adder_rhs_lo, adder_rhs_hi = spaghetti.select(
				common.match_instr(inputs.instr_lo, 0x0014, 0x0014):band(1):zeroable(),
				inputs.lhs_lo, ui_lhs_lo,
				inputs.lhs_hi, ui_lhs_hi,
				rhs_lo       , inputs.instr_lo:bsub(0x0FFF),
				rhs_hi       , inputs.instr_hi
			)
			if has_jal then
				local instr_jal = common.match_instr(inputs.instr_lo, 0x0048, 0x0048)
				adder_lhs_lo, adder_lhs_hi, adder_rhs_lo, adder_rhs_hi = spaghetti.select(
					instr_jal:band(1):zeroable(),
					adder_lhs_lo, inputs.pc_lo,
					adder_lhs_hi, inputs.pc_hi,
					adder_rhs_lo, inputs.jaloff_lo,
					adder_rhs_hi, inputs.jaloff_hi
				)
				instr_addx = instr_addx:bor(instr_jal:bxor(1))
			end
			local adder_outputs = adder.component({
				control = instr_addx:band(0x10000001),
				lhs_lo  = adder_lhs_lo,
				lhs_hi  = adder_lhs_hi,
				rhs_lo  = adder_rhs_lo,
				rhs_hi  = adder_rhs_hi,
			})
			local bitwise_outputs = bitwise.component({
				lhs_lo = inputs.lhs_lo,
				lhs_hi = inputs.lhs_hi,
				rhs_lo = rhs_lo,
				rhs_hi = rhs_hi,
			})
			local shifter_outputs = shifter.component({
				control = inputs.instr_hi:lshift(2),
				lhs_lo  = inputs.lhs_lo,
				lhs_hi  = inputs.lhs_hi,
				rhs_lo  = rhs_lo,
				rhs_hi  = rhs_hi,
			})
			local res_sl_lo  , res_sl_hi   = shifter_outputs.sl_lo , shifter_outputs.sl_hi
			local res_add_lo , res_add_hi  = adder_outputs.sum_lo  , adder_outputs.sum_hi
			local res_sltu_lo, res_sltu_hi = adder_outputs.ltu     , 0x10000000
			local res_slt_lo , res_slt_hi  = adder_outputs.lt      , 0x10000000
			local res_sr_lo  , res_sr_hi   = shifter_outputs.sr_lo , shifter_outputs.sr_hi
			local res_xor_lo , res_xor_hi  = bitwise_outputs.xor_lo, bitwise_outputs.xor_hi
			local res_and_lo , res_and_hi  = bitwise_outputs.and_lo, bitwise_outputs.and_hi
			local res_or_lo  , res_or_hi   = bitwise_outputs.or_lo , bitwise_outputs.or_hi
			local res_01_lo, res_01_hi, res_23_lo, res_23_hi, res_45_lo, res_45_hi, res_67_lo, res_67_hi = spaghetti.select(
				index:band(1):zeroable(),
				res_sl_lo  , res_add_lo,
				res_sl_hi  , res_add_hi,
				res_sltu_lo, res_slt_lo,
				res_sltu_hi, res_slt_hi,
				res_sr_lo  , res_xor_lo,
				res_sr_hi  , res_xor_hi,
				res_and_lo , res_or_lo ,
				res_and_hi , res_or_hi 
			)
			local res_03_lo, res_03_hi, res_47_lo, res_47_hi = spaghetti.select(
				index:band(2):zeroable(),
				res_23_lo, res_01_lo,
				res_23_hi, res_01_hi,
				res_67_lo, res_45_lo,
				res_67_hi, res_45_hi
			)
			local res_07_lo, res_07_hi = spaghetti.select(
				index:band(4):zeroable(),
				res_47_lo, res_03_lo,
				res_47_hi, res_03_hi
			)
			local zero = spaghetti.select(inputs.rhs_hi:bor(inputs.rhs_lo):band(0xFFFF):zeroable(), 1, 3)
			local res_czero_lo, res_czero_hi = spaghetti.select(
				common.match_instr(inputs.instr_lo, 0x1000, 0x0000):bxor(zero):band(2):zeroable(),
				0x10000000, inputs.lhs_lo,
				0x10000000, inputs.lhs_hi
			)
			local res_lo, res_hi = spaghetti.select(
				instr_czero:band(1):zeroable(),
				res_07_lo, res_czero_lo,
				res_07_hi, res_czero_hi
			)
			return {
				res_lo = res_lo,
				res_hi = res_hi,
				lt     = adder_outputs.lt,
				ltu    = adder_outputs.ltu,
				eq     = bitwise_outputs.eq,
				jal_lo = has_jal and adder_outputs.sum_lo or nil,
				jal_hi = has_jal and adder_outputs.sum_hi or nil,
			}
		end,
		fuzz_inputs = function()
			local lhs_lo = math.random(0x0000, 0xFFFF)
			local lhs_hi = math.random(0x0000, 0xFFFF)
			local rhs_lo = math.random(0x0000, 0xFFFF)
			local rhs_hi = math.random(0x0000, 0xFFFF)
			if math.random(0, 63) == 0 then
				rhs_lo = 0
				rhs_hi = 0
			end
			return {
				lhs_lo    = bitx.bor(lhs_lo, 0x10000000),
				lhs_hi    = bitx.bor(lhs_hi, 0x10000000),
				rhs_lo    = bitx.bor(rhs_lo, 0x10000000),
				rhs_hi    = bitx.bor(rhs_hi, 0x10000000),
				pc_lo     = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_hi     = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				instr_lo  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				instr_hi  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				jaloff_lo = has_jal and bitx.bor(bitx.lshift(math.random(0x0000, 0x7FFF), 1), 0x10000000) or nil,
				jaloff_hi = has_jal and bitx.bor(            math.random(0x0000, 0xFFFF)    , 0x10000000) or nil,
			}
		end,
		fuzz_outputs = function(inputs)
			local imm12s_outputs, err = imm12s.fuzz_outputs({
				instr_hi = inputs.instr_hi,
			})
			if not imm12s_outputs then
				return nil, "imm12s: " .. err
			end
			local instr_add   = bitx.band(inputs.instr_lo, 0x7034) == 0x0030 and bitx.band(inputs.instr_hi, 0x4000) == 0x0000
			local instr_addi  = bitx.band(inputs.instr_lo, 0x7034) == 0x0010
			local instr_auipc = bitx.band(inputs.instr_lo, 0x0034) == 0x0014
			local instr_lui   = bitx.band(inputs.instr_lo, 0x0034) == 0x0034
			local instr_czero = bitx.band(inputs.instr_hi, 0x0600) == 0x0600 and
			                    bitx.band(inputs.instr_lo, 0x0020) == 0x0020 and
			                    not instr_lui
			local index = bitx.band(bitx.rshift(inputs.instr_lo, 12), 7)
			local rhs_lo = inputs.rhs_lo
			local rhs_hi = inputs.rhs_hi
			if bitx.band(inputs.instr_lo, 0x0060) == 0x0000 then
				rhs_lo, rhs_hi = imm12s_outputs.imm12s_lo, imm12s_outputs.imm12s_hi
			end
			local adder_lhs_lo, adder_lhs_hi = inputs.lhs_lo, inputs.lhs_hi
			local adder_rhs_lo, adder_rhs_hi = rhs_lo, rhs_hi
			if instr_auipc then
				adder_lhs_lo, adder_lhs_hi = inputs.pc_lo, inputs.pc_hi
				adder_rhs_lo, adder_rhs_hi = bitx.band(inputs.instr_lo, 0x1000F000), inputs.instr_hi
			end
			if instr_lui then
				adder_lhs_lo, adder_lhs_hi = 0x10000000, 0x10000000
				adder_rhs_lo, adder_rhs_hi = bitx.band(inputs.instr_lo, 0x1000F000), inputs.instr_hi
			end
			local instr_jal = has_jal and bitx.band(inputs.instr_lo, 0x0048) == 0x0048
			if instr_jal then
				adder_lhs_lo, adder_lhs_hi = inputs.pc_lo, inputs.pc_hi
				adder_rhs_lo, adder_rhs_hi = inputs.jaloff_lo, inputs.jaloff_hi
			end
			local adder_outputs, err = adder.fuzz_outputs({
				control = (instr_add or instr_addi or instr_auipc or instr_lui or instr_jal) and 0x10000001 or 0x10000000,
				lhs_lo  = adder_lhs_lo,
				lhs_hi  = adder_lhs_hi,
				rhs_lo  = adder_rhs_lo,
				rhs_hi  = adder_rhs_hi,
			})
			if not adder_outputs then
				return nil, "adder: " .. err
			end
			local bitwise_outputs, err = bitwise.fuzz_outputs({
				lhs_lo = inputs.lhs_lo,
				lhs_hi = inputs.lhs_hi,
				rhs_lo = rhs_lo,
				rhs_hi = rhs_hi,
			})
			if not bitwise_outputs then
				return nil, "bitwise: " .. err
			end
			local shifter_outputs, err = shifter.fuzz_outputs({
				control = bitx.lshift(inputs.instr_hi, 1),
				lhs_lo  = inputs.lhs_lo,
				lhs_hi  = inputs.lhs_hi,
				rhs_lo  = rhs_lo,
				rhs_hi  = rhs_hi,
			})
			if not shifter_outputs then
				return nil, "shifter: " .. err
			end
			local branches = {
				[ 0 ] = { lo = adder_outputs.sum_lo  , hi = adder_outputs.sum_hi   },
				[ 1 ] = { lo = shifter_outputs.sl_lo , hi = shifter_outputs.sl_hi  },
				[ 2 ] = { lo = adder_outputs.lt      , hi = 0x10000000             },
				[ 3 ] = { lo = adder_outputs.ltu     , hi = 0x10000000             },
				[ 4 ] = { lo = bitwise_outputs.xor_lo, hi = bitwise_outputs.xor_hi },
				[ 5 ] = { lo = shifter_outputs.sr_lo , hi = shifter_outputs.sr_hi  },
				[ 6 ] = { lo = bitwise_outputs.or_lo , hi = bitwise_outputs.or_hi  },
				[ 7 ] = { lo = bitwise_outputs.and_lo, hi = bitwise_outputs.and_hi },
			}
			local ui_index = index
			if bitx.band(inputs.instr_lo, 0x0004) == 0x0004 then
				ui_index = 0
			end
			local res_lo = branches[ui_index].lo
			local res_hi = branches[ui_index].hi
			if instr_czero then
				local zero = bitx.band(inputs.rhs_lo, 0xFFFF) == 0 and
				             bitx.band(inputs.rhs_hi, 0xFFFF) == 0
				if bitx.band(index, 2) ~= 0 then
					zero = not zero
				end
				res_lo = zero and 0x10000000 or inputs.lhs_lo
				res_hi = zero and 0x10000000 or inputs.lhs_hi
			end
			return {
				res_lo = res_lo,
				res_hi = res_hi,
				lt     = adder_outputs.lt,
				ltu    = adder_outputs.ltu,
				eq     = bitwise_outputs.eq,
				jal_lo = has_jal and adder_outputs.sum_lo or nil,
				jal_hi = has_jal and adder_outputs.sum_hi or nil,
			}
		end,
	}
end)

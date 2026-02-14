local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local adder     = require("r4.comp.cpu.alu.adder")  .instantiate()
local bitwise   = require("r4.comp.cpu.alu.bitwise").instantiate()
local shifter   = require("r4.comp.cpu.alu.shifter").instantiate()
local imm12s    = require("r4.comp.cpu.alu.imm12s") .instantiate()

return testbed.module(function(params)
	return {
		tag = "core.alu",
		opt_params = {
			thread_count  = 1,
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			round_length  = 10000,
		},
		stacks        = 1,
		storage_slots = 50,
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
		},
		outputs = {
			{ name = "res_lo", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "res_hi", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "lt"    , index = 5, keepalive = 0x10000000, payload = 0x00000001 },
			{ name = "ltu"   , index = 7, keepalive = 0x10000000, payload = 0x00000001 },
			{ name = "eq"    , index = 9, keepalive = 0x10000000, payload = 0x00000001 },
		},
		func = function(inputs)
			local instr_2     = spaghetti.rshiftk(inputs.instr_lo, 2)
			local instr_2i    = instr_2:bxor(1)
			local instr_4     = spaghetti.rshiftk(inputs.instr_lo, 4)
			local instr_5     = spaghetti.rshiftk(inputs.instr_lo, 5)
			local instr_12    = spaghetti.rshiftk(inputs.instr_lo, 12)
			local instr_13    = spaghetti.rshiftk(instr_12, 1)
			local instr_14    = spaghetti.rshiftk(instr_12, 2)
			local instr_30    = spaghetti.rshiftk(inputs.instr_hi, 14)
			local group_add   = instr_2:bor(instr_12):bor(instr_13):bor(instr_14):bor(instr_5:bor(0x10000000):band(instr_30:bor(0x10000000))):bxor(1)
			local group_ui    = instr_2
			local instr_addx  = instr_4:bor(0x10000000):band(group_add:bor(group_ui):bor(0x10000000))
			local instr_ui    = instr_4:bor(0x10000000):band(              group_ui :bor(0x10000000))
			local index = spaghetti.select(group_ui:band(1):zeroable(), 0x10000, instr_12)
			local ui_lhs_lo, ui_lhs_hi = spaghetti.select(
				instr_5:band(1):zeroable(),
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
				instr_ui:band(1):zeroable(),
				ui_lhs_lo                   , inputs.lhs_lo,
				ui_lhs_hi                   , inputs.lhs_hi,
				inputs.instr_lo:bsub(0x0FFF), rhs_lo,
				inputs.instr_hi             , rhs_hi
			)
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
			return {
				res_lo = res_07_lo,
				res_hi = res_07_hi,
				lt     = adder_outputs.lt,
				ltu    = adder_outputs.ltu,
				eq     = bitwise_outputs.eq,
			}
		end,
		fuzz_inputs = function()
			return {
				lhs_lo   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				lhs_hi   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_lo   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_hi   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_lo    = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_hi    = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				instr_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				instr_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
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
			local index = bitx.band(bitx.rshift(inputs.instr_lo, 12), 7)
			if bitx.band(inputs.instr_lo, 0x0004) == 0x0004 then
				index = 0
			end
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
			local adder_outputs, err = adder.fuzz_outputs({
				control = (instr_add or instr_addi or instr_auipc or instr_lui) and 0x10000001 or 0x10000000,
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
			return {
				res_lo = branches[index].lo,
				res_hi = branches[index].hi,
				lt     = adder_outputs.lt,
				ltu    = adder_outputs.ltu,
				eq     = bitwise_outputs.eq,
			}
		end,
	}
end)

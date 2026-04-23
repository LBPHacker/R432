local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local common    = require("r4.comp.cpu.common")

return testbed.module(function(params)
	return {
		tag = "core.address",
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
			{ name = "instr_lo", index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "instr_hi", index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "lhs_lo"  , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "lhs_hi"  , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pc_lo"   , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pc_hi"   , index = 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		},
		outputs = {
			{ name = "sum_lo", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "sum_hi", index = 3, keepalive = 0x10000000, payload = 0x0000FFFF },
		},
		func = function(inputs)
			local instr_cbranch = common.match_instr(inputs.instr_lo, 0x0044, 0x0040)
			local instr_store   = common.match_instr(inputs.instr_lo, 0x0060, 0x0020)
			local sx = spaghetti.select(inputs.instr_hi:band(0x8000):zeroable(), 0x1000F000, 0x10000000)
			local rhs_lo_rest = spaghetti.rshiftk(inputs.instr_hi, 4)
			local rhs_lo_store = rhs_lo_rest:bsub(0x1F):bor(spaghetti.rshiftk(inputs.instr_lo:bsub(0xF000), 7))
			local rhs_lo_1 = spaghetti.select(
				instr_store:band(1):zeroable(),
				rhs_lo_rest :bor(0x10000000):band(0x1000FFFF),
				rhs_lo_store:bor(0x10000000):band(0x1000FFFF)
			)
			local rhs_lo_cbranch
			do
				local stretch_0 = spaghetti.lshiftk(spaghetti.rshiftk(inputs.instr_hi, 9):bsub(0x40  )             ,  5):assert(0x01000000, 0x000007E0)
				local stretch_1 = spaghetti.lshiftk(spaghetti.rshiftk(inputs.instr_lo, 8):bsub(0xF0  )             ,  1):assert(0x00200000, 0x0000001E)
				local stretch_2 = spaghetti.lshiftk(spaghetti.rshiftk(inputs.instr_lo, 7):bsub(0xFFFE):bor(0x20000), 11):assert(0x10000000, 0x00000800)
				rhs_lo_cbranch = stretch_0:bor(stretch_1):bor(stretch_2):band(0x1000FFFF)
			end
			local lhs_lo, lhs_hi, rhs_lo = spaghetti.select(
				instr_cbranch:band(1):zeroable(),
				inputs.lhs_lo, inputs.pc_lo,
				inputs.lhs_hi, inputs.pc_hi,
				rhs_lo_1, rhs_lo_cbranch
			)
			rhs_lo = rhs_lo:bor(sx)
			local generate_lo, propagate_lo, onesums_lo = common.ks16(lhs_lo, rhs_lo)
			local carries_lo    = spaghetti.lshiftk(generate_lo, 1):assert(0x20000000, 0x0001FFFE)
			local lhs_hi_decr   = common.incr16(lhs_hi, false, true)
			local lhs_hi_1      = spaghetti.select(
				inputs.instr_hi:band(0x8000):zeroable(),
				lhs_hi_decr, lhs_hi
			)
			local lhs_hi_1_incr = common.incr16(lhs_hi_1, false, false)
			local lhs_hi_2      = spaghetti.select(generate_lo:band(0x8000):zeroable(), lhs_hi_1_incr, lhs_hi_1)
			return {
				sum_lo = onesums_lo:bor(0x10000000):bxor(carries_lo):band(0x1000FFFF):assert(0x10000000, 0x0000FFFF),
				sum_hi = lhs_hi_2:band(0x1000FFFF),
			}
		end,
		fuzz_inputs = function()
			return {
				instr_lo = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				instr_hi = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				lhs_lo   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				lhs_hi   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_lo    = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_hi    = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
			}
		end,
		fuzz_outputs = function(inputs)
			local instr_cbranch = bitx.band(inputs.instr_lo, 0x0044) == 0x0040
			local instr_store   = bitx.band(inputs.instr_lo, 0x0060) == 0x0020
			local lhs_lo = inputs.lhs_lo
			local lhs_hi = inputs.lhs_hi
			local rhs_lo = bitx.bor(bitx.rshift(bitx.arshift(bitx.lshift(inputs.instr_hi, 16), 4), 16), 0x10000000)
			if instr_store then
				rhs_lo = bitx.bor(            bitx.band(bitx.rshift(inputs.instr_lo, 7), 0x001F)    ,
				                  bitx.lshift(bitx.band(bitx.rshift(inputs.instr_hi, 9), 0x007F), 5))
				rhs_lo = bitx.bor(bitx.rshift(bitx.arshift(bitx.lshift(rhs_lo, 20), 4), 16), 0x10000000)
			end
			if instr_cbranch then
				lhs_lo = inputs.pc_lo
				lhs_hi = inputs.pc_hi
				rhs_lo = bitx.bor(bitx.lshift(bitx.band(bitx.rshift(inputs.instr_lo,  7), 0x0001), 11),
				                  bitx.lshift(bitx.band(bitx.rshift(inputs.instr_lo,  8), 0x000F),  1),
				                  bitx.lshift(bitx.band(bitx.rshift(inputs.instr_hi,  9), 0x003F),  5),
				                  bitx.lshift(bitx.band(bitx.rshift(inputs.instr_hi, 15), 0x0001), 12))
				rhs_lo = bitx.bor(bitx.rshift(bitx.arshift(bitx.lshift(rhs_lo, 19), 3), 16), 0x10000000)
			end
			local lhs = bitx.bor(bitx.band(lhs_lo, 0xFFFF), bitx.lshift(bitx.band(lhs_hi, 0xFFFF), 16))
			local rhs = bitx.bor(bitx.band(rhs_lo, 0xFFFF), bitx.lshift(bitx.band(inputs.instr_hi, 0x8000) ~= 0 and 0xFFFF or 0x0000, 16))
			local sum = (lhs + rhs) % 0x100000000
			return {
				sum_lo = bitx.bor(0x10000000, bitx.band(            sum     , 0xFFFF)),
				sum_hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(sum, 16), 0xFFFF)),
			}
		end,
	}
end)

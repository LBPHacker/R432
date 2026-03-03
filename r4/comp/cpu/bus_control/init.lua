local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module(function(params)
	return {
		tag = "bus_control",
		opt_params = {
			thread_count  = 1,
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			round_length  = 10000,
			seed          = { 0x56789ABC, 0x87654321 },
		},
		stacks        = 1,
		storage_slots = 28,
		work_slots    = 9,
		inputs = {
			{ name = "pc_lo"         , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pc_hi"         , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pc_lo_prev"    , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pc_hi_prev"    , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "addr_lo"       , index =  9, keepalive = 0x10000000, payload = 0x03FFFFFF, initial = 0x10000000 },
			{ name = "bus_lo"        , index = 11, keepalive = 0x10000000, payload = 0x0003FFFF, initial = 0x10000000 },
			{ name = "pc_max_row"    , index = 13, keepalive = 0x10000000, payload = 0x0000003F, initial = 0x10000000 },
		},
		outputs = {
			{ name = "pc_lo"         , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "pc_hi"         , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "pc_row"        , index =  5, keepalive = 0x10000000, payload = 0x0000007F },
			{ name = "addr_combined" , index =  7, keepalive = 0x10000000, payload = 0x01FFFFFF },
		},
		func = function(inputs)
			local pc_lo, pc_hi = spaghetti.select(
				inputs.bus_lo:band(0x20000):zeroable(),
				inputs.pc_lo_prev, inputs.pc_lo,
				inputs.pc_hi_prev, inputs.pc_hi
			)
			local pc_row = spaghetti.rshiftk(pc_lo:bsub(0x8000), 9)
			local lt_one = pc_row:bor(0x100)
			local lt_xor = lt_one:bxor(inputs.pc_max_row)
			for ix_bit = 2, 0, -1 do
				local b = bitx.lshift(1, ix_bit)
				lt_xor, lt_one = spaghetti.select(
					lt_xor:band(bitx.band(0xFF, bitx.lshift(0xFF, 8 - b))):zeroable(),
					lt_xor, spaghetti.lshiftk(lt_xor, b):never_zero(),
					lt_one, spaghetti.lshiftk(lt_one, b):never_zero()
				)
				lt_xor:never_zero()
				lt_one:never_zero()
			end
			pc_row = spaghetti.select(lt_one:band(0x80):zeroable(), inputs.pc_max_row, pc_row:bor(0x10000000):band(0x1000FFFF))
			pc_row = pc_row:bxor(spaghetti.lshift(0x3FFFFFFE, pc_row:bxor(0xFFFF):bsub(7)):bxor(0x3FFFFFFF):bsub(7))
			pc_row = pc_row:bxor(spaghetti.lshift(0x3FFFFFFE, pc_row):bxor(0x3FFFFFFF))
			pc_row:force(0x10000000, 0x0000007F)
			return {
				pc_lo         = pc_lo,
				pc_hi         = pc_hi,
				pc_row        = pc_row,
				addr_combined = inputs.addr_lo:band(0x1000FFFF):bor(spaghetti.lshiftk(pc_lo:bsub(0xFE00):bor(0x1000), 16)),
			}
		end,
		fuzz_inputs = function()
			return {
				pc_lo      = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_hi      = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_lo_prev = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_hi_prev = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				addr_lo    = bitx.bor(math.random(0x00000000, 0x03FFFFFF), 0x10000000),
				bus_lo     = bitx.bor(math.random(0x00000000, 0x0003FFFF), 0x10000000),
				pc_max_row = bitx.bor(math.random(0x0000, 0x003F), 0x10000000),
			}
		end,
		fuzz_outputs = function(inputs)
			local pc         = bitx.bor(bitx.band(inputs.pc_lo     , 0xFFFF), bitx.lshift(bitx.band(inputs.pc_hi     , 0xFFFF), 16))
			local pc_prev    = bitx.bor(bitx.band(inputs.pc_lo_prev, 0xFFFF), bitx.lshift(bitx.band(inputs.pc_hi_prev, 0xFFFF), 16))
			local wait       = bitx.band(inputs.bus_lo, 0x20000) ~= 0
			local pc_max_row = bitx.band(inputs.pc_max_row, 0x3F)
			if wait then
				pc = pc_prev
			end
			local pc_row = math.min(bitx.band(bitx.rshift(pc, 9), 0x3F), pc_max_row)
			return {
				pc_lo         = bitx.bor(0x10000000, bitx.band(            pc     , 0xFFFF)),
				pc_hi         = bitx.bor(0x10000000, bitx.band(bitx.rshift(pc, 16), 0xFFFF)),
				pc_row        = bitx.bor(0x10000000, pc_row + 7),
				addr_combined = bitx.bor(0x10000000, bitx.band(inputs.addr_lo, 0xFFFF), bitx.lshift(bitx.band(pc, 0x1FF), 16)),
			}
		end,
	}
end)

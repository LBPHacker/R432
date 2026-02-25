local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")

return testbed.module(function(params)
	return {
		tag = "memory_rw",
		opt_params = {
			thread_count  = 1,
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			round_length  = 10000,
			seed          = { 0x56789ABC, 0x87654321 },
		},
		stacks        = 1,
		storage_slots = 37,
		work_slots    = 14,
		inputs = {
			{ name = "control" , index =  1, keepalive = 0x10000000, payload = 0x0000000F, initial = 0x10000000 },
			{ name = "core_lo" , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "core_hi" , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "addr_lo" , index = 11, keepalive = 0x10000000, payload = 0x01FFFFFF, initial = 0x10000000 },
			{ name = "mem_rest", index = 36, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 },
			{ name = "mem_lsb" , index = 37, keepalive = 0x00000000, payload = 0xFFFFFFFF, initial = 0x20000000, never_zero = true },
		},
		outputs = {
			{ name = "core_lo" , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "core_hi" , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "mem_rest", index = 34, keepalive = 0x00000001, payload = 0xFFFFFFFE },
			{ name = "mem_lsb" , index = 35, keepalive = 0x10000000, payload = 0x00000001 },
		},
		func = function(inputs)
			local mem_in_lo = inputs.mem_rest:bor(0x10000000):band(0x1000FFFF):force(0x10000000, 0x0000FFFF):bsub(1):bor(inputs.mem_lsb:bor(0x10000000):band(0x10000001))
			local mem_in_hi = spaghetti.rshiftk(spaghetti.rshiftk(inputs.mem_rest:bor(0x100):bsub(0xFF), 8):bor(0x10000000):bsub(0xFF), 8):bor(0x10000000):band(0x1000FFFF)
			local wmask_lo  = spaghetti.select(inputs.control:band(2):zeroable(), 0x100000FF, 0x1000FFFF)
			local wmask_hi  = spaghetti.select(inputs.control:band(6):zeroable(), 0x10000000, 0x1000FFFF)
			local wdata_lo, wdata_hi = inputs.core_lo, inputs.core_hi
			local rdata_lo, rdata_hi = mem_in_lo, mem_in_hi
			wmask_lo, wmask_hi = spaghetti.select(
				inputs.control:band(1):zeroable(),
				wmask_lo, 0x10000000,
				wmask_hi, 0x10000000
			)
			wmask_lo, wmask_hi, wdata_lo, wdata_hi, rdata_lo, rdata_hi = spaghetti.select(
				spaghetti.rshiftk(inputs.control, 1):bor(0x10000000):band(inputs.addr_lo):band(1):zeroable(),
				spaghetti.lshiftk(wmask_lo:bor(0x100000), 8):band(0x1000FFFF), wmask_lo,
				spaghetti.lshiftk(wmask_hi:bor(0x100000), 8):band(0x1000FFFF), wmask_hi,
				spaghetti.lshiftk(wdata_lo:bor(0x100000), 8):band(0x1000FFFF), wdata_lo,
				spaghetti.lshiftk(wdata_hi:bor(0x100000), 8):band(0x1000FFFF), wdata_hi,
				spaghetti.rshiftk(rdata_lo, 8):bor(0x10000000):bsub(0x100000), rdata_lo,
				spaghetti.rshiftk(rdata_hi, 8):bor(0x10000000):bsub(0x100000), rdata_hi
			)
			wmask_lo, wmask_hi, wdata_lo, wdata_hi, rdata_lo, rdata_hi = spaghetti.select(
				spaghetti.rshiftk(inputs.control, 1):bor(inputs.control):band(inputs.addr_lo):band(2):zeroable(),
				0x10000000, wmask_lo,
				wmask_lo, wmask_hi,
				0x10000000, wdata_lo,
				wdata_lo, wdata_hi,
				rdata_hi, rdata_lo,
				0x10000000, rdata_hi
			)
			local sx_8 = spaghetti.select(spaghetti.rshiftk(rdata_lo, 4):bor(0x10000000):band(inputs.control):band(8):zeroable(), 0x1000FF00, 0x10000000)
			rdata_lo = spaghetti.select(inputs.control:band(2):zeroable(), rdata_lo:band(0x100000FF):bor(sx_8), rdata_lo)
			local sx_16 = spaghetti.select(spaghetti.rshiftk(rdata_lo, 12):bor(0x10000000):band(inputs.control):band(8):zeroable(), 0x1000FFFF, 0x10000000)
			rdata_hi = spaghetti.select(inputs.control:band(6):zeroable(), sx_16, rdata_hi)
			local mem_out_lo = mem_in_lo:bxor(0x20000000):bxor(mem_in_lo:bxor(0x20000000):bxor(wdata_lo):band(wmask_lo:bxor(0x20000000)))
			local mem_out_hi = mem_in_hi:bxor(0x20000000):bxor(mem_in_hi:bxor(0x20000000):bxor(wdata_hi):band(wmask_hi:bxor(0x20000000)))
			return {
				core_lo  = rdata_lo,
				core_hi  = rdata_hi,
				mem_lsb  = mem_out_lo:band(0x10000001),
				mem_rest = spaghetti.lshiftk(spaghetti.lshiftk(mem_out_hi:bor(0x10000), 8):bor(1), 8)
					:bor(spaghetti.select(mem_out_hi:band(0x8000):zeroable(), 0x80000001, 1))
					:bor(spaghetti.select(mem_out_hi:band(0x4000):zeroable(), 0x40000001, 1))
					:assert(0x00000101, 0xFFFF0000)
					:bxor(mem_out_lo:bsub(1)):bxor(0x10000100),
			}
		end,
		fuzz_inputs = function()
			local mem_rest = bitx.bor(bitx.lshift(math.random(0x00000000, 0x7FFFFFFF), 1), 1)
			local mem_lsb = mem_rest
			if math.random(0, 31) == 0 then
				mem_lsb = 0x20000000
			end
			return {
				control  = bitx.bor(bitx.bor(
					math.random(0, 1),
					math.random(0, 2) * 2,
					math.random(0, 1) * 8
				), 0x10000000),
				core_lo  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				core_hi  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				mem_rest = mem_rest,
				mem_lsb  = mem_lsb,
				addr_lo  = bitx.bor(math.random(0x0000, 0x1FFFFFF), 0x10000000),
			}
		end,
		fuzz_outputs = function(inputs)
			local write    = bitx.band(inputs.control, 1) ~= 0
			local byte     = bitx.band(inputs.control, 2) ~= 0
			local halfword = bitx.band(inputs.control, 4) ~= 0
			local sx       = bitx.band(inputs.control, 8) ~= 0
			local core_in  = bitx.bor(bitx.band(inputs.core_lo, 0xFFFF), bitx.lshift(bitx.band(inputs.core_hi, 0xFFFF), 16))
			local mem_in   = bitx.bor(bitx.band(inputs.mem_rest, 0xFFFFFFFE), bitx.band(inputs.mem_lsb, 1))
			local core_out, write_data, write_mask
			local shiftf = sx and bitx.arshift or bitx.rshift
			if byte then
				local shift = bitx.band(inputs.addr_lo, 3) * 8
				core_out = shiftf(bitx.lshift(mem_in, 24 - shift), 24)
				write_data = bitx.lshift(core_in, shift)
				write_mask = bitx.lshift(0xFF, shift)
			elseif halfword then
				local shift = bitx.band(inputs.addr_lo, 2) * 8
				core_out = shiftf(bitx.lshift(mem_in, 16 - shift), 16)
				write_data = bitx.lshift(core_in, shift)
				write_mask = bitx.lshift(0xFFFF, shift)
			else
				core_out = mem_in
				write_data = core_in
				write_mask = 0xFFFFFFFF
			end
			if not write then
				write_mask = 0
			end
			local mem_out = bitx.bxor(mem_in, bitx.band(bitx.bxor(mem_in, write_data), write_mask))
			return {
				core_lo  = bitx.bor(0x10000000, bitx.band(            core_out     , 0xFFFF)),
				core_hi  = bitx.bor(0x10000000, bitx.band(bitx.rshift(core_out, 16), 0xFFFF)),
				mem_rest = bitx.bor(mem_out, 1),
				mem_lsb  = bitx.bor(bitx.band(mem_out, 1), 0x10000000),
			}
		end,
	}
end)

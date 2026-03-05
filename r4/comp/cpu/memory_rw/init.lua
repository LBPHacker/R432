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
		storage_slots = 43,
		work_slots    = 14,
		clobbers      = { 39 },
		inputs = {
			{ name = "addr_lo"       , index = 32, keepalive = 0x10000000, payload = 0x03FFFFFF, initial = 0x10000000 },
			{ name = "res_lo_addr_hi", index = 30, keepalive = 0x10000000, payload = 0x07FFFFFF, initial = 0x10000000 },
			{ name = "res_hi"        , index = 33, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "bus_lo"        , index =  5, keepalive = 0x10000000, payload = 0x0003FFFF, initial = 0x10000000 },
			{ name = "bus_hi"        , index = 38, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "res_rd"        , index = 31, keepalive = 0x10000000, payload = 0x0000001F, initial = 0x10000000 },
			{ name = "mem_rest"      , index = 36, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 },
			{ name = "mem_lsb"       , index = 37, keepalive = 0x00000000, payload = 0xFFFFFFFF, initial = 0x20000000, never_zero = true },
		},
		outputs = {
			{ name = "core_lo" , index = 40, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "core_hi" , index = 41, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "res_rd"  , index = 39, keepalive = 0x10000000, payload = 0x0000001F },
			{ name = "mem_rest", index = 34, keepalive = 0x00000001, payload = 0xFFFFFFFE },
			{ name = "mem_lsb" , index = 35, keepalive = 0x10000000, payload = 0x00000001 },
		},
		func = function(inputs)
			local loadstore = spaghetti.rshiftk(inputs.addr_lo, 24)
			local memmode   = spaghetti.rshiftk(inputs.res_lo_addr_hi, 24):bor(0x10000000)
			local byte      = memmode:bor(spaghetti.rshiftk(memmode, 1)):bxor(1)
			local mem_in_lo = inputs.mem_rest:bor(0x10000000):band(0x1000FFFF):force(0x10000000, 0x0000FFFF):bsub(1):bor(inputs.mem_lsb:bor(0x10000000):band(0x10000001))
			local mem_in_hi = spaghetti.rshiftk(spaghetti.rshiftk(inputs.mem_rest:bor(0x100):bsub(0xFF), 8):bor(0x10000000):bsub(0xFF), 8):bor(0x10000000):band(0x1000FFFF)
			local wmask_lo  = spaghetti.select(byte:band(1):zeroable(), 0x100000FF, 0x1000FFFF)
			local wmask_hi  = spaghetti.select(memmode:band(2):zeroable(), 0x1000FFFF, 0x10000000)
			local res_lo    = inputs.res_lo_addr_hi:band(0x1000FFFF)
			local wdata_lo, wdata_hi = res_lo, inputs.res_hi
			local rdata_lo, rdata_hi = mem_in_lo, mem_in_hi
			wmask_lo, wmask_hi = spaghetti.select(
				loadstore:band(2):zeroable(),
				wmask_lo, 0x10000000,
				wmask_hi, 0x10000000
			)
			local res_rd = inputs.res_rd
			wmask_lo, wmask_hi, res_rd = spaghetti.select(
				inputs.bus_lo:band(0x20000):zeroable(),
				0x10000000, wmask_lo,
				0x10000000, wmask_hi,
				0x10000000, res_rd
			)
			wmask_lo, wmask_hi, wdata_lo, wdata_hi, rdata_lo, rdata_hi = spaghetti.select(
				byte:bor(0x10000000):band(inputs.addr_lo):band(1):zeroable(),
				spaghetti.lshiftk(wmask_lo:bor(0x100000), 8):band(0x1000FFFF), wmask_lo,
				spaghetti.lshiftk(wmask_hi:bor(0x100000), 8):band(0x1000FFFF), wmask_hi,
				spaghetti.lshiftk(wdata_lo:bor(0x100000), 8):band(0x1000FFFF), wdata_lo,
				spaghetti.lshiftk(wdata_hi:bor(0x100000), 8):band(0x1000FFFF), wdata_hi,
				spaghetti.rshiftk(rdata_lo, 8):bor(0x10000000):bsub(0x100000), rdata_lo,
				spaghetti.rshiftk(rdata_hi, 8):bor(0x10000000):bsub(0x100000), rdata_hi
			)
			wmask_lo, wmask_hi, wdata_lo, wdata_hi, rdata_lo, rdata_hi = spaghetti.select(
				memmode:bxor(2):band(inputs.addr_lo):band(2):zeroable(),
				0x10000000, wmask_lo,
				wmask_lo, wmask_hi,
				0x10000000, wdata_lo,
				wdata_lo, wdata_hi,
				rdata_hi, rdata_lo,
				0x10000000, rdata_hi
			)
			local sx_8 = spaghetti.select(spaghetti.rshiftk(rdata_lo, 5):bor(0x20000):bsub(memmode):band(4):zeroable(), 0x1000FF00, 0x10000000)
			rdata_lo = spaghetti.select(byte:band(1):zeroable(), rdata_lo:band(0x100000FF):bor(sx_8), rdata_lo)
			local sx_16 = spaghetti.select(spaghetti.rshiftk(rdata_lo, 13):bor(0x20000):bsub(memmode):band(4):zeroable(), 0x1000FFFF, 0x10000000)
			rdata_hi = spaghetti.select(memmode:band(2):zeroable(), rdata_hi, sx_16)
			rdata_lo, rdata_hi, wmask_lo, wmask_hi = spaghetti.select(
				inputs.bus_lo:band(0x10000):zeroable(),
				inputs.bus_lo:band(0x1000FFFF), rdata_lo,
				inputs.bus_hi, rdata_hi,
				0x10000000, wmask_lo,
				0x10000000, wmask_hi
			)
			rdata_lo, rdata_hi = spaghetti.select(
				loadstore:band(1):zeroable(),
				rdata_lo, res_lo,
				rdata_hi, inputs.res_hi
			)
			local mem_out_lo = mem_in_lo:bxor(0x20000000):bxor(mem_in_lo:bxor(0x20000000):bxor(wdata_lo):band(wmask_lo:bxor(0x20000000)))
			local mem_out_hi = mem_in_hi:bxor(0x20000000):bxor(mem_in_hi:bxor(0x20000000):bxor(wdata_hi):band(wmask_hi:bxor(0x20000000)))
			return {
				core_lo  = rdata_lo,
				core_hi  = rdata_hi,
				res_rd   = res_rd,
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
			if math.random(0, 1) == 0 then
				mem_lsb = 0x20000000
			end
			return {
				addr_lo = bitx.bor(
					bitx.lshift(math.random(0, 2), 24),
					math.random(0x00000000, 0x00FFFFFF),
					0x10000000
				),
				res_lo_addr_hi = bitx.bor(math.random(0x00000000, 0x07FFFFFF), 0x10000000),
				res_hi         = bitx.bor(math.random(0x00000000, 0x0000FFFF), 0x10000000),
				res_rd         = bitx.bor(math.random(0x00000000, 0x0000001F), 0x10000000),
				bus_lo         = bitx.bor(math.random(0x00000000, 0x0003FFFF), 0x10000000),
				bus_hi         = bitx.bor(math.random(0x00000000, 0x0000FFFF), 0x10000000),
				mem_rest       = mem_rest,
				mem_lsb        = mem_lsb,
			}
		end,
		fuzz_outputs = function(inputs)
			local handled  = bitx.band(inputs.bus_lo, 0x10000) ~= 0
			local wait     = bitx.band(inputs.bus_lo, 0x20000) ~= 0
			local write    = bitx.band(inputs.addr_lo, 0x02000000) ~= 0
			local read     = bitx.band(inputs.addr_lo, 0x01000000) ~= 0
			local unsigned = bitx.band(inputs.res_lo_addr_hi, 0x04000000) ~= 0
			local word     = bitx.band(inputs.res_lo_addr_hi, 0x02000000) ~= 0
			local halfword = bitx.band(inputs.res_lo_addr_hi, 0x01000000) ~= 0
			local core_in  = bitx.bor(bitx.band(inputs.res_lo_addr_hi, 0xFFFF), bitx.lshift(bitx.band(inputs.res_hi, 0xFFFF), 16))
			local bus_in   = bitx.bor(bitx.band(inputs.bus_lo, 0xFFFF), bitx.lshift(bitx.band(inputs.bus_hi, 0xFFFF), 16))
			local mem_in   = bitx.bor(bitx.band(inputs.mem_rest, 0xFFFFFFFE), bitx.band(inputs.mem_lsb, 1))
			local core_out, write_data, write_mask
			local shiftf = unsigned and bitx.rshift or bitx.arshift
			if word then
				core_out = mem_in
				write_data = core_in
				write_mask = 0xFFFFFFFF
			elseif halfword then
				local shift = bitx.band(inputs.addr_lo, 2) * 8
				core_out = shiftf(bitx.lshift(mem_in, 16 - shift), 16)
				write_data = bitx.lshift(core_in, shift)
				write_mask = bitx.lshift(0xFFFF, shift)
			else
				local shift = bitx.band(inputs.addr_lo, 3) * 8
				core_out = shiftf(bitx.lshift(mem_in, 24 - shift), 24)
				write_data = bitx.lshift(core_in, shift)
				write_mask = bitx.lshift(0xFF, shift)
			end
			if handled then
				core_out = bus_in
			end
			if not read then
				core_out = core_in
			end
			if not write or handled then
				write_mask = 0
			end
			local res_rd = inputs.res_rd
			if wait then
				res_rd = 0x10000000
				write_mask = 0
			end
			local mem_out = bitx.bxor(mem_in, bitx.band(bitx.bxor(mem_in, write_data), write_mask))
			return {
				core_lo  = bitx.bor(0x10000000, bitx.band(            core_out     , 0xFFFF)),
				core_hi  = bitx.bor(0x10000000, bitx.band(bitx.rshift(core_out, 16), 0xFFFF)),
				res_rd   = res_rd,
				mem_rest = bitx.bor(mem_out, 1),
				mem_lsb  = bitx.bor(bitx.band(mem_out, 1), 0x10000000),
			}
		end,
	}
end)

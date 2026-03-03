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
		},
		stacks        = 1,
		storage_slots = 40,
		work_slots    = 20,
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
			{ name = "pc_row"        , index =  5, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "addr_combined" , index =  7, keepalive = 0x10000000, payload = 0x01FFFFFF },
		},
		func = function(inputs)
			-- local instr_tame = inputs.instr:bor(0x10000000):band(0x3FFFFFFE)
			-- local rs1 = spaghetti.rshiftk(instr_tame, 15):bor(0x10000000):band(0x1000001F)
			-- local rs2 = spaghetti.rshiftk(instr_tame, 20):bor(0x10000000):band(0x1000001F)
			-- local rd  = spaghetti.rshiftk(instr_tame,  7):bor(0x10000000):band(0x1000001F)
			-- return {
			-- 	rs1 = rs1,
			-- 	rs2 = rs2,
			-- 	rd  = spaghetti.select(instr_tame:bxor(0x10):band(0x50):zeroable(), 0x10000000, rd),
			-- }
		end,
		fuzz_inputs = function()
			-- return {
			-- 	instr = bitx.bor(bitx.lshift(math.random(0x00000000, 0x3FFFFFFF), 2), 3),
			-- }
		end,
		fuzz_outputs = function(inputs)
		-- 	local writes_reg = bitx.band(inputs.instr, 0x00000050) == 0x00000010
		-- 	local rs1 = bitx.band(bitx.rshift(inputs.instr, 15), 0x1F)
		-- 	local rs2 = bitx.band(bitx.rshift(inputs.instr, 20), 0x1F)
		-- 	local rd  = bitx.band(bitx.rshift(inputs.instr,  7), 0x1F)
		-- 	return {
		-- 		rs1 = bitx.bor(0x10000000, rs1),
		-- 		rs2 = bitx.bor(0x10000000, rs2),
		-- 		rd  = bitx.bor(0x10000000, writes_reg and rd or 0),
		-- 	}
		end,
	}
end)

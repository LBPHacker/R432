local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local common    = require("r4.common")

return testbed.module({
	tag = "stack_high",
	opt_params = {
		thread_count  = 1,
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
		round_length  = 10000,
	},
	stacks        = 1,
	storage_slots = 30,
	work_slots    = 12,
	inputs = {
		{ name = "high_half", index = 1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "low_half" , index = 3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	},
	outputs = {
		{ name = "both_31", index = 1, keepalive = 0x00000001, payload = 0xFFFFFFFE },
		{ name = "both_1" , index = 2, keepalive = 0x10000000, payload = 0x00000001 },
	},
	func = function(inputs)
		local high_8 = spaghetti.select(inputs.high_half:band(0x8000):zeroable(), 0x80000001, 1)
		local high_4 = spaghetti.select(inputs.high_half:band(0x4000):zeroable(), 0x40000001, 1)
		local high_half = spaghetti.lshiftk(spaghetti.lshiftk(inputs.high_half:bor(0x00010000), 8):bor(1), 8):bor(high_8):bor(high_4):bsub(0x100):assert(0x00000001, 0xFFFF0000)
		local low_half  = inputs.low_half:bor(1):bsub(0x10000000):assert(0x00000001, 0x0000FFFE)
		return {
			both_31 = high_half:bor(low_half),
			both_1  = inputs.low_half:bsub(0xFFFE),
		}
	end,
	fuzz_inputs = function()
		return {
			high_half = bitx.bor(0x10000000, bitx.lshift(math.random(0, 0xF), 12), math.random(0, 0xF)),
			low_half  = bitx.bor(0x10000000, bitx.lshift(math.random(0, 0xF), 12), math.random(0, 0xF)),
		}
	end,
	fuzz_outputs = function(inputs)
		local high_half   = bitx.band(inputs.high_half, 0xFFFF)
		local low_half    = bitx.band(inputs.low_half , 0xFFFF)
		local both_halves = common.merge32(low_half, high_half)
		return {
			both_31 = bitx.bor(both_halves, 1),
			both_1  = bitx.bor(0x10000000, bitx.band(both_halves, 1)),
		}
	end,
})

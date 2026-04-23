local spaghetti  = require("spaghetti")
local bitx       = require("spaghetti.bitx")
local testbed    = require("spaghetti.testbed")
local common     = require("r4.common")
local cpu_common = require("r4.comp.cpu.common")

return testbed.module(function(params)
	return {
		tag = "core.alu.multiplier",
		opt_params = {
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			seed          = { 0x56789ABC, 0x87654321 },
			thread_count        = 8,
			round_length        = 10000,
			rounds_per_exchange = 10,
			schedule = {
				durations    = { 1000000, 2000000, 6000000,        },
				temperatures = {      10,       2,       1,    0.5 },
			},
		},
		stacks        = 4,
		storage_slots = 72,
		work_slots    = 25,
		inputs = {
			{ name = "control"       , index = 53, keepalive = 0x10000000, payload = 0x00000007, initial = 0x10000000 },
			{ name = "res_lo_addr_hi", index = 54, keepalive = 0x10000000, payload = 0x07FFFFFF, initial = 0x10000000 },
			{ name = "res_hi"        , index = 56, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "res_rd"        , index = 55, keepalive = 0x10000000, payload = 0x0000001F, initial = 0x10000000 },
			{ name = "lhs_lo"        , index = 58, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "lhs_hi"        , index = 59, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_lo"        , index = 60, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_hi"        , index = 61, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		},
		outputs = {
			{ name = "res_lo_addr_hi", index = 54, keepalive = 0x10000000, payload = 0x07FFFFFF },
			{ name = "res_hi"        , index = 56, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "res_rd"        , index = 55, keepalive = 0x10000000, payload = 0x0000001F },
			{ name = "res_0"         , index = 71, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "res_1"         , index = 72, keepalive = 0x10000000, payload = 0x0000FFFF },
		},
		func = function(inputs)
			local lhs_signed = cpu_common.match_instr(inputs.control, 0x3, 0x3) -- normal
			local one_signed = cpu_common.match_instr(inputs.control, 0x3, 0x2) -- inverted
			local two_signed = cpu_common.match_instr(inputs.control, 0x2, 0x0) -- inverted
			local rhs_signed = cpu_common.match_instr(inputs.control, 0x2, 0x0) -- inverted
			local any_signed = cpu_common.match_instr(inputs.control, 0x3, 0x3) -- normal

			local rhs_lo_ka = spaghetti.lshiftk(spaghetti.lshiftk(inputs.rhs_lo, 1):bor(1), 1):bor(1)
			local rhs_hi_ka = spaghetti.lshiftk(spaghetti.lshiftk(inputs.rhs_hi, 1):bor(1), 1)

			local lhs = spaghetti.rshiftk(inputs.lhs_lo, 2):bor(2):bsub(1):bsub(0x04000000)
				:bor(spaghetti.lshiftk(spaghetti.lshiftk(inputs.lhs_hi:bor(0x10000), 8):bor(1), 6):bor(2):bsub(0x40))

			local lhs_sign = spaghetti.select(lhs_signed:band(1):zeroable(), 0x20000001, 1)
			local rhs_hi_ka_sign = spaghetti.select(rhs_signed:band(1):zeroable(), 1, 0x20001)

			local function rshift_chain(expr, k)
				for i = 0, 3 do
					local b = bitx.lshift(1, i)
					if bitx.band(k, b) ~= 0 then
						expr = spaghetti.rshiftk(expr, b)
					end
				end
				return expr
			end

			local cs_0 = spaghetti.constant(3)
			local cs_1 = spaghetti.constant(2)
			local rhs_bit = 0
			local function round(dest, cs_2)
				--[[
				cs_0         . x x x x x x x x x x x x x x x x x x x x x x x x x x x x x 1 1
				cs_1         . x x x x x x x x x x x x x x x x x x x x x x x x x x x x x 1 .
				cs_2         . x x x x x x x x x x x x x x x x x x x x x x x x x x x x x 1 1

				cs_01_x      . x x x x x x x x x x x x x x x x x x x x x x x x x x x x x . 1
				sums         . x x x x x x x x x x x x x x x x x x x x x x x x x x x x x 1 .
				carries_x    . x x x x x x x x x x x x x x x x x x x x x x x x x x x x x 1 .
				carries_a    . x x x x x x x x x x x x x x x x x x x x x x x x x x x x x . 1
				carries      . x x x x x x x x x x x x x x x x x x x x x x x x x x x x x 1 1

				cs_0'        . x x x x x x x x x x x x x x x x x x x x x x x x x x x x x 1 1
				cs_1'        . . x x x x x x x x x x x x x x x x x x x x x x x x x x x x 1 .
				cs_2'        . x x x x x x x x x x x x x x x x x x x x x x x x x x x x x 1 1
				--]]
				local cs_01_x   = cs_0     :bxor(cs_1     )
				local sums      = cs_01_x  :bxor(cs_2     )
				local carries_x = cs_0     :band(cs_1     )
				local carries_a = cs_01_x  :band(cs_2     )
				local carries   = carries_x:bor (carries_a)
				local dest_new  = spaghetti.rshiftk(dest, 1):bor(spaghetti.lshiftk(sums, 13):bor(0x10000000):bsub(0x4000):band(0x1000FFFF)):bxor(0x30000000)
				cs_1 = spaghetti.rshiftk(sums, 1):bor(2):bsub(1)
				cs_0 = carries
				return dest_new
			end
			local function round_rhs(dest)
				local cs_2 = lhs_sign:bxor(spaghetti.select(rshift_chain(rhs_bit >= 16 and inputs.rhs_hi or inputs.rhs_lo, rhs_bit):band(1):zeroable(), lhs, 2))
				if rhs_bit == 0 then
					cs_2 = cs_2:bor(spaghetti.select(two_signed:band(1):zeroable(), 1, 0x40000001))
				elseif rhs_bit == 31 then
					cs_2 = cs_2:bor(spaghetti.select(any_signed:band(1):zeroable(), 0x40000001, 1))
					cs_2 = spaghetti.select(rhs_signed:band(1):zeroable(), cs_2, cs_2:bxor(0x3FFFFFFE):bxor(2))
				end
				cs_2:label("cs_2_" .. rhs_bit)
				rhs_bit = rhs_bit + 1
				return round(dest, cs_2)
			end
			local function round_small(cs_2)
				local cs_01_x   = cs_0     :bxor(cs_1     )
				local sums      = cs_01_x  :bxor(cs_2     )
				local carries_x = cs_0     :band(cs_1     )
				local carries_a = cs_01_x  :band(cs_2     )
				local carries   = carries_x:bor (carries_a)
				cs_1 = sums
				cs_0 = spaghetti.lshiftk(carries, 1):bor(1):bsub(4)
			end

			--[[
			                                   0000000000000aaaaaaaaaaaaaaaa
			                                  0000000000000cccccccccccccccc
			                                 0000000000000eeeeeeeeeeeeeeee
			                                i000000000000gggggggggggggggg
			                               ixxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                              0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                             0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                            0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                           0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                          0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                         0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                        0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                       0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                      0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                     0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                    0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                   0000000000000bbbbbbbbbbbbbbbb
			                   0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                  0000000000000dddddddddddddddd
			                  0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                 0000000000000ffffffffffffffff
			                 0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			                0000000000000hhhhhhhhhhhhhhhh
			                0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			               0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			              0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			             0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			            0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			           0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			          0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			         0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			        0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			       0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			      0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			     0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			    0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			   0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			  0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			 0xxxxxxxxxxxxxxxxxxxxxxxxxxxx
			ixxxxxxxxxxxxxxxxxxxxxxxxxxxx
			--]]
			local res_0 = spaghetti.constant(0x20000000)
			for i = 0, 3 do
				local rhs_part_lo = spaghetti.select(rshift_chain(inputs.lhs_lo, i):band(1):zeroable(), rhs_lo_ka, 3)
				if i == 3 then
					rhs_part_lo = rhs_part_lo:bor(spaghetti.select(one_signed:band(1):zeroable(), 1, 0x40000001))
				end
				rhs_part_lo:label("rhs_part_lo_" .. i)
				res_0 = round(res_0, rhs_part_lo)
			end
			for i = 0, 11 do
				res_0 = round_rhs(res_0)
			end
			local res_1 = spaghetti.constant(0x20000000)
			for i = 0, 3 do
				local rhs_part_hi = rhs_hi_ka_sign:bxor(spaghetti.select(rshift_chain(inputs.lhs_lo, i):band(1):zeroable(), rhs_hi_ka, 2))
				rhs_part_hi:label("rhs_part_hi_" .. i)
				round_small(rhs_part_hi)
				res_1 = round_rhs(res_1)
			end
			for i = 0, 11 do
				res_1 = round_rhs(res_1)
			end
			local res_2q = spaghetti.constant(0x20000000)
			for i = 0, 3 do
				res_2q = round_rhs(res_2q)
			end
			res_2q = spaghetti.rshiftk(res_2q, 12)
			local res_2, res_3
			do
				local lhs = spaghetti.rshiftk(spaghetti.rshiftk(cs_0, 1):bor(0x20000000), 1)
				local rhs = spaghetti.rshiftk(spaghetti.rshiftk(cs_1, 1):bor(0x20000000), 1)
				local lhs_ka    = lhs:bor(0x20000000)
				local generate  = lhs_ka:band(rhs):assert(0x10000000, 0x0FFFFFFF)
				local propagate = lhs_ka:bxor(rhs):assert(0x20000000, 0x0FFFFFFF)
				local onesums   = lhs_ka:bxor(rhs):assert(0x20000000, 0x0FFFFFFF)
				for i = 0, 4 do
					local bit_i_m1          = bitx.lshift(1, i)
					local propagate_fill    = bitx.lshift(1, bit_i_m1) - 1
					local keepalive         = bitx.rshift(0x20000000, bit_i_m1)
					local generate_shifted  = spaghetti.lshiftk(generate :bor(keepalive), bit_i_m1)
					local propagate_shifted = spaghetti.lshiftk(propagate:bor(keepalive), bit_i_m1)
					if i == 2 then
						generate_shifted  = spaghetti.lshiftk(generate :bor(0x01000000), bit_i_m1):bor(0x20000000)
						propagate_shifted = spaghetti.lshiftk(propagate:bor(0x01000000), bit_i_m1):bor(0x20000000)
					end
					generate  = propagate:band(generate_shifted ):bor(generate)
					propagate = propagate:band(propagate_shifted :bor(propagate_fill))
				end
				local carries = spaghetti.lshiftk(generate, 1)
				local sum = onesums:bxor(carries:bor(0x10000000))
				res_2 = spaghetti.lshiftk(sum:bor(0x10000), 4):bor(res_2q:bor(0x10000000):band(0x1000000F)):band(0x1000FFFF)
				res_3 = spaghetti.rshiftk(spaghetti.rshiftk(sum, 1):bor(0x20000000), 11):bor(0x10000000):band(0x1000FFFF)
			end
			res_0 = res_0:bxor(0x30000000)
			res_1 = res_1:bxor(0x30000000)
			local res_lo, res_hi = spaghetti.select(
				inputs.control:band(3):zeroable(),
				res_2, res_0,
				res_3, res_1
			)
			res_lo, res_hi = spaghetti.select(
				inputs.control:band(4):zeroable(),
				res_lo, inputs.res_lo_addr_hi,
				res_hi, inputs.res_hi
			)
			return {
				res_lo_addr_hi = res_lo,
				res_hi         = res_hi,
				res_rd         = inputs.res_rd,
				res_0          = res_0,
				res_1          = res_1,
			}
		end,
		fuzz_inputs = function()
			return {
				control        = bitx.bor(math.random(0x00000000, 0x00000007), 0x10000000),
				res_lo_addr_hi = bitx.bor(math.random(0x00000000, 0x07FFFFFF), 0x10000000),
				res_hi         = bitx.bor(math.random(0x00000000, 0x0000FFFF), 0x10000000),
				res_rd         = bitx.bor(math.random(0x00000000, 0x0000001F), 0x10000000),
				lhs_lo         = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				lhs_hi         = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_lo         = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_hi         = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
			}
		end,
		fuzz_outputs = function(inputs)
			local lhs_lo     = bitx.band(inputs.lhs_lo, 0xFFFF)
			local lhs_hi     = bitx.band(inputs.lhs_hi, 0xFFFF)
			local rhs_lo     = bitx.band(inputs.rhs_lo, 0xFFFF)
			local rhs_hi     = bitx.band(inputs.rhs_hi, 0xFFFF)
			local lo32       = bitx.band(inputs.control, 0x3) == 0x0
			local lhs_signed = bitx.band(inputs.control, 0x3) ~= 0x3
			local rhs_signed = bitx.band(inputs.control, 0x2) == 0x0
			if lhs_signed and lhs_hi >= 0x8000 then
				lhs_hi = lhs_hi - 0x10000
			end
			if rhs_signed and rhs_hi >= 0x8000 then
				rhs_hi = rhs_hi - 0x10000
			end
			local r00_lo, r00_hi = common.split32(lhs_lo * rhs_lo % 0x100000000)
			local r01_lo, r01_hi = common.split32(lhs_lo * rhs_hi % 0x100000000)
			local r10_lo, r10_hi = common.split32(lhs_hi * rhs_lo % 0x100000000)
			local r11_lo, r11_hi = common.split32(lhs_hi * rhs_hi % 0x100000000)
			local r10_sx = (lhs_signed and r10_hi >= 0x8000) and 0xFFFF or 0x0000
			local r01_sx = (rhs_signed and r01_hi >= 0x8000) and 0xFFFF or 0x0000
			--[[
			                                [    r00_hi    ][    r00_lo    ]
			[    r01_sx    ][    r01_hi    ][    r01_lo    ]
			[    r10_sx    ][    r10_hi    ][    r10_lo    ]
			[    r11_hi    ][    r11_lo    ]
			--]]
			local res_0 = r00_lo
			local res_1, carry_2 = common.split32(r00_hi + r01_lo + r10_lo)
			local res_2, carry_3 = common.split32(r01_hi + r10_hi + r11_lo + carry_2)
			local res_3 = (r11_hi + carry_3 + r01_sx + r10_sx) % 0x10000
			local res_lo = bitx.bor(0x10000000, lo32 and res_0 or res_2)
			local res_hi = bitx.bor(0x10000000, lo32 and res_1 or res_3)
			if bitx.band(inputs.control, 4) == 0 then
				res_lo = inputs.res_lo_addr_hi
				res_hi = inputs.res_hi
			end
			return {
				res_lo_addr_hi = res_lo,
				res_hi         = res_hi,
				res_rd         = inputs.res_rd,
				res_0          = bitx.bor(0x10000000, res_0),
				res_1          = bitx.bor(0x10000000, res_1),
			}
		end,
	}
end)

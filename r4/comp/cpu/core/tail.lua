local spaghetti   = require("spaghetti")
local bitx        = require("spaghetti.bitx")
local testbed     = require("spaghetti.testbed")
local common      = require("r4.comp.cpu.common")
local unit        = require("r4.comp.cpu.core.unit")
local instr_split = require("r4.comp.cpu.core.instr_split").instantiate()
local address     = require("r4.comp.cpu.core.address")    .instantiate()
local regs        = require("r4.comp.cpu.core.regs")       .instantiate()

return testbed.module(function(params)
	local unit_last = unit.instantiate({ unit_type = "l" }, "?")

	return {
		tag = "core.head",
		opt_params = {
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			seed          = { 0x56789ABC, 0x87654324 },
			work_slot_overhead_penalty = 30,
			thread_count        = 8,
			round_length        = 10000,
			rounds_per_exchange = 10,
			schedule = {
				durations    = { 1000000, 2000000, 6000000,        },
				temperatures = {      10,       2,       1,    0.5 },
			},
		},
		stacks        = 2,
		storage_slots = 94,
		work_slots    = 25,
		inputs = {
			{ name = "pc_lo"   , index = 93, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "pc_hi"   , index = 94, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "shutdown", index = 70, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 },
			{ name = "start"   , index = 55, keepalive = 0x10000000, payload = 0x00000003, initial = 0x10000000 },
			{ name = "lhs_lo"  , index = 71, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "lhs_hi"  , index = 72, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_lo"  , index = 73, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "rhs_hi"  , index = 74, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "instr"   , index = 75, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 },
		},
		outputs = {
			{ name = "pc_lo"           , index = 91, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "pc_hi"           , index = 92, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "shutdown"        , index = 86, keepalive = 0x10000000, payload = 0x00000001 },
			{ name = "addr_lo"         , index = 70, keepalive = 0x10000000, payload = 0x03FFFFFF },
			{ name = "res_lo_addr_hi"  , index = 67, keepalive = 0x10000000, payload = 0x07FFFFFF },
			{ name = "res_hi"          , index = 69, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "res_rd"          , index = 68, keepalive = 0x10000000, payload = 0x0000001F },
			{ name = "addr_lo_b"       , index = 89, keepalive = 0x10000000, payload = 0x03FFFFFF },
			{ name = "res_lo_addr_hi_b", index = 87, keepalive = 0x10000000, payload = 0x07FFFFFF },
			{ name = "res_hi_b"        , index = 90, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "mul_control"     , index = 66, keepalive = 0x10000000, payload = 0x00000007 },
		},
		clobbers = { 64, 65, 78, 82 },
		func = function(inputs)
			local instr_split_outputs = instr_split.component({
				instr = inputs.instr,
			})
			local regs_outputs = regs.component({
				instr = inputs.instr,
			})
			local instr_hlt  = common.match_instr(instr_split_outputs.instr_lo, 0x0050, 0x0050)
			local instr_jal  = common.match_instr(instr_split_outputs.instr_lo, 0x0058, 0x0048)
			local instr_jalr = common.match_instr(instr_split_outputs.instr_lo, 0x005C, 0x0044)
			local instr_l    = common.match_instr(instr_split_outputs.instr_lo, 0x0074, 0x0000)
			local instr_s    = common.match_instr(instr_split_outputs.instr_lo, 0x0070, 0x0020)
			local unit_outputs = unit_last.component({
				lhs_lo   = inputs.lhs_lo,
				lhs_hi   = inputs.lhs_hi,
				rhs_lo   = inputs.rhs_lo,
				rhs_hi   = inputs.rhs_hi,
				pc_lo    = inputs.pc_lo,
				pc_hi    = inputs.pc_hi,
				defer    = inputs.shutdown,
				instr    = inputs.instr,
				instr_lo = instr_split_outputs.instr_lo,
				instr_hi = instr_split_outputs.instr_hi,
			})
			local address_outputs = address.component({
				instr_lo = instr_split_outputs.instr_lo,
				instr_hi = instr_split_outputs.instr_hi,
				lhs_lo   = inputs.lhs_lo,
				lhs_hi   = inputs.lhs_hi,
				pc_lo    = inputs.pc_lo,
				pc_hi    = inputs.pc_hi,
			})
			local pc_lo, pc_hi = spaghetti.select(
				unit_outputs.taken:bor(instr_jalr:bxor(1)):bsub(inputs.shutdown):band(1):zeroable(),
				address_outputs.sum_lo, unit_outputs.pc_lo,
				address_outputs.sum_hi, unit_outputs.pc_hi
			)
			pc_lo, pc_hi = spaghetti.select(
				instr_jal:bor(inputs.shutdown):band(1):zeroable(),
				pc_lo, unit_outputs.jal_lo,
				pc_hi, unit_outputs.jal_hi
			)
			local control_l =                   instr_l:bor(inputs.shutdown):bxor(1):bsub(0xFFFE)
			local control_s = spaghetti.lshiftk(instr_s:bor(inputs.shutdown):bxor(1):bsub(0xFFFE), 1)
			local memmode = spaghetti.rshiftk(instr_split_outputs.instr_lo, 12):bsub(8)
			local addr_lo = address_outputs.sum_lo:bor(spaghetti.lshiftk(address_outputs.sum_hi:bsub(0xFF00):bor(0x1000), 16))
			                                      :bor(spaghetti.lshiftk(control_l:bor(control_s):bor(0x10), 24))
			local res_lo, res_hi = spaghetti.select(
				instr_s:band(1):zeroable(),
				unit_outputs.res_lo, inputs.rhs_lo,
				unit_outputs.res_hi, inputs.rhs_hi
			)
			local res_lo_addr_hi = res_lo:bor(spaghetti.lshiftk(address_outputs.sum_hi:bsub(0xFF):bor(0x100000), 8))
			                             :bor(spaghetti.lshiftk(memmode:bor(0x10), 24))
			return {
				pc_lo            = pc_lo,
				pc_hi            = pc_hi,
				shutdown         = inputs.shutdown:bor(instr_hlt:bxor(1)):bsub(inputs.start):bor(spaghetti.rshiftk(inputs.start, 1)):bor(0x10000000):band(0x10000001),
				addr_lo          = addr_lo,
				res_lo_addr_hi   = res_lo_addr_hi,
				res_hi           = res_hi,
				addr_lo_b        = addr_lo,
				res_lo_addr_hi_b = res_lo_addr_hi,
				res_hi_b         = res_hi,
				res_rd           = spaghetti.select(unit_outputs.output:band(1):zeroable(), regs_outputs.rd, 0x10000000),
				mul_control      = unit_outputs.mul_control,
			}
		end,
		fuzz_inputs = function()
			return {
				pc_lo    = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_hi    = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				shutdown = bitx.bor(math.random(0x0000, 0x0001), 0x10000000),
				start    = bitx.bor(math.random(0x0000, 0x0003), 0x10000000),
				lhs_lo   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				lhs_hi   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_lo   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				rhs_hi   = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				instr    = bitx.bor(bitx.lshift(math.random(0x00000000, 0x7FFFFFFF), 1), 1),
			}
		end,
		fuzz_outputs = function(inputs)
			local instr_split_outputs, err = instr_split.fuzz_outputs({
				instr = inputs.instr,
			})
			if not instr_split_outputs then
				return nil, "instr_split: " .. err
			end
			local regs_outputs, err = regs.fuzz_outputs({
				instr = inputs.instr,
			})
			if not regs_outputs then
				return nil, "regs: " .. err
			end
			local instr_hlt  = bitx.band(instr_split_outputs.instr_lo, 0x0050) == 0x0050
			local instr_jal  = bitx.band(instr_split_outputs.instr_lo, 0x0058) == 0x0048
			local instr_jalr = bitx.band(instr_split_outputs.instr_lo, 0x005C) == 0x0044
			local instr_l    = bitx.band(instr_split_outputs.instr_lo, 0x0074) == 0x0000
			local instr_s    = bitx.band(instr_split_outputs.instr_lo, 0x0070) == 0x0020
			local defer = inputs.shutdown
			local unit_outputs, err = unit_last.fuzz_outputs({
				lhs_lo   = inputs.lhs_lo,
				lhs_hi   = inputs.lhs_hi,
				rhs_lo   = inputs.rhs_lo,
				rhs_hi   = inputs.rhs_hi,
				pc_lo    = inputs.pc_lo,
				pc_hi    = inputs.pc_hi,
				defer    = defer,
				instr    = inputs.instr,
				instr_lo = instr_split_outputs.instr_lo,
				instr_hi = instr_split_outputs.instr_hi,
			})
			if not unit_outputs then
				return nil, "unit: " .. err
			end
			local address_outputs, err = address.fuzz_outputs({
				instr_lo = instr_split_outputs.instr_lo,
				instr_hi = instr_split_outputs.instr_hi,
				lhs_lo   = inputs.lhs_lo,
				lhs_hi   = inputs.lhs_hi,
				pc_lo    = inputs.pc_lo,
				pc_hi    = inputs.pc_hi,
			})
			if not address_outputs then
				return nil, "address: " .. err
			end
			local pc_lo = unit_outputs.pc_lo
			local pc_hi = unit_outputs.pc_hi
			local branch_lo = instr_jal and unit_outputs.jal_lo or address_outputs.sum_lo
			local branch_hi = instr_jal and unit_outputs.jal_hi or address_outputs.sum_hi
			local cbranch_taken = bitx.band(unit_outputs.taken, 1) ~= 0
			if bitx.band(defer, 1) == 0 and (cbranch_taken or instr_jal or instr_jalr) then
				pc_lo = branch_lo
				pc_hi = branch_hi
			end
			local shutdown = bitx.band(inputs.shutdown, 1) ~= 0
			if instr_hlt then
				shutdown = true
			end
			if bitx.band(inputs.start, 1) ~= 0 then
				shutdown = false
			end
			if bitx.band(inputs.start, 2) ~= 0 then
				shutdown = true
			end
			local memmode = bitx.band(bitx.rshift(instr_split_outputs.instr_lo, 12), 7)
			local control = 0
			if bitx.band(defer, 1) == 0 then
				if instr_l then
					control = bitx.bor(control, 1)
				end
				if instr_s then
					control = bitx.bor(control, 2)
				end
			end
			local addr_lo = bitx.bor(
				address_outputs.sum_lo,
				bitx.lshift(bitx.band(address_outputs.sum_hi, 0xFF), 16),
				bitx.lshift(control, 24)
			)
			local res_lo = unit_outputs.res_lo
			local res_hi = unit_outputs.res_hi
			if instr_s then
				res_lo = inputs.rhs_lo
				res_hi = inputs.rhs_hi
			end
			local res_lo_addr_hi = bitx.bor(
				res_lo,
				bitx.lshift(bitx.band(bitx.rshift(address_outputs.sum_hi, 8), 0xFF), 16),
				bitx.lshift(memmode, 24)
			)
			local addr_lo        = bitx.bor(addr_lo       , 0x10000000)
			local res_lo_addr_hi = bitx.bor(res_lo_addr_hi, 0x10000000)
			local res_hi         = res_hi
			return {
				pc_lo            = pc_lo,
				pc_hi            = pc_hi,
				shutdown         = shutdown and 0x10000001 or 0x10000000,
				addr_lo          = addr_lo,
				res_lo_addr_hi   = res_lo_addr_hi,
				res_hi           = res_hi,
				addr_lo_b        = addr_lo,
				res_lo_addr_hi_b = res_lo_addr_hi,
				res_hi_b         = res_hi,
				res_rd           = bitx.band(unit_outputs.output, 1) ~= 0 and regs_outputs.rd or 0x10000000,
				mul_control      = unit_outputs.mul_control,
			}
		end,
	}
end)

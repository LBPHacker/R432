local spaghetti       = require("spaghetti")
local bitx            = require("spaghetti.bitx")
local testbed         = require("spaghetti.testbed")
local unit            = require("r4.comp.cpu.core.unit")
local internal_writer = require("r4.comp.cpu.core.internal_writer").instantiate()
local instr_split     = require("r4.comp.cpu.core.instr_split")    .instantiate()
local regs            = require("r4.comp.cpu.core.regs")           .instantiate()

return testbed.module(function(params)
	local unit_first  = unit.instantiate({ unit_type = "f" }, "?")
	local unit_middle = unit.instantiate({ unit_type = "m" }, "?")

	local units = 3
	local inputs = {
		{ name = "pc_lo"           , index =  1             , keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "pc_hi"           , index =  3             , keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "defer"           , index =  5             , keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000000 },
		{ name = "lhs_lo_" .. units, index =  8 + units * 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "lhs_hi_" .. units, index = 10 + units * 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "rhs_lo_" .. units, index = 12 + units * 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "rhs_hi_" .. units, index = 14 + units * 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "instr_"  .. units, index = 16 + units * 11, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 },
	}
	local outputs = {
		{ name = "pc_lo"           , index =  1             , keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "pc_hi"           , index =  3             , keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "lhs_lo_" .. units, index =  8 + units * 11, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "lhs_hi_" .. units, index = 10 + units * 11, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "rhs_lo_" .. units, index = 12 + units * 11, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "rhs_hi_" .. units, index = 14 + units * 11, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "instr_"  .. units, index = 16 + units * 11, keepalive = 0x00000001, payload = 0xFFFFFFFE },
	}
	for ix_unit = 0, units - 1 do
		table.insert(inputs , { name = "lhs_lo_" .. ix_unit, index =  8 + ix_unit * 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs , { name = "lhs_hi_" .. ix_unit, index = 10 + ix_unit * 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs , { name = "rhs_lo_" .. ix_unit, index = 12 + ix_unit * 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs , { name = "rhs_hi_" .. ix_unit, index = 14 + ix_unit * 11, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs , { name = "instr_"  .. ix_unit, index = 16 + ix_unit * 11, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 })
		table.insert(outputs, { name = "res_lo_" .. ix_unit, index =  8 + ix_unit * 11, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "res_hi_" .. ix_unit, index = 10 + ix_unit * 11, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "res_rd_" .. ix_unit, index = 12 + ix_unit * 11, keepalive = 0x10000000, payload = 0x0000001F })
	end
	return {
		tag = "core.head",
		opt_params = {
			thread_count  = 1,
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			round_length  = 10000,
			seed          = { 0x56789ABC, 0x87654325 },
			work_slot_overhead_penalty = 30,
		},
		stacks        = 5,
		storage_slots = 98,
		work_slots    = 25,
		inputs        = inputs,
		outputs       = outputs,
		func = function(inputs)
			local regs_outputs = {}
			for ix_unit = 0, units do
				inputs["instr_" .. ix_unit] = inputs["instr_" .. ix_unit]:bor(1)
				regs_outputs[ix_unit] = regs.component({
					instr = inputs["instr_" .. ix_unit],
				})
			end
			local outputs = {}
			local pc_lo = inputs.pc_lo
			local pc_hi = inputs.pc_hi
			for ix_unit = 0, units - 1 do
				local instr = inputs["instr_"  .. ix_unit]
				local instr_split_outputs = instr_split.component({
					instr = instr,
				})
				local unit_outputs = (ix_unit == 0 and unit_first or unit_middle).component({
					lhs_lo      = inputs["lhs_lo_" .. ix_unit],
					lhs_hi      = inputs["lhs_hi_" .. ix_unit],
					rhs_lo      = inputs["rhs_lo_" .. ix_unit],
					rhs_hi      = inputs["rhs_hi_" .. ix_unit],
					pc_lo       = pc_lo,
					pc_hi       = pc_hi,
					defer       = inputs.defer,
					instr       = instr,
					instr_lo    = instr_split_outputs.instr_lo,
					instr_hi    = instr_split_outputs.instr_hi,
					next_lhs_lo = inputs["lhs_lo_" .. (ix_unit + 1)],
					next_lhs_hi = inputs["lhs_hi_" .. (ix_unit + 1)],
					next_rhs_lo = inputs["rhs_lo_" .. (ix_unit + 1)],
					next_rhs_hi = inputs["rhs_hi_" .. (ix_unit + 1)],
					next_instr  = inputs["instr_"  .. (ix_unit + 1)],
				})
				inputs["lhs_lo_" .. (ix_unit + 1)] = unit_outputs.next_lhs_lo
				inputs["lhs_hi_" .. (ix_unit + 1)] = unit_outputs.next_lhs_hi
				inputs["rhs_lo_" .. (ix_unit + 1)] = unit_outputs.next_rhs_lo
				inputs["rhs_hi_" .. (ix_unit + 1)] = unit_outputs.next_rhs_hi
				inputs["instr_"  .. (ix_unit + 1)]  = unit_outputs.next_instr
				pc_lo  = unit_outputs.pc_lo
				pc_hi  = unit_outputs.pc_hi
				outputs["res_lo_" .. ix_unit] = unit_outputs.res_lo
				outputs["res_hi_" .. ix_unit] = unit_outputs.res_hi
				outputs["res_rd_" .. ix_unit] = spaghetti.select(unit_outputs.output:band(1):zeroable(), regs_outputs[ix_unit].rd, 0x10000000)
				for ix_next_unit = ix_unit + 1, units do
					local iw_lhs_outputs = internal_writer.component({
						rs     = regs_outputs[ix_next_unit].rs1,
						rs_lo  = inputs["lhs_lo_" .. ix_next_unit],
						rs_hi  = inputs["lhs_hi_" .. ix_next_unit],
						rw     = regs_outputs[ix_unit].rd,
						rw_lo  = unit_outputs.res_lo,
						rw_hi  = unit_outputs.res_hi,
						output = unit_outputs.output,
					})
					local iw_rhs_outputs = internal_writer.component({
						rs     = regs_outputs[ix_next_unit].rs2,
						rs_lo  = inputs["rhs_lo_" .. ix_next_unit],
						rs_hi  = inputs["rhs_hi_" .. ix_next_unit],
						rw     = regs_outputs[ix_unit].rd,
						rw_lo  = unit_outputs.res_lo,
						rw_hi  = unit_outputs.res_hi,
						output = unit_outputs.output,
					})
					inputs["lhs_lo_" .. ix_next_unit] = iw_lhs_outputs.rs_lo
					inputs["lhs_hi_" .. ix_next_unit] = iw_lhs_outputs.rs_hi
					inputs["rhs_lo_" .. ix_next_unit] = iw_rhs_outputs.rs_lo
					inputs["rhs_hi_" .. ix_next_unit] = iw_rhs_outputs.rs_hi
				end
			end
			outputs["lhs_lo_" .. units] = inputs["lhs_lo_" .. units]
			outputs["lhs_hi_" .. units] = inputs["lhs_hi_" .. units]
			outputs["rhs_lo_" .. units] = inputs["rhs_lo_" .. units]
			outputs["rhs_hi_" .. units] = inputs["rhs_hi_" .. units]
			outputs["instr_"  .. units] = inputs["instr_"  .. units]
			outputs.pc_lo = pc_lo
			outputs.pc_hi = pc_hi
			return outputs
		end,
		fuzz_inputs = function()
			local inputs = {
				pc_lo                  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				pc_hi                  = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				defer                  = bitx.bor(math.random(0x0000, 0x0001), 0x10000000),
				[ "lhs_lo_" .. units ] = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				[ "lhs_hi_" .. units ] = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				[ "rhs_lo_" .. units ] = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				[ "rhs_hi_" .. units ] = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				[ "instr_"  .. units ] = bitx.bor(bitx.lshift(math.random(0x00000000, 0x7FFFFFFF), 1), 1),
			}
			for ix_unit = 0, units - 1 do
				inputs["lhs_lo_" .. ix_unit] = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs["lhs_hi_" .. ix_unit] = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs["rhs_lo_" .. ix_unit] = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs["rhs_hi_" .. ix_unit] = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000)
				inputs["instr_"  .. ix_unit] = bitx.bor(bitx.lshift(math.random(0x00000000, 0x7FFFFFFF), 1), 1)
			end
			return inputs
		end,
		fuzz_outputs = function(inputs)
			local regs_outputs = {}
			for ix_unit = 0, units do
				local err
				regs_outputs[ix_unit], err = regs.fuzz_outputs({
					instr = inputs["instr_" .. ix_unit],
				})
				if not regs_outputs[ix_unit] then
					return nil, "regs/" .. ix_unit .. ": " .. err
				end
			end
			local outputs = {}
			local pc_lo = inputs.pc_lo
			local pc_hi = inputs.pc_hi
			for ix_unit = 0, units - 1 do
				local instr = inputs["instr_"  .. ix_unit]
				local instr_split_outputs, err = instr_split.fuzz_outputs({
					instr = instr,
				})
				if not instr_split_outputs then
					return nil, "instr_split/" .. ix_unit .. ": " .. err
				end
				local unit_outputs, err = (ix_unit == 0 and unit_first or unit_middle).fuzz_outputs({
					lhs_lo      = inputs["lhs_lo_" .. ix_unit],
					lhs_hi      = inputs["lhs_hi_" .. ix_unit],
					rhs_lo      = inputs["rhs_lo_" .. ix_unit],
					rhs_hi      = inputs["rhs_hi_" .. ix_unit],
					pc_lo       = pc_lo,
					pc_hi       = pc_hi,
					defer       = inputs.defer,
					instr       = instr,
					instr_lo    = instr_split_outputs.instr_lo,
					instr_hi    = instr_split_outputs.instr_hi,
					next_lhs_lo = inputs["lhs_lo_" .. (ix_unit + 1)],
					next_lhs_hi = inputs["lhs_hi_" .. (ix_unit + 1)],
					next_rhs_lo = inputs["rhs_lo_" .. (ix_unit + 1)],
					next_rhs_hi = inputs["rhs_hi_" .. (ix_unit + 1)],
					next_instr  = inputs["instr_"  .. (ix_unit + 1)],
				})
				if not unit_outputs then
					return nil, "unit/" .. ix_unit .. ": " .. err
				end
				inputs["lhs_lo_" .. (ix_unit + 1)] = unit_outputs.next_lhs_lo
				inputs["lhs_hi_" .. (ix_unit + 1)] = unit_outputs.next_lhs_hi
				inputs["rhs_lo_" .. (ix_unit + 1)] = unit_outputs.next_rhs_lo
				inputs["rhs_hi_" .. (ix_unit + 1)] = unit_outputs.next_rhs_hi
				inputs["instr_"  .. (ix_unit + 1)] = unit_outputs.next_instr
				pc_lo = unit_outputs.pc_lo
				pc_hi = unit_outputs.pc_hi
				outputs["res_lo_" .. ix_unit] = unit_outputs.res_lo
				outputs["res_hi_" .. ix_unit] = unit_outputs.res_hi
				outputs["res_rd_" .. ix_unit] = bitx.band(unit_outputs.output, 1) ~= 0 and regs_outputs[ix_unit].rd or 0x10000000
				for ix_next_unit = ix_unit + 1, units do
					local iw_lhs_outputs, err = internal_writer.fuzz_outputs({
						rs     = regs_outputs[ix_next_unit].rs1,
						rs_lo  = inputs["lhs_lo_" .. ix_next_unit],
						rs_hi  = inputs["lhs_hi_" .. ix_next_unit],
						rw     = regs_outputs[ix_unit].rd,
						rw_lo  = unit_outputs.res_lo,
						rw_hi  = unit_outputs.res_hi,
						output = unit_outputs.output,
					})
					if not iw_lhs_outputs then
						return nil, "internal_writer/" .. ix_unit .. "/" .. ix_next_unit .. "/lhs: " .. err
					end
					local iw_rhs_outputs, err = internal_writer.fuzz_outputs({
						rs     = regs_outputs[ix_next_unit].rs2,
						rs_lo  = inputs["rhs_lo_" .. ix_next_unit],
						rs_hi  = inputs["rhs_hi_" .. ix_next_unit],
						rw     = regs_outputs[ix_unit].rd,
						rw_lo  = unit_outputs.res_lo,
						rw_hi  = unit_outputs.res_hi,
						output = unit_outputs.output,
					})
					if not iw_rhs_outputs then
						return nil, "internal_writer/" .. ix_unit .. "/" .. ix_next_unit .. "/rhs: " .. err
					end
					inputs["lhs_lo_" .. ix_next_unit] = iw_lhs_outputs.rs_lo
					inputs["lhs_hi_" .. ix_next_unit] = iw_lhs_outputs.rs_hi
					inputs["rhs_lo_" .. ix_next_unit] = iw_rhs_outputs.rs_lo
					inputs["rhs_hi_" .. ix_next_unit] = iw_rhs_outputs.rs_hi
				end
			end
			outputs["lhs_lo_" .. units] = inputs["lhs_lo_" .. units]
			outputs["lhs_hi_" .. units] = inputs["lhs_hi_" .. units]
			outputs["rhs_lo_" .. units] = inputs["rhs_lo_" .. units]
			outputs["rhs_hi_" .. units] = inputs["rhs_hi_" .. units]
			outputs["instr_"  .. units] = inputs["instr_"  .. units]
			outputs.pc_lo = pc_lo
			outputs.pc_hi = pc_hi
			return outputs
		end,
	}
end)

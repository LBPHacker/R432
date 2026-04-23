local spaghetti       = require("spaghetti")
local bitx            = require("spaghetti.bitx")
local testbed         = require("spaghetti.testbed")
local unit            = require("r4.comp.cpu.core.unit")
local internal_writer = require("r4.comp.cpu.core.internal_writer").instantiate()
local instr_split     = require("r4.comp.cpu.core.instr_split")    .instantiate()
local regs            = require("r4.comp.cpu.core.regs")           .instantiate()

return testbed.module(function(params)
	local unit_first = unit.instantiate({ unit_type = "f" }, "?")
	local unit_middle = unit.instantiate({ unit_type = "m" }, "?")

	local units = 3
	local inputs = {
		{ name = "pc_lo"           , index = 62, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "pc_hi"           , index = 64, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "defer"           , index = 66, keepalive = 0x10000000, payload = 0x00000001, initial = 0x10000001 },
		{ name = "lhs_lo_" .. units, index = 85, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "lhs_hi_" .. units, index = 87, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "rhs_lo_" .. units, index = 89, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "rhs_hi_" .. units, index = 91, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "instr_"  .. units, index = 86, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 },
		{ name = "instr_prev"      , index = 78, keepalive = 0x00000009, payload = 0xFFFFFFF6, initial = 0x00000009 },
		{ name = "mul_prev_lo"     , index = 72, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
		{ name = "mul_prev_hi"     , index = 76, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
	}
	local outputs = {
		{ name = "pc_lo"                   , index = 89, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "pc_hi"                   , index = 90, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "lhs_lo_" .. units        , index = 67, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "lhs_hi_" .. units        , index = 68, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "rhs_lo_" .. units        , index = 69, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "rhs_hi_" .. units        , index = 70, keepalive = 0x10000000, payload = 0x0000FFFF },
		{ name = "instr_"  .. units        , index = 71, keepalive = 0x00000001, payload = 0xFFFFFFFE },
		{ name = "instr_"  .. units .. "_b", index = 94, keepalive = 0x00000009, payload = 0xFFFFFFF6 },
	}
	for ix_unit = 0, units - 1 do
		table.insert(inputs , { name = "lhs_lo_" .. ix_unit, index = 61 + ix_unit * 8, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs , { name = "lhs_hi_" .. ix_unit, index = 63 + ix_unit * 8, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs , { name = "rhs_lo_" .. ix_unit, index = 65 + ix_unit * 8, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs , { name = "rhs_hi_" .. ix_unit, index = 67 + ix_unit * 8, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 })
		table.insert(inputs , { name = "instr_"  .. ix_unit, index = 80 + ix_unit * 2, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 })
		table.insert(outputs, { name = "res_lo_" .. ix_unit, index = 79 + ix_unit * 3, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "res_hi_" .. ix_unit, index = 80 + ix_unit * 3, keepalive = 0x10000000, payload = 0x0000FFFF })
		table.insert(outputs, { name = "res_rd_" .. ix_unit, index = 78 + ix_unit * 3, keepalive = 0x10000000, payload = 0x0000001F })
	end
	return {
		tag = "core.head",
		opt_params = {
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			seed          = { 0x56789ABC, 0x8765432A },
			work_slot_overhead_penalty = 30,
			thread_count        = 8,
			round_length        = 10000,
			rounds_per_exchange = 10,
			schedule = {
				durations    = { 1000000, 2000000, 6000000,        },
				temperatures = {      10,       2,       1,    0.5 },
			},
		},
		stacks        = 5,
		storage_slots = 98,
		work_slots    = 25,
		inputs        = inputs,
		outputs       = outputs,
		clobbers      = { 68, 70, 74, 88, 90, 92, 93 },
		func = function(inputs)
			local outputs = {}
			for ix_unit = 0, units do
				local regs_outputs = regs.component({
					instr = inputs["instr_" .. ix_unit],
				})
				for ix_prev_unit = 0, ix_unit - 1 do
					local iw_lhs_outputs = internal_writer.component({
						rs     = regs_outputs.rs1,
						rs_lo  = inputs["lhs_lo_" .. ix_unit],
						rs_hi  = inputs["lhs_hi_" .. ix_unit],
						rw     = outputs["res_rd_" .. ix_prev_unit],
						rw_lo  = outputs["res_lo_" .. ix_prev_unit],
						rw_hi  = outputs["res_hi_" .. ix_prev_unit],
					})
					local iw_rhs_outputs = internal_writer.component({
						rs     = regs_outputs.rs2,
						rs_lo  = inputs["rhs_lo_" .. ix_unit],
						rs_hi  = inputs["rhs_hi_" .. ix_unit],
						rw     = outputs["res_rd_" .. ix_prev_unit],
						rw_lo  = outputs["res_lo_" .. ix_prev_unit],
						rw_hi  = outputs["res_hi_" .. ix_prev_unit],
					})
					inputs["lhs_lo_" .. ix_unit] = iw_lhs_outputs.rs_lo
					inputs["lhs_hi_" .. ix_unit] = iw_lhs_outputs.rs_hi
					inputs["rhs_lo_" .. ix_unit] = iw_rhs_outputs.rs_lo
					inputs["rhs_hi_" .. ix_unit] = iw_rhs_outputs.rs_hi
				end
				if ix_unit == units then
					break
				end
				local instr_split_outputs = instr_split.component({
					instr = inputs["instr_"  .. ix_unit],
				})
				local ix_next_unit = ix_unit + 1
				local unit_instance
				if ix_unit == 0 then
					unit_instance = unit_first
				else
					unit_instance = unit_middle
				end
				local unit_outputs = unit_instance.component({
					lhs_lo      = inputs["lhs_lo_" .. ix_unit],
					lhs_hi      = inputs["lhs_hi_" .. ix_unit],
					rhs_lo      = inputs["rhs_lo_" .. ix_unit],
					rhs_hi      = inputs["rhs_hi_" .. ix_unit],
					pc_lo       = inputs.pc_lo,
					pc_hi       = inputs.pc_hi,
					defer       = inputs.defer,
					instr       = inputs["instr_"  .. ix_unit],
					instr_lo    = instr_split_outputs.instr_lo,
					instr_hi    = instr_split_outputs.instr_hi,
					next_lhs_lo = inputs["lhs_lo_" .. ix_next_unit],
					next_lhs_hi = inputs["lhs_hi_" .. ix_next_unit],
					next_rhs_lo = inputs["rhs_lo_" .. ix_next_unit],
					next_rhs_hi = inputs["rhs_hi_" .. ix_next_unit],
					next_instr  = inputs["instr_"  .. ix_next_unit],
					instr_prev  = ix_unit == 0 and inputs.instr_prev or nil,
					mul_prev_lo = ix_unit == 0 and inputs.mul_prev_lo or nil,
					mul_prev_hi = ix_unit == 0 and inputs.mul_prev_hi or nil,
				})
				inputs["lhs_lo_" .. ix_next_unit] = unit_outputs.next_lhs_lo
				inputs["lhs_hi_" .. ix_next_unit] = unit_outputs.next_lhs_hi
				inputs["rhs_lo_" .. ix_next_unit] = unit_outputs.next_rhs_lo
				inputs["rhs_hi_" .. ix_next_unit] = unit_outputs.next_rhs_hi
				inputs["instr_"  .. ix_next_unit] = unit_outputs.next_instr
				inputs.pc_lo = unit_outputs.pc_lo
				inputs.pc_hi = unit_outputs.pc_hi
				outputs["res_lo_" .. ix_unit] = unit_outputs.res_lo
				outputs["res_hi_" .. ix_unit] = unit_outputs.res_hi
				outputs["res_rd_" .. ix_unit] = spaghetti.select(unit_outputs.output:band(1):zeroable(), regs_outputs.rd, 0x10000000)
			end
			outputs["lhs_lo_" .. units] = inputs["lhs_lo_" .. units]
			outputs["lhs_hi_" .. units] = inputs["lhs_hi_" .. units]
			outputs["rhs_lo_" .. units] = inputs["rhs_lo_" .. units]
			outputs["rhs_hi_" .. units] = inputs["rhs_hi_" .. units]
			outputs["instr_"  .. units] = inputs["instr_"  .. units]
			local iub = inputs["instr_"  .. units]:bor(spaghetti.lshiftk(inputs.defer:bor(2):band(3), 2))
			outputs["instr_"  .. units .. "_b"] = iub
			outputs.pc_lo = inputs.pc_lo
			outputs.pc_hi = inputs.pc_hi
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
				instr_prev             = bitx.bor(bitx.lshift(math.random(0x00000000, 0x7FFFFFFF), 1), 9),
				mul_prev_lo            = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
				mul_prev_hi            = bitx.bor(math.random(0x0000, 0xFFFF), 0x10000000),
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
			local outputs = {}
			for ix_unit = 0, units do
				local regs_outputs, err = regs.fuzz_outputs({
					instr = inputs["instr_" .. ix_unit],
				})
				if not regs_outputs then
					return nil, "regs/" .. ix_unit .. ": " .. err
				end
				for ix_prev_unit = 0, ix_unit - 1 do
					local iw_lhs_outputs, err = internal_writer.fuzz_outputs({
						rs     = regs_outputs.rs1,
						rs_lo  = inputs["lhs_lo_" .. ix_unit],
						rs_hi  = inputs["lhs_hi_" .. ix_unit],
						rw     = outputs["res_rd_" .. ix_prev_unit],
						rw_lo  = outputs["res_lo_" .. ix_prev_unit],
						rw_hi  = outputs["res_hi_" .. ix_prev_unit],
					})
					if not iw_lhs_outputs then
						return nil, "internal_writer/" .. ix_unit .. "/" .. ix_prev_unit .. "/lhs: " .. err
					end
					local iw_rhs_outputs, err = internal_writer.fuzz_outputs({
						rs     = regs_outputs.rs2,
						rs_lo  = inputs["rhs_lo_" .. ix_unit],
						rs_hi  = inputs["rhs_hi_" .. ix_unit],
						rw     = outputs["res_rd_" .. ix_prev_unit],
						rw_lo  = outputs["res_lo_" .. ix_prev_unit],
						rw_hi  = outputs["res_hi_" .. ix_prev_unit],
					})
					if not iw_rhs_outputs then
						return nil, "internal_writer/" .. ix_unit .. "/" .. ix_prev_unit .. "/rhs: " .. err
					end
					inputs["lhs_lo_" .. ix_unit] = iw_lhs_outputs.rs_lo
					inputs["lhs_hi_" .. ix_unit] = iw_lhs_outputs.rs_hi
					inputs["rhs_lo_" .. ix_unit] = iw_rhs_outputs.rs_lo
					inputs["rhs_hi_" .. ix_unit] = iw_rhs_outputs.rs_hi
				end
				if ix_unit == units then
					break
				end
				local instr_split_outputs, err = instr_split.fuzz_outputs({
					instr = inputs["instr_"  .. ix_unit],
				})
				if not instr_split_outputs then
					return nil, "instr_split/" .. ix_unit .. ": " .. err
				end
				local ix_next_unit = ix_unit + 1
				local unit_instance
				if ix_unit == 0 then
					unit_instance = unit_first
				else
					unit_instance = unit_middle
				end
				local unit_outputs, err = unit_instance.fuzz_outputs({
					lhs_lo      = inputs["lhs_lo_" .. ix_unit],
					lhs_hi      = inputs["lhs_hi_" .. ix_unit],
					rhs_lo      = inputs["rhs_lo_" .. ix_unit],
					rhs_hi      = inputs["rhs_hi_" .. ix_unit],
					pc_lo       = inputs.pc_lo,
					pc_hi       = inputs.pc_hi,
					defer       = inputs.defer,
					instr       = inputs["instr_"  .. ix_unit],
					instr_lo    = instr_split_outputs.instr_lo,
					instr_hi    = instr_split_outputs.instr_hi,
					next_lhs_lo = inputs["lhs_lo_" .. ix_next_unit],
					next_lhs_hi = inputs["lhs_hi_" .. ix_next_unit],
					next_rhs_lo = inputs["rhs_lo_" .. ix_next_unit],
					next_rhs_hi = inputs["rhs_hi_" .. ix_next_unit],
					next_instr  = inputs["instr_"  .. ix_next_unit],
					instr_prev  = ix_unit == 0 and inputs.instr_prev or nil,
					mul_prev_lo = ix_unit == 0 and inputs.mul_prev_lo or nil,
					mul_prev_hi = ix_unit == 0 and inputs.mul_prev_hi or nil,
				})
				if not unit_outputs then
					return nil, "unit/" .. ix_unit .. ": " .. err
				end
				inputs["lhs_lo_" .. ix_next_unit] = unit_outputs.next_lhs_lo
				inputs["lhs_hi_" .. ix_next_unit] = unit_outputs.next_lhs_hi
				inputs["rhs_lo_" .. ix_next_unit] = unit_outputs.next_rhs_lo
				inputs["rhs_hi_" .. ix_next_unit] = unit_outputs.next_rhs_hi
				inputs["instr_"  .. ix_next_unit] = unit_outputs.next_instr
				inputs.pc_lo = unit_outputs.pc_lo
				inputs.pc_hi = unit_outputs.pc_hi
				outputs["res_lo_" .. ix_unit] = unit_outputs.res_lo
				outputs["res_hi_" .. ix_unit] = unit_outputs.res_hi
				outputs["res_rd_" .. ix_unit] = bitx.band(unit_outputs.output, 1) ~= 0 and regs_outputs.rd or 0x10000000
			end
			outputs["lhs_lo_" .. units] = inputs["lhs_lo_" .. units]
			outputs["lhs_hi_" .. units] = inputs["lhs_hi_" .. units]
			outputs["rhs_lo_" .. units] = inputs["rhs_lo_" .. units]
			outputs["rhs_hi_" .. units] = inputs["rhs_hi_" .. units]
			outputs["instr_"  .. units] = inputs["instr_"  .. units]
			local iub = inputs["instr_"  .. units]
			if bitx.band(inputs.defer, 1) ~= 0 then
				iub = bitx.bor(iub, 0xC)
			else
				iub = bitx.bor(iub, 0x8)
			end
			outputs["instr_"  .. units .. "_b"] = iub
			outputs.pc_lo = inputs.pc_lo
			outputs.pc_hi = inputs.pc_hi
			return outputs
		end,
	}
end)

local spaghetti = require("spaghetti")
local bitx      = require("spaghetti.bitx")
local testbed   = require("spaghetti.testbed")
local regs      = require("r4.comp.cpu.core.regs").instantiate()

return testbed.module(function(params)
	local instrs = 4
	local inputs = {}
	local outputs = {}
	for ix_instr = 0, instrs - 1 do
		table.insert(inputs , { name = "instr_" .. ix_instr, index = #inputs  + 1, keepalive = 0x00000001, payload = 0xFFFFFFFE, initial = 0x00000001 })
		table.insert(outputs, { name = "addr_"  .. ix_instr .. "1a", index = #outputs + 1, keepalive = 0x0FFFFF80, payload = 0x0000007E })
		table.insert(outputs, { name = "addr_"  .. ix_instr .. "1b", index = #outputs + 1, keepalive = 0x0FFFFF80, payload = 0x0000007E })
		table.insert(outputs, { name = "addr_"  .. ix_instr .. "2a", index = #outputs + 1, keepalive = 0x0FFFFF80, payload = 0x0000007E })
		table.insert(outputs, { name = "addr_"  .. ix_instr .. "2b", index = #outputs + 1, keepalive = 0x0FFFFF80, payload = 0x0000007E })
	end

	return {
		tag = "reg_r",
		opt_params = {
			thread_count  = 1,
			temp_initial  = 1,
			temp_final    = 0.5,
			temp_loss     = 1e-6,
			round_length  = 10000,
		},
		stacks        = 1,
		storage_slots = 31,
		work_slots    = 20,
		inputs = inputs,
		outputs = outputs,
		func = function(inputs)
			local regs_outputs = {}
			for ix_instr = 0, instrs - 1 do
				regs_outputs[ix_instr] = regs.component({
					instr = inputs["instr_" .. ix_instr],
				})
			end
			local function const_sub(expr, amount)
				for ix_bit = 0, 3 do
					local b = bitx.lshift(1, ix_bit)
					if bitx.band(amount, b) ~= 0 then
						local expr_sub = expr
						local flip_sub = spaghetti.constant(0x3FFFFFFF)
						if ix_bit > 0 then
							expr_sub = expr_sub:bsub(b - 1)
							flip_sub = flip_sub:bsub(b - 1)
						end
						expr = expr:bxor(spaghetti.lshift(0x3FFFFFFE, expr_sub):bxor(flip_sub)):force(0x07FFFFC0, 0x0000003F)
					end
				end
				return expr
			end
			local outputs = {}
			for ix_instr = 0, instrs - 1 do
				local output_1 = regs_outputs[ix_instr].rs1:bxor(0x17FFFFFF)
				local output_2 = regs_outputs[ix_instr].rs2:bxor(0x17FFFFFF)
				output_1 = const_sub(output_1, ix_instr * 2 + 2)
				output_2 = const_sub(output_2, ix_instr * 2 + 3)
				output_1 = spaghetti.lshiftk(output_1, 1)
				output_2 = spaghetti.lshiftk(output_2, 1)
				outputs["addr_" .. ix_instr .. "1a"] = output_1
				outputs["addr_" .. ix_instr .. "1b"] = output_1
				outputs["addr_" .. ix_instr .. "2a"] = output_2
				outputs["addr_" .. ix_instr .. "2b"] = output_2
			end
			return outputs
		end,
		fuzz_inputs = function()
			local inputs = {}
			for ix_instr = 0, instrs - 1 do
				inputs["instr_" .. ix_instr] = bitx.bor(bitx.lshift(math.random(0x00000000, 0x7FFFFFFF), 1), 1)
			end
			return inputs
		end,
		fuzz_outputs = function(inputs)
			local regs_outputs = {}
			for ix_instr = 0, instrs - 1 do
				local err
				regs_outputs[ix_instr], err = regs.fuzz_outputs({
					instr = inputs["instr_" .. ix_instr],
				})
				if not regs_outputs[ix_instr] then
					return nil, "regs/" .. ix_instr .. ": " .. err
				end
			end
			local outputs = {}
			for ix_instr = 0, instrs - 1 do
				local output_1 = bitx.band(regs_outputs[ix_instr].rs1, 0x1F)
				local output_2 = bitx.band(regs_outputs[ix_instr].rs2, 0x1F)
				output_1 = 0x0FFFFFFA - ix_instr * 4     - output_1 * 2
				output_2 = 0x0FFFFFFA - ix_instr * 4 - 2 - output_2 * 2
				outputs["addr_"  .. ix_instr .. "1a"] = output_1
				outputs["addr_"  .. ix_instr .. "1b"] = output_1
				outputs["addr_"  .. ix_instr .. "2a"] = output_2
				outputs["addr_"  .. ix_instr .. "2b"] = output_2
			end
			return outputs
		end,
	}
end)

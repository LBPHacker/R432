local plot     = require("spaghetti.plot")
local bitx     = require("spaghetti.bitx")
local emulator = require("r4.emulator")
local r4plot   = require("r4.plot")

local pt = plot.pt

local row_size     = emulator.row_size
local reg_count    = emulator.reg_count
local sub_eu_count = emulator.sub_eu_count
local core_size    = 16

local global_key = "r4ilfuzz"

local function split32(value)
	return bitx.band(            value     , 0xFFFF),
	       bitx.band(bitx.rshift(value, 16), 0xFFFF)
end

local function merge32(value_lo, value_hi)
	return bitx.bor(value_lo, bitx.lshift(value_hi, 16))
end

local function detect()
	local cx, cy, mem_row_count, core_count, machine_id
	for id in sim.parts() do
		if sim.partProperty(id, "ctype") == 0x1864A205 and sim.partProperty(id, "type") == elem.DEFAULT_PT_QRTZ then
			local x, y = sim.partPosition(id)
			machine_id = sim.partProperty(sim.partID(x - 1, y), "ctype")
			cx, cy = x, y
			local arr = {}
			while true do
				x = x + 1
				local value = sim.partProperty(sim.partID(x, y), "ctype")
				if value == 0 then
					break
				end
				table.insert(arr, string.char(value))
			end
			local str = table.concat(arr)
			mem_row_count, core_count = assert(str:match("^R4A(..)(..)$"))
			mem_row_count = tonumber(mem_row_count)
			core_count = tonumber(core_count)
			break
		end
	end
	assert(mem_row_count)
	return cx, cy, mem_row_count, core_count, machine_id
end

local function pick_random(tbl)
	return tbl[math.random(1, #tbl)]
end

local function run(params)
	if rawget(_G, global_key) then
		_G[global_key].unregister()
	end

	local text_x = params.text_x or 80
	local text_y = params.text_y or 80
	local plot_x = params.plot_x or 100
	local plot_y = params.plot_y or 100

	local mem_row_count = 37
	local core_count = 3
	local machine_id = 0xDEAD

	r4plot.run({
		x             = plot_x,
		y             = plot_y,
		clear_sim     = true,
		mem_row_count = mem_row_count,
		core_count    = core_count,
		machine_id    = machine_id,
		-- debug_stacks = {
		-- 	x = 40,
		-- 	y = 40,
		-- },
	})
	local cx, cy
	do
		local mem_row_count_d, core_count_d, machine_id_d = detect()
		cx, cy, mem_row_count_d, core_count_d, machine_id_d = detect()
		assert(mem_row_count == mem_row_count_d)
		assert(core_count == core_count_d)
		assert(machine_id == machine_id_d)
	end
	local y_head = cy - 4 - core_count * core_size

	local emu = emulator.make_context({
		mem_row_count = mem_row_count,
		core_count    = core_count,
	})
	emu.started = true -- TODO: remove

	local pause_asap = false
	local frames_done = 0
	local fail_msg
	local function fail(msg)
		if not fail_msg then
			fail_msg = msg
		end
		pause_asap = true
	end

	local function mem_id(addr)
		assert(bitx.band(addr, 3) == 0)
		local col = bitx.band(bitx.rshift(addr, 2), 0x7F)
		local row = bitx.band(bitx.rshift(addr, 9), 0x3F)
		assert(row < mem_row_count)
		local x = cx + bitx.rshift(col, 6) + bitx.band(col, 0x3F) * 2 + 28
		local y = cy - row - core_count * core_size - 18
		return sim.partID(x, y)
	end
	local function set_mem(addr, value)
		emu.mem[addr] = value
		local bray = bitx.band(value, 1) ~= 0
		local id = mem_id(addr)
		sim.partProperty(id, "type" , bray and pt.BRAY or pt.FILT)
		sim.partProperty(id, "life" , bray and 988 or 4)
		sim.partProperty(id, "tmp"  , bray and   1 or 0)
		sim.partProperty(id, "ctype", bitx.bor(value, 1))
	end
	local function compare_mem(addr, value)
		local id = mem_id(addr)
		local expected = emu.mem[addr]
		local got = bitx.band(sim.partProperty(id, "ctype"), 0xFFFFFFFE)
		if sim.partProperty(id, "type") == pt.BRAY then
			got = bitx.bor(got, 1)
		end
		if expected ~= got then
			fail(("mem[0x%04X] expected to be 0x%08X, is actually 0x%08X"):format(addr, expected, got))
		end
	end

	local function reg_id(addr)
		assert(addr >= 0 and addr < reg_count)
		return sim.partID(cx + 123 - addr * 2, y_head - 2),
		       sim.partID(cx + 124 - addr * 2, y_head - 2)
	end
	local function set_reg(addr, value)
		if addr == 0 then
			return
		end
		emu.regs[addr] = value
		local id_lo, id_hi = reg_id(addr)
		sim.partProperty(id_lo, "ctype", bitx.bor(0x10000000, bitx.band(            value     , 0xFFFF)))
		sim.partProperty(id_hi, "ctype", bitx.bor(0x10000000, bitx.band(bitx.rshift(value, 16), 0xFFFF)))
	end
	local function compare_reg(addr, value)
		local id_lo, id_hi = reg_id(addr)
		local expected = emu.regs[addr]
		local got = merge32(bitx.band(sim.partProperty(id_lo, "ctype"), 0xFFFF),
		                    bitx.band(sim.partProperty(id_hi, "ctype"), 0xFFFF))
		if expected ~= got then
			fail(("regs[0x%02X] expected to be 0x%08X, is actually 0x%08X"):format(addr, expected, got))
		end
	end

	local function pc_id()
		return sim.partID(cx + 125, y_head),
		       sim.partID(cx + 127, y_head)
	end
	local function set_pc(value)
		local pc_lo_id, pc_hi_id = pc_id()
		local pc_lo, pc_hi = split32(value)
		sim.partProperty(pc_lo_id, "ctype", bitx.bor(0x10000000, pc_lo))
		sim.partProperty(pc_hi_id, "ctype", bitx.bor(0x10000000, pc_hi))
	end
	local function started_id()
		return sim.partID(cx + 129, y_head)
	end
	local function set_started(value)
		sim.partProperty(started_id(), "ctype", bitx.bor(0x10000000, value and 0 or 1))
	end
	local function compare_started(expected)
		local got = (sim.partProperty(started_id(), "ctype") == 0x10000000)
		if expected ~= got then
			fail(("started expected to be %s, is actually %s"):format(addr, tostring(expected), tostring(got)))
		end
	end

	local function sync_head()
		set_pc(emu.pc)
		set_started(emu.started)
		local instrs = emu:fetch_()
		for ix_subeu = 0, sub_eu_count - 1 do
			local instr = instrs[ix_subeu]
			sim.partProperty(sim.partID(cx + 143 + ix_subeu * 2, y_head), "ctype", instr)
			local rs1   = bitx.band(bitx.rshift(instr, 15), 0x1F)
			local rs2   = bitx.band(bitx.rshift(instr, 20), 0x1F)
			local rs1_lo, rs1_hi = split32(emu.regs[rs1])
			local rs2_lo, rs2_hi = split32(emu.regs[rs2])
			sim.partProperty(sim.partID(cx + 124 + ix_subeu * 8, y_head), "ctype", bitx.bor(0x10000000, rs1_lo))
			sim.partProperty(sim.partID(cx + 126 + ix_subeu * 8, y_head), "ctype", bitx.bor(0x10000000, rs1_hi))
			sim.partProperty(sim.partID(cx + 128 + ix_subeu * 8, y_head), "ctype", bitx.bor(0x10000000, rs2_lo))
			sim.partProperty(sim.partID(cx + 130 + ix_subeu * 8, y_head), "ctype", bitx.bor(0x10000000, rs2_hi))
		end
	end

	local until_next_randomize
	local function randomize()
		for i = 0, (mem_row_count * row_size - 1) * 4, 4 do
			set_mem(i, bitx.bor(0x00000013,
			                    -- bitx.lshift(pick_random({ 0, 1, 2, 3, 4, 5, 6, 7 }), 12),
			                    bitx.lshift(math.random(0, 7), 12),
			                    bitx.lshift(math.random(0, 0x1F), 7),
			                    bitx.lshift(math.random(0, 0x1F), 15),
			                    bitx.lshift(math.random(0, 0xFFF), 20)))
		end
		for i = 1, reg_count - 1 do
			set_reg(i, 0x00000000)
		end
		sync_head()
		until_next_randomize = math.random(50, 200)
	end
	randomize()

	local function tick()
		local text
		if fail_msg then
			text = "Failed: " .. fail_msg
		else
			text = ("Fuzzing, %i iterations done..."):format(frames_done)
		end
		gfx.drawText(text_x, text_y, text)
		if pause_asap then
			sim.paused(true)
			pause_asap = false
		end
	end

	local function aftersim()
		frames_done = frames_done + 1
		local frame_result = emu:frame("none")
		for addr, value in pairs(frame_result.reg_writes) do
			compare_reg(addr, value)
		end
		for addr, value in pairs(frame_result.mem_writes) do
			compare_mem(addr, value)
		end
		compare_started(frame_result.started)
		until_next_randomize = until_next_randomize - 1
		if until_next_randomize == 0 then
			randomize()
		end
	end

	local function aftersimdraw()
		-- TODO
	end

	event.register(event.TICK, tick)
	event.register(event.AFTERSIM, aftersim)
	event.register(event.AFTERSIMDRAW, aftersimdraw)
	local function unregister()
		event.unregister(event.TICK, tick)
		event.unregister(event.AFTERSIM, aftersim)
		event.unregister(event.AFTERSIMDRAW, aftersimdraw)
	end
	_G[global_key] = {
		unregister = unregister,
	}
	sim.paused(false)
end

return {
	run = run,
}

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

local function random32()
	return merge32(math.random(0x0000, 0xFFFF), math.random(0x0000, 0xFFFF))
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
	local which_weight
	do
		local weight_sum = 0
		for _, item in ipairs(tbl) do
			weight_sum = weight_sum + item.weight
		end
		which_weight = math.random(0, weight_sum - 1)
	end
	local which
	do
		local weight_sum = 0
		for _, item in ipairs(tbl) do
			if which_weight >= weight_sum and which_weight < weight_sum + item.weight then
				which = item
				break
			end
			weight_sum = weight_sum + item.weight
		end
	end
	return bitx.bor(which.constant, bitx.band(random32(), bitx.bxor(0xFFFFFFFF, which.mask)))
end

local function run(params)
	if rawget(_G, global_key) then
		_G[global_key].unregister()
	end

	local text_x = params.text_x or 80
	local text_y = params.text_y or 80
	local plot_x = params.plot_x or 100
	local plot_y = params.plot_y or 100

	local specific_sequence
	if false then
		local instr_seq = {}
		if false then
			for i = 1, 1000 do
				table.insert(instr_seq, pick_random({
					{ constant = 0x00002020, mask = 0x00002070, weight =   100 },
				}))
			end
			table.insert(instr_seq, 0x00000050)
			for _, v in ipairs(instr_seq) do
				print(("0x%08X,"):format(v))
			end
		else
			instr_seq = {
				0x83BFB72D,
				0x00000050,
			}
		end
		specific_sequence = {
			instr_seq = instr_seq,
		}
	end

	local mem_row_count = 37
	local core_count = 5
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
		local mem_row_count_d, core_count_d, machine_id_d
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

	local save_snap
	local auto_snap = false
	local always_compare_all = false
	local auto_unpause = true
	local load_snap_path -- = "r4ilfuzz.1772743024.state"

	if load_snap_path then
		auto_snap = false
	end

	local pause_asap = false
	local frames_done = 0
	local fail_msg
	local function fail(msg)
		if not fail_msg then
			if auto_snap then
				save_snap()
			end
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
	local function get_mem(addr)
		local id = mem_id(addr)
		local got = bitx.band(sim.partProperty(id, "ctype"), 0xFFFFFFFE)
		if sim.partProperty(id, "type") == pt.BRAY then
			got = bitx.bor(got, 1)
		end
		return got
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
		local expected = emu.mem[addr]
		local got = get_mem(addr)
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
	local function get_reg(addr)
		local id_lo, id_hi = reg_id(addr)
		return merge32(bitx.band(sim.partProperty(id_lo, "ctype"), 0xFFFF),
		               bitx.band(sim.partProperty(id_hi, "ctype"), 0xFFFF))
	end
	local function compare_reg(addr, value)
		local expected = emu.regs[addr]
		local got = get_reg(addr)
		if expected ~= got then
			fail(("regs[0x%02X] expected to be 0x%08X, is actually 0x%08X"):format(addr, expected, got))
		end
	end

	local function pc_id()
		return sim.partID(cx + 125, y_head),
		       sim.partID(cx + 127, y_head)
	end
	local function set_pc(value)
		emu.pc = value
		local pc_lo_id, pc_hi_id = pc_id()
		local pc_lo, pc_hi = split32(value)
		sim.partProperty(pc_lo_id, "ctype", bitx.bor(0x10000000, pc_lo))
		sim.partProperty(pc_hi_id, "ctype", bitx.bor(0x10000000, pc_hi))
	end
	local function get_pc()
		local pc_lo_id, pc_hi_id = pc_id()
		return merge32(bitx.band(sim.partProperty(pc_lo_id, "ctype"), 0xFFFF),
		               bitx.band(sim.partProperty(pc_hi_id, "ctype"), 0xFFFF))
	end
	local function compare_pc()
		local expected = emu.pc
		local got = get_pc()
		if expected ~= got then
			fail(("pc expected to be 0x%08X, is actually 0x%08X"):format(expected, got))
		end
	end
	local function started_id()
		return sim.partID(cx + 129, y_head)
	end
	local function set_started(value)
		emu.started = value
		sim.partProperty(started_id(), "ctype", bitx.bor(0x10000000, value and 0 or 1))
	end
	local function get_started()
		return sim.partProperty(started_id(), "ctype") == 0x10000000
	end
	local function compare_started(expected)
		local got = get_started()
		if expected ~= got then
			fail(("started expected to be %s, is actually %s"):format(tostring(expected), tostring(got)))
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

	local snap
	local function snap_all()
		snap = {
			mem = {},
			regs = {},
		}
		for i = 0, (mem_row_count * row_size - 1) * 4, 4 do
			snap.mem[i] = get_mem(i)
		end
		for i = 1, reg_count - 1 do
			snap.regs[i] = get_reg(i)
		end
		snap.started = get_started()
		snap.pc = get_pc()
	end
	function save_snap()
		local path = global_key .. "." .. os.time() .. ".state"
		local handle = assert(io.open(path, "wb"))
		for i = 0, (mem_row_count * row_size - 1) * 4, 4 do
			assert(handle:write(("0x%08X\n"):format(snap.mem[i])))
		end
		for i = 1, reg_count - 1 do
			assert(handle:write(("0x%08X\n"):format(snap.regs[i])))
		end
		assert(handle:write(("0x%08X\n"):format(snap.started and 1 or 0)))
		assert(handle:write(("0x%08X\n"):format(snap.pc)))
		assert(handle:close())
		print("saved to " .. path)
	end
	local function load_all(state_file)
		local handle = assert(io.open(state_file, "rb"))
		local pull = handle:read("*a"):gmatch("[^\n]+")
		assert(handle:close())
		for i = 0, (mem_row_count * row_size - 1) * 4, 4 do
			set_mem(i, tonumber(pull()))
		end
		for i = 1, reg_count - 1 do
			set_reg(i, tonumber(pull()))
		end
		set_started(tonumber(pull()) ~= 0)
		set_pc(tonumber(pull()))
		sync_head()
	end

	local until_next_randomize
	local function randomize()
		if specific_sequence then
			if not specific_sequence.mem then
				specific_sequence.mem = {}
				for index, value in ipairs(specific_sequence.instr_seq) do
					specific_sequence.mem[(index - 1) * 4] = value
				end
			end
			for i = 0, (mem_row_count * row_size - 1) * 4, 4 do
				set_mem(i, (specific_sequence.mem and specific_sequence.mem[i]) or 0x00000013)
			end
			for i = 1, reg_count - 1 do
				set_reg(i, (specific_sequence.regs and specific_sequence.regs[i]) or 0)
			end
			set_pc(specific_sequence.pc or 0)
			if specific_sequence.started == nil then
				specific_sequence.started = true
			end
			set_started(specific_sequence.started)
			sync_head()
			until_next_randomize = nil
			return
		end
		if load_snap_path then
			load_all(load_snap_path)
			load_snap_path = nil
			return
		end
		for i = 0, (mem_row_count * row_size - 1) * 4, 4 do
			set_mem(i, pick_random({
				{ constant = 0x00000010, mask = 0x00000074, weight = 10000 },
				{ constant = 0x00000030, mask = 0x00000074, weight = 10000 },
				{ constant = 0x00000050, mask = 0x00000050, weight =     1 },
				{ constant = 0x00000014, mask = 0x00000054, weight =   100 },
				{ constant = 0x00000048, mask = 0x00000058, weight =   100 },
				{ constant = 0x00000044, mask = 0x0000005C, weight =   100 },
				{ constant = 0x00000040, mask = 0x0000005C, weight =   100 },
				{ constant = 0x00000020, mask = 0x00000070, weight =   100 },
				{ constant = 0x00000000, mask = 0x00000074, weight =   100 },
				{ constant = 0x00000004, mask = 0x00000074, weight =    10 },
			}))
		end
		for i = 1, reg_count - 1 do
			set_reg(i, random32())
		end
		set_pc(random32())
		set_started(true) -- TODO: send in start/stop signals
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

	local function compare_all()
		for i = 0, (mem_row_count * row_size - 1) * 4, 4 do
			compare_mem(i, emu.mem[i])
		end
		for i = 1, reg_count - 1 do
			compare_reg(i, emu.regs[i])
		end
		compare_started(emu.started)
		compare_pc()
	end

	local function aftersim()
		frames_done = frames_done + 1
		local frame_result = emu:frame("none")
		if always_compare_all then
			compare_all()
		end
		if auto_snap then
			snap_all()
		else
			for addr, value in pairs(frame_result.reg_writes) do
				compare_reg(addr, value)
			end
			for addr, value in pairs(frame_result.mem_writes) do
				compare_mem(addr, value)
			end
			compare_started(frame_result.started)
			compare_pc()
		end
		if specific_sequence then
			compare_all()
			if not emu.started then
				fail("reached end of specific sequence")
			end
		end
		if until_next_randomize then
			until_next_randomize = until_next_randomize - 1
			if until_next_randomize == 0 then
				randomize()
			end
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
	if auto_unpause then
		sim.paused(false)
	end
end

return {
	run = run,
}

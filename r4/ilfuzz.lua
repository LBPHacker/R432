local modulepack   = require("modulepack")
local plot         = require("spaghetti.plot")
local bitx         = require("spaghetti.bitx")
local emulator     = require("r4.emulator")
local disassembler = require("r4.disassembler")
local r4plot       = require("r4.plot")
local common       = require("r4.common")

local pt = plot.pt

local row_size     = emulator.row_size
local reg_count    = emulator.reg_count
local sub_eu_count = emulator.sub_eu_count
local core_size    = 16

local global_key = "r4ilfuzz"

local split32  = common.split32
local merge32  = common.merge32

local random_next, get_random_state, set_random_state
do
	local random_state = os.time() % 0x100000000

	function random_next()
		random_state = bitx.bxor(random_state, bitx.lshift(random_state, 13))
		random_state = bitx.bxor(random_state, bitx.rshift(random_state, 17))
		random_state = bitx.bxor(random_state, bitx.lshift(random_state,  5))
		return random_state
	end

	function get_random_state()
		return random_state
	end

	function set_random_state(value)
		random_state = value
	end
end

local function random_between(lo, hi)
	return math.floor(random_next() * (hi + 1 - lo) / 0x100000000) + lo
end

local random32 = random_next

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
		which_weight = random_between(0, weight_sum - 1)
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
			for i = 1, 20 do
				table.insert(instr_seq, pick_random({
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
			table.insert(instr_seq, 0x00000050)
			for ix_item, item in ipairs(instr_seq) do
				local str = disassembler.disassemble(item, (ix_item - 1) * 4 + 0)
				local collect = {}
				for word in str:gmatch("%S+") do
					table.insert(collect, word)
					table.insert(collect, (" "):rep(12 - #word))
				end
				print(("0x%08X, -- %s"):format(item, table.concat(collect)))
			end
		else
			instr_seq = {
				0x3C5F7711, -- andi        x14,        x30,        0x000003C5
				0x217E1A99, -- slli        x21,        x28,        23
				0x7AB2F612, -- andi        x12,        x5,         0x000007AB
				0xEBD407B3, -- mul         x15,        x8,         x29
				0xE2FEE4B9, -- mul         x9,         x29,        x15
				0x31061FBA, -- sll         x31,        x12,        x16
				0x82A14230, -- mul         x4,         x2,         x10
				0x4547A792, -- sltiu       x15,        x15,        1108
				0x9812FC3A, -- and         x24,        x5,         x1
				0x996B00BA, -- add         x1,         x22,        x22
				0x4BACDE91, -- srai        x29,        x25,        26
				0x4F893C9B, -- slti        x25,        x18,        1272
				0x59929B91, -- slli        x23,        x5,         25
				0x488CDB9B, -- srai        x23,        x25,        8
				0xE73BD292, -- srai        x5,         x23,        19
				0xD941AB05, -- fence
				0xB6B3E51B, -- ori         x10,        x7,         0xFFFFFB6B
				0xC7CBB6B0, -- czero.nez   x13,        x23,        x28
				0x21CABB93, -- slti        x23,        x21,        540
				0x39D3161A, -- slli        x12,        x6,         29
				0x00000050, -- hlt
			}
		end
		specific_sequence = {
			instr_seq = instr_seq,
			random_state = 1339,
		}
	end

	local mem_row_count = 37
	local core_types = "miimm"
	local machine_id = 0xDEAD
	local save_snap
	local auto_snap = true
	local always_compare_all = true
	local auto_unpause = true
	local load_snap_path -- = "r4ilfuzz.1775588672.state"

	if load_snap_path then
		auto_snap = false
	end

	local core_count = #core_types
	local cx = plot_x - 18
	local cy = plot_y + core_count * core_size + mem_row_count + 27
	local extra_parts = {}
	do
		local pt = plot.pt
		local ucontext = plot.common_structures(extra_parts)
		local part = ucontext.part
		local ldtc = ucontext.ldtc

		for ix_eu = 0, core_count - 1 do
			local x_base = cx - plot_x + 164
			local y_base = cy - plot_y + (ix_eu - core_count) * core_size - 2
			part({ type = pt.FILT, x = x_base, y = y_base + 3 })
			part({ type = pt.FILT, x = x_base, y = y_base + 4 })
			local source_0 = part({ type = pt.FILT, x = x_base + 3, y = y_base + 3, ctype = 0x10000000 })
			local source_1 = part({ type = pt.FILT, x = x_base + 3, y = y_base + 4, ctype = 0x10000000 })
			ldtc(x_base + 1, y_base + 3, source_0.x, source_0.y)
			ldtc(x_base + 1, y_base + 4, source_1.x, source_1.y)
		end
	end

	r4plot.run({
		x             = plot_x,
		y             = plot_y,
		clear_sim     = true,
		mem_row_count = mem_row_count,
		core_types    = core_types,
		machine_id    = machine_id,
		extra_parts   = extra_parts,
		-- debug_stacks = {
		-- 	x = 40,
		-- 	y = 40,
		-- },
	})
	local y_head = cy - 4 - core_count * core_size

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

	local function bus_ids(ix_eu)
		local x_base = cx + 162
		local y_base = cy - 2 + (ix_eu - core_count) * core_size
		local out_0_id = sim.partID(x_base    , y_base    )
		local out_1_id = sim.partID(x_base + 1, y_base + 1)
		local out_2_id = sim.partID(x_base + 1, y_base + 2)
		local in_0_id  = sim.partID(x_base + 5, y_base + 3)
		local in_1_id  = sim.partID(x_base + 5, y_base + 4)
		return out_0_id, out_1_id, out_2_id, in_0_id, in_1_id
	end

	local bus_inputs = {}
	local bus_outputs = {}
	local function compare_bus_outputs()
		for ix_eu = 0, core_count - 1 do
			local store       = bus_outputs[ix_eu].store
			local load        = bus_outputs[ix_eu].load
			local sign_extend = bus_outputs[ix_eu].sign_extend
			local size        = bus_outputs[ix_eu].size
			local address     = bus_outputs[ix_eu].address
			local value       = bus_outputs[ix_eu].value
			local out_0_id, out_1_id, out_2_id = bus_ids(ix_eu)
			local out_0 = sim.partProperty(out_0_id, "ctype")
			local out_1 = sim.partProperty(out_1_id, "ctype")
			local out_2 = sim.partProperty(out_2_id, "ctype")
			local function check(what, mask, expected, got)
				local expected = bitx.band(expected, mask)
				local got      = bitx.band(got     , mask)
				if expected ~= got then
					fail(("bus[%i].%s & 0x%08X expected to be 0x%08X, is actually 0x%08X"):format(ix_eu, what, mask, expected, got))
				end
			end
			check("out_0", 0x01000000, load  and 0x01000000 or 0x00000000, out_0)
			check("out_0", 0x02000000, store and 0x02000000 or 0x00000000, out_0)
			if load or store then
				check("out_0", 0x00FFFFFF, bitx.band(address, 0xFFFFFF), out_0)
				check("out_1", 0x00FF0000, bitx.band(bitx.rshift(address, 8), 0xFF0000), out_1)
				if size == 4 then
					check("out_1", 0x02000000, 0x02000000, out_1)
				else
					check("out_1", 0x01000000, bitx.lshift(size - 1, 24), out_1)
				end
			end
			if load then
				check("out_1", 0x04000000, sign_extend and 0x00000000 or 0x04000000, out_1)
			end
			if store then
				local value_lo, value_hi = split32(value)
				check("out_1", 0x0000FFFF, value_lo, out_1)
				check("out_2", 0x0000FFFF, value_hi, out_2)
			end
		end
	end
	local function sync_bus_inputs()
		for ix_eu = 0, core_count - 1 do
			local value_lo, value_hi = split32(bus_inputs[ix_eu].value)
			value_lo = bitx.bor(value_lo, bus_inputs[ix_eu].handled and 0x10000 or 0)
			value_lo = bitx.bor(value_lo, bus_inputs[ix_eu].wait    and 0x20000 or 0)
			local _, _, _, in_0_id, in_1_id = bus_ids(ix_eu)
			sim.partProperty(in_0_id, "ctype", bitx.bor(value_lo, 0x10000000))
			sim.partProperty(in_1_id, "ctype", bitx.bor(value_hi, 0x10000000))
		end
	end
	local function empty_bus_inputs()
		for ix_eu = 0, core_count - 1 do
			bus_inputs[ix_eu] = {
				value   = 0x00000000,
				handled = false,
				wait    = false,
			}
		end
		sync_bus_inputs()
	end
	local function random_bus_inputs()
		-- empty_bus_inputs()
		for ix_eu = 0, core_count - 1 do
			bus_inputs[ix_eu] = {
				value   = random32(),
				handled = random_between(0, 1) == 0,
				wait    = random_between(0, 1) == 0,
			}
		end
		sync_bus_inputs()
	end
	local function bus_access(ix_eu, store, load, sign_extend, size, address, value)
		bus_outputs[ix_eu] = {
			store       = store,
			load        = load,
			sign_extend = sign_extend,
			size        = size,
			address     = address,
			value       = value,
		}
		return bus_inputs[ix_eu].value, bus_inputs[ix_eu].handled, bus_inputs[ix_eu].wait
	end
	empty_bus_inputs()

	local emu = emulator.make_context({
		mem_row_count = mem_row_count,
		core_types    = core_types,
		bus_access    = bus_access,
	})

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

	local function mulstate_id()
		return sim.partID(cx + 141, y_head),
		       sim.partID(cx + 135, y_head),
		       sim.partID(cx + 139, y_head)
	end
	local function set_mulstate(instr, value)
		emu.mulstate_instr = instr
		emu.mulstate_value = value
		local mulstate_instr_id, mulstate_lo_id, mulstate_hi_id = mulstate_id()
		local value_lo, value_hi = split32(value)
		sim.partProperty(mulstate_instr_id, "ctype", instr)
		sim.partProperty(mulstate_lo_id, "ctype", bitx.bor(0x10000000, value_lo))
		sim.partProperty(mulstate_hi_id, "ctype", bitx.bor(0x10000000, value_hi))
	end
	local function get_mulstate()
		local mulstate_instr_id, mulstate_lo_id, mulstate_hi_id = mulstate_id()
		return                   sim.partProperty(mulstate_instr_id, "ctype"),
		       merge32(bitx.band(sim.partProperty(mulstate_lo_id   , "ctype"), 0xFFFF),
		               bitx.band(sim.partProperty(mulstate_hi_id   , "ctype"), 0xFFFF))
	end
	local function compare_mulstate()
		local expected_instr, expected_value = emu.mulstate_instr, emu.mulstate_value
		local got_instr, got_value = get_mulstate()
		if expected_instr ~= got_instr then
			fail(("mulstate_instr expected to be 0x%08X, is actually 0x%08X"):format(expected_instr, got_instr))
		end
		if bitx.band(expected_instr, 0x06000074) == 0x02000034 then
			if expected_value ~= got_value then
				fail(("mulstate_value expected to be 0x%08X, is actually 0x%08X"):format(expected_value, got_value))
			end
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

	local next_emu_start_action = "none"
	local function start_action_ctype(start_action)
		local ctype = 0x10000000
		if start_action == "start" then
			ctype = 0x10000001
		elseif start_action == "stop" then
			ctype = 0x10000002
		end
		return ctype
	end
	local function start_action_str(ctype)
		if ctype == 0x10000001 then
			return "start"
		elseif ctype == 0x10000002 then
			return "stop"
		end
		return "none"
	end
	local function set_next_start_action(start_action)
		sim.partProperty(sim.partID(cx + 112, cy - 18), "ctype", start_action_ctype(start_action))
		next_emu_start_action = start_action
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
		snap.random_state = get_random_state()
		snap.started = get_started()
		snap.mulstate_instr, snap.mulstate_value = get_mulstate()
		snap.pc = get_pc()
		snap.next_emu_start_action = next_emu_start_action
		snap.bus_inputs = {}
		for ix_eu = 0, core_count - 1 do
			snap.bus_inputs[ix_eu] = bus_inputs[ix_eu]
		end
	end
	function save_snap()
		local path = global_key .. "." .. os.time() .. ".state"
		local handle = assert(io.open(path, "wb"))
		assert(handle:write(("0x%08X\n"):format(mem_row_count)))
		assert(handle:write(("0x%08X\n"):format(core_count)))
		for i = 0, (mem_row_count * row_size - 1) * 4, 4 do
			assert(handle:write(("0x%08X\n"):format(snap.mem[i])))
		end
		for i = 1, reg_count - 1 do
			assert(handle:write(("0x%08X\n"):format(snap.regs[i])))
		end
		assert(handle:write(("0x%08X\n"):format(snap.random_state)))
		assert(handle:write(("0x%08X\n"):format(snap.started and 1 or 0)))
		assert(handle:write(("0x%08X\n"):format(snap.pc)))
		assert(handle:write(("0x%08X\n"):format(snap.mulstate_instr)))
		assert(handle:write(("0x%08X\n"):format(snap.mulstate_value)))
		assert(handle:write(("0x%08X\n"):format(start_action_ctype(snap.next_emu_start_action))))
		for ix_eu = 0, core_count - 1 do
			assert(handle:write(("0x%08X\n"):format(snap.bus_inputs[ix_eu].value)))
			assert(handle:write(("0x%08X\n"):format(snap.bus_inputs[ix_eu].handled and 1 or 0)))
			assert(handle:write(("0x%08X\n"):format(snap.bus_inputs[ix_eu].wait    and 1 or 0)))
		end
		assert(handle:close())
		print("saved to " .. path)
	end
	local function load_all(state_file)
		local handle = assert(io.open(state_file, "rb"))
		local pull = handle:read("*a"):gmatch("[^\n]+")
		assert(handle:close())
		local mem_row_count_f = tonumber(pull())
		local core_count_f = tonumber(pull())
		assert(mem_row_count_f == mem_row_count)
		assert(core_count_f == core_count)
		for i = 0, (mem_row_count * row_size - 1) * 4, 4 do
			set_mem(i, tonumber(pull()))
		end
		for i = 1, reg_count - 1 do
			set_reg(i, tonumber(pull()))
		end
		set_random_state(tonumber(pull()))
		set_started(tonumber(pull()) ~= 0)
		set_pc(tonumber(pull()))
		set_mulstate(tonumber(pull()), tonumber(pull()))
		sync_head()
		set_next_start_action(start_action_str(tonumber(pull())))
		for ix_eu = 0, core_count - 1 do
			bus_inputs[ix_eu].value   = tonumber(pull())
			bus_inputs[ix_eu].handled = tonumber(pull()) ~= 0
			bus_inputs[ix_eu].wait    = tonumber(pull()) ~= 0
		end
		sync_bus_inputs()
	end

	local until_next_randomize
	local until_next_restart
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
			set_random_state(specific_sequence.random_state or 1337)
			set_pc(specific_sequence.pc or 0)
			if specific_sequence.started == nil then
				specific_sequence.started = true
			end
			set_started(specific_sequence.started)
			set_mulstate(0x0000000F, 0x00000000) -- TODO: get from specific_sequence
			sync_head()
			until_next_randomize = nil
			until_next_restart = nil
			if auto_snap then
				snap_all()
			end
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
		set_started(random_between(1, 10) == 1)
		set_mulstate(0x0000000F, 0x00000000) -- TODO: pick something really random; but it's hard, screw it
		sync_head()
		random_bus_inputs()
		until_next_randomize = random_between(50, 200)
		if auto_snap then
			snap_all()
		end
	end
	randomize()

	local function tick()
		local text
		if fail_msg then
			text = "Failed: " .. fail_msg
		else
			text = ("Fuzzing, %i iterations done..."):format(frames_done)
		end
		do
			local id = sim.partID(sim.adjustCoords(ui.mousePosition()))
			if id then
				text = text .. "\n" .. disassembler.disassemble(sim.partProperty(id, "ctype"), 0)
			end
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
		local frame_result = emu:frame(next_emu_start_action)
		random_bus_inputs()
		next_emu_start_action = "none"
		compare_bus_outputs()
		if always_compare_all then
			compare_all()
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
		if not until_next_restart and not emu.started then
			until_next_restart = random_between(5, 10)
		end
		if emu.started and random_between(1, 1000) == 1 then
			set_next_start_action("stop")
		end
		if until_next_randomize then
			until_next_randomize = until_next_randomize - 1
			if until_next_randomize == 0 then
				randomize()
			end
		end
		if until_next_restart then
			until_next_restart = until_next_restart - 1
			if until_next_restart == 0 then
				set_next_start_action("start")
				until_next_restart = nil
			end
		end
		if auto_snap then
			snap_all()
		end
	end

	tick = modulepack.xpcall_wrap(tick)
	aftersim = modulepack.xpcall_wrap(aftersim)
	event.register(event.TICK, tick)
	event.register(event.AFTERSIM, aftersim)
	local function unregister()
		event.unregister(event.TICK, tick)
		event.unregister(event.AFTERSIM, aftersim)
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

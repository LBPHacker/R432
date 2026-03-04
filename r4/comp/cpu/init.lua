local plot        = require("spaghetti.plot")
local check       = require("spaghetti.check")
local misc        = require("spaghetti.misc")
local bitx        = require("spaghetti.bitx")
local bus_control = require("r4.comp.cpu.bus_control.generated")
local memory_rw   = require("r4.comp.cpu.memory_rw.generated")
local reg_r       = require("r4.comp.cpu.reg_r.generated")
local head        = require("r4.comp.cpu.core.generated_head")
local tail        = require("r4.comp.cpu.core.generated_tail")

local audited_pairs = pairs

local function build_internal(params)
	check.integer_range("params.mem_row_count", params.mem_row_count, 1, 64)
	check.integer_range("params.core_count", params.core_count, 1, 50)
	if params.machine_id ~= nil then
		check.integer("params.machine_id", params.machine_id)
	end

	local parts = {}

	local pt = plot.pt
	local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
	local mutate        = ucontext.mutate
	local part          = ucontext.part
	local spark         = ucontext.spark
	local piston_extend = ucontext.piston_extend
	local solid_spark   = ucontext.solid_spark
	local lsns_spark    = ucontext.lsns_spark
	local dray          = ucontext.dray
	local ldtc          = ucontext.ldtc
	local cray          = ucontext.cray
	local aray          = ucontext.aray

	local machine_id       = params.machine_id or 0x1337
	local eu_spacing       = 16
	local eus              = params.core_count
	local height           = params.mem_row_count
	local width_order      = 7
	local max_height_order = 6

	local x_body = 10
	local y_body = 10
	local x_bank = x_body
	local y_bank = y_body + height + 2
	local x_write_dray
	local instr_fetch_1
	local instr_fetch_2
	local instr_fetch_3
	local instr_fetch_4

	local y_eu = y_body + height + 22
	local function y_ix_eu(ix_eu)
		return y_eu + ix_eu * eu_spacing
	end
	local function y_ix_eu_next(ix_eu)
		local y_usage_next = y_ix_eu(ix_eu) + eu_spacing
		if ix_eu == eus - 1 then
			y_usage_next = y_usage_next - 8
		end
		return y_usage_next
	end
	do -- memory
		local function memory32(p, value)
			local bray = bitx.band(value, 1) ~= 0
			return mutate(p, {
				type    = bray and pt.BRAY or pt.FILT,
				life    = bray and     988 or 4,
				tmp     = bray and       1 or 0,
				ctype   = bitx.bor(bitx.band(value, 0xFFFFFFFE), 1),
			})
		end

		local width = bitx.lshift(1, width_order)
		local height_order = misc.ilog2ceil(height)
		for y = 0, height - 1 do
			for x = 0, width - 1 do
				local scrambled = bitx.bor(
					bitx.band(bitx.rshift(x, 6), 0x01),
					bitx.band(bitx.lshift(x, 1), 0x7E)
				)
				part(memory32({ x = x_body + scrambled, y = y_body + (height - y - 1) }, bitx.bor(0x00013, bitx.lshift(bitx.band(y * width + x, 0xFFF), 20))))
			end
			local x_dmnd = x_body + width
			local last_filt
			if y == 0 then
				for i = 0, 5 do
					last_filt = part({ type = pt.FILT, x = x_dmnd, y = y_body + y, ctype = 0x0000006F, life = 4 }) -- jal r0, 0
					x_dmnd = x_dmnd + 1
				end
			end
			local last_dmnd = part({ type = pt.DMND, x = x_dmnd, y = y_body + y, unstack = true })
			if y == 0 then
				last_filt.dcolour = 0xFFFFFFFF
				last_dmnd.dcolour = 0xFFFFFFFF
			end
			part({ type = pt.STOR, x = x_body - 1, y = y_body + y })
			local y_aray = y_body + (height - 1 - y)
			aray(x_body - 2 - ((y + 1) % 2 * 3), y_aray, -1, 0, pt.METL, nil, 988)
			if y % 2 == 0 then
				part({ type = pt.STOR, x = x_body - 2, y = y_aray })
				part({ type = pt.STOR, x = x_body - 3, y = y_aray })
				part({ type = pt.STOR, x = x_body - 4, y = y_aray })
			end
		end

		local apom_count = 0
		local apom_prev, apom_next, apom_parts
		local apom_part, apom_add_prev, apom_virtual
		do
			apom_prev = {}
			apom_next = {}
			function apom_add_prev(name, prev_name)
				apom_prev[name] = prev_name
				apom_next[prev_name] = name
			end

			apom_parts = {}
			function apom_part(p, name, prev_name)
				if prev_name then
					apom_add_prev(name, prev_name)
				end
				apom_count = apom_count + 1
				apom_parts[name] = p
				return p
			end

			function apom_virtual(name)
				apom_count = apom_count + 1
				apom_parts[name] = true
			end
		end
		apom_virtual("vert_write_dray")
		apom_virtual("vert_read_ldtc1")
		apom_virtual("vert_read_ldtc3")
		apom_virtual("vert_read_ldtc2")
		apom_virtual("fetch_1")
		apom_virtual("fetch_2")
		apom_virtual("fetch_3")
		apom_virtual("fetch_4")

		local y_horiz_bank
		local head_sparks
		do -- vertical axis
			y_horiz_bank = y_bank
			local x_piston = x_bank - 14
			local x_head = x_bank - 3
			local x_left = x_piston - 1 - max_height_order
			for x = 0, height - 1 do
				part({ type = pt.LDTC, x = x_bank + x * 2    , y = y_bank    , tmp = 1, life = x + 5 })
				part({ type = pt.DRAY, x = x_bank + x * 2 + 1, y = y_bank    , tmp = 1, tmp2 = x + 4 })
				part({ type = pt.LDTC, x = x_bank + x * 2 + 1, y = y_bank + 1, tmp = 1, life = x + 5, ctype = pt.BRAY })
			end
			head_sparks = {
				spark({ type = pt.PSCN, x = x_head + 5, y = y_bank - 2 }),
				spark({ type = pt.PSCN, x = x_head + 4, y = y_bank - 2 }),
				spark({ type = pt.PSCN, x = x_head + 1, y = y_bank - 2 }),
			}
			part     ({ type = pt.INSL, x = x_bank + height * 2 + 1, y = y_bank - 1 })
			part     ({ type = pt.HEAC, x = x_head   +  5, y = y_bank - 1 })
			apom_part({ type = pt.DRAY, x = x_head   +  4, y = y_bank - 1, tmp = 1, tmp2 = 2 }, "horiz_copy_1", "fetch_copy")
			part     ({ type = pt.HEAC, x = x_head   +  3, y = y_bank - 1 })
			part     ({ type = pt.HEAC, x = x_head   +  3, y = y_bank - 2 })
			part     ({ type = pt.HEAC, x = x_head   +  2, y = y_bank - 2 })
			apom_part({ type = pt.DRAY, x = x_head   +  2, y = y_bank - 1, tmp = 2, tmp2 = 0 }, "horiz_copy_2", "horiz_copy_1")
			part     ({ type = pt.HEAC, x = x_head   +  1, y = y_bank - 1 })
			part     ({ type = pt.FRME, x = x_head       , y = y_bank - 1 })
			part     ({ type = pt.FRME, x = x_head       , y = y_bank - 2 })
			part     ({ type = pt.PSTN, x = x_left   +  4, y = y_bank - 1, extend = 0, debug_dcolour = 0xFF00FF00 })
			part     ({ type = pt.PSTN, x = x_left   +  3, y = y_bank - 1, extend = 0, debug_dcolour = 0xFF00FF00 })
			apom_part({ type = pt.PSTN, x = x_left   +  2, y = y_bank - 1, extend = 1, debug_dcolour = 0xFFFF0000 }, "horiz_out")
			spark    ({ type = pt.PSCN, x = x_left   +  2, y = y_bank     })
			part     ({ type = pt.PSTN, x = x_left   +  1, y = y_bank - 1, extend = 0, debug_dcolour = 0xFF00FF00 })
			apom_part({ type = pt.PSTN, x = x_left       , y = y_bank - 1, extend = math.huge, debug_dcolour = 0xFFFF0000 }, "horiz_in", "horiz_copy_2")
			spark    ({ type = pt.NSCN, x = x_left       , y = y_bank     })
			part     ({ type = pt.INSL, x = x_left   -  1, y = y_bank - 1 })
			part     ({ type = pt.INSL, x = x_left   + 12, y = y_bank - 2 })
			part     ({ type = pt.PSTN, x = x_left   + 12, y = y_bank     })
			part({ type = pt.PSTN, x = x_piston -  2, y = y_bank - 1, extend = 0, debug_dcolour = 0xFF00FF00 })
			part({ type = pt.PSTN, x = x_piston -  1, y = y_bank - 1, extend = 0, debug_dcolour = 0xFF00FF00 })
			part({ type = pt.PSTN, x = x_piston -  0, y = y_bank - 1, extend = 0, debug_dcolour = 0xFF00FF00 })
			part({ type = pt.PSTN, x = x_piston +  1, y = y_bank - 1, extend = 0, debug_dcolour = 0xFF00FF00 })
			part({ type = pt.PSTN, x = x_piston +  2, y = y_bank - 1, extend = 0, debug_dcolour = 0xFF00FF00 })
			part({ type = pt.PSTN, x = x_piston +  3, y = y_bank - 1, extend = 0, debug_dcolour = 0xFF00FF00 })
			part({ type = pt.PSTN, x = x_piston +  4, y = y_bank - 1, extend = 0, debug_dcolour = 0xFF00FF00 })
			part({ type = pt.PSTN, x = x_piston + 10, y = y_bank - 1, extend = bitx.lshift(2, 0), debug_dcolour = 0xFF007FFF }) -- remote config
			part({ type = pt.PSTN, x = x_piston +  9, y = y_bank - 1, extend = bitx.lshift(2, 1), debug_dcolour = 0xFF007FFF }) -- remote config
			part({ type = pt.PSTN, x = x_piston +  8, y = y_bank - 1, extend = bitx.lshift(2, 2), debug_dcolour = 0xFF007FFF }) -- remote config
			part({ type = pt.PSTN, x = x_piston +  7, y = y_bank - 1, extend = bitx.lshift(2, 3), debug_dcolour = 0xFF007FFF }) -- remote config
			part({ type = pt.PSTN, x = x_piston +  6, y = y_bank - 1, extend = bitx.lshift(2, 4), debug_dcolour = 0xFF007FFF }) -- remote config
			part({ type = pt.PSTN, x = x_piston +  5, y = y_bank - 1, extend = bitx.lshift(2, 5), debug_dcolour = 0xFF007FFF }) -- remote config
		end

		local get_head_parts_count = 8
		local x_head_parts = x_body - 27
		local y_head_parts = y_body + height + 1
		do -- head parts apom level 2
			apom_part({ type = pt.CRAY, x = x_head_parts, y = y_head_parts, tmp = get_head_parts_count, tmp2 = 0, ctype = pt.SPRK }, "get_head_parts", "horiz_out")
			spark({ type = pt.PSCN, x = x_head_parts    , y = y_head_parts - 1 })
			part ({ type = pt.LSNS, x = x_head_parts    , y = y_head_parts - 2, tmp = 3 })
			part ({ type = pt.FILT, x = x_head_parts + 1, y = y_head_parts - 2, ctype = 0x10000003 })
			for _, sprk in ipairs(head_sparks) do
				cray(x_head_parts + 1, y_head_parts - 1, sprk.x, sprk.y, pt.PSCN, 1, false)
				cray(x_head_parts + 1, y_head_parts - 1, sprk.x, sprk.y, pt.PSCN, 1, false)
				cray(x_head_parts + 4, y_head_parts - 1, sprk.x, sprk.y, pt.SPRK, 1, pt.INWR, nil, 3)
			end
			part({ type = pt.DMND, x = x_head_parts + 1, y = y_head_parts - 1 })
		end

		local y_vert_bank
		local type_query_filt
		do -- horizontal axis
			local x_bank = x_body - 1
			local y_bank = y_body + height + 5
			y_vert_bank = y_bank
			local x_piston = x_bank - 7
			type_query_filt = part({ type = pt.FILT, x = x_bank - 2, y = y_bank + 1 })
			part     ({ type = pt.FILT, x = x_bank - 3, y = y_bank - 1 })
			spark    ({ type = pt.PSCN, x = x_bank - 3, y = y_bank + 1 })
			part     ({ type = pt.HEAC, x = x_bank - 4, y = y_bank - 1 })
			part     ({ type = pt.FILT, x = x_bank - 4, y = y_bank + 1 })
			part     ({ type = pt.FRME, x = x_bank - 5, y = y_bank - 1 })
			part     ({ type = pt.FRME, x = x_bank - 5, y = y_bank     })
			part     ({ type = pt.FRME, x = x_bank - 5, y = y_bank + 1 })
			part     ({ type = pt.PSTN, x = x_bank - 6, y = y_bank, extend = 1, debug_dcolour = 0xFF00FF00 })
			part     ({ type = pt.PSTN, x = x_bank - 7, y = y_bank, extend = 0, debug_dcolour = 0xFF00FF00 })
			apom_part({ type = pt.PSTN, x = x_bank - 8, y = y_bank, extend = 2, debug_dcolour = 0xFFFF0000 }, "vert_adjust_1", "vert_read_ldtc1")
			spark    ({ type = pt.NSCN, x = x_bank - 8, y = y_bank - 1 })
			for x = 0, width_order - 1 do
				part({ type = pt.PSTN, x = x_piston - x - 2, y = y_bank, extend = bitx.lshift(1, x), debug_dcolour = 0xFF007FFF }) -- remote config
			end
			local x_left = x_piston - 1 - width_order
			part({ type = pt.LSNS, x = x_left -  8, y = y_bank + 2, tmp = 3 })
			part({ type = pt.FILT, x = x_left -  8, y = y_bank + 1, ctype = 0x10000003 })
			part     ({ type = pt.INSL, x = x_bank + width + 3, y = y_bank - 1 })
			part     ({ type = pt.INSL, x = x_left - 10, y = y_bank })
			apom_part({ type = pt.PSTN, x = x_left -  9, y = y_bank, extend = math.huge, debug_dcolour = 0xFFFF0000, tmp = 8 }, "vert_write_in", "vert_write_dray")
			spark    ({ type = pt.NSCN, x = x_left -  9, y = y_bank + 2 })
			part     ({ type = pt.PSTN, x = x_left -  8, y = y_bank, extend = 0, debug_dcolour = 0xFF00FF00 })
			apom_part({ type = pt.PSTN, x = x_left -  7, y = y_bank, extend = 1, debug_dcolour = 0xFFFF0000 }, "vert_read_finish", "vert_read_ldtc3")
			spark    ({ type = pt.PSCN, x = x_left -  7, y = y_bank + 2 })
			part     ({ type = pt.PSTN, x = x_left -  6, y = y_bank, extend = 0, debug_dcolour = 0xFF00FF00 })
			apom_part({ type = pt.PSTN, x = x_left -  5, y = y_bank, extend = math.huge, debug_dcolour = 0xFFFF0000 }, "vert_read_out", "horiz_in")
			spark    ({ type = pt.PSCN, x = x_left -  5, y = y_bank - 1 })
			part     ({ type = pt.PSTN, x = x_left -  4, y = y_bank, extend = 0, debug_dcolour = 0xFF00FF00 })
			apom_part({ type = pt.PSTN, x = x_left -  3, y = y_bank, extend = 1, debug_dcolour = 0xFFFF0000 }, "vert_write_address", "vert_read_finish")
			spark    ({ type = pt.NSCN, x = x_left -  3, y = y_bank - 1 })
			part     ({ type = pt.PSTN, x = x_left -  2, y = y_bank, extend = 0, debug_dcolour = 0xFF00FF00 })
			apom_part({ type = pt.PSTN, x = x_left -  1, y = y_bank, extend = -2, debug_dcolour = 0xFFFF0000 }, "vert_read_address", "vert_read_out")
			spark    ({ type = pt.NSCN, x = x_left -  1, y = y_bank - 1 })
			apom_add_prev("vert_read_ldtc1", "vert_read_address")
			apom_add_prev("vert_read_ldtc2", "vert_adjust_1")
			apom_add_prev("vert_read_ldtc3", "vert_read_ldtc2")
			apom_add_prev("vert_write_dray", "vert_write_address")

			part({ type = pt.LSNS, x = x_left -  4, y = y_bank - 2, tmp = 3 })
			part({ type = pt.FILT, x = x_left -  3, y = y_bank - 2, ctype = 0x10000003 })
			part({ type = pt.LSNS, x = x_left -  2, y = y_bank - 2, tmp = 3 })
			part({ type = pt.FILT, x = x_left +  5, y = y_bank - 2, ctype = 0x10000003 })
			part({ type = pt.LSNS, x = x_left +  6, y = y_bank - 2, tmp = 3 })
			part({ type = pt.INSL, x = x_left - 1, y = y_bank + 2 })
			part({ type = pt.PSTN, x = x_left - 1, y = y_bank + 1 })

			part({ type = pt.FILT, x = x_left + 13, y = y_bank + 2, ctype = 0x10000003 })
			part({ type = pt.CONV, x = x_left + 12, y = y_bank + 2, tmp = pt.PSTN, ctype = pt.INSL })
			part({ type = pt.CONV, x = x_left + 12, y = y_bank + 4, tmp = pt.INSL, ctype = pt.PSTN })
			part({ type = pt.LSNS, x = x_left + 12, y = y_bank + 2, tmp = 3 })
		end

		local y_fetch
		do -- instruction fetch
			local x_fetch = x_body - 1
			y_fetch = y_body + height + 9

			apom_part({ type = pt.CRAY, x = x_fetch - 10, y = y_fetch - 1, tmp = 4, tmp2 = 9, ctype = pt.LDTC }, "fetch_copy", "get_head_parts")
			lsns_spark({ type = pt.INWR, x = x_fetch - 11, y = y_fetch - 1, life = 3 }, 0, -1, -1, 0)
			apom_add_prev("fetch_1", "fetch_out")
			apom_add_prev("fetch_2", "fetch_1")
			apom_add_prev("fetch_3", "fetch_2")
			apom_add_prev("fetch_4", "fetch_3")

			instr_fetch_1 = part({ type = pt.FILT, x = x_fetch     , y = y_fetch     })
			instr_fetch_2 = part({ type = pt.FILT, x = x_fetch +  2, y = y_fetch     })
			instr_fetch_3 = part({ type = pt.FILT, x = x_fetch +  4, y = y_fetch     })
			instr_fetch_4 = part({ type = pt.FILT, x = x_fetch +  6, y = y_fetch     })
			part({ type = pt.INSL, x = x_fetch + width + 7, y = y_fetch - 1, unstack = true, dcolour = 0xFFFFFFFF })
			part({ type = pt.INSL, x = x_fetch - 20, y = y_fetch + 1 })
			part({ type = pt.INSL, x = x_fetch - 18, y = y_fetch + 1 })
			part({ type = pt.INSL, x = x_fetch - 16, y = y_fetch + 1 })
			part({ type = pt.FRME, x = x_fetch -  1, y = y_fetch - 1 })
			part({ type = pt.FRME, x = x_fetch -  1, y = y_fetch     })
			part({ type = pt.HEAC, x = x_fetch +  1, y = y_fetch - 1 })
			part({ type = pt.HEAC, x = x_fetch +  1, y = y_fetch     })
			part({ type = pt.HEAC, x = x_fetch +  3, y = y_fetch - 1 })
			part({ type = pt.HEAC, x = x_fetch +  3, y = y_fetch     })
			part({ type = pt.HEAC, x = x_fetch +  5, y = y_fetch - 1 })
			part({ type = pt.HEAC, x = x_fetch +  5, y = y_fetch     })
			part({ type = pt.PSTN, x = x_fetch -  2, y = y_fetch, extend =  1, debug_dcolour = 0xFF007FFF })
			for i = 0, width_order + max_height_order - 1 do
				part({ type = pt.PSTN, x = x_fetch - 3 - i, y = y_fetch, extend = 0, debug_dcolour = 0xFF00FF00 })
			end
			part({ type = pt.FILT, x = x_fetch -  2, y = y_fetch + 1, ctype = 0x20000000 })
			part({ type = pt.PSTN, x = x_fetch - 16, y = y_fetch, extend =  2, debug_dcolour = 0xFF007FFF })
			part({ type = pt.PSTN, x = x_fetch - 17, y = y_fetch, extend =  4, debug_dcolour = 0xFF007FFF })
			part({ type = pt.PSTN, x = x_fetch - 18, y = y_fetch, extend =  8, debug_dcolour = 0xFF007FFF })
			part({ type = pt.PSTN, x = x_fetch - 19, y = y_fetch, extend = 16, debug_dcolour = 0xFF007FFF })
			part({ type = pt.PSTN, x = x_fetch - 20, y = y_fetch, extend = 32, debug_dcolour = 0xFF007FFF })
			part({ type = pt.PSTN, x = x_fetch - 21, y = y_fetch, extend = 64, debug_dcolour = 0xFF007FFF })
			apom_part({ type = pt.PSTN, x = x_fetch - 22, y = y_fetch, extend = 1, debug_dcolour = 0xFFFF0000 }, "fetch_out", "vert_write_in")
			part({ type = pt.PSTN, x = x_fetch - 23, y = y_fetch, extend =  0, debug_dcolour = 0xFF00FF00 })
			apom_part({ type = pt.PSTN, x = x_fetch - 24, y = y_fetch, extend = math.huge, debug_dcolour = 0xFFFF0000, tmp = 8 }, "fetch_in", "fetch_4")
			part({ type = pt.INSL, x = x_fetch - 25, y = y_fetch })
		end

		local apom_order
		do
			apom_order = {}
			local count = 0
			for name in audited_pairs(apom_parts) do
				if not apom_prev[name] then
					local curr = name
					while curr do
						count = count + 1
						apom_order[curr] = count
						curr = apom_next[curr]
					end
				end
			end
		end

		local ballast_off_cutoff = 13

		local x_cray       = x_body - 29
		local x_ballast    = x_body + 8
		local x_apom_read  = x_ballast + ballast_off_cutoff
		local x_core       = x_apom_read + 36
		local x_ballast_2  = x_core + 33
		local x_write      = x_ballast_2 + 3
		local x_apom_write = x_write + 9
		local function apom_get_x_ballast(order)
			local off = x_ballast
			if order > ballast_off_cutoff then
				off = x_ballast_2
			end
			return off + order
		end
		for ix_eu = 0, eus - 1 do -- usage site
			local x_usage      = x_body
			local y_usage      = y_ix_eu(ix_eu)
			local y_usage_next = y_ix_eu_next(ix_eu)

			-- local address_source = part({ type = pt.FILT, x = x_body - 2, y = y_usage - 5, tmp = 1, ctype = 0x11BA0BAD }) -- TODO

			local function assert_identical(a, b)
				local function one_way(x, y)
					for k, v in audited_pairs(x) do
						if k ~= "y" then
							assert(y[k] == v)
						end
					end
				end
				one_way(a, b)
				one_way(b, a)
			end

			local apom_puts = {}
			local function apom_add_put(p, name)
				table.insert(apom_puts, {
					name  = name,
					index = #apom_puts + 1,
					part  = p,
				})
			end

			local apom_gets = {}
			local function apom_add_get(p, name)
				table.insert(apom_gets, {
					name  = name,
					index = #apom_gets + 1,
					part  = p,
				})
			end

			local sources = {}
			local function apom_put_get(name)
				local p_src = apom_parts[name]
				local px, py = p_src.x, y_usage - 1
				local key = plot.xy_key(px, py)
				-- print(name, key)
				local template_size = 1
				if sources[key] then
					assert_identical(sources[key], p_src)
				else
					sources[key] = p_src
					if name == "get_head_parts" then
						py = py - 1
						template_size = 2
					elseif name == "fetch_copy" then
						py = py - 2
						template_size = 3
					end
					part(mutate(p_src, { y = py }))
				end
				local p = sources[key]
				apom_add_put(dray(p_src.x, y_usage, p_src.x, p_src.y + (template_size - 1), template_size, pt.PSCN, 7000 + #apom_puts), name)
				if name == "fetch_copy" then
					cray(p_src.x, y_usage, p_src.x, p_src.y + 1, pt.PSTN, 1, pt.PSCN, 7000 + 1 + #apom_puts)
					local piston_cray = cray(p_src.x, y_usage, p_src.x, p_src.y + 1, pt.PSTN, 1, pt.PSCN, 7000 + 2 + #apom_puts)
					piston_cray.temp = piston_extend(1)
				end

				local cr
				if name == "get_head_parts" then
					cr = dray(p_src.x, y_usage_next, p_src.x, p_src.y, 1, pt.PSCN, 5000 + #apom_gets * 10)
				elseif name == "fetch_copy" then
					cr = dray(p_src.x, y_usage_next, p_src.x, p_src.y, 1, pt.PSCN, 5000 + #apom_gets * 10)
				else
					cr = cray(p_src.x, y_usage_next, p_src.x, p_src.y, pt.SPRK, 1, pt.PSCN, 5000 + #apom_gets * 10)
				end
				apom_add_get(cr, name)
			end

			do
				local cr = cray(x_head_parts, y_usage, x_head_parts, y_head_parts + get_head_parts_count + 1, pt.HEAC, get_head_parts_count, pt.PSCN, 7000 + #apom_puts)
				apom_add_put(cr, "fetch_1")
				apom_add_put(cr, "fetch_2")
				apom_add_put(cr, "fetch_3")
				apom_add_put(cr, "fetch_4")
				apom_add_put(cr, "vert_write_dray")
				apom_add_put(cr, "vert_read_ldtc1")
				apom_add_put(cr, "vert_read_ldtc3")
				apom_add_put(cr, "vert_read_ldtc2")
			end
			apom_put_get("horiz_copy_1")
			apom_put_get("horiz_copy_2")
			apom_put_get("horiz_out")
			apom_put_get("horiz_in")
			apom_put_get("vert_adjust_1")
			apom_put_get("vert_write_address")
			apom_put_get("vert_read_finish")
			apom_put_get("vert_write_in")
			apom_put_get("vert_read_out")
			apom_put_get("vert_read_address")
			apom_put_get("get_head_parts")
			apom_put_get("fetch_copy")
			apom_put_get("fetch_out")
			apom_put_get("fetch_in")

			part({ type = pt.FILT, x = type_query_filt.x, y = y_usage - 1, ctype = 0x20000000 })
			dray(type_query_filt.x, y_usage, type_query_filt.x, type_query_filt.y, 1, pt.PSCN)
			part({ type = pt.LSNS, x = x_usage - 11, y = y_usage - 2, tmp = 3 })
			do
				local source = part({ type = pt.CRAY, x = x_usage + width - 4, y = y_usage - 3, tmp = 4, tmp2 = 9, ctype = pt.LDTC })
				part({ type = pt.LSNS, x = source.x - 1, y = source.y, tmp = 3 })
				dray(source.x + 1, source.y, x_usage - 11, source.y, 1, pt.PSCN)
			end

			do
				local temp_target = { x = type_query_filt.x + 7, y = y_usage_next }
				local cr1 = cray(type_query_filt.x - 2, y_usage_next    , type_query_filt.x - 2, type_query_filt.y - 1, pt.HEAC, 1, pt.PSCN, 5000 + #apom_gets * 10)
				apom_add_get(cr1, "vert_read_ldtc1")
				local cr2 = cray(type_query_filt.x    , y_usage_next    , type_query_filt.x    , type_query_filt.y - 1, pt.HEAC, 2, pt.PSCN, 5000 + #apom_gets * 10)
				apom_add_get(cr2, "vert_read_ldtc2")
				apom_add_get(cr2, "vert_read_ldtc3")
				cray(type_query_filt.x - 1, y_usage_next - 1, type_query_filt.x - 1, type_query_filt.y - 1, pt.HEAC, 1, pt.PSCN)
				part ({ type = pt.FILT, tmp = 3, x = temp_target.x + 1, y = y_usage_next - 1, ctype = 0x10000003, unstack = true })
				spark({ type = pt.PSCN, tmp = 3, x = temp_target.x, y = y_usage_next - 2, life = 3 })
				part ({ type = pt.LSNS, tmp = 3, x = temp_target.x, y = y_usage_next - 1, z = 5000 + #apom_gets * 10 })
				cray(temp_target.x, y_usage_next - 1, temp_target.x, temp_target.y, pt.HEAC, 1, false, 5000 + 1 + #apom_gets * 10)
				local cr3 = cray(x_cray, y_usage_next, temp_target.x, temp_target.y, pt.HEAC, 1, pt.PSCN)
				apom_add_get(cr3, "vert_write_dray")

				apom_add_get(cray(type_query_filt.x + 2, y_usage_next, type_query_filt.x + 2, type_query_filt.y + 2, pt.LDTC, 1, pt.PSCN, 5000     + #apom_gets * 10), "fetch_1")
				apom_add_get(cray(type_query_filt.x + 4, y_usage_next, type_query_filt.x + 4, type_query_filt.y + 2, pt.LDTC, 1, pt.PSCN, 5000 + 1 + #apom_gets * 10), "fetch_2")
				apom_add_get(cray(type_query_filt.x + 6, y_usage_next, type_query_filt.x + 6, type_query_filt.y + 2, pt.LDTC, 1, pt.PSCN, 5000 + 2 + #apom_gets * 10), "fetch_3")
				apom_add_get(cray(type_query_filt.x + 8, y_usage_next, type_query_filt.x + 8, type_query_filt.y + 2, pt.LDTC, 1, pt.PSCN, 5000 + 3 + #apom_gets * 10), "fetch_4")
			end

			local function sort_put_get(lhs, rhs)
				if lhs.part.y ~= rhs.part.y then return lhs.part.y < rhs.part.y end
				if lhs.part.x ~= rhs.part.x then return lhs.part.x < rhs.part.x end
				if lhs.index  ~= rhs.index  then return lhs.index  < rhs.index  end
				return false
			end
			table.sort(apom_puts, sort_put_get)
			table.sort(apom_gets, sort_put_get)

			local apom_order_put = {}
			for key, value in audited_pairs(apom_order) do
				apom_order_put[key] = value
			end

			if ix_eu > 0 then
				local y_flip_top = {
					[ -17 ] = { { y = y_eu + 4, count = 10 }, { y = y_eu - 14, count = 12 } },
					[ -15 ] = { { y = y_eu + 3, count = 11 }, { y = y_eu -  4, count =  2 } },
					[ -13 ] = { { y = y_eu + 3, count = 11 } },
					[ -11 ] = { { y = y_eu + 4, count =  9 } },
					[  -9 ] = { { y = y_eu + 6, count =  7 } },
					[  -7 ] = { { y = y_eu + 7, count =  5 } },
					[  -1 ] = { { y = y_eu + 7, count =  4 } },
					[   1 ] = { { y = y_eu + 7, count =  3 } },
					[   5 ] = { { y = y_eu + 7, count =  2 } },
					[   7 ] = { { y = y_eu + 7, count =  2 } },
					[   9 ] = { { y = y_eu + 7, count =  2 } },
					[  11 ] = { { y = y_eu + 7, count =  1 } },
				}
				local seen_get_at = {}
				local min_put = math.huge
				for _, put in ipairs(apom_puts) do
					min_put = math.min(min_put, put.part.x)
				end
				local get_xs = {}
				for _, get in ipairs(apom_gets) do
					if get.part.x >= min_put and not seen_get_at[get.part.x] then
						seen_get_at[get.part.x] = true
						table.insert(get_xs, get.part.x)
					end
				end
				for ix_get = #get_xs, 1, -1 do
					local x_get = get_xs[ix_get]
					for ix_put, put in ipairs(apom_puts) do
						if put.part.x >= x_get then
							local to_save = (#apom_puts - ix_put) + 1
							local y_flip_top_i = y_flip_top[x_get]
							-- for _, info in ipairs(y_flip_top_i) do
							-- 	for ix_save = 0, info.count - 1 do
							-- 		part({ type = pt.GRVT, x = x_get, y = info.y + ix_save, unstack = true, life = 1 })
							-- 	end
							-- end
							local expect_to_save = 0
							for ix_info, info in ipairs(y_flip_top_i) do
								expect_to_save = expect_to_save + info.count
								cray(x_get, y_usage, x_get, info.y + info.count - 1, pt.CRMC, info.count, pt.PSCN, 4000 + ix_info)
								cray(x_get, y_usage, x_get, info.y + info.count - 1, pt.CRMC, info.count, pt.PSCN, 6000 + ix_info)
							end
							assert(to_save == expect_to_save)
							local flip = {}
							for ix_flip = ix_put, #apom_puts do
								flip[apom_puts[ix_flip].name] = apom_order_put[apom_puts[ix_flip].name]
							end
							for ix_flip = ix_put, #apom_puts do
								apom_order_put[apom_puts[ix_flip].name] = flip[apom_puts[ix_put + #apom_puts - ix_flip].name]
							end
							break
						end
					end
				end
			end

			for ix_put = #apom_puts, 1, -1 do
				local put = apom_puts[ix_put]
				local get = apom_gets[ix_put]

				local put_order = apom_order_put[put.name]
				local put_off = apom_get_x_ballast(put_order)
				local ballast = part({ type = pt.HEAC, x = put_off, y = y_usage })
				cray(x_cray, y_usage, ballast.x, y_usage, pt.HEAC, 1, pt.PSCN)

				local get_order = apom_order[get.name]
				cray(x_ballast, y_usage_next, apom_get_x_ballast(get_order), y_usage_next, pt.HEAC, 1, pt.PSCN)
			end

			local x_ldtc_1 = x_body + 127
			local x_dray   = x_body + 128
			x_write_dray = x_dray
			local x_ldtc_2 = x_body + 129
			local function x_storage_slot(index)
				return x_core + 2 + index
			end
			plot.merge_parts(x_core, y_usage, parts, memory_rw.get_parts(), {
				[ 33 ] = x_write + 2 - x_core - 3,
				[ 34 ] = x_write + 4 - x_core - 3,
				[ 35 ] = x_ldtc_1    - x_core - 3,
				[ 36 ] = x_ldtc_2    - x_core - 3,
				[ 37 ] = 73,
				[ 38 ] = 55,
				[ 39 ] = 56,
				[ 40 ] = 57,
				[ 41 ] = 58,
				[ 42 ] = 59,
			})
			-- for _, info in ipairs({
			-- 	{ name = "control", index =  1, initial = 0x10000000 },
			-- 	{ name = "core_lo", index =  3, initial = 0x10000000 },
			-- 	{ name = "core_hi", index =  5, initial = 0x10000000 },
			-- 	{ name = "addr_lo", index = 11, initial = 0x10000000 },
			-- }) do
			-- 	part({ type = pt.FILT, x = x_core + info.index + 2, y = y_usage - 1 })
			-- 	local source = part({ type = pt.FILT, x = x_core + info.index + 2, y = y_usage - 4, ctype = info.initial })
			-- 	if info.name == "addr_lo" then
			-- 		source.y = address_source.y
			-- 		ldtc(source.x - 1, source.y, address_source.x, address_source.y)
			-- 	end
			-- 	ldtc(x_core + info.index + 2, y_usage - 2, source.x, source.y)
			-- end
			-- for _, info in ipairs({
			-- 	{ name = "core_lo" , index = 1 },
			-- 	{ name = "core_hi" , index = 3 },
			-- }) do
			-- 	part({ type = pt.FILT, x = x_core + info.index + 2, y = y_usage + 3 })
			-- 	ldtc(x_core + info.index + 2, y_usage + 2, x_core + info.index + 2, y_usage)
			-- end

			do
				local x_apom = x_apom_read
				local source = part({ type = pt.CRMC, x = x_apom + 1, y = y_usage })
				               part({ type = pt.CRMC, x = x_apom + 2, y = y_usage })
				cray(x_apom + 2, y_usage - 1, source.x, source.y, pt.SPRK, 1, pt.PSCN)
				spark({ type = pt.PSCN, x = x_apom + 2, y = y_usage - 2 })
				dray(x_apom + 5, y_usage -1, x_ldtc_1, y_usage - 1, 1, pt.PSCN)
				dray(x_apom + 5, y_usage -1, x_ldtc_2, y_usage - 1, 1, pt.PSCN)
				part ({ type = pt.LDTC, x = x_apom + 6, y = y_usage - 1, tmp = 1, life = y_usage - type_query_filt.y - 2 })

				local y_finish = y_usage + 8
				if ix_eu == eus - 1 then
					y_finish = y_finish - 1
				end
				cray(x_ldtc_1, y_finish, x_ldtc_1, y_usage - 1, pt.SPRK, 1, pt.PSCN)
				cray(x_ldtc_2, y_finish, x_ldtc_2, y_usage - 1, pt.SPRK, 1, pt.PSCN)
				cray(x_ldtc_2 + 2, y_finish, x_apom + 2, y_finish, pt.CRMC, 2, pt.PSCN)

				cray(x_apom + 1, y_finish + 2, source.x    , y_finish, pt.CRMC, 1, pt.PSCN)
				cray(x_apom + 1, y_finish + 2, source.x    , source.y, pt.CRMC, 1, pt.PSCN)
				cray(x_apom + 2, y_finish + 3, source.x + 1, y_finish, pt.CRMC, 1, pt.PSCN)
				cray(x_apom + 2, y_finish + 3, source.x + 1, source.y, pt.CRMC, 1, pt.PSCN)
			end
			do
				dray(x_write + 1, y_usage, x_write +  6, y_usage, 1, pt.INST)
				part({ type = pt.STOR, x = x_write +  3, y = y_usage })
				part({ type = pt.FILT, x = x_write +  5, y = y_usage, ctype = 1, tmp = 1 })
				part({ type = pt.DMND, x = x_write +  8, y = y_usage })
				aray(x_write  + 1, y_usage, -1, 0, pt.INST, nil, 988)
				aray(x_write  + 1, y_usage, -1, 0, pt.INST, nil, 988) -- sets tmp to 1
				dray(x_write  + 1, y_usage, x_write + 7, y_usage, 1, pt.INST)
				dray(x_write  + 1, y_usage, x_dray - 5, y_usage, 6, pt.INST)
				for i = 5, 2, -1 do
					part({ type = pt.CRMC, x = x_dray - i, y = y_usage, unstack = true })
				end

				dray(x_ldtc_2 + 2, y_usage, x_write + 6, y_usage, 1, pt.PSCN)
				dray(x_ldtc_2 + 2, y_usage, x_write + 7, y_usage, 1, pt.PSCN)
			end
			do
				local x_apom = x_apom_write + 1
				local source = part({ type = pt.CRMC, x = x_apom, y = y_usage     })
				cray(x_apom, y_usage - 1, source.x, source.y, pt.SPRK, 1, pt.PSCN)
				local template = part({ type = pt.DRAY, x = x_dray, y = y_usage, tmp = 1, tmp2 = y_usage - type_query_filt.y + 1 })
				solid_spark(x_dray, y_usage + 3, 0, -1, pt.PSCN)
				dray(x_dray, y_usage - 1, x_dray, y_usage + 1, 1, pt.PSCN)
				cray(x_dray, y_usage - 1, x_dray, y_usage, pt.SPRK, 1, pt.PSCN)

				local y_finish = y_usage + 9
				if ix_eu == eus - 1 then
					y_finish = y_finish - 1
				end
				part(mutate(template, { y = y_finish }))
				dray(x_dray, y_finish + 1, template.x, template.y, 1, pt.PSCN)
				cray(x_dray, y_finish + 1, template.x, template.y + 1, pt.SPRK, 1, pt.PSCN)
				cray(x_dray + 2, y_finish + 1, x_apom, y_finish + 1, pt.CRMC, 1, pt.PSCN)
				cray(x_apom, y_finish + 2, x_apom, y_finish + 1, pt.CRMC, 1, pt.PSCN)
				cray(x_apom, y_finish + 2, x_apom, y_usage, pt.CRMC, 1, pt.PSCN)
			end

			do -- decode address
				local x_decode = x_body + 1
				local y_decode = y_usage - 2

				local function change_conductor(conductor, from)
					part({ type = pt.CONV, x = x_decode, y = y_decode, ctype = conductor, tmp = from or pt.SPRK })
					part({ type = pt.CONV, x = x_decode, y = y_decode, ctype = pt.SPRK, tmp = conductor })
					part({ type = pt.LSNS, x = x_decode, y = y_decode, tmp = 3 })
				end

				local fetch_left = 6
				local lsns_life = part({ type = pt.FILT, x = x_decode + 2, y = y_decode, ctype = 0x10000003 })
				local pistons = {
					{ bit = 24 },
					{ bit = 18 },
					{ bit = 19 },
					{ bit = 20 },
					{ bit = 21 },
					{ bit = 22 },
					{ bit =  3 },
					{ bit =  4 },
					{ bit =  5 },
					{ bit =  6 },
					{ bit =  7 },
					{ bit =  8 },
					{ bit =  2 },
					{ bit =  9 },
					{ bit = 10 },
					{ bit = 11 },
					{ bit = 12 },
					{ bit = 13 },
					{ bit = 14 },
					{ bit = 23 },
				}
				do
					local x_bit_filt = x_decode + 4
					local x_piston = x_decode - 25
					for ix_piston = 1, #pistons do
						local piston = pistons[ix_piston]
						piston.bit_filt = part({ type = pt.FILT, x = x_bit_filt, y = y_decode, ctype = bitx.lshift(1, piston.bit) })
						x_bit_filt = x_bit_filt + 1
						if x_bit_filt == x_apom_read + 1 then
							x_bit_filt = x_apom_read + 8
						end
						piston.part = part({ type = pt.PSTN, x = x_piston + ix_piston + 1, y = y_decode })
					end
				end
				local first_piston = pistons[       1].part
				local last_piston  = pistons[#pistons].part

				part({ type = pt.DMND, x = first_piston.x - 1, y = y_decode })
				part({ type = pt.INSL, x = x_decode - 22, y = y_decode - 1 })
				part({ type = pt.INSL, x = x_decode - 20, y = y_decode - 1 })
				part({ type = pt.INSL, x = x_decode - 18, y = y_decode - 1 })
				part({ type = pt.INSL, x = x_decode - 10, y = y_decode - 1 })
				part({ type = pt.CONV, x = x_decode    , y = y_decode + 1, tmp = pt.SPRK, ctype = pt.CRMC, z = -1000 })
				part({ type = pt.CRMC, x = x_decode + 1, y = y_decode })
				part({ type = pt.FILT, x = x_decode - 1, y = y_decode })
				part({ type = pt.LDTC, x = x_decode - 2, y = y_decode, life = 129 })
				part({ type = pt.STOR, x = x_decode - 2, y = y_decode })
				local addr_combined = part({ type = pt.FILT, x = x_decode - 3, y = y_decode, tmp = 1, ctype = 0x1000DEAD })

				-- important: the ids of the pistons here never change, they get allocated from the same set every time
				do
					-- without this, the pistons would extend due to the sparks below
					local x_pacify = x_decode - 2 * width_order - max_height_order - 5
					cray(x_pacify, y_decode, first_piston.x, first_piston.y, pt.INSL, 2 * width_order + max_height_order, pt.PSCN)
				end
				ldtc(x_decode, y_decode, lsns_life.x, lsns_life.y)
				change_conductor(pt.PSCN, pt.CRMC)
				cray(x_decode, y_decode, last_piston.x, last_piston.y, pt.STOR, 2 * width_order + max_height_order - 1, false)
				change_conductor(pt.METL)
				local function handle_bit(piston_bit, piston_index, invert, last) -- TODO: rework in terms of conditional cray
					ldtc(x_decode, y_decode, pistons[piston_index].bit_filt.x, pistons[piston_index].bit_filt.y)
					part({ type = pt.ARAY, x = x_decode, y = y_decode })
					ldtc(x_decode, y_decode, lsns_life.x, lsns_life.y)
					change_conductor(pt.PSCN)
					local extend_if_set = piston_extend(0)
					local extend_if_clear = piston_extend(bitx.lshift(1, piston_bit))
					if invert then
						extend_if_set, extend_if_clear = extend_if_clear, extend_if_set
					end
					local piston = pistons[piston_index].part
					local cond
					if last then
						cond = cray(x_decode, y_decode, piston.x, piston.y, pt.PSTN, 1, false)
					else
						local prev_piston = pistons[piston_index + 1].part
						cond = cray(x_decode, y_decode, prev_piston.x, prev_piston.y, pt.PSTN, 2, false)
					end
					change_conductor(pt.METL)
					local uncond = cray(x_decode, y_decode, piston.x, piston.y, pt.PSTN, 1, false)
					cond.temp = extend_if_clear
					uncond.temp = extend_if_set
				end
				for i = 0, fetch_left - 1 do
					local piston_index = 1 + i
					handle_bit(i, piston_index, true, false)
					local piston = pistons[piston_index].part
					local stagger = (piston.x + 1) % 2
					dray(piston.x, y_usage - stagger, piston.x, y_fetch + 1 - stagger, 2 - stagger, pt.PSCN)
				end
				for i = 0, width_order - 1 do
					local piston_index = 7 + i
					handle_bit(width_order - i - 1, piston_index, false, false)
					local piston = pistons[piston_index].part
					local stagger = (piston.x + 1) % 2
					dray(piston.x, y_usage - stagger, piston.x, y_vert_bank + 1 - stagger, 2 - stagger, pt.PSCN)
				end
				for i = 0, max_height_order - 1 do
					local piston_index = 14 + i
					handle_bit(max_height_order - i, piston_index, true, false)
					local piston = pistons[piston_index].part
					local stagger = (piston.x + 1) % 2
					dray(piston.x, y_usage - stagger, piston.x, y_horiz_bank - stagger, 2 - stagger, pt.PSCN)
				end
				for i = fetch_left, width_order - 1 do
					local piston_index = 14 + i
					handle_bit(i, piston_index, true, i == width_order - 1)
					local piston = pistons[piston_index].part
					local stagger = (piston.x + 1) % 2
					dray(piston.x, y_usage - stagger, piston.x, y_fetch + 1 - stagger, 2 - stagger, pt.PSCN)
				end
			end
		end

		do -- cleanup
			local y_cleanup = y_ix_eu(0) + eus * eu_spacing - 7

			for ix_put = 1, apom_count do
				local x_cray = apom_get_x_ballast(ix_put)
				for ix_eu = 0, eus - 1 do -- usage site
					cray(x_cray, y_cleanup + ix_put % 2, x_cray, y_ix_eu_next(ix_eu), pt.HEAC, 1, pt.PSCN)
					cray(x_cray, y_cleanup + ix_put % 2, x_cray, y_ix_eu     (ix_eu), pt.HEAC, 1, pt.PSCN)
				end
			end
		end
	end

	do -- register access
		local regs        = 32
		local writers     = 4
		local readers     = 8

		local x_regs      = x_bank + 95
		local y_regs_base = y_ix_eu(0) + 5

		local top_regs = {}
		local prev_regs = {}
		for ix_reg = 0, regs - 1 do
			local x_top_reg = x_regs - ix_reg * 2 + 1
			top_regs[ix_reg] = {
				lo = part({ type = pt.FILT, x = x_top_reg    , y = y_regs_base - eu_spacing, ctype = ix_reg == 0 and 0x10000000 or (0x1000AD00 + ix_reg) }),
				hi = part({ type = pt.FILT, x = x_top_reg - 1, y = y_regs_base - eu_spacing, ctype = ix_reg == 0 and 0x10000000 or (0x1000DE00 + ix_reg) }),
			}
			prev_regs[ix_reg] = {
				lo = top_regs[ix_reg].lo,
				hi = top_regs[ix_reg].hi,
			}
			if ix_reg ~= 0 then
				dray(top_regs[ix_reg].lo.x, top_regs[ix_reg].lo.y + eus * eu_spacing + 1, top_regs[ix_reg].lo.x, top_regs[ix_reg].lo.y    , 1, pt.PSCN)
				dray(top_regs[ix_reg].hi.x, top_regs[ix_reg].hi.y + eus * eu_spacing + 2, top_regs[ix_reg].hi.x, top_regs[ix_reg].hi.y + 1, 2, pt.PSCN)
			end
		end

		local x_regmove_left        = x_regs - 64 - eu_spacing
		local x_regmove_ballast     = x_regmove_left - 2
		local x_reg_core            = x_regs - 81
		local x_instr_2             = x_reg_core + 107
		local y_regmove_apom_top    = y_regs_base - eu_spacing
		local y_regmove_apom_bottom = y_regs_base + (eus - 1) * eu_spacing + 5
		local y_read_dray_up        = y_regs_base + (eus - 1) * eu_spacing + 5
		local regmove_ballasts = {}
		for ix_eu = 0, eus - 1 do -- usage site
			local y_regs = y_regs_base + ix_eu * eu_spacing

			local x_decode = x_regs + 1
			local x_target = x_regs + 4 - eu_spacing
			local y_decode = y_regs - 3

			for ix_reg = 0, regs - 1 do
				local x_reg = x_regs - ix_reg * 2 + 1 - eu_spacing

				local source_lo = prev_regs[ix_reg].lo
				prev_regs[ix_reg].lo = part({ type = pt.FILT, x = x_reg, y = y_regs })
				if ix_reg ~= 0 then
					part({ type = pt.LDTC, x = x_reg + 1, y = y_regs - 1, life = eu_spacing - 2 })
					part({ type = pt.LDTC, x = x_reg + 1, y = y_regs - 1, life = 1, tmp = 1 })
				end

				local source_hi = prev_regs[ix_reg].hi
				prev_regs[ix_reg].hi = part({ type = pt.FILT, x = x_reg - 1, y = y_regs })
				if ix_reg ~= 0 then
					part({ type = pt.LDTC, x = x_reg, y = y_regs - 1, life = eu_spacing - 2 })
					part({ type = pt.LDTC, x = x_reg, y = y_regs - 1, life = 1, tmp = 1 })
				end
			end
			do
				local rz = prev_regs[0]
				rz.lo.x = rz.lo.x + 16
				rz.hi.x = rz.hi.x + 16
				rz.lo.ctype = 0x10000000
				rz.hi.ctype = 0x10000000
				part({ type = pt.LDTC, x = rz.lo.x    , y = rz.lo.y - 1, life = 4, tmp = 1 })
				part({ type = pt.FILT, x = rz.lo.x    , y = rz.lo.y - 6, ctype = 0x10000000 })
				part({ type = pt.FILT, x = rz.lo.x + 5, y = rz.lo.y - 6, ctype = 0x10000000 })
			end

			local function change_conductor(conductor, lsns_distance, invert_conv)
				part({ type = pt.CONV, x = x_decode, y = y_decode, ctype = conductor, tmp = invert_conv or pt.SPRK, tmp2 = invert_conv and 1 or 0 })
				part({ type = pt.CONV, x = x_decode, y = y_decode, ctype = pt.SPRK, tmp = conductor })
				part({ type = pt.LSNS, x = x_decode, y = y_decode, tmp = 3, tmp2 = lsns_distance or 1 })
			end

			do
				local y_core = y_regs - 2
				local remap = {}
				for ix_remap = 0, 15 do
					remap[ix_remap] = ix_remap * 2 - x_reg_core + 108 - 2
				end
				for ix_remap = 16, 27 do
					remap[ix_remap] = ix_remap - x_reg_core + 74 - 2
				end
				for ix_remap = 28, 30 do
					remap[ix_remap] = ix_remap * 2 - x_reg_core + 69 - 2
				end
				plot.merge_parts(x_reg_core + 2, y_core, parts, reg_r.get_parts(), remap)

				ldtc(instr_fetch_1.x, y_core - 2, instr_fetch_1.x, instr_fetch_1.y, -10000000)
				ldtc(instr_fetch_2.x, y_core - 2, instr_fetch_2.x, instr_fetch_2.y, -10000000)
				ldtc(instr_fetch_3.x, y_core - 2, instr_fetch_3.x, instr_fetch_3.y, -10000000)
				ldtc(instr_fetch_4.x, y_core - 2, instr_fetch_4.x, instr_fetch_4.y, -10000000)
				part({ type = pt.FILT, x = instr_fetch_1.x, y = y_core - 1 })
				part({ type = pt.FILT, x = instr_fetch_2.x, y = y_core - 1 })
				part({ type = pt.FILT, x = instr_fetch_3.x, y = y_core - 1 })
				part({ type = pt.FILT, x = instr_fetch_4.x, y = y_core - 1 })

				local instr_fetch_2_1 = part({ type = pt.FILT, x = x_instr_2 - 1, y = y_core - 1 })
				local instr_fetch_2_2 = part({ type = pt.FILT, x = x_instr_2 + 1, y = y_core - 1 })
				local instr_fetch_2_3 = part({ type = pt.FILT, x = x_instr_2 + 3, y = y_core - 1 })
				local instr_fetch_2_4 = part({ type = pt.FILT, x = x_instr_2 + 5, y = y_core - 1 })
				dray(instr_fetch_1.x - 2, y_core - 1, instr_fetch_2_1.x - 1, instr_fetch_2_1.y, 8, pt.PSCN, nil, true)
				part({ type = pt.CONV, x = instr_fetch_1.x - 2, y = y_core - 1, tmp = pt.FILT, ctype = pt.PSCN })
				part({ type = pt.CONV, x = instr_fetch_1.x - 2, y = y_core - 1, tmp = pt.PSCN, ctype = pt.SPRK })
				part({ type = pt.LSNS, x = instr_fetch_1.x - 1, y = y_core    , tmp = 3, tmp2 = 2 })
				part({ type = pt.FILT, x = instr_fetch_1.x + 1, y = y_core + 1, ctype = 0x10000003 })
				dray(instr_fetch_1.x - 1, y_core, x_reg_core + 87, y_core, 7, false)
				part({ type = pt.LDTC, x = instr_fetch_2_1.x - 4, y = instr_fetch_2_1.y + 4, life = 3 })
				part({ type = pt.LDTC, x = instr_fetch_2_2.x - 4, y = instr_fetch_2_2.y + 4, life = 3 })
				part({ type = pt.LDTC, x = instr_fetch_2_3.x - 4, y = instr_fetch_2_3.y + 4, life = 3 })
				part({ type = pt.LDTC, x = instr_fetch_2_4.x - 4, y = instr_fetch_2_4.y + 4, life = 3 })

				part({ type = pt.LDTC, x = x_instr_2 - 23, y = y_core + 3, life = 8 })
				part({ type = pt.LDTC, x = x_instr_2 - 21, y = y_core + 3, life = 8 })
				part({ type = pt.LDTC, x = x_instr_2 - 19, y = y_core + 3, life = 12 })
				if ix_eu < eus - 1 then
					part({ type = pt.FILT, x = x_instr_2 - 21, y = y_core + 5 })
				end
				part({ type = pt.LDTC, x = x_instr_2 - 20, y = y_core - 11 })
				part({ type = pt.LDTC, x = x_instr_2 - 19, y = y_core - 11 })
				part({ type = pt.LDTC, x = x_instr_2 - 18, y = y_core - 11 })
				part({ type = pt.LDTC, x = x_instr_2 - 37, y = y_core -  9, tmp = 1 })
				part({ type = pt.FILT, x = x_instr_2 - 37, y = y_core -  8, ctype = 0x10000000 })
				part({ type = pt.LDTC, x = x_instr_2 - 17, y = y_core - 11 })
				part({ type = pt.LDTC, x = x_instr_2 - 16, y = y_core - 11 })
				part({ type = pt.LDTC, x = x_instr_2 -  1 + 4, y = y_core - 11, tmp = 1 })
				part({ type = pt.LDTC, x = x_instr_2 -  2 + 4, y = y_core - 11, tmp = 1 })
				if ix_eu == 0 then
					part({ type = pt.INSL, x = x_instr_2  - 1 + 4, y = y_core - 11 })
					part({ type = pt.INSL, x = x_instr_2 - 17, y = y_core - 11 })
					part({ type = pt.INSL, x = x_instr_2 - 19, y = y_core - 11 })
				end
				part({ type = pt.FILT, x = x_instr_2 -  4 + 4, y = y_core -  9 })
				part({ type = pt.FILT, x = x_instr_2 -  3 + 4, y = y_core -  9 })
				part({ type = pt.FILT, x = x_instr_2 -  5 + 4, y = y_core -  8 })
				part({ type = pt.FILT, x = x_instr_2 -  4 + 4, y = y_core -  8 })
				part({ type = pt.FILT, x = x_instr_2 -  6 + 4, y = y_core -  7 })
				part({ type = pt.FILT, x = x_instr_2 -  5 + 4, y = y_core -  7 })
				part({ type = pt.LDTC, x = x_instr_2 - 21, y = y_core -  8, life = 1 })
				part({ type = pt.FILT, x = x_instr_2 - 20, y = y_core -  7 })
				part({ type = pt.LDTC, x = x_instr_2 -  8 + 4, y = y_core -  7, life = 2 })
				part({ type = pt.LDTC, x = x_instr_2 -  7 + 4, y = y_core -  7, life = 2 })
				part({ type = pt.LDTC, x = x_instr_2 - 31, y = y_core -  4, life = 5 })
				part({ type = pt.LDTC, x = x_instr_2 - 30, y = y_core -  4, life = 5 })
				part({ type = pt.LDTC, x = x_instr_2 - 29, y = y_core -  4, life = 5 })
				part({ type = pt.LDTC, x = x_instr_2 - 28, y = y_core -  4, life = 5 })
				part({ type = pt.LDTC, x = x_instr_2 + 12, y = y_core -  4, life = 1 })

				part({ type = pt.LDTC, x = x_instr_2 - 18, y = y_core -  2, life = 9 })
				part({ type = pt.LDTC, x = x_instr_2 - 17, y = y_core -  2, life = 9 })
				part({ type = pt.LDTC, x = x_instr_2 - 16, y = y_core -  2, life = 9 })
				part({ type = pt.LDTC, x = x_instr_2 - 15, y = y_core -  2, life = 9 })
				part({ type = pt.LDTC, x = x_instr_2 - 14, y = y_core -  2, life = 9 })
				part({ type = pt.LDTC, x = x_instr_2 - 13, y = y_core -  2, life = 9 })
				part({ type = pt.LDTC, x = x_instr_2 - 12, y = y_core -  2, life = 9 })
				part({ type = pt.LDTC, x = x_instr_2 - 11, y = y_core -  2, life = 9 })
				part({ type = pt.LDTC, x = x_instr_2 - 10, y = y_core -  2, life = 9 })

				part({ type = pt.LDTC, x = x_instr_2 -  7, y = y_core -  2 })
				part({ type = pt.LDTC, x = x_instr_2 -  6, y = y_core -  2 })
				part({ type = pt.LDTC, x = x_instr_2 -  5, y = y_core -  2 })
				part({ type = pt.LDTC, x = x_instr_2 +  6, y = y_core -  7, life = 1, tmp = 1 })
				part({ type = pt.FILT, x = x_instr_2 +  4, y = y_core -  9, ctype = 0x10000000 + height - 1 })

				part({ type = pt.BRAY, x = x_instr_2 +  6, y = y_core -  6, life = 1 })
				aray(x_instr_2 + 8, y_core - 6, 1, 0, false, nil, 1)
				solid_spark(x_instr_2 + 9, y_core - 5, 0, -1, pt.METL)
				part({ type = pt.DTEC, x = x_instr_2 +  8, y = y_core -  6, tmp2 = 2 })
				part({ type = pt.FILT, x = x_instr_2 +  8, y = y_core -  5 })
				part({ type = pt.INSL, x = x_instr_2 +  9, y = y_core -  7 })

				part({ type = pt.LDTC, x = x_instr_2 - 23, y = y_core - 9, tmp = 1 })
				local bus_hi         = part({ type = pt.FILT, x = x_instr_2 - 99, y = y_core -  6, ctype = 0x10000000 })
				local bus_lo         = part({ type = pt.FILT, x = x_instr_2 - 99, y = y_core -  7, ctype = 0x10000000 })
				local res_hi         = part({ type = pt.FILT, x = x_instr_2 - 24, y = y_core -  8 })
				local res_lo_addr_hi = part({ type = pt.FILT, x = x_instr_2 - 25, y = y_core -  9 })
				local addr_lo        =      {                 x = x_instr_2 - 23, y = y_core - 10 }
				aray(x_instr_2 - 26, y_core - 9, -1, 1, pt.METL, nil, 1)
				part({ type = pt.DTEC, x = x_instr_2 - 26, y = y_core -  9, tmp2 = 2 })
				part({ type = pt.BRAY, x = x_instr_2 - 24, y = y_core - 11, life = 1 })
				if ix_eu == 0 then
					part({ type = pt.INSL, x = x_instr_2 - 22, y = y_core - 13 })
				end

				part({ type = pt.FILT, x = x_instr_2 + 14, y = res_hi.y, dcolour = 0xFF00FFFF })
				part({ type = pt.FILT, x = x_instr_2 + 13, y = res_hi.y, dcolour = 0xFF00FFFF })
				ldtc(x_instr_2 + 12, res_hi.y, res_hi.x, res_hi.y)
				part({ type = pt.FILT, x = x_instr_2 + 14, y = res_lo_addr_hi.y, dcolour = 0xFF00FFFF })
				part({ type = pt.FILT, x = x_instr_2 + 13, y = res_lo_addr_hi.y, dcolour = 0xFF00FFFF })
				part({ type = pt.FILT, x = x_instr_2 + 12, y = res_lo_addr_hi.y })
				ldtc(x_instr_2 + 11, res_lo_addr_hi.y, res_lo_addr_hi.x, res_lo_addr_hi.y)
				part({ type = pt.FILT, x = x_instr_2 + 14, y = addr_lo.y, dcolour = 0xFF00FFFF })
				part({ type = pt.FILT, x = x_instr_2 + 13, y = addr_lo.y, dcolour = 0xFF00FFFF })
				part({ type = pt.FILT, x = x_instr_2 + 12, y = addr_lo.y })
				part({ type = pt.FILT, x = x_instr_2 + 11, y = addr_lo.y })
				ldtc(x_instr_2 + 10, addr_lo.y, addr_lo.x, addr_lo.y)
				part({ type = pt.FILT, x = x_instr_2 + 14, y = bus_lo.y, dcolour = 0xFF00FFFF })
				part({ type = pt.FILT, x = x_instr_2 + 13, y = bus_lo.y, dcolour = 0xFF00FFFF })
				part({ type = pt.FILT, x = x_instr_2 + 12, y = bus_lo.y })
				ldtc(x_instr_2 + 11, bus_lo.y, bus_lo.x, bus_lo.y)
				part({ type = pt.FILT, x = x_instr_2 + 14, y = bus_hi.y, dcolour = 0xFF00FFFF })
				part({ type = pt.FILT, x = x_instr_2 + 13, y = bus_hi.y, dcolour = 0xFF00FFFF })
				part({ type = pt.FILT, x = x_instr_2 + 12, y = bus_hi.y })
				part({ type = pt.FILT, x = x_instr_2 + 11, y = bus_hi.y })
				ldtc(x_instr_2 + 10, bus_hi.y, bus_hi.x, bus_hi.y)

				local insl   = part({ type = pt.INSL, x = instr_fetch_1.x -  1, y = y_core })
				local buffer =      {                 x = instr_fetch_1.x - 29, y = y_core }
				cray(x_reg_core + 2, y_core, insl  .x, insl  .y, pt.INSL, 1, false, -10000001)
				cray(x_reg_core + 2, y_core, buffer.x, buffer.y, pt.INSL, 1, false, -10000000)
				cray(x_reg_core + 2, y_core, buffer.x, buffer.y, pt.INSL, 1, false,  10000000)
				cray(x_reg_core + 2, y_core, insl  .x, insl  .y, pt.INSL, 1, false,  10000001)
			end

			for ix_reader = 0, readers - 1 do
				local x_reader = x_regs + ix_reader * 4 + 3

				local function half(x, y)
					local output = part({ type = pt.FILT, x = x, y = y })
					part({ type = pt.LDTC, x = x + 1, y = y })
					part({ type = pt.LSNS, x = x + 1, y = y - 1, tmp = 3, tmp2 = 2 })
					return output
				end
				local output_lo = half(x_reader    , y_regs)
				local output_hi = half(x_reader + 2, y_regs)

				part({ type = pt.LDTC, x = x_reader - 1, y = y_regs + 1, tmp = 1 })
				part({ type = pt.LDTC, x = x_reader + 1, y = y_regs + 1, tmp = 1 })
			end

			local lsns_life = part({ type = pt.FILT, x = x_decode + 2, y = y_decode, ctype = 0x10000003 })
			local bit_filt = {}
			for ix_bit = 0, 4 do
				local x_source = x_decode + 3 + ix_bit
				if ix_bit >= 3 then
					x_source = x_source + 30
				end
				bit_filt[ix_bit] = part({ type = pt.FILT, x = x_source, y = y_decode, ctype = bitx.lshift(1, ix_bit) })
			end

			local writer_info = {}
			for ix_writer = 0, writers - 1 do
				local x_source = x_decode +  8 + ix_writer * 3
				if ix_writer < writers - 1 then
					x_source = x_source - 2
				end
				writer_info[ix_writer] = {
					addr    = part({ type = pt.FILT, x = x_source    , y = y_decode, ctype = 0x10000005 + ix_writer }),
					data_lo = part({ type = pt.FILT, x = x_source + 1, y = y_decode, ctype = 0x1000FE00 + ix_writer }),
					data_hi = part({ type = pt.FILT, x = x_source + 2, y = y_decode, ctype = 0x1000CA00 + ix_writer }),
				}
			end

			for ix_reg = 0, regs - 1 do
				part({ type = ix_reg == 0 and pt.FILT or pt.STOR, x = x_target - ix_reg * 2    , y = y_decode })
				part({ type = ix_reg == 0 and pt.FILT or pt.STOR, x = x_target - ix_reg * 2 - 1, y = y_decode })
			end
			do
				local x_end = x_target - regs * 2
				part({ type = pt.CONV, x = x_end, y = y_decode, tmp = pt.FILT, ctype = pt.STOR })
				for ix_bit = 0, 5 do
					local b = bitx.lshift(1, ix_bit)
					dray(x_end, y_decode, x_end + 1 + b, y_decode, b, pt.PSCN)
				end
				part({ type = pt.DMND, x = x_end, y = y_decode, z = 20000000 })
			end

			spark({ type = pt.METL, x = x_decode + 1, y = y_decode })
			local pattern_head = part({ type = pt.FILT, x = x_decode - 1, y = y_decode })
			part({ type = pt.FILT, x = x_decode -  2, y = y_decode })
			part({ type = pt.FILT, x = x_decode -  3, y = y_decode })
			part({ type = pt.FILT, x = x_decode -  4, y = y_decode })
			part({ type = pt.FILT, x = x_decode -  5, y = y_decode })
			part({ type = pt.FILT, x = x_decode -  6, y = y_decode })
			part({ type = pt.FILT, x = x_decode -  7, y = y_decode })
			part({ type = pt.FILT, x = x_decode -  8, y = y_decode })
			part({ type = pt.FILT, x = x_decode -  9, y = y_decode })
			part({ type = pt.FILT, x = x_decode - 10, y = y_decode, tmp = 1, ctype = 0x10000005 })
			local query_bray =   { x = x_decode - 11, y = y_decode }
			part({ type = pt.DMND, x = x_decode - 12, y = y_decode, unstack = true })
			part({ type = pt.DMND, x = x_target +  1, y = y_decode })

			for ix_writer = 0, writers - 1 do
				local addr    = writer_info[writers - ix_writer - 1].addr
				local data_lo = writer_info[writers - ix_writer - 1].data_lo
				local data_hi = writer_info[writers - ix_writer - 1].data_hi

				ldtc(x_decode, y_decode, addr.x, addr.y)
				part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.FILT, ctype = pt.STOR })
				change_conductor(pt.PSCN, 2)
				cray(x_decode, y_decode, x_target, y_decode, pt.STOR, regs * 2, false)
				dray(x_decode, y_decode, x_decode - 2, y_decode, 1, false)
				dray(x_decode, y_decode, x_decode - 3, y_decode, 2, false)
				dray(x_decode, y_decode, x_decode - 5, y_decode, 4, false)
				dray(x_decode, y_decode, x_decode - 9, y_decode, 1, false)
				part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.STOR, ctype = pt.FILT })
				change_conductor(pt.METL, 2)

				for ix_bit = 0, 4 do
					local b = bitx.lshift(1, ix_bit)

					ldtc(x_decode, y_decode, bit_filt[ix_bit].x, bit_filt[ix_bit].y)
					part({ type = pt.ARAY, x = x_decode, y = y_decode })
					part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.FILT, ctype = pt.STOR })

					if ix_bit <= 1 then
						change_conductor(pt.PSCN, 2)
						if ix_bit == 0 then
							cray(x_decode, y_decode, pattern_head.x - 2, pattern_head.y, pt.STOR, 2, false)
							cray(x_decode, y_decode, pattern_head.x - 6, pattern_head.y, pt.STOR, 2, false)
						else
							cray(x_decode, y_decode, pattern_head.x - 4, pattern_head.y, pt.STOR, 4, false)
						end

						part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.SPRK, ctype = pt.PSCN })
						local inverted = ldtc(x_decode, y_decode, query_bray.x, query_bray.y, nil, 2)
						inverted.ctype = pt.BRAY
						inverted.tmp2 = 1
						part({ type = pt.LSNS, x = x_decode, y = y_decode, tmp = 3, tmp2 = 2 })
						cray(x_decode, y_decode, pattern_head.x, pattern_head.y, pt.STOR, 8, false)

						part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.PSCN, ctype = pt.INSL })
						change_conductor(pt.METL, 2, pt.STOR)

						for ix_place = 0, regs - 1, 4 do
							dray(x_decode, y_decode, x_target - ix_place * 2, y_decode, 8, false)
						end

						cray(x_decode, y_decode, pattern_head.x, pattern_head.y, pt.STOR, 1, false)
						dray(x_decode, y_decode, x_decode - 2, y_decode, 1, false)
						dray(x_decode, y_decode, x_decode - 3, y_decode, 2, false)
						dray(x_decode, y_decode, x_decode - 5, y_decode, 4, false)
					else
						part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.SPRK, ctype = pt.METL })
						local normal = ldtc(x_decode, y_decode, query_bray.x, query_bray.y, nil, 1)
						normal.ctype = pt.BRAY
						part({ type = pt.LSNS, x = x_decode, y = y_decode, tmp = 3, tmp2 = 2 })
						for ix_place = 0, regs - 1, 4 do
							if bitx.band(ix_place, b) == 0 then
								dray(x_decode, y_decode, x_target - ix_place * 2, y_decode, 8, false)
							end
						end

						part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.SPRK, ctype = pt.INSL })
						part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.METL, ctype = pt.INSL })
						part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.INSL, ctype = pt.METL })

						local inverted = ldtc(x_decode, y_decode, query_bray.x, query_bray.y, nil, 2)
						inverted.ctype = pt.BRAY
						inverted.tmp2 = 1
						part({ type = pt.LSNS, x = x_decode, y = y_decode, tmp = 3, tmp2 = 2 })
						for ix_place = 0, regs - 1, 4 do
							if bitx.band(ix_place, b) ~= 0 then
								dray(x_decode, y_decode, x_target - ix_place * 2, y_decode, 8, false)
							end
						end

						part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.METL, ctype = pt.INSL })
					end

					change_conductor(pt.PSCN, 2, pt.STOR)
					cray(x_decode, y_decode, query_bray.x, query_bray.y, pt.SPRK, 1, false)
					part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.STOR, ctype = pt.FILT })
					if ix_bit < 4 then
						change_conductor(pt.METL, 2)
					end
				end

				ldtc(x_decode, y_decode, data_lo.x, data_lo.y)
				dray(x_decode, y_decode, x_decode - 3, y_decode, 1, false)
				dray(x_decode, y_decode, x_decode - 5, y_decode, 3, false)
				dray(x_decode, y_decode, x_decode - 9, y_decode, 1, false)
				ldtc(x_decode, y_decode, data_hi.x, data_hi.y)
				dray(x_decode, y_decode, x_decode - 8, y_decode, 1, false)
				dray(x_decode, y_decode, x_decode - 6, y_decode, 1, false)
				dray(x_decode, y_decode, x_decode - 4, y_decode, 1, false)
				dray(x_decode, y_decode, x_decode - 2, y_decode, 1, false)
				change_conductor(pt.METL, 2)
				for ix_reg = 0, regs - 1, 4 do
					dray(x_decode, y_decode, x_target - ix_reg * 2 + 1, y_decode, 9, false)
				end
			end

			part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.SPRK, ctype = pt.METL })
			part({ type = pt.CONV, x = x_decode, y = y_decode, tmp = pt.METL, ctype = pt.SPRK })
			part({ type = pt.DMND, x = x_decode, y = y_decode })

			part({ type = pt.INSL, x = x_regs + 2, y = y_regs })

			part({ type = pt.PSTN, x = x_regmove_left + 1, y = y_regs })
			part({ type = pt.PSTN, x = x_regmove_left    , y = y_regs })
			part({ type = pt.PSTN, x = x_regmove_left - 1, y = y_regs, tmp = 64, extend = math.huge })
			part({ type = pt.INSL, x = x_regmove_left - 3, y = y_regs })
			local y_ballast = y_regs + eu_spacing
			if ix_eu == eus - 1 then
				y_ballast = y_regs + 4
			end
			local ballast = part({ type = pt.HEAC, x = x_regmove_ballast, y = y_ballast })
			solid_spark(x_regmove_left - 2, y_regs + 1, 1, 0, pt.PSCN)
			lsns_spark({ type = pt.NSCN, x = x_regmove_left - 4, y = y_regs, life = 3 }, -1, 1, 0, 1)

			cray(ballast.x, y_regmove_apom_top, ballast.x, ballast.y, pt.HEAC, 1, pt.PSCN)
			dray(ballast.x, y_regmove_apom_top, ballast.x, y_regs, 1, pt.PSCN)
			regmove_ballasts[ix_eu] = {
				part   = ballast,
				y_regs = y_regs,
			}
		end
		for ix_eu = eus - 1, 0, -1 do
			local ballast = regmove_ballasts[ix_eu].part
			local y_regs  = regmove_ballasts[ix_eu].y_regs
			cray(ballast.x, y_regmove_apom_bottom, ballast.x, y_regs, pt.HEAC, 1, pt.PSCN)
			cray(ballast.x, y_regmove_apom_bottom, ballast.x, ballast.y, pt.HEAC, 1, pt.PSCN)
		end
		part({ type = pt.PSTN, x = x_regmove_ballast, y = y_regmove_apom_top + 1, tmp = 62 })

		local y_reader = y_read_dray_up - 3
		for ix_reader = 0, readers - 1 do
			local x_reader = x_regs + ix_reader * 4 + 1

			local target_lo = part({ type = pt.FILT, x = x_reader    , y = y_reader })
			local target_hi = part({ type = pt.FILT, x = x_reader + 2, y = y_reader })
			local y_src = target_lo.y + 1
			local y_target = target_lo.y - eu_spacing * eus
			local length = 1
			y_src = y_src + 1
			length = length + 1
			y_target = y_target + 1
			dray(target_lo.x, y_src, target_lo.x, y_target, length, pt.PSCN)
			-- if ix_reader == readers - 1 then
			-- end
			dray(target_hi.x, y_src, target_hi.x, y_target, length, pt.PSCN)
		end
		for ix_instr = 0, 3 do
			local x_instr = x_regs + ix_instr * 2 + 20
			local target_instr = part({ type = pt.FILT, x = x_instr, y = y_reader })
			dray(target_instr.x, target_instr.y + 1, target_instr.x, target_instr.y - eu_spacing * eus, 1, pt.PSCN)
		end
		do
			local target_pc_lo = part({ type = pt.FILT, x = x_regs + 2, y = y_reader })
			local target_pc_hi = part({ type = pt.FILT, x = x_regs + 4, y = y_reader })
			local target_defer = part({ type = pt.FILT, x = x_regs + 6, y = y_reader })
			dray(target_pc_lo.x, target_pc_lo.y + 1, target_pc_lo.x, target_pc_lo.y - eu_spacing * eus, 1, pt.PSCN)
			dray(target_pc_hi.x, target_pc_hi.y + 1, target_pc_hi.x, target_pc_hi.y - eu_spacing * eus, 1, pt.PSCN)
			local y_target_defer = target_defer.y - eu_spacing * eus
			dray(target_defer.x, target_defer.y + 1, target_defer.x, y_target_defer, 1, pt.PSCN)
			dray(target_defer.x + 1, y_target_defer - 1, target_defer.x - 2, y_target_defer + 2, 1, pt.PSCN)
		end
		cray(x_regs +  7, y_reader + 2, x_regs +  7, y_reader - eu_spacing * eus + 1, pt.INSL, 1, pt.PSCN)
		cray(x_regs +  9, y_reader + 2, x_regs +  9, y_reader - eu_spacing * eus + 1, pt.INSL, 1, pt.PSCN)
		cray(x_regs + 29, y_reader + 2, x_regs + 29, y_reader - eu_spacing * eus + 1, pt.INSL, 1, pt.PSCN)
	end

	do -- head
		for ix_eu = 0, eus - 1 do
			local x_core = x_body + 25
			local y_core = y_ix_eu(ix_eu) - 9
			plot.merge_parts(x_core, y_core, parts, head.get_parts(), {})
		end
	end
	do -- tail
		for ix_eu = 0, eus - 1 do
			local x_core = x_body + 25
			local y_core = y_ix_eu(ix_eu) - 7
			plot.merge_parts(x_core, y_core, parts, tail.get_parts(), {
				[ 86 ] = 90,
				[ 87 ] = 91,
				[ 88 ] = 92,
				[ 89 ] = 93,
			})
		end
	end
	do -- bus control
		for ix_eu = 0, eus - 1 do
			local x_core = x_body + 91
			local y_core = y_ix_eu(ix_eu) - 3
			plot.merge_parts(x_core, y_core, parts, bus_control.get_parts(), {
				[ 29 ] = 34,
			})
			do
				local x_bus_lo = x_core - 28
				cray(x_bus_lo, y_core - 2, x_bus_lo - 2, y_core    , pt.LDTC, 1, false)
				cray(x_bus_lo, y_core - 2, x_bus_lo - 1, y_core - 1, pt.LDTC, 1, false)
				part({ type = pt.LSNS, x = x_bus_lo    , y = y_core - 2, tmp = 3, tmp2 = 2 })
				part({ type = pt.FILT, x = x_bus_lo + 2, y = y_core - 3, ctype = 0x10000000 - 72 })
				solid_spark(x_bus_lo + 1, y_core - 2, 0, -1, pt.PSCN)
				part({ type = pt.HEAC, x = x_bus_lo - 2, y = y_core })
				cray(x_bus_lo - 3, y_core + 1, x_bus_lo - 1, y_core - 1, pt.HEAC, 1, pt.PSCN)
				cray(x_bus_lo - 3, y_core + 1, x_bus_lo - 2, y_core    , pt.HEAC, 1, pt.PSCN)
				part({ type = pt.FILT, x = x_bus_lo + 1, y = y_core - 1 })
				part({ type = pt.FILT, x = x_bus_lo    , y = y_core - 1 })
				aray(x_bus_lo, y_core, -1, 1, pt.METL, nil, 1)
				part({ type = pt.BRAY, x = x_bus_lo + 2, y = y_core - 2, life = 1 })
				part({ type = pt.INSL, x = x_bus_lo + 3, y = y_core - 3 })
				part({ type = pt.FILT, x = x_bus_lo + 4, y = y_core     })
				part({ type = pt.LDTC, x = x_bus_lo + 3, y = y_core + 1 })
				part({ type = pt.FILT, x = x_bus_lo + 2, y = y_core + 2 })
				part({ type = pt.DTEC, x = x_bus_lo + 3, y = y_core     , tmp2 = 2 })
				dray(x_bus_lo + 3, y_core, x_bus_lo + 45, y_core, 1, pt.PSCN)
			end
		end
	end

	do -- tptasm anchor
		local x_anchor = x_body - 28
		local y_anchor = y_ix_eu(eus - 1) + 11
		part({ x = x_anchor - 1, y = y_anchor, type = pt.FILT, ctype = machine_id })
		part({ x = x_anchor    , y = y_anchor, type = pt.QRTZ, ctype = 0x1864A205, tmp2 = 0x201 }) -- data in ctype, dx = 1, dy = 0
		local checksum = 0
		local x_push = x_anchor + 1
		local function push(value)
			part({ x = x_push, y = y_anchor, type = pt.FILT, ctype = value })
			checksum = checksum + value
			x_push = x_push + 1
		end
		local model_name = ("R4A%02i%02i"):format(height, eus)
		for ch in model_name:gmatch(".") do
			push(ch:byte())
		end
		push(0)
		push(checksum)
	end

	ucontext.frame(x_body - 31, y_body - 1, x_body + 134, y_body + eus * eu_spacing + height + 18)

	return parts
end

return {
	build_internal = build_internal,
}

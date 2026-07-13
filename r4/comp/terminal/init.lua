local bitx          = require("spaghetti.bitx")
local plot          = require("spaghetti.plot")
local check         = require("spaghetti.check")
local misc          = require("spaghetti.misc")
local write_tap     = require("r4.comp.bus.write_tap")
local read_tap      = require("r4.comp.bus.read_tap")
local font_template = require("r4.comp.terminal.font")
local screen_core   = require("r4.comp.terminal.core.generated_screen")
local keyboard_core = require("r4.comp.terminal.core.generated_keyboard")

local pt = plot.pt
local audited_pairs = pairs
local peripheral_mask = 0xFFFFE000

local function build(params, params_name, component)
	local have_screen = params.screen_y and true
	local have_keyboard = params.keyboard_y and true

	if not have_screen and not have_keyboard then
		misc.user_error("at least one of %s and %s must be specified", params_name .. ".screen_top/.screen_bottom", params_name .. ".keyboard_top/.keyboard_bottom")
	end

	local size_bw, size_bh
	check.integer_range(params_name .. ".chars_nh", params.chars_nh, 12, 32)
	if have_screen then
		check.integer_range(params_name .. ".chars_nv", params.chars_nv, 3, 32)
		if params.single_pixel then
			if params.chars_nv < 5 + math.ceil(params.chars_nh / 4) then
				misc.user_error("%s and %s specify too many columns compared to the amount of rows", params_name .. ".chars_nh", params_name .. ".chars_nv")
			end
		end
		if params.chars_nh < 6 + math.ceil(params.chars_nv / 2) then
			misc.user_error("%s and %s specify too many rows compared to the amount of columns", params_name .. ".chars_nv", params_name .. ".chars_nh")
		end
		size_bh = params.chars_nv
	end
	size_bw = params.chars_nh

	local areas = {}

	local block_size = 8

	local width = size_bw * block_size + 44
	local height

	local xoff
	if params.x.which == "left" then
		xoff = params.x.value
	else
		xoff = params.x.value - width + 1
	end
	local screen_yoff
	if have_screen then
		height = size_bh * block_size + 44
		if params.screen_y.which == "screen_top" then
			screen_yoff = params.screen_y.value
		else
			screen_yoff = params.screen_y.value - height + 1
		end
	end
	local keyboard_yoff
	if have_keyboard then
		if params.keyboard_y.which == "keyboard_top" then
			keyboard_yoff = params.keyboard_y.value
		else
			keyboard_yoff = params.keyboard_y.value - 50
		end
	end

	local peripheral_base = params.base_address

	local colors = {
		[ 0 ] = 0x000000, 0x0000AA, 0x00AA00, 0x00AAAA,
		        0xAA0000, 0xAA00AA, 0xAAAA00, 0xAAAAAA,
		        0x555555, 0x5555FF, 0x55FF55, 0x55FFFF,
		        0xFF5555, 0xFF55FF, 0xFFFF55, 0xFFFFFF,
	}
	if params.colors ~= nil then
		local colors_name = params_name .. ".colors"
		check.table(colors_name, params.colors)
		for key, value in audited_pairs(params.colors) do
			check.integer_range(colors_name .. " key " .. tostring(key), key, 0, 15)
			check.integer_range(colors_name .. "[" .. key .. "]", value, 0, 0xFFFFFF)
			colors[key] = value
		end
	end

	local function parse_font_bitmap(value_name, value, width, height)
		check.string(value_name, value)
		local next_char = value:gmatch("[%.#]")
		local data = {}
		for ix_row = 0, height - 1 do
			local row = {}
			for ix_column = 0, width - 1 do
				local ch = next_char()
				if not ch then
					misc.user_error("%s is missing pixel (%i; %i)", value_name, ix_column, ix_row)
				end
				local pixel = false
				if ch == "#" then
					pixel = true
				elseif ch ~= "." then
					misc.user_error("%s pixel (%i; %i) is neither . nor #", value_name, ix_column, ix_row)
				end
				row[ix_column] = pixel
			end
			data[ix_row] = row
		end
		if next_char() then
			misc.user_error("%s has excess pixels", value_name)
		end
		return data
	end

	local font = {}
	for key, value in audited_pairs(font_template) do
		local data = {}
		for ix_row = 0, 7 do
			local row = {}
			for ix_column = 0, 7 do
				row[ix_column] = bitx.band(value[ix_row], bitx.lshift(1, ix_column)) ~= 0
			end
			data[ix_row] = row
		end
		font[key] = data
	end
	if params.font ~= nil then
		local font_name = params_name .. ".font"
		check.table(font_name, params.font)
		for key, value in audited_pairs(params.font) do
			check.integer_range(font_name .. " key " .. tostring(key), key, 0, 0xFF)
			font[key] = parse_font_bitmap(font_name .. "[" .. key .. "]", value, 8, 8)
		end
	end

	local parts = {}
	local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
	local mutate        = ucontext.mutate
	local cray          = ucontext.cray
	local dray          = ucontext.dray
	local part          = ucontext.part
	local aray          = ucontext.aray
	local ldtc          = ucontext.ldtc
	local spark         = ucontext.spark
	local solid_spark   = ucontext.solid_spark
	local lsns_spark    = ucontext.lsns_spark
	local piston_extend = ucontext.piston_extend
	local dray_log      = ucontext.dray_log
	local spark_row     = ucontext.spark_row
	local sig_magn      = ucontext.sig_magn

	local x_base = xoff + 22

	if have_screen then
		local y_base = screen_yoff + 11
		local sparks_under_banks = {}
		local x_cmem = x_base
		local y_cmem = y_base
		local cmem_width  = 64
		local cmem_height = 8
		do -- character memory
			local function memory32(p, value)
				local bray = bitx.band(value, 1) ~= 0
				return mutate(p, {
					type    = bray and pt.BRAY or pt.FILT,
					life    = bray and     988 or 4,
					tmp     = bray and       1 or 0,
					ctype   = bitx.bor(bitx.band(value, 0xFFFFFFFE), 1),
					dcolour = 0x00000000,
				})
			end
			cray(x_cmem - 5, y_cmem - 8, x_cmem - 5, y_cmem, pt.METL, 8, pt.PSCN)
			cray(x_cmem - 5, y_cmem - 8, x_cmem - 5, y_cmem, pt.METL, 8, pt.PSCN)
			cray(x_cmem - 5, y_cmem - 1, x_cmem - 5, y_cmem, pt.SPRK, 8, false, nil, 3)
			table.insert(sparks_under_banks, spark({ type = pt.INWR, x = x_cmem - 5, y = y_cmem - 2 }))
			part({ type = pt.INSL, x = x_cmem - 4, y = y_cmem - 1 })
			part({ type = pt.INSL, x = x_cmem - 3, y = y_cmem - 1 })
			part({ type = pt.INSL, x = x_cmem - 2, y = y_cmem - 1 })
			for y = 0, cmem_height - 1 do
				part({ type = pt.INSL, x = x_cmem + cmem_width, y = y_cmem + y })
				for x = 0, cmem_width - 1 do
					local char_index = x + (3 - bitx.band(y, 3)) * 0x40
					local base = bitx.band(y, 4)
					local data = 0
					for ix_row = 0, 3 do
						local row = font[char_index][base + ix_row]
						for ix_column = 0, 7 do
							data = bitx.bor(data, bitx.lshift(row[ix_column] and 1 or 0, ix_column + ix_row * 8))
						end
					end
					part(memory32({ x = x_cmem + x, y = y_cmem + y }, data))
				end
				local mask = (y % 2 == 0) and 0x2000 or 0x20000000
				part ({ type = pt.STOR, x = x_cmem - 1, y = y_cmem + y })
				part ({ type = pt.FILT, x = x_cmem - 2, y = y_cmem + y, ctype = mask, tmp = 1 })
				part ({ type = pt.FILT, x = x_cmem - 3, y = y_cmem + y, ctype = mask })
				part ({ type = pt.ARAY, x = x_cmem - 4, y = y_cmem + y, life = 988 })
				spark({ type = pt.METL, x = x_cmem - 5, y = y_cmem + y })
			end
			do
				local source = part({ type = pt.FILT, x = x_cmem - 11, y = y_cmem - 9, ctype = 0x10000000 })
				ldtc(x_cmem - 11, y_cmem - 2, source.x, source.y)
				part({ type = pt.FILT, x = x_cmem - 11, y = y_cmem - 1 })
			end
			local function ldtc_stack(x, ldtc_ctype)
				for y = 0, cmem_height - 1 do
					local mask_type = (y % 2 == 0) and pt.CRMC or pt.HEAC
					part({ type = pt.CONV  , x = x - 2, y = y_cmem + y, tmp = mask_type, ctype = pt.FILT })
					part({ type = pt.LDTC  , x = x - 2, y = y_cmem + y, ctype = ldtc_ctype })
					part({ type = mask_type, x = x - 3, y = y_cmem + y })
					part({ type = pt.FILT  , x = x - 4, y = y_cmem + y })
					part({ type = pt.CONV  , x = x - 2, y = y_cmem + y + 1, tmp = pt.FILT, ctype = mask_type })
				end
			end
			dray(x_cmem - 9, y_cmem - 1, x_cmem - 9, y_cmem + 1, 1, false)
			dray(x_cmem - 9, y_cmem - 1, x_cmem - 9, y_cmem + 2, 2, false)
			dray(x_cmem - 9, y_cmem - 1, x_cmem - 9, y_cmem + 4, 4, false)
			table.insert(sparks_under_banks, spark({ type = pt.PSCN, x = x_cmem - 9, y = y_cmem - 2 }))
			ldtc_stack(x_cmem -  7, pt.BRAY)
			cray(x_cmem - 13, y_cmem - 1, x_cmem - 13, y_cmem, pt.LDTC, 8, false)
			cray(x_cmem - 13, y_cmem - 1, x_cmem - 13, y_cmem, pt.LDTC, 8, false)
			cray(x_cmem - 13, y_cmem - 1, x_cmem - 13, y_cmem, pt.LDTC, 8, false)
			cray(x_cmem - 13, y_cmem - 1, x_cmem - 13, y_cmem, pt.LDTC, 8, false)
			part({ type = pt.FILT, x = x_cmem - 14, y = y_cmem - 2 })
			do
				local prev = part({ type = pt.FILT, x = x_cmem - 3, y = y_cmem - 2 })
				local source = part({ type = pt.FILT, x = x_cmem, y = y_cmem - 5, ctype = bitx.bor(0x10000000, 12) })
				ldtc(x_cmem - 2, y_cmem - 3, source.x, source.y)
				ldtc(x_cmem - 13, y_cmem - 2, prev.x, prev.y)
			end
			part({ type = pt.LSNS, x = x_cmem - 13, y = y_cmem - 2, tmp = 3 })
			table.insert(sparks_under_banks, spark({ type = pt.PSCN, x = x_cmem - 13, y = y_cmem - 2 }))
			ldtc_stack(x_cmem - 11,     nil)

			do -- bray ldtc apom
				local x_apom        = x_cmem - 10
				local y_apom_top    = y_cmem - 8
				local y_apom_bottom = y_cmem + 26
				local source = part({ type = pt.STOR, x = x_apom, y = y_cmem - 1, tmp = 3 })
				part({ type = pt.FILT, x = x_apom +  2, y = y_cmem - 2 })
				local source_2 = part({ type = pt.FILT, x = x_apom + 11, y = y_cmem - 5, ctype = bitx.bor(0x10000000, 8) })
				do
					local prev = part({ type = pt.FILT, x = x_apom + 8, y = y_cmem - 2 })
					ldtc(x_apom + 3, y_cmem - 2, prev.x, prev.y)
				end
				ldtc(x_apom + 9, y_cmem - 3, source_2.x, source_2.y)
				cray(x_apom, y_apom_top, source.x, source.y, pt.HEAC, 2, pt.PSCN)
				dray(x_apom, y_apom_top, source.x, y_apom_bottom - 1, 1, pt.PSCN)
				dray(x_apom, y_apom_top, source.x, source.y + 1, 1, pt.PSCN)
				part({ type = pt.CONV, x = x_apom + 1, y = y_cmem - 1, tmp = pt.LSNS, ctype = pt.CRMC })
				local templ = part({ type = pt.LSNS, x = x_apom, y = y_apom_top + 1, tmp = 3, tmp2 = 2 })
				cray(x_apom, y_apom_top, templ.x, templ.y, pt.HEAC, 1, pt.PSCN)
				cray(x_apom, y_apom_top, source.x, source.y, pt.HEAC, 1, pt.PSCN)
				cray(x_apom, y_apom_bottom, source.x, source.y, pt.HEAC, 1, pt.PSCN)
				dray(x_apom, y_apom_bottom, templ.x, templ.y, 1, pt.PSCN)
				cray(x_apom, y_apom_bottom, source.x, source.y + 1, pt.STOR, 2, pt.PSCN)
				cray(x_apom, y_apom_bottom, x_apom, y_apom_bottom - 1, pt.SPRK, 1, pt.PSCN)
				cray(x_apom, y_apom_bottom, source.x, source.y + 1, pt.CRMC, 1, pt.PSCN)
			end

			do -- write head
				local x_head = x_cmem + cmem_width - 1
				local x_end  = x_base + size_bw * block_size + 10
				local y_head = y_cmem + cmem_height + 1

				do
					local target = spark({ type = pt.PSCN, x = x_head, y = y_head + 1 })
					spark_row(target.x + 15, target.y, target.x, target.y, pt.PSCN, 1, 4)
				end
				do
					local y_top = y_base - 8
					local target_1 = part({ type = pt.DRAY, x = x_head     , y = y_head })
					local target_2 = part({ type = pt.PSTN, x = x_head +  9, y = y_head })
					cray(target_2.x - (target_2.y - y_top), y_top, target_2.x, target_2.y, pt.CRMC, 1, pt.PSCN)
					cray(target_1.x, y_top, target_1.x, target_1.y, pt.CRMC, 1, pt.PSCN)
					cray(target_2.x, y_top, target_2.x, target_2.y, pt.PSTN, 1, pt.PSCN)
					cray(target_1.x + (target_1.y - y_top), y_top, target_1.x, target_1.y, pt.CRMC, 1, pt.PSCN)

					cray(x_head + 30, target_2.y, target_2.x, target_2.y, pt.CRMC, 1, pt.PSCN)
					cray(x_head + 30, target_1.y, target_1.x, target_1.y, pt.CRMC, 1, pt.PSCN)
					cray(x_head + 30, target_2.y, target_2.x, target_2.y, pt.PSTN, 1, pt.PSCN)
					cray(x_head + 30, target_1.y, target_1.x, target_1.y, pt.CRMC, 1, pt.PSCN)
				end
				part({ type = pt.FRME, x = x_head +  1, y = y_head - 1 })
				part({ type = pt.FRME, x = x_head +  1, y = y_head     })
				part({ type = pt.FRME, x = x_head +  1, y = y_head + 1 })
				part({ type = pt.DMND, x = x_head +  2, y = y_head - 1 })
				part({ type = pt.FILT, x = x_head     , y = y_head - 1 })
				part({ type = pt.PSTN, x = x_head +  2, y = y_head, extend = 1 })
				part({ type = pt.PSTN, x = x_head + 10, y = y_head, extend = math.huge, tmp = 2 })
				part({ type = pt.INSL, x = x_head + 11, y = y_head })
				solid_spark(x_head + 11, y_head + 1, -1, 0, pt.NSCN)

				local x_stack = x_head + 12
				local y_stack = y_head - 1

				part({ type = pt.FILT, x = x_stack + 2, y = y_stack + 2, ctype = 0x10000003 })
				do
					local target = spark({ type = pt.PSCN, x = x_stack - 2, y = y_stack, life = 3 })
					spark_row(x_base - 15, target.y, target.x, target.y, pt.PSCN, 1, target.life)
				end
				part ({ type = pt.FILT, x = x_stack - 1, y = y_stack })
				spark({ type = pt.PSCN, x = x_stack + 1, y = y_stack, life = 3 })
				part ({ type = pt.FILT, x = x_stack - 3, y = y_stack, ctype = 0x1000DEAD, tmp = 1 })

				do
					local target = spark({ type = pt.PSCN, x = x_stack - 8, y = y_stack - 3, life = 3 })
					spark_row(x_end, target.y, target.x, target.y, pt.PSCN, 1, target.life, 8)
				end

				local function change_conductor(conductor, from)
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = conductor, tmp = from or pt.SPRK })
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.SPRK, tmp = conductor })
					part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3, tmp2 = 2 })
				end

				part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3, tmp2 = 2 })
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 6, tmp2 = 3, ctype = pt.SPRK })
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 5, tmp2 = 3, ctype = pt.STOR })
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.FILT, ctype = pt.CRMC })
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.CRMC, ctype = bitx.bor(pt.FILT, bitx.lshift(1, sim.PMAPBITS)) })
				ldtc(x_stack, y_stack, x_stack + 10, y_stack)
				part({ type = pt.DRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 1 })
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.FILT, ctype = pt.CRMC })
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.CRMC, ctype = pt.FILT })
				local bits = {
					[ 0 ] = 1,
					[ 1 ] = 2,
					[ 2 ] = 3,
					[ 3 ] = 4,
					[ 4 ] = 5,
					[ 5 ] = 6,
				}
				for i = 0, 5 do
					part({ type = pt.INSL, x = x_head + 3 + i, y = y_head - 1 })
					part({ type = pt.PSTN, x = x_head + 3 + i, y = y_head, extend = bitx.lshift(1, math.max(0, i - 1)) })
					local b = part({ type = pt.FILT, x = x_end + i, y = y_stack, ctype = bitx.lshift(1, bits[i]) })

					change_conductor(pt.INST)
					ldtc(x_stack, y_stack, b.x, b.y)
					part({ type = pt.ARAY, x = x_stack, y = y_stack, life = 1000 })
					part({ type = pt.DRAY, x = x_stack, y = y_stack, tmp = 2, tmp2 = 5 - i })
					change_conductor(pt.PSCN)
					if i < 5 then
						part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 7 - i, ctype = pt.SPRK })
					end
				end
			end

			do -- write dray bank
				local x_bank = x_cmem + cmem_width + 5
				local y_bank = y_cmem + cmem_height - 2
				local x_end  = x_base + size_bw * block_size + 10

				part({ type = pt.FILT, x = x_bank + 17, y = y_bank - 3 })
				do
					local source = part({ type = pt.FILT, x = x_bank + 17, y = y_base - 7, ctype = 0x1000DEAD, unstack = true })
					ldtc(source.x, y_bank - 4, source.x, source.y)
					ldtc(source.x, y_bank + 1, source.x, source.y)
					part({ type = pt.FILT, x = source.x, y = y_bank + 2 })
				end

				do
					local target = spark({ type = pt.PSCN, x = x_bank + 7, y = y_bank - 2, life = 3 })
					spark_row(x_bank + 24, target.y, target.x, target.y, pt.PSCN, 1, target.life)
				end
				do
					local target_1 = part({ type = pt.CRMC, x = x_bank + 7, y = y_bank - 1 })
					local target_2 = part({ type = pt.CRMC, x = x_bank - 4, y = y_bank - 1 })
					local source = part({ type = pt.PSTN, x = x_bank + 14, y = y_bank - 1 })
					cray(x_base - 18, source.y  , source.x  , source.y  , pt.PSTN, 2, pt.PSCN)
					cray(x_base - 18, target_1.y, target_1.x, target_1.y, pt.CRMC, 1, pt.PSCN)
					cray(x_base - 18, target_2.y, target_2.x, target_2.y, pt.CRMC, 1, pt.PSCN)
					cray(x_base - 18, source.y  , source.x  , source.y  , pt.PSTN, 2, pt.PSCN)
					dray(x_base - 18, target_1.y, target_1.x, target_1.y, 1, pt.PSCN)
					dray(x_base - 18, target_2.y, target_2.x, target_2.y, 1, pt.PSCN)
					part({ type = pt.DRAY, x = x_base - 17, y = target_1.y, tmp = 1 })
					cray(x_end, source.y  , source.x + 1, source.y  , pt.PSTN, 2, pt.PSCN) -- 95 94 85 87 ...
					cray(x_end, target_2.y, target_2.x  , target_2.y, pt.CRMC, 1, pt.PSCN)
					cray(x_end, target_1.y, target_1.x  , target_1.y, pt.CRMC, 1, pt.PSCN)
					cray(x_end, source.y  , source.x + 1, source.y  , pt.PSTN, 2, pt.PSCN)
					cray(x_end, target_2.y, target_2.x  , target_2.y, pt.CRMC, 1, pt.PSCN)
					cray(x_end, target_1.y, target_1.x  , target_1.y, pt.CRMC, 1, pt.PSCN)
				end
				part({ type = pt.INSL, x = x_bank -  2, y = y_bank - 2 })
				part({ type = pt.CRMC, x = x_bank -  1, y = y_bank     })
				part({ type = pt.FRME, x = x_bank +  8, y = y_bank - 2 })
				part({ type = pt.FRME, x = x_bank +  8, y = y_bank - 1 })
				part({ type = pt.DMND, x = x_bank +  9, y = y_bank - 2 })
				part({ type = pt.PSTN, x = x_bank +  9, y = y_bank - 1, extend = 1 })
				part({ type = pt.FILT, x = x_bank + 14, y = y_bank - 2 })
				part({ type = pt.FILT, x = x_bank + 15, y = y_bank - 2 })
				part({ type = pt.PSTN, x = x_bank + 15, y = y_bank - 1 })
				part({ type = pt.FILT, x = x_bank + 16, y = y_bank - 2 })
				part({ type = pt.PSTN, x = x_bank + 16, y = y_bank - 1, tmp = 2 })
				part({ type = pt.INSL, x = x_bank + 17, y = y_bank - 1 })
				for x = 0, 7 do
					local input = 7 - x
					local distance = (3 - bitx.band(input, 3)) + bitx.band(input, 4)
					part({ type = pt.DRAY, x = x_bank + x, y = y_bank, tmp = 1, tmp2 = distance })
				end
				solid_spark(x_bank + 17, y_bank, -1, 0, pt.NSCN)

				part({ type = pt.FRME, x = x_bank +  9, y = y_bank + 1, tmp = 1 })
				part({ type = pt.PSTN, x = x_bank + 10, y = y_bank + 1, extend = 1 })
				part({ type = pt.PSTN, x = x_bank + 11, y = y_bank + 1, extend = 12 })
				part({ type = pt.PSTN, x = x_bank + 12, y = y_bank + 1 })
				part({ type = pt.INSL, x = x_bank + 13, y = y_bank + 1 })
				solid_spark(x_bank + 13, y_bank + 2, -1, 0, pt.NSCN)
				solid_spark(x_bank + 10, y_bank + 2, 1, 0, pt.PSCN)

				lsns_spark({ type = pt.PSCN, x = x_bank - 4, y = y_bank - 2, life = 3 }, 0, -1, 0, -2)
				part({ type = pt.CRMC, x = x_bank - 4, y = y_bank + 1 })
				do
					local source = part({ type = pt.INSL, x = x_bank + 20, y = y_bank + 1 })
					local target = part({ type = pt.DRAY, x = x_bank -  3, y = y_bank    , tmp = 1, tmp2 = 1 })
					local x_from = x_bank + 23
					local y_end = y_base + size_bh * block_size + 17
					cray(source.x + 1, source.y - 1, source.x, source.y, pt.INSL, 1, pt.PSCN)
					dray(x_from + 1, target.y, target.x, target.y, 1, pt.PSCN)
					cray(target.x, y_end, target.x, target.y, pt.INSL, 1, pt.PSCN)
					cray(source.x, y_end, source.x, source.y, pt.INSL, 1, pt.PSCN, 2000)
					target.x = x_from
				end

				lsns_spark({ type = pt.PSCN, x = x_bank + 1, y = y_bank - 5, life = 3 }, 1, 0, 2, 0)
				local if_bray
				do
					if_bray = part({ type = pt.FILT, x = x_bank - 1, y = y_bank - 3 })
					part({ type = pt.INSL, x = x_bank - 2, y = y_bank - 3 })
					dray(x_base - 18, if_bray.y, if_bray.x, if_bray.y, 1, pt.PSCN)
				end
				do
					local source = part({ type = pt.INSL, x = x_bank + 20, y = y_bank - 3 })
					local target = part({ type = pt.DRAY, x = x_bank, y = y_bank - 4, tmp = 1, tmp2 = 4 })
					local x_from = x_bank + 23
					local y_end = y_base + size_bh * block_size + 17
					cray(source.x + 1, source.y - 1, source.x, source.y, pt.INSL, 1, pt.PSCN)
					dray(x_from + 1, target.y, target.x, target.y, 1, pt.PSCN)
					cray(target.x, y_end, target.x, target.y, pt.INSL, 1, pt.PSCN)
					cray(source.x, y_end, source.x, source.y, pt.INSL, 1, pt.PSCN, 1000)
					target.x = x_from
				end

				local x_end = x_base + size_bw * block_size
				local target_31b = { x = x_end + 10, y = y_bank - 3 }
				local target_1b  = { x = x_end + 11, y = y_bank - 3 }

				part({ type = pt.FILT, x = x_bank, y = y_bank - 3 })
				ldtc(x_bank + 1, y_bank - 3, target_31b.x, target_31b.y)
				part({ type = pt.STOR, x = x_bank + 1, y = y_bank - 3 })
				part({ type = pt.STOR, x = x_bank + 2, y = y_bank - 3 })
				part({ type = pt.FILT, x = x_bank + 3, y = y_bank - 3, tmp = 1, ctype = 1 })
				part({ type = pt.STOR, x = x_bank + 4, y = y_bank - 3 })
				part({ type = pt.FILT, x = x_bank + 5, y = y_bank - 3 })
				ldtc(x_bank + 6, y_bank - 3, target_1b.x, target_1b.y)
				part({ type = pt.STOR, x = x_bank + 6, y = y_bank - 3 })
				aray(x_bank + 7, y_bank - 3, 1, 0, pt.METL, nil, 1000)

				part({ type = pt.FILT, x = x_bank + 9, y = y_bank - 3, dcolour = 0 })
				ldtc(x_bank + 10, y_bank - 3, target_31b.x, target_31b.y)
				dray(x_bank + 10, y_bank - 3, if_bray.x, if_bray.y, 1, pt.METL)

				local x_stack = x_bank + 20
				local y_stack = y_bank - 2

				solid_spark(x_stack - 1, y_stack + 1, -1, -1, pt.PSCN)
				part ({ type = pt.FILT, x = x_stack - 1, y = y_stack })
				spark({ type = pt.PSCN, x = x_stack + 1, y = y_stack })
				part ({ type = pt.FILT, x = x_stack - 3, y = y_stack, tmp = 1, ctype = 0x1000DEAD })

				local function change_conductor(conductor, from)
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = conductor, tmp = from or pt.SPRK })
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.SPRK, tmp = conductor })
					part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3, tmp2 = 2 })
				end

				part({ type = pt.FILT, x = x_stack + 2, y = y_stack + 2, ctype = 0x10000003 })
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 4, tmp2 = 6, ctype = pt.SPRK })
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 3, tmp2 = 6, ctype = pt.STOR })
				local bits = {
					[ 0 ] = 7,
					[ 1 ] = 8,
					[ 2 ] = 0,
					[ 3 ] = 9,
				}
				for i = 0, 3 do
					part({ type = pt.INSL, x = x_bank + 10 + i, y = y_bank - 2 })
					part({ type = pt.PSTN, x = x_bank + 10 + i, y = y_bank - 1, extend = bitx.lshift(1, math.max(0, i - 1)) })
					local b = part({ type = pt.FILT, x = x_end + 4 + i, y = y_stack, ctype = bitx.lshift(1, bits[i]) })

					change_conductor(pt.INST)
					ldtc(x_stack, y_stack, b.x, b.y)
					part({ type = pt.ARAY, x = x_stack, y = y_stack, life = 1000 })
					part({ type = pt.DRAY, x = x_stack, y = y_stack, tmp = 2, tmp2 = 6 - i })
					change_conductor(pt.PSCN)
					if i < 3 then
						part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 8 - i, ctype = pt.SPRK })
					end
				end
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = pt.PSCN })
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.PSCN, ctype = pt.SPRK })
			end
		end

		local x_blocks = x_base
		local y_blocks = y_cmem + cmem_height + 3
		do -- blocks
			for by = 0, size_bh - 1 do
				for bx = 0, size_bw - 1 do
					for y = 0, block_size - 1 do
						for x = 0, block_size - 1 do
							local xx = block_size * bx + x
							local yy = block_size * by + y
							local freezable = xx >= sim.CELL and
							                  yy >= sim.CELL and
							                  xx <  size_bw * block_size - sim.CELL and
							                  yy <  size_bh * block_size - sim.CELL
							part({ type = pt.CRMC, x = x_blocks + xx, y = y_blocks + yy, freezable = freezable, dcolour = 0xFF000000 + colors[0] })
						end
					end
				end
			end
		end

		local x_be_bottom = x_blocks
		local y_be_bottom = y_blocks + block_size * size_bh + 10
		do -- bottom block emitter
			for x = 0, block_size - 1 do
				part({ type = pt.DMND, x = x_be_bottom - block_size + x, y = y_be_bottom - 1 })
				for y = 0, block_size - 1 do
					part({ type = pt.CRMC, x = x_be_bottom - block_size + x, y = y_be_bottom + y, grvt_cover = params.grvt_cover })
				end
			end

			for bx = 0, size_bw - 1 do
				for y = 0, block_size - 1 do
					for x = 0, block_size - 1 do
						part({ type = pt.CRMC, x = x_be_bottom + block_size * bx + x, y = y_be_bottom + y, grvt_cover = params.grvt_cover })
					end
				end
			end
		end

		local x_be_right = x_blocks + block_size * size_bw + 10
		local y_be_right = y_blocks
		do -- right block emitter
			for by = 0, size_bh - 1 do
				for y = 0, block_size - 1 do
					for x = 0, block_size - 1 do
						part({ type = pt.CRMC, x = x_be_right + x, y = y_be_right + block_size * by + y, grvt_cover = params.grvt_cover })
					end
				end
			end
		end

		local x_block_spawner = x_blocks - block_size
		local y_block_spawner = y_blocks
		do -- block spawner
			spark_row(x_block_spawner -  7, y_block_spawner - 3, x_block_spawner - 1, y_block_spawner - 3, pt.INWR, block_size + 1, 3)
			spark({ type = pt.INWR, x = x_block_spawner - 1, y = y_block_spawner - 3 })

			spark_row(x_block_spawner + 96, y_block_spawner - 2, x_be_right, y_block_spawner - 2, pt.INWR, block_size, 3)
			for x = 0, block_size - 1 do
				spark({ type = pt.INWR, x = x_block_spawner + x, y = y_block_spawner - 3 })
				part ({ type = pt.CRMC, x = x_block_spawner + x, y = y_block_spawner - 1 })
				for y = 0, block_size - 1 do
					dray(x_block_spawner + x, y_block_spawner - 2, x_block_spawner + x, y_block_spawner + y, 1, false)
					part({ type = pt.CRMC, x = x_block_spawner + x, y = y_block_spawner + y, grvt_cover = params.grvt_cover })
				end
				dray(x_block_spawner + x, y_block_spawner - 2, x_block_spawner + x, y_be_bottom - 1, block_size + 1, false)
				cray(x_block_spawner + x, y_base - 8 + ((x % 2 == 0) and 3 or 0), x_block_spawner + x, y_be_bottom, pt.SPRK, block_size, pt.PSCN)
				cray(x_be_right + x, y_base - 8 + ((x % 2 == 0) and 3 or 0), x_be_right + x, y_block_spawner, pt.SPRK, size_bh * block_size, pt.PSCN)
				spark({ type = pt.INWR, x = x_be_right + x, y = y_block_spawner - 2, life = 3 })
				dray_log(x_be_right + x, y_block_spawner - 1, x_be_right + x, y_block_spawner + block_size, (size_bh - 1) * block_size, false)
			end

			do
				local x_apom = x_cmem + cmem_width + 12
				local y_apom_1 = y_block_spawner + 17
				local y_apom_2 = y_base + size_bh * block_size + 16
				for x = 0, block_size - 1 do
					part({ type = pt.HEAC, x = x_apom + x, y = y_block_spawner - 2 })
				end
				lsns_spark({ type = pt.PSCN, x = x_block_spawner - 4, y = y_block_spawner - 2, life = 3 }, 1, 0, 2, 1)
				local templ = cray(x_block_spawner - 3, y_block_spawner - 2, x_apom, y_block_spawner - 2, pt.HEAC, block_size, false)
				part({ type = pt.INSL, x = x_block_spawner - 3, y = y_block_spawner - 2 })
				part(mutate(templ, { x = x_block_spawner - 3, y = y_apom_1 - 1 }))
				cray(templ.x, y_apom_1, templ.x, templ.y, pt.INSL, 2, pt.PSCN)
				dray(x_block_spawner - 3, y_apom_1, x_block_spawner - 3, y_block_spawner - 2, 1, pt.PSCN)
				local source = part({ type = pt.STOR, x = x_block_spawner - 1, y = y_apom_1, z = 20000000 })
				cray(source.x - 6, source.y, source.x, source.y, pt.STOR, 1, pt.PSCN)
				cray(x_block_spawner - 1, y_apom_1, x_block_spawner - 1, y_block_spawner + block_size + - 1, pt.SPRK, block_size, pt.PSCN)
				dray(templ.x, y_apom_2, templ.x, templ.y, 1, pt.PSCN)
				cray(templ.x, y_apom_2, templ.x, templ.y - 1, pt.INSL, 1, pt.PSCN)
				cray(templ.x, y_apom_2, templ.x, templ.y, pt.INSL, 1, pt.PSCN)
				cray(source.x, y_apom_2, source.x, source.y, pt.STOR, 1, pt.PSCN)
			end

			dray(x_block_spawner - 1, y_block_spawner - 2, x_block_spawner - 1, y_block_spawner    , 1, false)
			dray(x_block_spawner - 1, y_block_spawner - 2, x_block_spawner - 1, y_block_spawner + 1, 2, false)
			dray(x_block_spawner - 1, y_block_spawner - 2, x_block_spawner - 1, y_block_spawner + 3, 4, false)
			dray(x_block_spawner - 1, y_block_spawner - 2, x_block_spawner - 1, y_block_spawner + 7, 1, false)
			part({ type = pt.DRAY, x = x_block_spawner - 1, y = y_block_spawner - 1, tmp = 8, tmp2 = size_bw * block_size + 10 })

			spark_row(x_block_spawner - 2, y_block_spawner - 16, x_block_spawner - 2, y_block_spawner, pt.INWR, block_size, 3)
			spark_row(x_block_spawner - 2, y_block_spawner - 16, x_block_spawner - 2, y_be_bottom, pt.INWR, block_size, 3)
			for y = 0, block_size - 1 do
				cray(x_block_spawner - 7 + ((y % 2 == 0) and 3 or 0), y_be_bottom + y, x_block_spawner + block_size, y_be_bottom + y, pt.SPRK, size_bw * block_size, pt.PSCN)
				spark({ type = pt.INWR, x = x_block_spawner - 2, y = y_be_bottom + y })
				dray_log(x_block_spawner - 1, y_be_bottom + y, x_block_spawner + block_size, y_be_bottom + y, size_bw * block_size, false)
			end
			for y = 0, block_size - 1 do
				spark({ type = pt.INWR, x = x_block_spawner - 2, y = y_block_spawner + y })
			end

			do
				local x_take = x_block_spawner
				local y_take = y_block_spawner + 10

				local function take_input(y_take_i, y_source_i, down_filt_mask, x_direct, y_direct, beam_size, spark_workaround)
					local sources = {
						[ 0 ] = part({ type = pt.FILT, x = x_take - 7, y = y_source_i + 1 }),
						[ 1 ] = part({ type = pt.FILT, x = x_take - 3, y = y_source_i + 1 }),
					}

					local ldtc_1 = part({ type = pt.LDTC, x = x_take - 7, y = sources[0].y - 1 })
					local ldtc_2 = part({ type = pt.LDTC, x = x_take - 3, y = sources[1].y - 1 })
					               part({ type = pt.DTEC, x = x_take - 6, y = sources[0].y + 1 })
					               part({ type = pt.DTEC, x = x_take - 4, y = sources[1].y + 1 })
					               part({ type = pt.INSL, x = x_take - 5, y = sources[0].y     })
					local direct = part({ type = pt.INSL, x = x_take - 4, y = sources[1].y     })
					dray(x_be_right - 2, direct.y, direct.x, direct.y, 2, pt.PSCN)

					for i = 0, 1 do
						local source = part({ type = pt.FILT, x = x_direct + i, y = y_base - 7, ctype = 0x10000001, unstack = true })
						local target_1 = { x = x_be_right - 4 + i, y = sources[i].y }
						cray(x_be_right - 4 + i, y_take + 10 - i, target_1.x, target_1.y, pt.SPRK, 1, pt.PSCN)
						if spark_workaround then
							part({ type = pt.LSNS, x = x_direct + i + 1, y = y_direct - 1, tmp = 3, tmp2 = 2 })
						end
						ldtc(x_direct + i, y_direct - 1, source.x, source.y)
						part({ type = pt.INSL, x = x_direct + i, y = y_direct - 1 })
						part({ type = pt.FILT, x = x_direct + i    , y = y_direct     })
						for j = 1, beam_size do
							if j == beam_size then
								part({ type = pt.INSL, x = x_direct + i - j, y = y_direct + j, unstack = true })
							else
								part({ type = pt.BRAY, x = x_direct + i - j, y = y_direct + j, life = 1 })
							end
						end
						local conductor = not spark_workaround and pt.METL or false
						aray(x_direct + i + 1, y_direct - 1, 1, -1, conductor, nil, 1)
						local y_target = y_direct + x_direct + i - target_1.x
						dray(x_direct + i + 1, y_direct - 1, target_1.x + 1, y_target - 1, 2, conductor)
						part({ type = pt.INSL, x = target_1.x + 1, y = y_target - 1, unstack = true })
						if spark_workaround then
							if i == 0 then
								part({ type = pt.CONV, x = x_direct + i + 1, y = y_direct - 1, tmp = pt.SPRK, ctype = pt.HEAC })
								part({ type = pt.HEAC, x = x_direct + i + 2, y = y_direct - 2 })
							else
								spark({ type = pt.METL, x = x_direct + i + 2, y = y_direct - 2, life = 3 })
							end
						end
					end

					part({ type = pt.FILT, x = x_take - 9, y = ldtc_1.y - 1 })
					part({ type = pt.LSNS, x = x_take - 9, y = ldtc_1.y, tmp = 3 })
					cray(x_take - 8, ldtc_1.y, ldtc_1.x, ldtc_1.y, pt.LDTC, 2, false)
					cray(x_take - 8, ldtc_1.y, ldtc_1.x, ldtc_1.y, pt.LDTC, 2, false)
					solid_spark(x_take - 9, ldtc_1.y + 1, 0, -1, pt.PSCN)
					part({ type = pt.FILT, x = x_take - 6, y = ldtc_1.y })
					part({ type = pt.FILT, x = x_take - 5, y = ldtc_1.y })
					part({ type = pt.FILT, x = x_take - 4, y = ldtc_1.y })

					ldtc(x_take - 7, y_take_i - 1, sources[0].x, sources[0].y)
					part({ type = pt.FILT, x = x_take - 7, y = y_take_i, ctype = 0x1000DEAD })
					part({ type = pt.FILT, x = x_take - 1, y = y_take_i })
					part({ type = pt.HEAC, x = x_take - 2, y = y_take_i })
					part({ type = pt.CONV, x = x_take - 3, y = y_take_i, tmp = pt.FILT, ctype = pt.HEAC })
					part({ type = pt.CONV, x = x_take - 3, y = y_take_i, tmp = down_filt_mask, ctype = bitx.bor(pt.FILT, bitx.lshift(6, sim.PMAPBITS)) })
					ldtc(x_take - 3, y_take_i, sources[1].x, sources[1].y)
					part({ type = pt.HEAC, x = x_take - 3, y = y_take_i })
					part({ type = pt.HEAC, x = x_take - 4, y = y_take_i })
					cray(x_take - 8, y_take_i, x_take - 4, y_take_i, pt.FILT, 3, pt.PSCN)
					cray(x_take - 8, y_take_i, x_take - 4, y_take_i, pt.FILT, 3, pt.PSCN)
					part({ type = pt.LDTC, x = x_take - 5, y = y_take_i })
					part({ type = pt.FILT, x = x_take - 1, y = y_take_i + 1 })
					part({ type = pt.ARAY, x = x_take - 2, y = y_take_i + 1 })
					part({ type = down_filt_mask, x = x_take - 3, y = y_take_i + 1 })
					dray(x_take - 4, y_take_i + 1, x_take - 2, y_take_i + 1, 1, pt.PSCN)
					dray(x_take - 4, y_take_i + 1, x_take - 1, y_take_i + 1, 2, pt.PSCN)
					dray(x_take - 4, y_take_i + 1, x_take + 1, y_take_i + 1, 4, pt.PSCN)
					dray(x_take - 4, y_take_i + 1, x_take + 5, y_take_i + 1, 3, pt.PSCN)
					part({ type = pt.CONV, x = x_take - 4, y = y_take_i + 1, tmp = pt.FILT, ctype = pt.ARAY })
					dray(x_take - 4, y_take_i + 1, x_take - 2, y_take_i + 1, 1, pt.PSCN)
					part({ type = pt.CONV, x = x_take - 4, y = y_take_i + 1, tmp = pt.ARAY, ctype = down_filt_mask })
				end
				part({ type = pt.LDTC, x = x_take - 9, y = y_take - 7, life = 2 })
				take_input(y_take    , y_take - 9, pt.INSL, x_be_right + 6, y_take - 18, 2, false)
				take_input(y_take + 2, y_take - 5, pt.SWCH, x_be_right + 3, y_take - 21, 4, true)
				part({ type = pt.FILT, x = x_be_right + 6, y = y_take - 21, ctype = 0x10000003 })
				part({ type = pt.CONV, x = x_be_right + 6, y = y_take - 24, tmp = pt.HEAC, ctype = pt.METL })
				part({ type = pt.CONV, x = x_be_right + 6, y = y_take - 24, tmp = pt.METL, ctype = pt.SPRK })

				do
					local source_2 = part({ type = pt.FILT, x = x_take + 7, y = y_take - 26, ctype = bitx.bor(0x10000000, 8) })
					ldtc(x_take + 5, y_take - 24, source_2.x, source_2.y)
					local source_3 = part({ type = pt.FILT, x = x_take + 4, y = y_take - 23 })
					ldtc(x_take - 8, source_3.y, source_3.x, source_3.y)
					local source = part({ type = pt.FILT, x = x_take - 9, y = source_3.y })
					ldtc(source.x, y_take - 11, source.x, source.y)
				end

				do
					local y_forward = y_take - 16
					spark({ type = pt.INWR, x = x_be_right - 4, y = y_forward })
					spark({ type = pt.INWR, x = x_be_right - 3, y = y_forward })
					spark_row(x_be_right, y_forward, x_be_right - 3, y_forward, pt.INWR, 2, 3, 8)
					dray(x_be_right - 4, y_forward + 1, x_be_right - 4, y_take - 4, 1, false)
					dray(x_be_right - 3, y_forward + 1, x_be_right - 3, y_take - 4, 1, false)
					part ({ type = pt.BRAY, x = x_be_right - 4, y = y_forward + 2, life = 1 })
					part ({ type = pt.BRAY, x = x_be_right - 3, y = y_forward + 2, life = 1 })
				end
				do
					local y_condition = y_take - 9
					local templ = part({ type = pt.CONV, x = x_be_right - 4, y = y_condition - 9, tmp = pt.BRAY, ctype = pt.INSL })
					local cond_1 = part({ type = pt.INSL, x = templ.x, y = y_condition     })
					local cond_2 = part({ type = pt.INSL, x = templ.x, y = y_condition + 4 })
					local source = part({ type = pt.FILT, x = templ.x + 6, y = templ.y - 10, ctype = 0x10000000, unstack = true })
					ldtc(templ.x - 1, templ.y - 3, source.x, source.y)
					part({ type = pt.FILT, x = templ.x - 2, y = templ.y - 2 })
					part({ type = pt.FILT, x = templ.x - 5, y = templ.y - 1, ctype = 0x10000003 })
					part({ type = pt.FILT, x = templ.x - 4, y = templ.y - 1, ctype = 1 })
					part({ type = pt.FILT, x = templ.x - 3, y = templ.y - 1, tmp = 1 })
					part({ type = pt.FILT, x = templ.x - 2, y = templ.y - 1, ctype = 0x10000004 })
					ldtc(templ.x, templ.y - 1, templ.x - 5, templ.y - 1, nil, 1)
					ldtc(templ.x, templ.y - 1, templ.x - 1, templ.y - 1, nil, 1)
					aray(templ.x - 6, templ.y - 1, -1, 0, pt.METL)
					dray(templ.x + 3, templ.y - 1, templ.x - 1, templ.y - 1, 1, pt.PSCN)
					lsns_spark({ type = pt.PSCN, x = templ.x, y = templ.y - 2, life = 3 }, 0, 1, 1, 1)
					dray(templ.x, templ.y - 1, cond_1.x, cond_1.y, 1, false)
					dray(templ.x, templ.y - 1, cond_2.x, cond_2.y, 1, false)
					cray(cond_1.x, y_condition + 19, cond_1.x, cond_1.y, pt.INSL, 1, pt.PSCN)
					cray(cond_1.x, y_condition + 19, cond_1.x, cond_1.y, pt.INSL, 1, pt.PSCN)
					cray(cond_2.x, y_condition + 19, cond_2.x, cond_2.y, pt.INSL, 1, pt.PSCN)
					cray(cond_2.x, y_condition + 19, cond_2.x, cond_2.y, pt.INSL, 1, pt.PSCN)
				end
			end

			local y_stack = y_block_spawner + 16
			for x = 0, block_size - 1 do
				local x_stack = x_block_spawner + x

				local spark_mask_type = (x % 2 == 0) and pt.CRMC or pt.HEAC
				local filt_mask_type  = (x % 2 == 0) and pt.ARAY or pt.SWCH

				part({ type = pt.FILT, x = x_stack, y = y_stack - 8, tmp = 6 })
				part({ type = pt.FILT, x = x_stack, y = y_stack - 7, tmp = 6, ctype = 0x10000003 })

				local data = {}
				data[0] = part({ type = pt.FILT, x = x_stack, y = y_stack - 6, tmp = (x == 0) and 6 or 1 })
				data[2] = part({ type = pt.FILT, x = x_stack, y = y_stack - 5, tmp = 6 })
				data[1] = part({ type = pt.FILT, x = x_stack, y = y_stack - 4, tmp = 6 })
				data[3] = part({ type = pt.FILT, x = x_stack, y = y_stack - 3, tmp = 6 })

				part({ type = pt.FILT, x = x_stack, y = y_stack + 2 })
				local lsns_life = part({ type = pt.BRAY, x = x_stack, y = y_stack + 3, ctype = 0x10000003, life = 1000 })

				part({ type = pt.STOR, x = x_stack, y = y_stack - 2 })

				local bit_filts = {}
				for y = 0, 3 do
					local ctype = bitx.lshift(1, y * 8 + x)
					if x >= 6 then
						ctype = bitx.bor(1, ctype)
					end
					bit_filts[y] = part({ type = pt.FILT, x = x_stack, y = lsns_life.y + 1 + y, ctype = ctype })
				end

				local function change_conductor(conductor, from)
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = conductor, tmp = from or pt.SPRK })
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.SPRK, tmp = conductor })
					part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3 })
				end

				part({ type = filt_mask_type, x = x_stack, y = y_stack - 1 })
				part({ type = spark_mask_type, x = x_stack, y = y_stack + 1 })

				local function swap_data(from, to)
					part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.FILT, ctype = pt.INSL })
					part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = pt.FILT })
					ldtc(x_stack, y_stack, x_stack, y_stack - 6 + from)
					part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.FILT, ctype = pt.PSCN })
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.SPRK, tmp = pt.PSCN })
					part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.INSL, ctype = bitx.bor(pt.FILT, bitx.lshift(1, sim.PMAPBITS)) })
					ldtc(x_stack, y_stack, lsns_life.x, lsns_life.y)
					part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3 })
					ldtc(x_stack, y_stack, x_stack, y_stack + 2)
					dray(x_stack, y_stack, x_stack, y_stack - 6 + to, 1, false)
					part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.FILT, ctype = pt.INSL })
					part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.INSL, ctype = pt.FILT })
					ldtc(x_stack, y_stack, lsns_life.x, lsns_life.y)
				end
				local function emit_half(y_off)
					local y = bitx.band(y_off, 3)
					change_conductor(pt.METL)
					ldtc(x_stack, y_stack, bit_filts[y].x, bit_filts[y].y)
					part({ type = pt.ARAY, x = x_stack, y = y_stack, life = 1 })
					dray(x_stack, y_stack, x_stack, y_block_spawner + y_off + 1, 2, false)
					ldtc(x_stack, y_stack, lsns_life.x, lsns_life.y)
					change_conductor(pt.PSCN)
					if y_off < 7 then
						cray(x_stack, y_stack, x_stack, y_block_spawner + y_off + 1, pt.SPRK, 1, false)
					end
				end
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = filt_mask_type, ctype = pt.FILT })
				ldtc(x_stack, y_stack, lsns_life.x, lsns_life.y)
				change_conductor(pt.PSCN, spark_mask_type)
				if x >= 6 then
					part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.FILT, ctype = pt.INSL })
					          dray(x_stack, y_stack, x_stack, y_stack - 8, 1, false)
					          cray(x_stack, y_stack, x_stack, y_stack - 8, pt.SPRK, 1, false)
					local p = cray(x_stack, y_stack, x_stack, y_stack - 8, bitx.bor(pt.FILT, bitx.lshift(5, sim.PMAPBITS)), 1, false)
					p.temp = 273.15 + 100
					part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.INSL, ctype = pt.FILT })
					ldtc(x_stack, y_stack, lsns_life.x, lsns_life.y)
				end

				cray(x_stack, y_stack, x_stack, y_block_spawner + block_size - 1, pt.SPRK, block_size, false)
				cray(x_stack, y_stack, x_stack, y_block_spawner + block_size - 1, pt.STOR, block_size - 1, false)

				if x == 0 then
					swap_data(1, 1)
					emit_half(0)
					swap_data(0, 1)
					emit_half(1)
					emit_half(2)
					emit_half(3)
					swap_data(3, 1)
					emit_half(4)
					swap_data(2, 1)
					emit_half(5)
					emit_half(6)
					emit_half(7)
				else
					emit_half(0)
					emit_half(1)
					emit_half(2)
					emit_half(3)
					swap_data(2, 0)
					emit_half(4)
					emit_half(5)
					emit_half(6)
					emit_half(7)
				end

				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = spark_mask_type })
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.FILT, ctype = filt_mask_type })
			end

			aray(x_block_spawner - 5, y_stack + 3, -1, 0, pt.INST, nil, 1000)
			for i = 1, 4 do
				part({ type = pt.FILT, x = x_block_spawner - i, y = y_stack + 3, unstack = true })
			end
		end

		local x_bank       = x_base - 12
		local y_bank       = y_base - 3
		local x_bank_right = x_be_right + block_size
		do -- fg/bg/delivery banks
			local max_dim = math.max(size_bw, size_bh)
			local min_dim = math.min(size_bw, size_bh)
			local dim_diff = max_dim - min_dim
			local wider_than_tall = size_bw > size_bh
			local max_arm_lengths = {
				2 * (max_dim - 1) + 26 + 2 * max_dim,
				2 * (max_dim - 1) + 29,
				14 + 15,
				15,
			}
			local max_arm_length_index = 0
			local extends = {
				1, 2, 4, 8,
				"skip",
				-15,
				14,
				1, 2, 4, 8,
				"skip",
				{ -15, 2 },
				29,
				dim_diff * 2,
				2, 4, 8, 16, 32,
				"skip",
				{ -31, 3 },
				{ 13 + max_dim, 2 },
				dim_diff * 2,
				2, 4, 8, 16, 32,
				"skip0",
				{ -26, 6 },
			}
			local cumulative = 0
			local head_source = {}
			for i = #extends, 1, -1 do
				local want = extends[i]
				local extend = 0
				local amount = 1
				local spark_type
				local use_as_source = false
				if want == "skip" then
					use_as_source = true
				else
					if want == "skip0" then
						want = 0
						use_as_source = true
					else
						spark_type = pt.PSCN
					end
					if type(want) == "table" then
						amount = want[2]
						want = want[1]
					end
					if want < 0 then
						want = -want
						spark_type = pt.NSCN
						max_arm_length_index = max_arm_length_index + 1
					end
					extend = want - cumulative
					cumulative = want
				end
				if spark_type then
					spark({ type = spark_type, x = x_bank + i - 1, y = y_bank - 1, life = 3 })
				else
					part({ type = pt.FILT, x = x_bank + i - 1, y = y_bank - 1 })
				end
				for j = 1, amount do
					local p = part({ type = pt.PSTN, x = x_bank + i - 1, y = y_bank, extend = extend, tmp2 = max_arm_lengths[max_arm_length_index] })
					if use_as_source then
						table.insert(head_source, 1, p)
					end
				end
			end
			part({ type = pt.CONV, x = x_bank - 1, y = y_bank, tmp = pt.DRAY, ctype = pt.INSL })
			do
				local target = part({ type = pt.DRAY, x = x_bank - 1, y = y_bank, tmp = 1 })
				local source = part({ type = pt.DRAY, x = x_bank_right - 1, y = y_bank, tmp = 1 })
				dray(source.x + 1, source.y, target.x, target.y, 1, pt.PSCN)
			end

			local x_head = x_bank + #extends
			part ({ type = pt.PSTN, x = x_head    , y = y_bank    , extend = 1 })
			part ({ type = pt.DMND, x = x_head    , y = y_bank - 1 })
			part ({ type = pt.FRME, x = x_head + 1, y = y_bank - 1 })
			part ({ type = pt.FRME, x = x_head + 1, y = y_bank     })
			spark({ type = pt.PSCN, x = x_head + 2, y = y_bank - 1 })
			part ({ type = pt.FILT, x = x_head + 3, y = y_bank - 1 })
			part ({ type = pt.FILT, x = x_head + 3, y = y_bank     })
			spark({ type = pt.PSCN, x = x_head + 4, y = y_bank - 1 })
			part ({ type = pt.FILT, x = x_head + 5, y = y_bank - 1 })
			part ({ type = pt.FILT, x = x_head + 5, y = y_bank     })
			part ({ type = pt.FILT, x = x_head + 6, y = y_bank - 1 })
			part ({ type = pt.FILT, x = x_head + 6, y = y_bank     })
			spark({ type = pt.PSCN, x = x_head + 7, y = y_bank - 1 })
			spark({ type = pt.PSCN, x = x_head + 8, y = y_bank - 1 })
			part ({ type = pt.FILT, x = x_head + 8, y = y_bank     })
			spark({ type = pt.PSCN, x = x_head + 9, y = y_bank - 1 })
			local head_active = part({ type = pt.CRMC, x = x_head + 2, y = y_bank })
			                    part({ type = pt.CRMC, x = x_head + 4, y = y_bank })
			                    part({ type = pt.CRMC, x = x_head + 7, y = y_bank })
			                    part({ type = pt.CRMC, x = x_head + 9, y = y_bank })

			local x_stack = x_bank - 6
			local y_stack = y_bank - 1

			local bit_filt  = part({ type = pt.FILT, x = x_stack - 2, y = y_stack, ctype = 0x100000 })
			part ({ type = pt.FILT, x = x_stack + 2, y = y_stack - 1, ctype = 0x10000003 })
			part ({ type = pt.LSNS, x = x_stack + 1, y = y_stack - 1, tmp = 3 })
			spark({ type = pt.PSCN, x = x_stack - 1, y = y_stack })
			part ({ type = pt.FILT, x = x_stack + 1, y = y_stack })
			part ({ type = pt.FILT, x = x_stack + 3, y = y_stack, tmp = 11, ctype = 2 })
			spark({ type = pt.PSCN, x = x_stack + 2, y = y_stack })
			part ({ type = pt.FILT, x = x_stack + 5, y = y_stack, tmp = 3 })

			local function change_conductor(conductor, from)
				part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = conductor, tmp = from or pt.SPRK })
				part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.SPRK, tmp = conductor })
				part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3, tmp2 = 2 })
			end

			part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 27, tmp2 =  5, ctype = pt.SPRK })
			part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 27, tmp2 =  5, ctype = pt.STOR })

			ldtc(x_stack, y_stack, bit_filt.x, bit_filt.y)
			local spark_offset = 32
			local function handle_bits(amount, cond_invert_last)
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = spark_offset + 1, ctype = pt.STOR })
				for i = 0, amount - 1 do
					change_conductor(pt.INST)
					part({ type = pt.ARAY, x = x_stack, y = y_stack, life = 1000 })
					if cond_invert_last and i == amount - 1 then
						change_conductor(pt.PSCN)
						part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = spark_offset - i + 1, ctype = pt.STOR })
						change_conductor(pt.INST)
					end
					part({ type = pt.DRAY, x = x_stack, y = y_stack, tmp = 2, tmp2 = spark_offset - 2 - i })
					change_conductor(pt.PSCN)
					part({ type = pt.DTEC, x = x_stack, y = y_stack, tmp2 = 4 })
					if i < amount - 1 then
						part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = spark_offset - i, ctype = pt.SPRK })
					end
					part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 3, ctype = pt.SPRK })
				end
				spark_offset = spark_offset - amount - 3
			end
			handle_bits(6, wider_than_tall)
			handle_bits(6, wider_than_tall)
			handle_bits(4, false)
			handle_bits(4, false)
			local sparks = {
				{ type = pt.NSCN, x = x_bank +  5 },
				{ type = pt.PSCN, x = x_bank +  6 },
				{ type = pt.NSCN, x = x_bank + 12 },
				{ type = pt.PSCN, x = x_bank + 13 },
				{ type = pt.NSCN, x = x_bank + 21 },
				{ type = pt.PSCN, x = x_bank + 22 },
				{ type = pt.NSCN, x = x_bank + 30 },
				{ type = pt.PSCN, x = x_bank + 33 },
				{ type = pt.PSCN, x = x_bank + 35 },
				{ type = pt.PSCN, x = x_bank + 38 },
				{ type = pt.PSCN, x = x_bank + 39 },
				{ type = pt.PSCN, x = x_bank + 40 },
			}
			for _, p in ipairs(sparks) do
				cray(x_stack, y_stack, p.x, y_stack, p.type, 1, false)
				cray(x_stack, y_stack, p.x, y_stack, p.type, 1, false)
			end
			change_conductor(pt.INWR)
			part({ type = pt.CRAY, x = x_stack, y = y_stack, ctype = pt.SPRK, tmp = #sparks, life = 3 })
			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = pt.PSCN })
			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.PSCN, ctype = pt.SPRK })

			local x_next_part = x_bank + 33
			local y_next_part = y_bank + 1
			local function to_bank(p)
				part(mutate(p, { x = x_next_part, y = y_next_part }))
				x_next_part = x_next_part + 1
			end
			for i = 0, 15 do
				to_bank({ type = pt.CRMC, dcolour = 0xFF000000 + colors[i] })
			end
			for i = 0, 15 do
				to_bank({ type = pt.STOR, dcolour = 0xFF000000 + colors[i] })
			end
			x_next_part = x_next_part + 1
			for i = 0, max_dim - 1 do
				to_bank({ type = pt.DRAY, tmp = 8,    tmp2 = (max_dim - 1 - i) * block_size + 10 })
				to_bank({ type = pt.PSTN, extend = 0, tmp  = (max_dim - 1 - i) * block_size +  6 })
			end
			for i = 0, max_dim - 1 do
				to_bank({ type = pt.CRAY, ctype = pt.SPRK, tmp = 8, tmp2 = (max_dim - 1 - i) * block_size     })
				to_bank({ type = pt.CRAY, ctype = pt.SPRK, tmp = 8, tmp2 = (max_dim - 1 - i) * block_size + 3 })
			end

			part({ type = pt.CRAY, x = x_bank - 2, y = y_bank, ctype = pt.PSTN, tmp = 1, tmp2 = 1, temp = piston_extend(-1) })
			part({ type = pt.CRAY, x = x_bank - 2, y = y_bank, ctype = pt.PSTN, tmp = 1, tmp2 = 1, temp = piston_extend(-1) })

			cray(x_bank - 2, y_bank, head_active.x, head_active.y, pt.SPRK, 4, pt.PSCN)
			for i = #head_source, 1, -1 do
				cray(x_bank - 2, y_bank, head_source[i].x, head_source[i].y, pt.SPRK, 1, pt.PSCN)
			end
			dray(x_bank - 2, y_bank, head_active.x + 0, head_active.y, 1, pt.PSCN)
			dray(x_bank - 2, y_bank, head_active.x + 2, head_active.y, 1, pt.PSCN)
			dray(x_bank - 2, y_bank, head_active.x + 5, head_active.y, 1, pt.PSCN)
			dray(x_bank - 2, y_bank, head_active.x + 7, head_active.y, 1, pt.PSCN)
			for i = 1, #head_source do
				local p = cray(x_bank - 2, y_bank, head_source[i].x, head_source[i].y, pt.PSTN, 1, pt.PSCN)
				p.temp = piston_extend(head_source[i].extend)
			end
			cray(x_bank_right, y_bank, head_active.x + 7, head_active.y, pt.SPRK, 4, pt.PSCN)
			for i = #head_source, 1, -1 do
				cray(x_bank_right, y_bank, head_source[i].x, head_source[i].y, pt.SPRK, 1, pt.PSCN)
			end
			cray(x_bank_right, y_bank, head_active.x + 7, head_active.y, pt.CRMC, 4, pt.PSCN)
			for i = 1, #head_source do
				local q = cray(x_bank_right, y_bank, head_source[i].x, head_source[i].y, pt.PSTN, 1, pt.PSCN)
				q.temp = piston_extend(head_source[i].extend)
			end

			table.insert(sparks_under_banks, spark({ type = pt.PSCN, x = x_bank + 20, y = y_bank + 1 }))
			table.insert(sparks_under_banks, spark({ type = pt.NSCN, x = x_bank + 21, y = y_bank + 1 }))
			part({ type = pt.PSTN, x = x_bank + 20, y = y_bank + 2, extend = math.huge })
			part({ type = pt.PSTN, x = x_bank + 21, y = y_bank + 2, extend = math.huge })
			part({ type = pt.PSTN, x = x_bank + 22, y = y_bank + 2, extend = math.huge })
			part({ type = pt.FRME, x = x_bank + 23, y = y_bank + 2, tmp = 1 })

			dray(x_bank + 12, y_bank + 2, x_bank_right - 10, y_bank + 2, 4, false)
			do
				local p = spark({ type = pt.PSCN, x = x_bank + 11, y = y_bank + 2, life = 3 })
				spark_row(x_bank - 3, y_bank + 2, p.x, p.y, p.ctype, 1, p.life)
			end

			table.sort(sparks_under_banks, function(lhs, rhs)
				return lhs.x > rhs.x
			end)
			for _, p in ipairs(sparks_under_banks) do
				p.life = 3
				cray(x_bank + 28, p.y, p.x, p.y, p.ctype, 1, pt.PSCN)
				cray(x_bank + 28, p.y, p.x, p.y, p.ctype, 1, pt.PSCN)
			end
			local first = sparks_under_banks[1]
			cray(x_bank + 31, first.y, first.x, first.y, pt.SPRK, #sparks_under_banks, pt.INWR, nil, 3)
		end

		local bank_target_dray_1
		local bank_target_dray_2
		local bank_target_cray_1
		local bank_target_cray_2
		local bank_target_cray_3
		local bank_target_cray_4
		local bank_target_pstn

		local x_bd_right = x_blocks + block_size * size_bw
		local y_bd_right = y_blocks
		do -- right block delivery
			local y_frame_hack = y_bd_right + block_size * size_bh + 9
			local y_end = y_bd_right + block_size * size_bh
			part({ type = pt.HEAC, x = x_bd_right + 5, y = y_frame_hack - 1, z = 2000 })
			part({ type = pt.HEAC, x = x_bd_right + 5, y = y_frame_hack - 2, z = 2000 })
			part({ type = pt.FRME, x = x_bd_right + 5, y = y_frame_hack - 3, z = 2000 })
			for by = 0, size_bh - 2 do
				local byy = y_bd_right + block_size * by
				dray(x_bd_right + 5, y_frame_hack, x_bd_right + 5, byy + 9, 3, pt.PSCN)
			end

			dray(x_bd_right, y_bd_right - 3, x_bd_right, y_bd_right - 1, 1, pt.PSCN)
			                     part({ type = pt.CONV, x = x_bd_right + 2, y = y_end - 1, tmp = pt.SPRK, ctype = pt.CRMC })
			bank_target_cray_3 = part({ type = pt.CRAY, x = x_bd_right    , y = y_end     })
			bank_target_cray_4 = part({ type = pt.CRAY, x = x_bd_right + 3, y = y_end + 3 })
			dray(x_bd_right + 3, y_bd_right - 5, bank_target_cray_4.x, bank_target_cray_4.y, 1, pt.PSCN)
			dray(x_bd_right    , y_bd_right - 3, bank_target_cray_3.x, bank_target_cray_3.y, 1, pt.PSCN)
			dray_log(x_bd_right + 3, y_bd_right - 5, x_bd_right + 3, y_bd_right - 2, size_bh * block_size + 2, pt.PSCN)
			part({ type = pt.CONV, x = x_bd_right, y = y_bd_right - 3, tmp = pt.CRAY, ctype = pt.FILT })
			dray_log(x_bd_right, y_bd_right - 3, x_bd_right, y_bd_right, size_bh * block_size, pt.PSCN)
			bank_target_cray_1 = part({ type = pt.CRAY, x = x_bd_right    , y = y_bd_right - 2 })
			                     part({ type = pt.FILT, x = x_bd_right    , y = y_bd_right - 1 })
			                     part({ type = pt.INSL, x = x_bd_right + 1, y = y_bd_right - 1 })
			bank_target_cray_2 = part({ type = pt.CRAY, x = x_bd_right + 3, y = y_bd_right - 4 })
			                     part({ type = pt.FILT, x = x_bd_right + 3, y = y_bd_right - 3 })
			                     part({ type = pt.FILT, x = x_bd_right + 3, y = y_bd_right - 2 })
			                     part({ type = pt.FILT, x = x_bd_right + 3, y = y_bd_right - 1 })
			                     part({ type = pt.INSL, x = x_bd_right + 4, y = y_bd_right - 1 })
			for by = 0, size_bh - 1 do
				local byy = y_bd_right + block_size * by
				for y = 0, block_size - 1 do
					local yy = byy + y
					for x = 0, 4 do
						part({ type = pt.FILT, x = x_bd_right + x, y = yy, unstack = true })
					end
					local x_off = (block_size * by + y + 1) % 2 * 3
					part({ type = pt.CRAY, x = x_bd_right + x_off    , y = yy })
					part({ type = pt.STOR, x = x_bd_right + x_off + 1, y = yy })
					part({ type = (by == 0 or y >= 2) and pt.FRME or pt.HEAC, x = x_bd_right + 5, y = yy })
				end
				part ({ type = pt.PSTN, x = x_bd_right + 6, y = byy +  7 })
				part ({ type = pt.PSTN, x = x_bd_right + 7, y = byy +  7, ctype = pt.DMND, extend = 9 })
				part ({ type = pt.PSTN, x = x_bd_right + 8, y = byy +  7, ctype = pt.DMND, tmp = (size_bw - 1) * block_size + 6 })
				part ({ type = pt.PSTN, x = x_bd_right + 9, y = byy +  7                 , tmp = (size_bw - 1) * block_size + 6 })
				if by < size_bh - 1 then
					part ({ type = pt.CONV, x = x_bd_right + 6, y = byy +  8, tmp = pt.FRME, ctype = pt.CRMC })
					part ({ type = pt.CONV, x = x_bd_right + 6, y = byy +  8, tmp = pt.HEAC, ctype = pt.FRME })
				end
				part ({ type = pt.CONV, x = x_bd_right + 7, y = byy +  8, z = 2000, tmp = pt.SPRK, ctype = pt.PSCN })
				part ({ type = pt.CONV, x = x_bd_right + 8, y = byy +  8, z = 2000, tmp = pt.SPRK, ctype = pt.NSCN })
				spark({ type = pt.PSCN, x = x_bd_right + 8, y = byy +  8, z = 2001 })
				spark({ type = pt.NSCN, x = x_bd_right + 9, y = byy +  8, z = 2001 })
				part ({ type = pt.BTRY, x = x_bd_right + 9, y = byy + 10 })
			end

			local x_copy = x_bd_right + 18
			for y = 0, size_bh * block_size - 1 do
				part ({ type = pt.INSL, x = x_copy    , y = y_bd_right + y + 7 })
				spark({ type = pt.INWR, x = x_copy + 1, y = y_bd_right + y     })
			end
			do
				cray(x_copy + 1, y_end + 10, x_copy + 1, y_end - 1, pt.INWR, size_bh * block_size, pt.PSCN)
				cray(x_copy + 1, y_end + 10, x_copy + 1, y_end - 1, pt.INWR, size_bh * block_size, pt.PSCN)
				cray(x_copy + 1, y_end + 14, x_copy + 1, y_end - 1, pt.SPRK, size_bh * block_size, false, nil, 4)
				solid_spark(x_copy + 1, y_end + 16, 0, -1, pt.INWR)
				local source = part({ type = pt.FILT, x = x_copy, y = y_base - 7, ctype = 0x10000003, unstack = true })
				ldtc(source.x, y_end + 11, source.x, source.y)
				part({ type = pt.FILT, x = source.x, y = y_end + 12 })
				part({ type = pt.LSNS, x = source.x, y = y_end + 13, tmp = 3 })
				cray(x_copy, y_end + 7, x_copy, y_end - 1, pt.INSL, size_bh * block_size, pt.PSCN)
				cray(x_copy, y_end + 7, x_copy, y_end - 1, pt.INSL, size_bh * block_size, pt.PSCN)
				cray(x_copy, y_end + 7, x_copy, y_end - 1, pt.INSL, size_bh * block_size, pt.PSCN)
				cray(x_copy, y_end + 7, x_copy, y_end + 6, pt.INSL, size_bh * block_size, pt.PSCN)
			end
			cray(x_copy, y_bd_right - 3, x_copy, y_bd_right + 7, pt.INSL, size_bh * block_size, pt.PSCN)
			cray(x_copy, y_bd_right - 3, x_copy, y_bd_right + 7, pt.INSL, size_bh * block_size, pt.PSCN)
			cray(x_copy, y_bd_right - 3, x_copy, y_bd_right + 7, pt.INSL, size_bh * block_size, pt.PSCN)
			bank_target_dray_1 = part({ type = pt.DRAY, x = x_copy, y = y_bd_right - 2, tmp = 8, tmp2 = (size_bw - 1) * block_size + 10 })
			part({ type = pt.INSL, x = x_copy, y = y_bd_right - 1 })
			dray_log(x_copy, y_bd_right - 3, x_copy, y_bd_right - 1, size_bh * block_size + 1, pt.PSCN)
			part({ type = pt.CONV, x = x_copy, y = y_bd_right - 3, tmp = pt.DRAY, ctype = pt.INSL })
			dray(x_copy, y_bd_right - 3, x_copy, y_bd_right - 1, 1, pt.PSCN)
		end

		local x_bd_bottom = x_blocks
		local y_bd_bottom = y_blocks + block_size * size_bh
		do -- bottom block delivery
			local x_frame_hack = x_bd_bottom + block_size * size_bw + 7
			part({ type = pt.HEAC, x = x_frame_hack - 1, y = y_bd_bottom + 5 })
			part({ type = pt.FRME, x = x_frame_hack - 2, y = y_bd_bottom + 5 })
			for bx = 0, size_bw - 2 do
				local bxx = x_bd_bottom + block_size * bx
				dray(x_frame_hack, y_bd_bottom + 5, bxx + 8, y_bd_bottom + 5, 2, pt.PSCN)
			end

			for bx = 0, size_bw - 1 do
				local bxx = x_bd_bottom + block_size * bx
				for x = 0, block_size - 1 do
					local xx = bxx + x
					for y = 0, 4 do
						part({ type = pt.FILT, x = xx, y = y_bd_bottom + y, unstack = true })
					end
					local y_off = (block_size * bx + x) % 2 * 3
					if bx > 0 or x > 0 then
						part({ type = pt.CRAY, x = xx, y = y_bd_bottom + y_off     })
					end
					part({ type = pt.STOR, x = xx, y = y_bd_bottom + y_off + 1 })
					part({ type = (bx == size_bw - 1 or x < 7) and pt.FRME or pt.HEAC, x = xx, y = y_bd_bottom + 5, z = 2000 })
				end
				part ({ type = pt.PSTN, x = bxx + 7, y = y_bd_bottom + 6 })
				part ({ type = pt.PSTN, x = bxx + 7, y = y_bd_bottom + 7, ctype = pt.DMND, extend = 9 })
				part ({ type = pt.PSTN, x = bxx + 7, y = y_bd_bottom + 8, ctype = pt.DMND, tmp = (size_bh - 1) * block_size + 6 })
				solid_spark(bxx + 7, y_bd_bottom + 8, 1, 0, pt.PSCN, true)
				part ({ type = pt.PSTN, x = bxx + 7, y = y_bd_bottom + 8                 , tmp = (size_bh - 1) * block_size + 6 })
				part ({ type = pt.INSL, x = bxx + 7, y = y_bd_bottom + 9 })
				solid_spark(bxx + 6, y_bd_bottom + 9, -1, -1, pt.NSCN)
				if bx < size_bw - 1 then
					cray(bxx + 10, y_bd_bottom + 8, bxx + 7, y_bd_bottom + 5, pt.HEAC, 1, pt.PSCN)
					cray(bxx + 10, y_bd_bottom + 8, bxx + 7, y_bd_bottom + 5, pt.HEAC, 1, pt.PSCN)
					cray(bxx + 11, y_bd_bottom + 8, bxx + 8, y_bd_bottom + 5, pt.FRME, 1, pt.PSCN)
					cray(bxx + 11, y_bd_bottom + 8, bxx + 8, y_bd_bottom + 5, pt.FRME, 1, pt.PSCN)
				end
			end

			local y_end = y_bd_bottom + 18
			do
				local x_end = x_bd_bottom + block_size * size_bw + 14
				local x_copy = x_bd_right + 18
				for x = 0, size_bw * block_size - 1 do
					part ({ type = pt.INSL, x = x_bd_bottom + x, y = y_end     })
					spark({ type = pt.INWR, x = x_bd_bottom + x, y = y_end + 1 })
				end
				bank_target_dray_2 = part({ type = pt.HEAC, x = x_end - 1, y = y_end })
				bank_target_pstn = part({ type = pt.HEAC, x = x_end - 5, y = y_end - 10 })
				local function apom(x_init, x_reset, input, target, strategy)
					local source = part({ type = pt.STOR, x = x_init, y = target.y })
					local p = dray(input.x + 1, target.y, target.x, target.y, 1, false, 2000)
					cray(source.x - 2, p.y, source.x, source.y, pt.SPRK, 1, pt.PSCN)
					dray(source.x - 2, p.y, p.x, p.y, 1, pt.PSCN)
					cray(x_reset, p.y, p.x, p.y, pt.STOR, 1, pt.PSCN)
					cray(x_reset, p.y, source.x, source.y, pt.STOR, 1, pt.PSCN)
					p.x = source.x - 1
					if strategy == "solid_spark" then
						solid_spark(input.x + 3, target.y, -1, 0, pt.PSCN)
					end
					if strategy == "spark_row" then
						local p = spark({ type = pt.PSCN, x = input.x + 2, y = target.y, tmp = pt.INSL, ctype = pt.PSCN })
						spark_row(x_bd_bottom - 13, p.y, p.x, p.y, p.ctype, 1, 3)
					end
				end
				cray(x_bd_bottom - 6, bank_target_cray_3.y, x_end - 13, bank_target_cray_3.y, pt.STOR, 1, pt.PSCN)
				cray(x_bd_bottom - 6, bank_target_cray_3.y, x_end - 10, bank_target_cray_3.y, pt.STOR, 1, pt.PSCN)
				cray(x_bd_bottom - 6, bank_target_cray_4.y, x_end - 13, bank_target_cray_4.y, pt.STOR, 1, pt.PSCN)
				cray(x_bd_bottom - 6, bank_target_cray_4.y, x_end - 10, bank_target_cray_4.y, pt.STOR, 1, pt.PSCN)
				apom(x_bd_bottom - 4, x_end + 4, bank_target_dray_2, part({ type = pt.DRAY, x = x_bd_bottom - 1, y = bank_target_dray_2.y     }), "solid_spark")
				apom(x_bd_bottom - 4, x_end    , bank_target_pstn  , part({ type = pt.PSTN, x = x_bd_bottom - 1, y = bank_target_pstn.y       }), "solid_spark")
				apom(x_bd_bottom - 4, x_end - 3, bank_target_cray_3, part({ type = pt.CRAY, x = x_bd_bottom    , y = bank_target_cray_3.y     }), "spark_row")
				                                                     part({ type = pt.FILT, x = x_bd_bottom - 1, y = bank_target_cray_3.y     })
				apom(x_bd_bottom - 4, x_end - 3, bank_target_cray_4, part({ type = pt.CRAY, x = x_bd_bottom - 1, y = bank_target_cray_4.y     }), "solid_spark")
				                                                     part({ type = pt.INSL, x = x_bd_bottom - 1, y = bank_target_cray_3.y + 1 })
				                                                     part({ type = pt.INSL, x = x_bd_bottom - 1, y = bank_target_cray_4.y + 1 })
				cray(x_end - 3, bank_target_cray_3.y, x_end - 13, bank_target_cray_3.y, pt.STOR, 1, pt.PSCN)
				cray(x_end - 3, bank_target_cray_3.y, x_end - 10, bank_target_cray_3.y, pt.STOR, 1, pt.PSCN)
				cray(x_end - 3, bank_target_cray_4.y, x_end - 13, bank_target_cray_4.y, pt.STOR, 1, pt.PSCN)
				cray(x_end - 3, bank_target_cray_4.y, x_end - 10, bank_target_cray_4.y, pt.STOR, 1, pt.PSCN)
				dray_log(x_bd_bottom - 2, bank_target_dray_2.y, x_bd_bottom, bank_target_dray_2.y, size_bw * block_size, pt.PSCN)
				dray_log(x_bd_bottom - 2, bank_target_cray_3.y, x_bd_bottom + 1, bank_target_cray_3.y, size_bw * block_size - 1, pt.PSCN)
				dray_log(x_bd_bottom - 2, bank_target_cray_4.y, x_bd_bottom + 1, bank_target_cray_4.y, size_bw * block_size - 1, pt.PSCN)
				for x = 0, size_bw - 1 do
					dray(x_bd_bottom - 2, bank_target_pstn.y, x_bd_bottom + x * block_size + 7, bank_target_pstn.y, 1, pt.PSCN)
				end
			end
			do
				local x_end = x_bd_bottom + block_size * size_bw + 6
				cray(x_end + 1, y_end + 1, x_end - 7, y_end + 1, pt.INWR, size_bw * block_size, pt.PSCN)
				cray(x_end + 1, y_end + 1, x_end - 7, y_end + 1, pt.INWR, size_bw * block_size, pt.PSCN)
				cray(x_end + 5, y_end + 1, x_end - 7, y_end + 1, pt.SPRK, size_bw * block_size, false, nil, 4)
				solid_spark(x_end + 7, y_end + 1, -1, 0, pt.INWR)
				local source = part({ type = pt.FILT, x = x_end + 13, y = y_base - 7, ctype = 0x10000003, unstack = true })
				local source_2 = part({ type = pt.FILT, x = x_end + 13, y = y_end - 10 })
				ldtc(source_2.x, source_2.y - 1, source.x, source.y)
				ldtc(x_end + 5, y_end - 2, source_2.x, source_2.y)
				part({ type = pt.FILT, x = x_end + 4, y = y_end - 1 })
				part({ type = pt.LSNS, x = x_end + 4, y = y_end, tmp = 3 })
			end
		end

		do -- bank last-mile
			local y_dr2_pre = y_bank + 12 - x_bank_right + bank_target_dray_2.x
			local dr2_pre = part({ type = pt.DRAY, x = bank_target_dray_2.x, y = y_dr2_pre })
			dray(dr2_pre.x, dr2_pre.y - 1, bank_target_dray_2.x, bank_target_dray_2.y, 1, pt.PSCN)
			part({ type = pt.INSL, x = x_bank_right - 6, y = y_bank + 2, tmp = 1 })
			for i = 0, 5 do
				local target = { type = pt.HEAC, x = x_bank_right - 7 - i, y = y_bank + 2 }
				if i < 4 then
					part(target)
				else
					dray(target.x, y_base + size_bh * block_size + 20 + i % 2, target.x, target.y, 1, pt.PSCN)
				end
			end
			part({ type = pt.CRMC, x = x_bank_right - 12, y = y_bank })
			part({ type = pt.CONV, x = x_bank_right - 11, y = y_bank + 1, tmp = pt.CRMC, ctype = pt.PSCN })
			part({ type = pt.CONV, x = x_bank_right - 11, y = y_bank + 1, tmp = pt.PSCN, ctype = pt.SPRK })
			part({ type = pt.LSNS, x = x_bank_right - 11, y = y_bank + 1, tmp = 3 })
			part({ type = pt.FILT, x = x_bank_right - 10, y = y_bank, ctype = 0x10000003 })
			dray(x_bank_right - 11, y_bank + 1, bank_target_dray_1.x, bank_target_dray_1.y, 1, false)
			dray(x_bank_right - 11, y_bank + 1, dr2_pre           .x, dr2_pre           .y, 1, false)
			dray(x_bank_right -  7, y_bank + 1, bank_target_cray_1.x, bank_target_cray_1.y, 1, pt.PSCN)
			dray(x_bank_right -  6, y_bank + 1, bank_target_cray_2.x, bank_target_cray_2.y, 1, pt.PSCN)
			part({ type = pt.CONV, x = x_bank_right - 11, y = y_bank + 1, tmp = pt.SPRK, ctype = pt.CRMC })
			for y = 0, size_bh - 1 do
				dray(x_bank_right -  9, y_bank + 1, x_bank_right - 9, y_bank + 21 + y * block_size, 1, pt.PSCN)
			end
			dray(x_bank_right -  9, y_bank + 1, bank_target_pstn.x, bank_target_pstn.y, 1, pt.PSCN)

			local bank_target_fg = part({ type = pt.STOR, x = x_be_right - 3, y = y_blocks + 14 })
			                       part({ type = pt.DMND, x = x_be_right - 3, y = y_blocks + 13 })
			                       part({ type = pt.DMND, x = x_be_right - 3, y = y_blocks + 12 })
			local bank_target_bg = part({ type = pt.CRMC, x = x_be_right - 4, y = y_blocks -  1 })
			                       part({ type = pt.DMND, x = x_be_right - 4, y = y_blocks -  3 })
			for x = 0, block_size - 1 do
				dray(bank_target_fg.x + 1, bank_target_fg.y, x_blocks - block_size + x, bank_target_fg.y, 1, pt.PSCN)
				dray(bank_target_bg.x + 1, bank_target_bg.y, x_blocks - block_size + x, bank_target_bg.y, 1, pt.PSCN)
			end

			local function apom_dray(target, y_end, top_conductor)
				local p = dray(target.x, y_base - 4, target.x, target.y - 2, 3, false)
				spark({ type = pt.INWR, x = target.x, y = p.y - 1 })
				part ({ type = pt.FILT, x = target.x, y = p.y - 3, unstack = true })
				p.y = p.y - 2
				local source = part({ type = pt.HEAC, x = p.x, y = y_base + 9 })
				if top_conductor == false then
					part({ type = pt.STOR, x = p.x    , y = p.y - 3 })
					part({ type = pt.CONV, x = p.x    , y = p.y - 2, tmp = pt.SPRK, ctype = pt.CRMC })
					part({ type = pt.CONV, x = p.x    , y = p.y - 2, tmp = pt.STOR, ctype = pt.PSCN })
					part({ type = pt.CONV, x = p.x    , y = p.y - 2, tmp = pt.PSCN, ctype = pt.SPRK })
					part({ type = pt.LSNS, x = p.x    , y = p.y - 2, tmp = 3, tmp2 = 2 })
					part({ type = pt.FILT, x = p.x + 2, y = p.y    , ctype = 0x10000003 })
				end
				cray(p.x, p.y - 2, target.x, target.y, pt.SPRK, 1, top_conductor)
				cray(p.x, p.y - 2, source.x, source.y, pt.HEAC, 1, top_conductor)
				dray(p.x, p.y - 2, p.x, p.y + 1, 2, top_conductor)
				cray(p.x, y_end, p.x, p.y + 2, pt.HEAC, 1, pt.PSCN)
				cray(p.x, y_end, source.x, source.y, pt.HEAC, 1, pt.PSCN)
				if top_conductor == false then
					part({ type = pt.CONV, x = p.x, y = p.y - 2, tmp = pt.SPRK, ctype = pt.STOR })
					part({ type = pt.CONV, x = p.x, y = p.y - 2, tmp = pt.CRMC, ctype = pt.PSCN })
					part({ type = pt.CONV, x = p.x, y = p.y - 2, tmp = pt.PSCN, ctype = pt.SPRK })
				end
				return p
			end
			                apom_dray(bank_target_fg, y_base + 30, false)
			local dray_bg = apom_dray(bank_target_bg, y_base + 31, pt.PSCN)
			local x_head = bank_target_bg.x - 15
			dray(x_head, dray_bg.y + 1, bank_target_bg.x    , dray_bg.y + 1, 1, pt.PSCN)
			dray(x_head, dray_bg.y + 1, bank_target_bg.x + 1, dray_bg.y + 1, 1, pt.PSCN)
			part({ type = pt.INSL, x = x_head + 1, y = dray_bg.y + 1 })
			spark_row(x_head + 3, dray_bg.y + 1, bank_target_bg.x, dray_bg.y + 1, pt.INWR, 2, 3)
		end

		do -- scrollmask usage site
			local function usage_site(x_stack, y_stack, x_sparks, y_sparks, size, dray_off_2)
				local x_dir = sig_magn(x_sparks - x_stack)
				local y_dir = sig_magn(y_sparks - y_stack)
				local function off_x(off)
					return x_dir * off
				end
				local function off_y(off)
					return y_dir * off
				end

				local function transform(p)
					local offset = p.x - x_stack
					p.x = x_stack - offset * x_dir
					p.y = y_stack - offset * y_dir
					return p
				end
				local bit_filt = transform(part({ type = pt.FILT, x = x_stack + 4, y = y_stack, ctype = 1 }))
				transform(part ({ type = pt.FILT, x = x_stack + 2, y = y_stack }))
				transform(spark({ type = pt.PSCN, x = x_stack + 1, y = y_stack }))
				transform(part ({ type = pt.FILT, x = x_stack - 1, y = y_stack }))
				transform(part ({ type = pt.FILT, x = x_stack - 3, y = y_stack, tmp = 10, ctype = 2 }))
				transform(part ({ type = pt.FILT, x = x_stack - 6, y = y_stack, tmp =  6 }))
				transform(part ({ type = pt.FILT, x = x_stack - 5, y = y_stack, tmp =  6, ctype = 0x10000000 }))
				transform(part ({ type = pt.FILT, x = x_stack - 7, y = y_stack, tmp =  3, ctype = 0x10000000 }))

				local function change_conductor(conductor, from)
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = conductor, tmp = from or pt.SPRK })
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.SPRK, tmp = conductor })
					part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3, tmp2 = 2 })
				end

				cray(x_stack, y_stack, x_sparks, y_sparks, pt.STOR,  size      * 4, false)
				cray(x_stack, y_stack, x_sparks, y_sparks, pt.STOR, (size - 1) * 4, false)
				ldtc(x_stack, y_stack, bit_filt.x, bit_filt.y)
				for i = 0, size - 1 do
					if i == 16 then
						part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.FILT, ctype = pt.CRMC })
						part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = pt.FILT })
						part({ type = pt.LDTC, x = x_stack, y = y_stack, life = 4 })
						change_conductor(pt.PSCN, pt.FILT)
						part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.CRMC, ctype = bitx.bor(pt.FILT, bitx.lshift(3, sim.PMAPBITS)) })
						part({ type = pt.LDTC, x = x_stack, y = y_stack, life = 1 })
						part({ type = pt.DRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 5 })
						part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.FILT, ctype = pt.CRMC })
						part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.CRMC, ctype = pt.FILT })
						ldtc(x_stack, y_stack, bit_filt.x, bit_filt.y)
					end
					change_conductor(pt.INST)
					part({ type = pt.ARAY, x = x_stack, y = y_stack, life = 1000 })
					local dray_off = (size - i - 1) * block_size - dray_off_2
					for j = 0, 6, 2 do
						dray(x_stack, y_stack, x_sparks + off_x(dray_off + j), y_sparks + off_y(dray_off + j), 2, false)
					end
					change_conductor(pt.PSCN)
					part({ type = pt.DTEC, x = x_stack, y = y_stack, tmp2 = 4 })
					if i < size - 1 then
						local spark_off = (size - i - 2) * block_size
						cray(x_stack, y_stack, x_sparks + off_x(spark_off), y_sparks + off_y(spark_off), pt.STOR, 4, false)
					end
					part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 3, ctype = pt.SPRK })
				end
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = pt.PSCN })
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.PSCN, ctype = pt.SPRK })
			end
			local x_end = x_blocks + size_bw * block_size
			local y_end = y_blocks + size_bh * block_size
			for y = 0, 3, 3 do
				usage_site(x_end + 15, y_end + 1 + y, x_end - 1, y_end + 1 + y, size_bw, (y == 3) and 1 or 0)
				part({ type = pt.FILT, x = x_end + 17, y = y_end + 2 + y, ctype = 0x10000003 })
				solid_spark(x_end + 14, y_end + y, -1, 1, pt.PSCN)
				for x = 0, 7 do
					part({ type = pt.FILT, x = x_end + x, y = y_end + 1 + y, unstack = true })
				end
			end
			for x = 0, 3, 3 do
				usage_site(x_end + 1 + x, y_end + 14, x_end + 1 + x, y_end - 1, size_bh, (x == 0) and 1 or 0)
				part({ type = pt.FILT, x = x_end + 3 + x, y = y_end + 16, ctype = 0x10000003 })
				solid_spark(x_end + 2 + x, y_end + 13, -1, -1, pt.PSCN)
				for y = 0, 6 do
					if y == 0 or y == 3 then
						part({ type = pt.STOR, x = x_end + 1 + x, y = y_end + y })
					else
						part({ type = pt.FILT, x = x_end + 1 + x, y = y_end + y, unstack = true })
					end
				end
			end
			part({ type = pt.FILT, x = x_end +  8, y = y_end + 2 })
			part({ type = pt.FILT, x = x_end +  8, y = y_end + 3 })
			part({ type = pt.FILT, x = x_end + 10, y = y_end + 2 })
			part({ type = pt.FILT, x = x_end + 10, y = y_end + 3 })
			part({ type = pt.FILT, x = x_end +  2, y = y_end + 7 })
			part({ type = pt.FILT, x = x_end +  3, y = y_end + 7 })
			part({ type = pt.FILT, x = x_end +  2, y = y_end + 9 })
			part({ type = pt.FILT, x = x_end +  3, y = y_end + 9 })
			do
				local source_1a = part({ type = pt.FILT, x = x_end +  9, y = y_end + 7 })
				local source_1b = part({ type = pt.FILT, x = x_end + 11, y = y_end + 9 })
				ldtc(x_end + 5, y_end + 7, source_1a.x, source_1a.y, 1000)
				ldtc(x_end + 5, y_end + 9, source_1b.x, source_1b.y, 1000)
				local source_2a = part({ type = pt.FILT, x = source_1a.x, y = y_base - 7, ctype = 0x10000000, unstack = true })
				local source_2b = part({ type = pt.FILT, x = source_1b.x, y = y_base - 7, ctype = 0x10000000, unstack = true })
				ldtc(source_1a.x, source_1a.y - 1, source_2a.x, source_2a.y, 1000)
				ldtc(source_1b.x, source_1b.y - 1, source_2b.x, source_2b.y, 1000)
				local source_3a = part({ type = pt.FILT, x = x_end +  8, y = y_base - 7, ctype = 0x10000000, unstack = true })
				local source_3b = part({ type = pt.FILT, x = x_end + 10, y = y_base - 7, ctype = 0x10000000, unstack = true })
				ldtc(source_3a.x, y_end, source_3a.x, source_3a.y, 1000)
				ldtc(source_3b.x, y_end, source_3b.x, source_3b.y, 1000)
			end
		end

		do -- bus interface
			local x_reader = x_base + size_bw * block_size + 2
			local y_end    = y_base + size_bh * block_size
			local y_reader = y_base - 8
			for x = 0, 3 do
				local target = part({ type = pt.FILT, x = x_reader + x, y = y_end + 31, ctype = 0x10000000, dcolour = 0xFF00FFFF })
				part({ type = pt.FILT, x = x_reader + x, y = y_end + 32, dcolour = 0xFF00FFFF })
				part({ type = pt.FILT, x = x_reader + x    , y = y_reader - 1 })
				part({ type = pt.FILT, x = x_reader + x - 2, y = y_reader + 1, unstack = true })
				if x > 0 then
					part({ type = pt.LDTC, x = x_reader + x - 3, y = y_reader + 2 })
					part({ type = pt.FILT, x = x_reader + x - 4, y = y_reader + 3 })
				end
				ldtc(x_reader + x, y_reader, target.x, target.y)
				part({ type = pt.INSL, x = x_reader + x    , y = y_reader     })
			end
			do
				part({ type = pt.BRAY, x = x_reader - 1, y = y_reader, life = 1 })
				aray(x_reader - 3, y_reader + 2, -1, 1, pt.METL, nil, 1)
				part({ type = pt.FILT, x = x_reader + 1, y = y_reader + 2 })
				part({ type = pt.DTEC, x = x_reader + 2, y = y_reader + 2, tmp2 = 3 })
				local target = part({ type = pt.FILT, x = x_base - 11, y = y_reader + 2 })
				               part({ type = pt.LDTC, x = x_base - 12, y = y_reader + 3 })
				dray(x_reader + 2, y_reader + 2, target.x, target.y, 1, pt.PSCN)
			end
			do
				dray(x_reader, y_reader + 3, x_base + 1, y_reader + 3, 3, false)
				local p = spark({ type = pt.PSCN, x = x_reader + 1, y = y_reader + 3, life = 3 })
				spark_row(p.x - 15, p.y, p.x, p.y, p.ctype, 1, p.life)
			end
			cray(x_reader -  8, y_reader, x_reader    , y_reader, pt.LDTC, 4, pt.PSCN)
			cray(x_reader -  8, y_reader, x_reader    , y_reader, pt.LDTC, 4, pt.PSCN)
			cray(x_reader -  8, y_reader, x_reader    , y_reader, pt.LDTC, 4, pt.PSCN)
			cray(x_reader -  8, y_reader, x_reader - 1, y_reader, pt.LDTC, 4, pt.PSCN)
			cray(x_reader + 16, y_reader, x_reader + 2, y_reader, pt.INSL, 4, pt.PSCN)
			cray(x_reader + 16, y_reader, x_reader + 3, y_reader, pt.INSL, 4, pt.PSCN)
			cray(x_reader + 16, y_reader, x_reader + 3, y_reader, pt.INSL, 4, pt.PSCN)
			cray(x_reader + 16, y_reader, x_reader + 3, y_reader, pt.INSL, 4, pt.PSCN)

			local busy = part({ type = pt.FILT, x = x_reader + 13, y = y_reader + 1, ctype = 0x10000001, unstack = true })
			local output = part({ type = pt.FILT, x = x_reader + 4, y = y_end + 32, dcolour = 0xFF00FFFF })
			               part({ type = pt.FILT, x = x_reader + 4, y = y_end + 31, dcolour = 0xFF00FFFF })
			               part({ type = pt.FILT, x = x_reader + 4, y = y_end + 30 })
			local busy_3 = part({ type = pt.FILT, x = busy.x, y = output.y - 7 })
			local busy_2 = part({ type = pt.FILT, x = output.x, y = output.y - 7 })
			ldtc(busy_3.x, busy_3.y - 1, busy.x, busy.y)
			ldtc(busy_2.x + 1, busy_2.y, busy_3.x, busy_3.y)
			ldtc(busy_2.x, output.y - 3, busy_2.x, busy_2.y)
		end

		if params.single_pixel then
			local rows = size_bw * block_size / 4

			local x_plotter = x_base - 7
			local y_plotter = y_base + size_bh * block_size - rows - 2
			local y_end     = y_base + size_bh * block_size + 10

			do
				local source = part({ type = pt.FILT, x = x_plotter + 96, y = y_base - 7, ctype = 0x1000DEAD, unstack = true })
				local source_2 = part({ type = pt.FILT, x = x_plotter + 96, y = y_base + 10 })
				ldtc(source.x, source_2.y - 1, source.x, source.y)
				local source_3 = part({ type = pt.FILT, x = x_plotter - 8, y = y_base + 10 })
				ldtc(source_3.x + 1, source_3.y, source_2.x, source_2.y)
				local source_4 = part({ type = pt.FILT, x = x_plotter - 8, y = y_plotter - 11, tmp = 1 })
				ldtc(source_4.x, source_4.y - 1, source_3.x, source_3.y)
				dray(source_4.x - 1, source_4.y - 1, source_4.x + 8, source_4.y + 8, 1, pt.PSCN)
				local source_5 = part({ type = pt.FILT, x = x_plotter - 8, y = y_end - 11 })
				ldtc(source_5.x, source_5.y - 1, source_3.x, source_3.y)
				ldtc(source_5.x + 10, source_5.y + 10, source_5.x, source_5.y)
				local source_6 = part({ type = pt.FILT, x = x_plotter - 8, y = y_end + 9 })
				ldtc(source_6.x, source_6.y - 1, source_3.x, source_3.y)
				ldtc(source_6.x - 2, source_6.y + 2, source_6.x, source_6.y)
			end

			for x = 0, 3 do
				part({ type = pt.CRMC, x = x_plotter + x, y = y_plotter - 1 })
				for y = 0, rows - 1 do
					part({ type = pt.DRAY, x = x_plotter + x, y = y_plotter + y, tmp = 1, tmp2 = (rows - y - 1) * 4 + 20 - x })
				end
			end

			do -- column-column select
				local x_stack = x_plotter - 3
				local y_stack = y_plotter - 3
				local y_end   = y_base + size_bh * block_size + 10

				solid_spark(x_stack + 1, y_stack + 1, 1, -1, pt.PSCN, true)
				lsns_spark({ type = pt.NSCN, x = x_stack + 9, y = y_stack + 2, life = 3 }, 0, 1, 0, 2)

				local lsns_life = part({ type = pt.FILT, x = x_stack - 2, y = y_stack, ctype = 0x10000003 })
				local bit_filts = {
					[ 0 ] = part({ type = pt.FILT, x = x_stack - 4, y = y_stack, ctype = 0x400 }),
					[ 1 ] = part({ type = pt.FILT, x = x_stack - 3, y = y_stack, ctype = 0x200 }),
				}

				part({ type = pt.HEAC, x = x_stack - 1, y = y_stack })
				part({ type = pt.FILT, x = x_stack + 1, y = y_stack })
				part({ type = pt.FILT, x = x_stack + 3, y = y_stack, tmp = 1, ctype = 0x1000DEAD })
				part({ type = pt.STOR, x = x_stack + 4, y = y_stack })
				part({ type = pt.STOR, x = x_stack + 5, y = y_stack })
				part({ type = pt.STOR, x = x_stack + 6, y = y_stack })
				part({ type = pt.DMND, x = x_stack + 9, y = y_stack })
				part({ type = pt.INSL, x = x_stack + 8, y = y_stack - 1, unstack = true })

				part({ type = pt.PSTN, x = x_stack + 3, y = y_stack + 1 })
				part({ type = pt.PSTN, x = x_stack + 4, y = y_stack + 1 })
				part({ type = pt.PSTN, x = x_stack + 5, y = y_stack + 1 })
				part({ type = pt.PSTN, x = x_stack + 6, y = y_stack + 1, extend = 1 })
				do
					local target = { x = x_stack + 9, y = y_stack + 1 }
					local source = part({ type = pt.INSL, x = x_stack + 9, y = y_end - 2 })
					cray(target.x, y_base - 8, source.x, source.y, pt.INSL, 1, pt.PSCN)
					cray(target.x, y_base - 8, target.x, target.y, pt.PSTN, 1, pt.PSCN)
					cray(target.x, y_end + 6, target.x, target.y, pt.INSL, 1, pt.PSCN)
					cray(target.x, y_end + 6, source.x, source.y, pt.INSL, 1, pt.PSCN)
				end

				local function change_conductor(conductor, from)
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = conductor, tmp = from or pt.SPRK })
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.SPRK, tmp = conductor })
					part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3 })
				end

				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.HEAC, ctype = pt.PSCN })
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.PSCN, ctype = pt.SPRK })
				ldtc(x_stack, y_stack, lsns_life.x, lsns_life.y)
				part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3 })
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 2, tmp2 = 6, ctype = pt.SPRK })
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 6, ctype = pt.STOR })
				for i = 0, 1 do
					part({ type = pt.INSL, x = x_stack + 7 + i, y = y_stack     })
					part({ type = pt.PSTN, x = x_stack + 7 + i, y = y_stack + 1, ctype = pt.FILT, extend = bitx.lshift(1, math.max(0, i - 1)) })

					change_conductor(pt.INST)
					ldtc(x_stack, y_stack, bit_filts[i].x, bit_filts[i].y)
					part({ type = pt.ARAY, x = x_stack, y = y_stack, life = 1000 })
					part({ type = pt.DRAY, x = x_stack, y = y_stack, tmp = 2, tmp2 = 4 - i })
					ldtc(x_stack, y_stack, lsns_life.x, lsns_life.y)
					if i < 1 then
						change_conductor(pt.PSCN)
						part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 6 - i, ctype = pt.SPRK })
					end
				end
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = pt.HEAC })

				local target = part({ type = pt.INSL, x = x_stack - 1, y = y_end     })
				               part({ type = pt.INSL, x = x_stack - 1, y = y_end - 1 })
				dray(target.x + 1, target.y, target.x - 8, target.y, 1, pt.PSCN)
				do
					local target = dray(x_stack - 1, y_stack - 1, target.x, target.y - 1, 2, false)
					local source = part({ type = pt.FRME, x = target.x, y = y_end - 2 })
					part({ type = pt.INSL, x = target.x, y = target.y })
					cray(target.x, target.y - 3, target.x, target.y, pt.INSL, 1, pt.PSCN)
					cray(target.x, target.y - 3, source.x, source.y, pt.FRME, 1, pt.PSCN)
					dray(target.x, target.y - 3, target.x, target.y, 1, pt.PSCN)
					cray(target.x, target.y - 3, source.x, source.y, pt.FRME, 1, pt.PSCN)
					cray(target.x, y_end + 6, target.x, target.y, pt.INSL, 1, pt.PSCN)
					cray(target.x, y_end + 6, source.x, source.y, pt.FRME, 1, pt.PSCN)
					cray(target.x, y_end + 6, target.x, target.y, pt.INSL, 1, pt.PSCN)
					cray(target.x, y_end + 6, source.x, source.y, pt.FRME, 1, pt.PSCN)
					lsns_spark({ type = pt.PSCN, x = target.x, y = target.y - 1, life = 3 }, -1, 0, -2, 0)
					target.y = target.y - 2
				end
			end

			do -- column-row select
				local x_stack = x_plotter + 3
				local y_stack = y_plotter + rows + 19
				local y_top   = y_stack - 7 - size_bh * block_size

				part({ type = pt.INSL, x = x_stack - 5, y = y_plotter - 4 })
				part({ type = pt.CRMC, x = x_stack - 7, y = y_plotter - 2 })
				part({ type = pt.CRMC, x = x_stack - 6, y = y_plotter - 2 })
				part({ type = pt.CRMC, x = x_stack - 5, y = y_plotter - 2 })
				part({ type = pt.CRMC, x = x_stack - 4, y = y_plotter - 2 })
				lsns_spark({ type = pt.PSCN, x = x_bank - 5, y = y_plotter - 2, life = 3 }, 0, 1, 0, 2)
				do
					local target = cray(x_stack - 12, y_plotter - 2, x_stack - 7, y_plotter - 2, pt.CRMC, 4, false)
					local source = part({ type = pt.INSL, x = target.x, y = y_stack - 8 })
					cray(target.x, target.y - 3, source.x, source.y, pt.INSL, 1, pt.PSCN)
					dray(target.x, target.y - 3, target.x, target.y, 1, pt.PSCN)
					dray(source.x, source.y + 7, target.x, target.y, 1, pt.PSCN)
					cray(source.x, source.y + 7, source.x, source.y, pt.INSL, 1, pt.PSCN)
					target.y = target.y - 2
				end

				part({ type = pt.FRME, x = x_stack - 6, y = y_stack - 9 })
				part({ type = pt.FRME, x = x_stack - 5, y = y_stack - 9 })
				part({ type = pt.FRME, x = x_stack - 4, y = y_stack - 9 })
				part({ type = pt.PSTN, x = x_stack - 4, y = y_stack - 8 })
				part({ type = pt.PSTN, x = x_stack - 4, y = y_stack - 7 })
				part({ type = pt.PSTN, x = x_stack - 4, y = y_stack - 6, extend = math.huge })
				part({ type = pt.PSTN, x = x_stack - 4, y = y_stack - 5, extend = math.huge, tmp = 1 })
				part({ type = pt.INSL, x = x_stack - 4, y = y_stack - 4 })
				solid_spark(x_stack - 5, y_stack - 3, 1, 0, pt.NSCN)

				do
					local target = { x = x_stack + 1, y = y_stack - 20 }
					local source = part({ type = pt.INSL, x = x_stack + 1, y = y_stack - 8 })
					cray(source.x, y_top - 18, source.x, source.y, pt.INSL, 1, pt.PSCN)
					cray(target.x, y_top - 18, target.x, target.y, pt.DRAY, 1, pt.PSCN)
					cray(target.x, y_stack - 1, target.x, target.y, pt.CRMC, 1, pt.PSCN)
					cray(source.x, y_stack - 1, source.x, source.y, pt.CRMC, 1, pt.PSCN)
				end
				spark({ type = pt.PSCN, x = x_stack + 2, y = y_stack - 20, life = 3 })
				part ({ type = pt.LSNS, x = x_stack + 3, y = y_stack - 20, tmp = 3 })
				part ({ type = pt.FILT, x = x_stack + 3, y = y_stack - 19, ctype = 0x10000003 })
				part ({ type = pt.FRME, x = x_stack + 1, y = y_stack - 19 })
				part ({ type = pt.FRME, x = x_stack + 2, y = y_stack - 19 })
				part ({ type = pt.DMND, x = x_stack    , y = y_stack - 18 })
				part ({ type = pt.PSTN, x = x_stack + 2, y = y_stack - 18, extend = 1 })
				part ({ type = pt.PSTN, x = x_stack + 2, y = y_stack - 10 })
				part ({ type = pt.PSTN, x = x_stack + 2, y = y_stack -  9 })
				part ({ type = pt.PSTN, x = x_stack + 2, y = y_stack -  8, extend = math.huge, tmp = 2 })
				part ({ type = pt.INSL, x = x_stack + 2, y = y_stack -  7 })
				local bit_filt = part({ type = pt.FILT, x = x_stack    , y = y_stack + 13, ctype = 0x400 })

				local function change_conductor(conductor, from)
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = conductor, tmp = from or pt.SPRK })
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.SPRK, tmp = conductor })
					part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3, tmp2 = 2 })
				end

				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = pt.CRMC })
				change_conductor(pt.PSCN, pt.HEAC)
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 7, tmp2 = 10, ctype = pt.SPRK })
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 6, tmp2 = 10, ctype = pt.STOR })
				ldtc(x_stack, y_stack, bit_filt.x, bit_filt.y)
				for i = 0, 6 do
					spark({ type = pt.PSCN, x = x_stack    , y = y_stack - 17 + i })
					part ({ type = pt.PSTN, x = x_stack + 2, y = y_stack - 17 + i, extend = bitx.lshift(1, math.max(0, i - 1)) })

					change_conductor(pt.INST)
					part({ type = pt.ARAY, x = x_stack, y = y_stack, life = 1000 })
					part({ type = pt.DRAY, x = x_stack, y = y_stack, tmp = 2, tmp2 = 13 - i })
					part({ type = pt.DTEC, x = x_stack, y = y_stack, tmp2 = 5 })
					change_conductor(pt.PSCN)
					if i < 6 then
						part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 15 - i, ctype = pt.SPRK })
					end
					part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 4, ctype = pt.SPRK })
				end
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = pt.HEAC })
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.CRMC, ctype = pt.PSCN })
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.PSCN, ctype = pt.SPRK })

				solid_spark(x_stack + 3, y_stack - 7, 0, -1, pt.NSCN)
				part ({ type = pt.STOR, x = x_stack    , y = y_stack - 10 })
				part ({ type = pt.STOR, x = x_stack    , y = y_stack -  9 })
				part ({ type = pt.STOR, x = x_stack    , y = y_stack -  8 })
				part ({ type = pt.FILT, x = x_stack    , y = y_stack -  7, tmp =  3, ctype = 0x1000DEAD })
				part ({ type = pt.FILT, x = x_stack    , y = y_stack -  4, tmp = 10, ctype = 2 })
				part ({ type = pt.CONV, x = x_stack - 1, y = y_stack -  3, tmp = pt.SPRK, ctype = pt.CRMC, z = 1000 })
				spark({ type = pt.PSCN, x = x_stack    , y = y_stack -  2 })
				part ({ type = pt.CONV, x = x_stack - 1, y = y_stack -  1, tmp = pt.CRMC, ctype = pt.PSCN })
				part ({ type = pt.CONV, x = x_stack - 1, y = y_stack -  1, tmp = pt.PSCN, ctype = pt.SPRK })
				part ({ type = pt.FILT, x = x_stack    , y = y_stack -  1 })
				part ({ type = pt.HEAC, x = x_stack    , y = y_stack +  1 })
				part ({ type = pt.FILT, x = x_stack + 2, y = y_stack +  1, ctype = 0x10000003 })
				part ({ type = pt.CONV, x = x_stack + 3, y = y_stack -  4, tmp = pt.BRAY, ctype = pt.STOR, z = 1000 })
				part ({ type = pt.CONV, x = x_stack + 5, y = y_stack -  1, tmp = pt.BRAY, ctype = pt.STOR, z = 1000 })
			end

			do -- row select
				local x_stack  = x_plotter - 11
				local y_stack  = y_plotter + rows + 29
				local y_top    = y_stack - 16 - size_bh * block_size

				do
					local target = part({ type = pt.CRMC, x = x_stack, y = y_plotter + rows + 12 })
					local source = { x = target.x + 10, y = target.y - 10 }
					lsns_spark({ type = pt.PSCN, x = source.x + 2, y = source.y - 2, life = 3 }, -1, 0, 0, 1)
					dray(source.x + 1, source.y - 1, target.x, target.y, 1, false)
					dray(source.x, y_base + 9, source.x, source.y, 1, false)
					cray(source.x + 1, source.y + 1, source.x, source.y, pt.CRMC, 1, pt.PSCN)
				end

				local bit_filt = part({ type = pt.FILT, x = x_stack, y = y_stack + 2, ctype = 1 })

				part ({ type = pt.INSL, x = x_stack - 2, y = y_top - 1 })
				spark({ type = pt.PSCN, x = x_stack - 2, y = y_stack - 17, life = 3 })
				part ({ type = pt.LSNS, x = x_stack - 1, y = y_stack - 17, tmp = 3, tmp2 = 2 })
				part ({ type = pt.FILT, x = x_stack - 2, y = y_stack - 15, ctype = 0x10000003 })
				part ({ type = pt.FRME, x = x_stack    , y = y_stack - 16 })
				part ({ type = pt.FRME, x = x_stack - 1, y = y_stack - 16 })
				part ({ type = pt.FRME, x = x_stack - 2, y = y_stack - 16 })
				part ({ type = pt.DMND, x = x_stack    , y = y_stack - 14 })
				part ({ type = pt.PSTN, x = x_stack - 1, y = y_stack - 15, extend = 1 })
				for j = 1, 10 do
					part({ type = pt.PSTN, x = x_stack - 1, y = y_stack - 14, extend = 26 })
				end
				part ({ type = pt.PSTN, x = x_stack - 1, y = y_stack - 4, extend = math.huge, tmp = 2 })
				part ({ type = pt.INSL, x = x_stack - 1, y = y_stack - 3 })
				do
					local source = part({ type = pt.PSTN, x = x_stack - 1, y = y_stack -  5 })
					local target = part({ type = pt.DRAY, x = x_stack - 1, y = y_stack - 17 })
					cray(source.x, y_top - 19, source.x, source.y, pt.CRMC, 1, pt.PSCN)
					cray(target.x, y_top - 19, target.x, target.y, pt.CRMC, 1, pt.PSCN)
					cray(source.x, y_top - 19, source.x, source.y, pt.PSTN, 1, pt.PSCN)
					cray(target.x, y_top - 19, target.x, target.y, pt.CRMC, 1, pt.PSCN)
					cray(source.x, y_stack + 2, source.x, source.y, pt.CRMC, 1, pt.PSCN)
					cray(target.x, y_stack + 2, target.x, target.y, pt.CRMC, 1, pt.PSCN)
					cray(source.x, y_stack + 2, source.x, source.y, pt.PSTN, 1, pt.PSCN)
					cray(target.x, y_stack + 2, target.x, target.y, pt.CRMC, 1, pt.PSCN)
				end

				local function change_conductor(conductor, from)
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = conductor, tmp = from or pt.SPRK })
					part({ type = pt.CONV, x = x_stack, y = y_stack, ctype = pt.SPRK, tmp = conductor })
					part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3, tmp2 = 2 })
				end

				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 8, tmp2 = 5, ctype = pt.SPRK })
				part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 7, tmp2 = 5, ctype = pt.STOR })
				ldtc(x_stack, y_stack, bit_filt.x, bit_filt.y)
				for i = 0, 7 do
					part({ type = pt.INSL, x = x_stack    , y = y_stack - 13 + i })
					if i == 0 then
						part({ type = pt.PSTN, x = x_stack - 1, y = y_stack - 13 + i, extend = -25 })
					else
						part({ type = pt.PSTN, x = x_stack - 1, y = y_stack - 13 + i, extend = bitx.lshift(1, math.max(0, i - 1)) })
					end

					change_conductor(pt.INST)
					part({ type = pt.ARAY, x = x_stack, y = y_stack, life = 1000 })
					part({ type = pt.DRAY, x = x_stack, y = y_stack, tmp = 2, tmp2 = 9 - i })
					part({ type = pt.DTEC, x = x_stack, y = y_stack, tmp2 = 4 })
					change_conductor(pt.PSCN)
					if i < 7 then
						part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 11 - i, ctype = pt.SPRK })
					end
					part({ type = pt.CRAY, x = x_stack, y = y_stack, tmp = 1, tmp2 = 2, ctype = pt.SPRK })
				end
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = pt.PSCN })
				part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.PSCN, ctype = pt.SPRK })

				spark({ type = pt.PSCN, x = x_stack, y = y_stack + 1 })

				part({ type = pt.FILT, x = x_stack    , y = y_stack - 5, tmp =  3, ctype = 0x1000DEAD })
				part({ type = pt.FILT, x = x_stack    , y = y_stack - 3, tmp = 10, ctype = 2 })
				part({ type = pt.FILT, x = x_stack    , y = y_stack - 1 })
				part({ type = pt.FILT, x = x_stack + 2, y = y_stack    , ctype = 0x10000003 })
				solid_spark(x_stack - 2, y_stack - 13, 0, -1, pt.PSCN)
				solid_spark(x_stack - 2, y_stack -  3, 0, -1, pt.NSCN)
				solid_spark(x_stack - 1, y_stack -  1, 1, -1, pt.NSCN)
			end
		end

		do
			local remap = {}
			for i = 55, 76 do
				remap[i] = i + (size_bw - 12) * block_size
			end
			plot.merge_parts(x_base + 34, y_base - 7, parts, screen_core.get_parts(), remap)
		end

		local screen_body = {
			type = "solid",
			name = "screen_body",
			x    = xoff,
			y    = screen_yoff,
			w    = width,
			h    = height,
		}
		ucontext.frame(screen_body.x + 1, screen_body.y + 1, screen_body.x + screen_body.w - 2, screen_body.y + screen_body.h - 2)
		table.insert(areas, screen_body)

		write_tap.build({
			parts        = parts,
			areas        = areas,
			debug_stacks = params.debug_stacks,
			bus          = params.bus,
			x            = xoff + size_bw * block_size + 5,
			tap_mask     = peripheral_mask,
			tap_base     = peripheral_base,
			area_name    = "screen_interface",
		})

		do
			local y_local = screen_yoff + size_bh * block_size + 44
			local area = {
				type      = "solid",
				name      = "screen_local",
				x         = xoff + size_bw * block_size + 24,
				y         = y_local,
				w         = 5,
				h         = params.bus.y - y_local - 4,
				filt_wire = true,
			}
			for y = area.y, area.y + area.h - 1 do
				for x = area.x, area.x + area.w - 1 do
					part({ type = pt.FILT, x = x, y = y, dcolour = 0xFF00FFFF, unstack = true })
				end
			end
			table.insert(areas, area)
		end
	end

	if have_keyboard then
		local x_keyboard = xoff
		local y_keyboard = keyboard_yoff

		local function make_special_key(key, width, bitmap)
			return {
				key    = key,
				width  = width,
				bitmap = parse_font_bitmap("?", bitmap, width, 8)
			}
		end
		local f1 = make_special_key("\17\28", 16, [[
			.....#####......
			....#######.....
			....##..###.....
			....##..###.....
			....##...##.....
			....#######.....
			.....#####......
			................
		]])
		local f2 = make_special_key("\18\29", 16, [[
			.....#####......
			....#######.....
			....##...##.....
			....###..##.....
			....###..##.....
			....#######.....
			.....#####......
			................
		]])
		local space = make_special_key("space", 56, [[
			........................................................
			........................................................
			........................................................
			........................................................
			........................................................
			.......................##.....##........................
			.......................#########........................
			........................................................
		]])
		local f3 = make_special_key("\19\30", 16, [[
			.....#####......
			....#######.....
			....##...##.....
			....##..###.....
			....##..###.....
			....#######.....
			.....#####......
			................
		]])
		local f4 = make_special_key("\20\31", 16, [[
			.....#####......
			....#######.....
			....###..##.....
			....###..##.....
			....##...##.....
			....#######.....
			.....#####......
			................
		]])
		local tab = make_special_key("\9\25", 12, [[
			.....#......
			.....##.....
			.#######....
			.########...
			.#######....
			.....##.....
			.....#......
			............
		]])
		local caps = make_special_key("caps", 16, [[
			....#...........
			...###..........
			..#####.........
			.#######........
			...###..........
			................
			...###..........
			................
		]])
		local lshift = make_special_key("lshift", 20, [[
			....#...............
			...###..............
			..#####.............
			.#######............
			...###..............
			...###..............
			...###..............
			....................
		]])
		local backspace = make_special_key("\8\24", 16, [[
			....#...........
			...##...........
			..############..
			.#############..
			..############..
			...##...........
			....#...........
			................
		]])
		local kreturn = make_special_key("\10\26", 16, [[
			....#......###..
			...##......###..
			..############..
			.#############..
			..###########...
			...##...........
			....#...........
			................
		]])
		local rshift = make_special_key("rshift", 20, [[
			..............#.....
			.............###....
			............#####...
			...........#######..
			.............###....
			.............###....
			.............###....
			....................
		]])
		local pipe = {
			key = "\\|",
			width = 12,
		}
		local layout = {
			{ "`~", "1!", "2@", "3#", "4$", "5%", "6^", "7&", "8*", "9(", "0)", "-_", "=+",  backspace },
			{  tab   , "qQ", "wW", "eE", "rR", "tT", "yY", "uU", "iI", "oO", "pP", "[{", "]}",    pipe },
			{  caps     , "aA", "sS", "dD", "fF", "gG", "hH", "jJ", "kK", "lL", ";:", "'\"",   kreturn },
			{  lshift      , "zZ", "xX", "cC", "vV", "bB", "nN", "mM", ",<", ".>", "/?",        rshift },
			{  f1       ,   f2      ,                  space                  ,   f3      ,         f4 },
		}
		local max_width = 120
		if params.layout ~= nil then
			local layout_name = params_name .. ".layout"
			check.table(layout_name, params.layout)
			for key, value in audited_pairs(params.layout) do
				local row = {}
				check.integer_range(layout_name .. " key " .. tostring(key), key, 1, 5)
				local value_name = layout_name .. "[" .. key .. "]"
				check.table(value_name, value)
				check.integer_range(value_name .. " size", #value, 1, 15)
				local x = 0
				for ix_rvalue = 1, #value do
					local rvalue = value[ix_rvalue]
					local rvalue_name = value_name .. "[" .. ix_rvalue .. "]"
					local rvalue_key_name = rvalue_name
					if type(rvalue) == "string" then
						rvalue = { key = rvalue }
					else
						rvalue_key_name = rvalue_key_name .. ".key"
					end
					check.table(rvalue_name, rvalue)
					check.string(rvalue_key_name, rvalue.key)
					if not (rvalue.key == "caps" or
					        rvalue.key == "lshift" or
					        rvalue.key == "rshift" or
					        rvalue.key == "space") and #rvalue.key ~= 2 then
						misc.user_error("%s is not a 2-character string", rvalue_key_name)
					end
					local width
					if rvalue.width ~= nil then
						check.integer_range(rvalue_name .. ".width", rvalue.width, 8, max_width)
						width = rvalue.width
					end
					local bitmap
					local effective_width = width or 8
					if rvalue.left ~= nil then
						check.integer_range(rvalue_name .. ".left", rvalue.left, 0, max_width)
						if rvalue.left < x then
							misc.user_error("%s is below current key position %i", rvalue_name .. ".left", x)
						end
						x = rvalue.left
					end
					if x + effective_width > max_width then
						misc.user_error("%s causes its row to exceed %i pixels in width", rvalue_name, max_width)
					end
					if rvalue.bitmap ~= nil then
						bitmap = parse_font_bitmap(rvalue_name .. ".bitmap", rvalue.bitmap, effective_width, 8)
					end
					row[ix_rvalue] = {
						key    = rvalue.key,
						left   = x,
						width  = width,
						bitmap = bitmap,
					}
					x = x + effective_width
				end
				layout[key] = row
			end
		end

		local indicate_shift
		local indicate_caps
		local indicate_busy
		local x_keys_min = x_keyboard + 9
		local x_keys     = x_keys_min + ((size_bw - 12) * block_size) / 2
		local y_keys     = y_keyboard + 3
		local y_bottom   = y_keys + #layout * 8 + 2
		local keys_width = 120
		local x_end      = x_keys + keys_width
		do
			local y_gather = y_keys + 42

			local down_drays = {}
			local keyboard_parts = {}
			local keyboard_parts_ordered = {}
			local function keyboard_part(p)
				local q = keyboard_parts[plot.xy_key(p.x, p.y)]
				if q then
					return q
				end
				table.insert(keyboard_parts_ordered, p)
				keyboard_parts[plot.xy_key(p.x, p.y)] = p
				return p
			end
			local function emit_char(life, x, y, w, h, bitmap)
				for yy = 0, h do
					for xx = 0, w do
						local ptype = pt.INST
						local dcolour = 0xFF3F3F3F
						if xx == 0 or yy == 0 or xx == w or yy == h then
							ptype = pt.INSL
							dcolour = 0xFF000000
						end
						if xx >= 1 and yy >= 1 and xx <= w and yy <= h then
							if bitmap[yy - 1][xx - 1] then
								dcolour = 0xFFFFFFFF
							end
						end
						keyboard_part({ type = ptype, x = x + xx, y = y + yy, dcolour = dcolour, z = 2000 })
					end
				end
				local d = { x = x + 4, y = y + h }
				down_drays[plot.xy_key(d.x, d.y)] = life
			end
			for y = 1, #layout do
				local row = layout[y]
				local x = 0
				for i = 1, #row do
					local w = 8
					local key = row[i]
					local bitmap
					if type(key) == "table" then
						if key.width then
							w = key.width
						end
						if key.bitmap then
							bitmap = key.bitmap
						end
						if key.left then
							x = key.left
						end
						key = key.key
					end
					local h = 8
					local life
					if key == "caps" then
						if y == 3 and x <= 8 and x + w >= 16 then
							indicate_caps = true
						end
						life = 2
					elseif key == "lshift" then
						if y == 4 and x <= 12 and x + w >= 20 then
							indicate_shift = true
						end
						life = 1
					elseif key == "rshift" then
						life = 1
					else
						if key == "space" then
							if y == 5 and x <= 76 and x + w >= 84 then
								indicate_busy = true
							end
							key = " \16"
						end
						life = bitx.bor(bitx.bor(key:byte(1), bitx.lshift(key:byte(2), 7)), 0x4000)
					end
					local normal = key:sub(1, 1)
					if not bitmap then
						local index = normal:byte()
						if index >= 0x61 and index <= 0x7A then
							life = bitx.bor(life, 0x8000)
							index = index - 0x20
						end
						bitmap = font[index]
					end
					emit_char(life, x_keys + x, y_keys + (y - 1) * 8, w, h, bitmap)
					x = x + w
				end
			end
			for _, p in audited_pairs(keyboard_parts) do
				if p.type == pt.INST then
					if down_drays[plot.xy_key(p.x    , p.y + 1)] then p.type = pt.NSCN end
					if down_drays[plot.xy_key(p.x    , p.y - 2)] then p.type = pt.PSCN end
					if down_drays[plot.xy_key(p.x + 1, p.y + 1)] then p.type = pt.INWR end
					if down_drays[plot.xy_key(p.x - 1, p.y + 1)] then p.type = pt.INWR end
					if down_drays[plot.xy_key(p.x + 1, p.y - 1)] then p.type = pt.INWR end
					if down_drays[plot.xy_key(p.x - 1, p.y - 1)] then p.type = pt.INWR end
				end
				local data = down_drays[plot.xy_key(p.x, p.y - 1)]
				if data then
					p.type = pt.CRMC
					p.life = data
				end
			end
			for k, data in audited_pairs(down_drays) do
				local x, y = plot.xy_key_back(k)
				keyboard_part({ type = pt.CRMC, x = x, y = y + 1, life = data })
				dray(x, y, x, y_gather, 1, false, 1000)
			end

			local function emit_indicator(x_ind, y_ind, dcolour, x_state)
				for yy = 0, 2 do
					cray(x_keys_min - 6 + yy % 2 * 3, y_ind + yy, x_ind, y_ind + yy, pt.SPRK, 3, pt.PSCN)
				end
				local spark_target = spark({ type = pt.NSCN, x = x_ind - 1, y = y_bottom + 1 })
				for xx = 0, 2 do
					part ({ type = pt.LCRY, x = x_ind + xx, y = y_bottom + 1, dcolour = dcolour })
					spark({ type = pt.INWR, x = x_ind + xx, y = y_bottom + 3 })
					for yy = 0, 2 do
						local lx, ly = x_ind + xx, y_ind + yy
						dray(x_ind + xx, y_bottom + 2, lx, ly, 1, false)
						local p = keyboard_parts[plot.xy_key(lx, ly)]
						p.type = pt.LCRY
						p.dcolour = dcolour
					end
				end
				spark_row(x_keys + 7, y_bottom + 3, x_ind, y_bottom + 3, pt.INWR, 3, 4, 3)
				local function emit_reader(x_reader, ptype)
					part ({ type = pt.LSNS, x = x_reader    , y = y_bottom + 1, tmp = 3 })
					spark({ type = pt.PSCN, x = x_reader - 1, y = y_bottom + 1, tmp = 3 })
					dray(x_reader - 2, y_bottom + 1, spark_target.x, spark_target.y, 1, false)
					lsns_spark({ type = ptype, x = x_reader - 3, y = y_bottom + 1, life = 3 }, 0, 1, 1, 1)
				end
				emit_reader(x_state, pt.PSCN)
				emit_reader(x_state + 5, pt.NSCN)
			end
			if indicate_caps then
				emit_indicator(x_keys + 11, y_keys + 19, 0xFFFF0000, x_keys + 109)
			end
			if indicate_shift then
				emit_indicator(x_keys + 15, y_keys + 27, 0xFF00FF00, x_keys +  99)
			end
			if indicate_busy then
				emit_indicator(x_keys + 79, y_keys + 35, 0xFFFFFF00, x_keys +  89)
			end

			for _, p in ipairs(keyboard_parts_ordered) do
				part(p)
			end

			part({ type = pt.HEAC, x = x_keys - 3, y = y_bottom })
			part({ type = pt.HEAC, x = x_keys - 2, y = y_bottom, unstack = true })
			part({ type = pt.HEAC, x = x_keys - 1, y = y_bottom, unstack = true })
			part({ type = pt.PSTN, x = x_keys    , y = y_bottom, ctype = pt.HEAC, extend = math.huge })
			part({ type = pt.PSTN, x = x_keys + 1, y = y_bottom, ctype = pt.HEAC, extend = math.huge, tmp = 1 })
			part({ type = pt.PSTN, x = x_keys + 2, y = y_bottom })
			part({ type = pt.DMND, x = x_keys + 3, y = y_bottom })
			solid_spark(x_keys + 1, y_bottom + 1, -1, 0, pt.PSCN, true)
			solid_spark(x_keys + 2, y_bottom + 1, -1, 0, pt.NSCN, true)

			part({ type = pt.LSNS, x = x_end    , y = y_bottom    , tmp = 1 })
			part({ type = pt.HEAC, x = x_end    , y = y_bottom     })
			part({ type = pt.LDTC, x = x_end + 2, y = y_bottom - 1, life = 1 })
			part({ type = pt.FILT, x = x_end + 4, y = y_bottom - 3, life = 1, ctype = 0x10000000 })
			part({ type = pt.FILT, x = x_end + 1, y = y_bottom     })
			part({ type = pt.LDTC, x = x_end + 3, y = y_bottom    , life = 1 })
			aray(x_end + 3, y_bottom, -1, 0, pt.METL, nil, 1)
			part({ type = pt.FILT, x = x_end + 4, y = y_bottom     })
			part({ type = pt.BRAY, x = x_end + 5, y = y_bottom     })
			part({ type = pt.DTEC, x = x_end + 6, y = y_bottom     })
			cray(x_end + 7, y_bottom, x_end - 1, y_bottom, pt.SPRK, 1000, pt.PSCN)
		end

		local x_core_input, x_core_output
		do
			local remap = {}
			remap[0] = 79
			remap[16] = 43
			remap[17] = 48
			remap[18] = 53
			remap[19] = 58
			remap[20] = 63
			remap[21] = 68
			remap[22] = 81
			plot.merge_parts(x_keys + 44, y_bottom + 1, parts, keyboard_core.get_parts(), remap)
			x_core_input = x_keys + 48
			x_core_output = x_keys + 62
		end

		do
			local source = { x = x_keys + 11, y = y_bottom + 1 }
			local target = { x = x_keys + 72, y = y_bottom + 1 }
			dray(source.x - 3, source.y, target.x - 2, source.y, 3, pt.PSCN)
			part({ type = pt.INSL, x = target.x - 1, y = target.y })
			part({ type = pt.INSL, x = target.x    , y = target.y })
			dray(target.x + 1, target.y, source.x + 2, target.y, 1, pt.PSCN)
		end

		part({ type = pt.FILT, x = x_keys_min - 1, y = y_keys - 3, dcolour = 0xFF00FFFF })
		part({ type = pt.FILT, x = x_keys_min - 1, y = y_keys - 2, dcolour = 0xFF00FFFF })
		part({ type = pt.FILT, x = x_keys_min - 2, y = y_keys - 3, dcolour = 0xFF00FFFF })
		part({ type = pt.FILT, x = x_keys_min - 2, y = y_keys - 2, dcolour = 0xFF00FFFF })
		part({ type = pt.FILT, x = x_keys_min - 3, y = y_keys - 3, dcolour = 0xFF00FFFF })
		part({ type = pt.FILT, x = x_keys_min - 3, y = y_keys - 2, dcolour = 0xFF00FFFF })
		part({ type = pt.LDTC, x = x_keys_min - 3, y = y_keys - 1 })
		part({ type = pt.FILT, x = x_keys_min - 3, y = y_keys + 1, ctype = 0x10000000 })
		for y = y_keys - 1, y_bottom + 1 do
			part({ type = pt.FILT, x = x_keys_min - 1, y = y })
			part({ type = pt.FILT, x = x_keys_min - 2, y = y })
		end
		part({ type = pt.FILT, x = x_keys_min - 2, y = y_bottom + 2 })
		part({ type = pt.DTEC, x = x_keys_min - 2, y = y_bottom + 3 })
		dray(x_keys_min - 3, y_bottom + 1, x_core_input - 1, y_bottom + 1, 2, pt.PSCN)
		part({ type = pt.FILT, x =  x_core_input - 1, y = y_bottom + 1 })
		part({ type = pt.BRAY, x = x_core_output + 1, y = y_bottom     })
		part({ type = pt.BRAY, x = x_core_output + 2, y = y_bottom - 1, unstack = true })
		aray(x_core_output - 1, y_bottom + 2, -1, 1, pt.METL)
		part({ type = pt.DTEC, x = x_core_output + 2, y = y_bottom + 2, tmp2 = 2 })
		aray(x_core_output + 2, y_bottom + 2, -1, 0, pt.METL)
		part({ type = pt.FILT, x = x_core_output + 3, y = y_bottom + 2 })
		part({ type = pt.BRAY, x = x_core_output + 4, y = y_bottom + 2 })
		do
			local target = part({ type = pt.BRAY, x = x_keys_min - 1, y = y_bottom + 2 })
			dray(x_core_output + 5, y_bottom + 2, target.x, target.y, 1, pt.PSCN)
		end

		local keyboard_body = {
			type = "solid",
			name = "keyboard_body",
			x    = xoff,
			y    = keyboard_yoff,
			w    = width,
			h    = 51,
		}
		ucontext.frame(keyboard_body.x + 1, keyboard_body.y + 1, keyboard_body.x + keyboard_body.w - 2, keyboard_body.y + keyboard_body.h - 2)
		table.insert(areas, keyboard_body)

		read_tap.build({
			parts        = parts,
			areas        = areas,
			debug_stacks = params.debug_stacks,
			bus          = params.bus,
			x            = xoff + 2,
			tap_mask     = peripheral_mask,
			tap_base     = peripheral_base,
			area_name    = "keyboard_interface",
		})

		do
			local area = {
				type      = "solid",
				name      = "keyboard_local",
				x         = xoff + 6,
				y         = params.bus.y + 9,
				w         = 3,
				h         = keyboard_yoff - params.bus.y - 9,
				filt_wire = true,
			}
			for y = area.y, area.y + area.h - 1 do
				for x = area.x, area.x + area.w - 1 do
					part({ type = pt.FILT, x = x, y = y, dcolour = 0xFF00FFFF, unstack = true })
				end
			end
			table.insert(areas, area)
		end
	end

	return {
		parts = parts,
		areas = areas,
	}
end

local function param_types()
	return {
		x = {
			type = "lowhigh",
			low  = "left",
			high = "right",
		},
		screen_y = {
			type     = "lowhigh",
			low      = "screen_top",
			high     = "screen_bottom",
			optional = true,
		},
		keyboard_y = {
			type     = "lowhigh",
			low      = "keyboard_top",
			high     = "keyboard_bottom",
			optional = true,
		},
		bus = {
			type = "cpu_bus",
		},
		base_address = {
			type  = "base_address",
			buses = { "bus" },
			mask  = peripheral_mask,
		},
	}
end

return {
	build       = build,
	param_types = param_types,
}

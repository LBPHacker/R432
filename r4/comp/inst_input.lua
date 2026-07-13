local bitx       = require("spaghetti.bitx")
local plot       = require("spaghetti.plot")
local check      = require("spaghetti.check")
local filt_input = require("r4.comp.filt_input")

local pt = plot.pt
local peripheral_mask = 0xFFFFFFFF

local function build(params, params_name, component)
	check.integer_range(params_name .. ".bits", params.bits, 1, 32)
	local width = math.max(35, params.bits * 2 + 3)
	if params.bits > 16 then
		width = math.max(41, width)
	end
	local areas = {}

	local xoff
	if params.x.which == "left" then
		xoff = params.x.value
	else
		xoff = params.x.value - width + 1
	end
	local x_base = xoff
	local y_base = params.bus.y

	local peripheral_base = params.base_address

	local parts = {}
	local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
	local cray        = ucontext.cray
	local dray        = ucontext.dray
	local part        = ucontext.part
	local aray        = ucontext.aray
	local ldtc        = ucontext.ldtc
	local spark       = ucontext.spark
	local dray_log    = ucontext.dray_log
	local solid_spark = ucontext.solid_spark

	local internal_parts = filt_input.build_internal({
		x               = xoff + 2,
		debug_stacks    = params.debug_stacks,
		bus             = params.bus,
		peripheral_mask = peripheral_mask,
		peripheral_base = peripheral_base,
		width           = width,
		low_profile     = true,
	})
	plot.merge_parts(0, 0, parts, internal_parts)

	local function emit_output(index, shift, last)
		local b = index
		if shift then
			b = b - 16
		end
		local x_input = x_base + index * 2 + 1
		local y_shift = shift and 1 or 0

		part({ type = pt.FILT, x = x_input, y = y_base + 10, tmp = 2, ctype = bitx.lshift(1, b) })
		part({ type = pt.DRAY, x = x_input, y = y_base + 11, dcolour = 0xFF7F7F00, tmp = 1, tmp2 = y_shift })
		part({ type = pt.INST, x = x_input, y = y_base + 12, dcolour = 0xFF7F7F00 })

		part({ type = pt.FILT, x = x_input, y = y_base - 6, tmp = 2, ctype = bitx.lshift(1, b) })
		part({ type = pt.DRAY, x = x_input, y = y_base - 7, dcolour = 0xFF7F7F00, tmp = 1, tmp2 = y_shift })
		part({ type = pt.INST, x = x_input, y = y_base - 8, dcolour = 0xFF7F7F00 })
	end

	do
		local last = math.min(params.bits, 16) - 1
		local func_last = math.max(last, 15)

		aray(x_base - 1, y_base + 9, -1, 0, pt.INST, nil, 1000)
		part({ type = pt.FILT, x = x_base, y = y_base + 9, ctype = 0x10000000 })
		local x_end = x_base + func_last * 2 + 2
		do
			local target = part({ type = pt.BRAY, x = x_end, y = y_base + 9, life = 1000, ctype = 0x10000000 })
			local y_read = y_base + 2
			cray(target.x, y_read - 1, target.x, target.y, pt.SPRK, 1, pt.PSCN)
			ldtc(target.x, y_read - 2, target.x, target.y, -1000)
			aray(target.x + 1, y_read - 4, 1, 0, pt.METL, nil, 1)
			part({ type = pt.FILT, x = target.x, y = y_read - 3, tmp = 6 })
			part({ type = pt.FILT, x = target.x, y = y_read - 4, ctype = 0x10000000 })
			part({ type = pt.STOR, x = x_end - 1, y = y_read - 4 })
			part({ type = pt.STOR, x = x_end - 2, y = y_read - 4 })
			part({ type = pt.LDTC, x = x_end - 2, y = y_read - 5, life = 1, tmp = 1 })
			part({ type = pt.FILT, x = x_end - 3, y = y_read - 4, tmp = 2 })
		end
		dray_log(x_end + 1, y_base + 9, x_end - 1, y_base + 9, func_last * 2 + 1, pt.PSCN)
		cray(x_end + 1, y_base + 9, x_end - 1, y_base + 9, pt.SPRK, func_last * 2 + 1, pt.PSCN)

		aray(x_base - 1, y_base - 5, -1, 0, pt.METL, nil, 1)
		part({ type = pt.FILT, x = x_base, y = y_base - 5, ctype = 0x10000000 })
		dray_log(x_end + 1, y_base - 5, x_end - 1, y_base - 5, func_last * 2 + 1, pt.PSCN)
		cray(x_end + 1, y_base - 5, x_end - 1, y_base - 5, pt.SPRK, func_last * 2 + 1, pt.PSCN)
		part({ type = pt.BRAY, x = x_end, y = y_base - 5, life = 1, ctype = 0x10000000 })

		local x_piston = x_base + 30
		local y_piston = y_base + 5
		part({ type = pt.FRME, x = x_piston - 1, y = y_piston     })
		part({ type = pt.FRME, x = x_piston - 1, y = y_piston + 1 })
		part({ type = pt.PSTN, x = x_piston    , y = y_piston    , extend = 1 })
		part({ type = pt.PSTN, x = x_piston + 1, y = y_piston    , extend = 1 })
		part({ type = pt.PSTN, x = x_piston + 2, y = y_piston    , tmp = 3 })
		part({ type = pt.INSL, x = x_piston + 3, y = y_piston     })
		solid_spark(x_piston + 2, y_piston + 1, -1, 0, pt.PSCN, true)
		solid_spark(x_piston + 3, y_piston + 1, -1, 0, pt.NSCN)
		part ({ type = pt.INSL, x = x_piston - 4, y = y_piston + 2 })
		part ({ type = pt.INSL, x = x_piston - 6, y = y_piston - 3 })
		part ({ type = pt.ARAY, x = x_piston - 3, y = y_piston    , life = 1 })
		spark({ type = pt.METL, x = x_piston - 2, y = y_piston     })
		aray(x_piston - 3, y_piston + 1, 1, 0, pt.METL, nil, 1)
		for x = x_piston - 12, x_piston - 5 do
			part({ type = pt.FILT, x = x, y = y_piston    , tmp = 2, ctype = 0x10000000 })
			part({ type = pt.FILT, x = x, y = y_piston + 1, tmp = 2, ctype = 0x10000000 })
		end
		do
			part({ type = pt.CONV, x = x_piston - 12, y = y_piston - 1, tmp = pt.HEAC, ctype = pt.FILT })
			local target = part({ type = pt.HEAC, x = x_piston - 12, y = y_piston - 1 })
			part({ type = pt.HEAC, x = target.x, y = target.y + 3 })
			part({ type = pt.CONV, x = target.x, y = target.y + 4, tmp = pt.PSCN, ctype = pt.SPRK })
			part({ type = pt.LSNS, x = target.x, y = target.y + 4, tmp = 3 })
			part({ type = pt.FILT, x = target.x + 1, y = target.y + 4, ctype = 0x10000003 })
			dray(target.x, target.y + 4, target.x, target.y, 1, false)
			cray(target.x, target.y - 7, target.x, target.y + 5, pt.PSCN, 1, pt.PSCN)
		end
		dray(x_piston - 12, y_base - 3, x_piston - 12, y_piston, 2, pt.PSCN)
		dray(x_piston -  4, y_base - 1, x_piston -  4, y_piston, 2, pt.PSCN)
		part({ type = pt.FILT, x = x_piston -  4, y = y_piston - 5, tmp = 2, ctype = 0x10000000 })
		part({ type = pt.DTEC, x = x_piston -  3, y = y_piston - 6 })
		part({ type = pt.INSL, x = x_piston -  3, y = y_piston - 7 })
		part({ type = pt.BRAY, x = x_piston -  2, y = y_piston - 7 })
		part({ type = pt.FILT, x = x_piston -  4, y = y_piston - 4, tmp = 2, ctype = 0x10000000 })
		do
			local target = part({ type = pt.CRMC, x = x_piston - 14, y = y_piston })
			cray(x_base, target.y, target.x, target.y, pt.CRMC, 2, pt.PSCN)
		end
		part({ type = pt.BRAY, x = x_piston - 14, y = y_piston + 1 })
		part({ type = pt.BRAY, x = x_piston - 13, y = y_piston     })
		part({ type = pt.BRAY, x = x_piston - 13, y = y_piston + 1 })
		part({ type = pt.BRAY, x = x_piston -  4, y = y_piston + 1 })
		part({ type = pt.DTEC, x = x_piston - 15, y = y_piston + 1, tmp2 = 2 })
		do
			local source = part({ type = pt.FILT, x = x_piston - 16, y = y_piston + 2, ctype = 0x10000000 })
			ldtc(x_base + 4, source.y, source.x, source.y)
			part({ type = pt.FILT, x = x_base + 3, y = y_piston + 2, ctype = 0x10000000 })
			part({ type = pt.LDTC, x = x_base + 3, y = y_piston + 1 })
			part({ type = pt.FILT, x = x_base + 3, y = y_piston    , ctype = 0x10000000 })
		end
		part({ type = pt.DTEC, x = x_piston - 14, y = y_piston + 2 })
		do
			local source = part({ type = pt.FILT, x = x_piston - 13, y = y_piston + 2, ctype = 0x10000000 })
			ldtc(x_base + 8, source.y, source.x, source.y)
			part({ type = pt.FILT, x = x_base + 7, y = y_piston + 2, ctype = 0x10000000 })
			part({ type = pt.LDTC, x = x_base + 7, y = y_piston + 1 })
			part({ type = pt.FILT, x = x_base + 7, y = y_piston    , ctype = 0x10000000 })
		end

		for i = 0, last do
			emit_output(i, false, last)
		end
	end
	if params.bits > 16 then
		local last = params.bits - 17
		local func_last = math.max(last, 2)

		aray(x_base + 31, y_base + 8, -1, 0, pt.METL, nil, 1000)
		part({ type = pt.FILT, x = x_base + 32, y = y_base + 8, ctype = 0x10000000 })
		local x_end = x_base + func_last * 2 + 34
		do
			local target = part({ type = pt.BRAY, x = x_end, y = y_base + 8, life = 1000, ctype = 0x10000000 })
			local y_read = y_base + 3
			cray(target.x, y_read - 1, target.x, target.y, pt.SPRK, 1, pt.PSCN)
			ldtc(target.x, y_read - 2, target.x, target.y, -1000)
			aray(target.x + 1, y_read - 4, 1, 0, pt.INST, nil, 1)
			for x = x_base + 30, target.x - 4 do
				part({ type = pt.STOR, x = x, y = y_read - 4, unstack = true })
			end
			part({ type = pt.INSL, x = x_base + 28, y = y_read - 4 })
			part({ type = pt.BRAY, x = x_base + 29, y = y_read - 4 })
			part({ type = pt.DTEC, x = x_base + 28, y = y_read - 2, tmp2 = 2 })
			part({ type = pt.FILT, x = x_base + 27, y = y_read - 2 })
			part({ type = pt.FILT, x = target.x, y = y_read - 3 })
			part({ type = pt.FILT, x = target.x, y = y_read - 4, ctype = 0x10000000 })
			part({ type = pt.STOR, x = x_end - 1, y = y_read - 4 })
			part({ type = pt.STOR, x = x_end - 2, y = y_read - 4 })
			part({ type = pt.LDTC, x = x_end - 2, y = y_read - 5, life = 1, tmp = 1 })
			part({ type = pt.FILT, x = x_end - 3, y = y_read - 4, tmp = 2 })
		end
		dray_log(x_end + 1, y_base + 8, x_end - 1, y_base + 8, func_last * 2 + 1, pt.PSCN)
		cray(x_end + 1, y_base + 8, x_end - 1, y_base + 8, pt.SPRK, func_last * 2 + 1, pt.PSCN)

		aray(x_base + 31, y_base - 4, -1, 0, pt.METL, nil, 1)
		part({ type = pt.FILT, x = x_base + 32, y = y_base - 4, ctype = 0x10000000 })
		dray_log(x_end + 1, y_base - 4, x_end - 1, y_base - 4, func_last * 2 + 1, pt.PSCN)
		cray(x_end + 1, y_base - 4, x_end - 1, y_base - 4, pt.SPRK, func_last * 2 + 1, pt.PSCN)
		part({ type = pt.BRAY, x = x_end, y = y_base - 4, life = 1, ctype = 0x10000000 })

		for i = 0, last do
			emit_output(i + 16, true, last)
		end
	end

	local interface = {
		type = "solid",
		name = "body",
		x    = xoff - 4,
		y    = params.bus.y - 8,
		w    = width + 6,
		h    = 21,
	}
	table.insert(areas, interface)
	table.insert(params.bus.through_areas, interface)

	ucontext.frame(interface.x + 1, interface.y + 1, interface.x + interface.w - 2, interface.y + interface.h - 2, -1, 1, 0xFF00FFFF)

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

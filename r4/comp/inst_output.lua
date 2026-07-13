local bitx        = require("spaghetti.bitx")
local plot        = require("spaghetti.plot")
local check       = require("spaghetti.check")
local filt_output = require("r4.comp.filt_output")

local pt = plot.pt
local peripheral_mask = 0xFFFFFFFF

local function build(params, params_name, component)
	check.integer_range(params_name .. ".bits", params.bits, 1, 32)
	local width = math.max(32, params.bits * 2 + 7)

	local initial_value = 0
	if params.initial_value ~= nil then
		check.integer_range(params_name .. ".initial_value", params.initial_value, 0, 0xFFFFFFFF)
		initial_value = params.initial_value
	end

	local areas = {}

	local xoff
	if params.x.which == "left" then
		xoff = params.x.value
	else
		xoff = params.x.value - width + 1
	end
	local x_base = xoff + 2
	local y_base = params.bus.y

	local peripheral_base = params.base_address

	local parts = {}
	local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
	local cray  = ucontext.cray
	local dray  = ucontext.dray
	local part  = ucontext.part
	local aray  = ucontext.aray
	local ldtc  = ucontext.ldtc
	local spark = ucontext.spark

	local filt_output_parts = filt_output.build_internal({
		x               = xoff + 2,
		debug_stacks    = params.debug_stacks,
		bus             = params.bus,
		peripheral_mask = peripheral_mask,
		peripheral_base = peripheral_base,
		width           = width,
		initial_value   = initial_value,
	})
	plot.merge_parts(0, 0, parts, filt_output_parts)

	local function emit_output(index, shift, last)
		local b = index
		if shift then
			b = b - 16
		end
		local x_output = x_base + 3 + index * 2
		local y_shift = shift and 1 or 0

		aray(x_output, y_base + 8 - y_shift, 0, -1, pt.METL, nil, 1)
		part({ type = pt.FILT, x = x_output    , y = y_base +  9 - y_shift, ctype = 0x10000000 })
		part({ type = pt.FILT, x = x_output    , y = y_base + 10, tmp = 1, ctype = bitx.lshift(1, b) })
		part({ type = pt.PSCN, x = x_output    , y = y_base + 11, dcolour = 0xFF7F7F00 })
		part({ type = pt.INST, x = x_output    , y = y_base + 12, dcolour = 0xFF7F7F00 })
		if b < last then
			part({ type = pt.FILT, x = x_output + 1, y = y_base +  9 - y_shift, ctype = 0x10000000 })
		end
		if b < last or (not shift and params.bits >= 16) then
			part({ type = pt.INSL, x = x_output + 1, y = y_base + 11, dcolour = 0xFFFFFFFF })
			part({ type = pt.INSL, x = x_output + 1, y = y_base + 12, dcolour = 0xFFFFFFFF })
		end
		if shift then
			part({ type = pt.STOR, x = x_output, y = y_base + 9 })
		else
			part({ type = pt.STOR, x = x_output, y = y_base + 8, z = 20000000 })
		end

		aray(x_output, y_base - 4 + y_shift, 0, 1, pt.METL, nil, 1000)
		part({ type = pt.FILT, x = x_output    , y = y_base - 5 + y_shift, ctype = 0x10000000 })
		part({ type = pt.FILT, x = x_output    , y = y_base - 6, tmp = 1, ctype = bitx.lshift(1, b) })
		part({ type = pt.PSCN, x = x_output    , y = y_base - 7, dcolour = 0xFF7F7F00 })
		part({ type = pt.INST, x = x_output    , y = y_base - 8, dcolour = 0xFF7F7F00 })
		if b < last then
			part({ type = pt.FILT, x = x_output + 1, y = y_base - 5 + y_shift, ctype = 0x10000000 })
		end
		if b < last or (not shift and params.bits >= 16) then
			part({ type = pt.INSL, x = x_output + 1, y = y_base - 7, dcolour = 0xFFFFFFFF })
			part({ type = pt.INSL, x = x_output + 1, y = y_base - 8, dcolour = 0xFFFFFFFF })
		end
		if shift then
			part({ type = pt.STOR, x = x_output, y = y_base - 5 })
		else
			part({ type = pt.STOR, x = x_output, y = y_base - 4, z = 20000000 })
		end
	end
	for x = -2, -1 do
		for y = 0, 4 do
			local p = part({ type = pt.FILT, x = x_base + x, y = y_base + y })
		end
	end
	part({ type = pt.DTEC, x = x_base + 1, y = y_base + 9 })
	part({ type = pt.INSL, x = x_base + 1, y = y_base + 8 })
	part({ type = pt.FILT, x = x_base + 2, y = y_base + 9 })
	for x = x_base + 3, x_base + 19 do
		part({ type = pt.STOR, x = x, y = y_base + 8, unstack = true })
	end
	part ({ type = pt.DTEC, x = x_base +  1, y = y_base - 5 })
	part ({ type = pt.INSL, x = x_base +  1, y = y_base - 4 })
	part ({ type = pt.FILT, x = x_base +  2, y = y_base - 5 })
	dray(x_base + 2, y_base - 3, x_base + 2, y_base - 6, 1, pt.PSCN)
	cray(x_base + 2, y_base - 3, x_base + 2, y_base - 4, pt.SPRK, 1, pt.PSCN)
	part({ type = pt.CONV, x = x_base + 4, y = y_base - 2, tmp = pt.SPRK, ctype = pt.METL })
	part({ type = pt.CONV, x = x_base + 4, y = y_base - 2, tmp = pt.METL, ctype = pt.SPRK })

	part ({ type = pt.BRAY, x = x_base +  2, y = y_base - 6, life = 1000, ctype = 0x10000000 })
	part ({ type = pt.BRAY, x = x_base +  2, y = y_base + 8 })
	if params.bits > 9 then
		spark({ type = pt.METL, x = x_base + 22, y = y_base - 4 })
		spark({ type = pt.METL, x = x_base + 22, y = y_base + 8 })
	else
		aray(x_base + 21, y_base - 4, 1, 0, pt.METL, nil, 1000)
		aray(x_base + 21, y_base + 8, 1, 0, pt.METL, nil, 1)
	end
	for x = x_base + 3, x_base + 19 do
		part({ type = pt.STOR, x = x, y = y_base - 4, unstack = true })
	end

	do
		local last = math.min(params.bits, 16) - 1
		for i = 0, last do
			emit_output(i, false, last)
		end
	end
	if params.bits > 16 then
		part({ type = pt.LDTC, x = x_base + 34, y = y_base - 4, tmp = 1, life = 7 })
		part({ type = pt.LDTC, x = x_base + 34, y = y_base + 8 })
		part({ type = pt.FILT, x = x_base + 26, y = y_base - 4, ctype = 0x10000000 })
		part({ type = pt.LDTC, x = x_base + 27, y = y_base - 4, tmp = 1 })
		part({ type = pt.LDTC, x = x_base + 27, y = y_base - 4, tmp = 1, life = 2 })
		part({ type = pt.FILT, x = x_base + 28, y = y_base - 4, ctype = 0x10000000 })
		local last = params.bits - 17
		for i = 0, last do
			emit_output(i + 16, true, last)
		end
	end

	local interface = {
		type = "solid",
		name = "body",
		x    = xoff,
		y    = params.bus.y - 8,
		w    = width + 2,
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

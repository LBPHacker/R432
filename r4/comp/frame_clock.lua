local bitx       = require("spaghetti.bitx")
local plot       = require("spaghetti.plot")
local check      = require("spaghetti.check")
local filt_input = require("r4.comp.filt_input")

local pt = plot.pt
local peripheral_mask = 0xFFFFFFFF

local function build(params, params_name, component)
	local width = 28
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
	local cray   = ucontext.cray
	local part   = ucontext.part
	local aray   = ucontext.aray
	local ldtc   = ucontext.ldtc
	local mutate = ucontext.mutate

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

	do
		local x_incr = x_base - 1
		local y_incr = y_base - 2

		aray(x_incr, y_incr, -1, 0, pt.METL)
		local function emit_incr(x, initial, material_decr)
			local decr = { x = x + 10, y = y_incr }
			if material_decr then
				part(mutate(decr, { type = pt.BRAY }))
			end
			local underflow = { x = x + 14, y = y_incr }
			part({ type = pt.FILT, x = x +  1, y = y_incr, ctype = 0x3FFFFFFE })
			part({ type = pt.STOR, x = x +  2, y = y_incr })
			part({ type = pt.FILT, x = x +  3, y = y_incr, tmp = 10, ctype = initial })
			ldtc(x + 4, y_incr, decr.x, decr.y, nil, 1)
			ldtc(x + 4, y_incr, underflow.x, underflow.y, nil, 1)
			part({ type = pt.STOR, x = x +  4, y = y_incr })
			part({ type = pt.STOR, x = x +  5, y = y_incr })
			part({ type = pt.FILT, x = x +  6, y = y_incr, tmp =  7, ctype = 0x3FFFFFFF })
			part({ type = pt.STOR, x = x +  7, y = y_incr })
			part({ type = pt.FILT, x = x +  8, y = y_incr, tmp =  7, ctype = initial })
			ldtc(x + 9, y_incr, decr.x, decr.y, nil, 1)
			ldtc(x + 9, y_incr, underflow.x, underflow.y, nil, 1)
			part({ type = pt.STOR, x = x +  9, y = y_incr })
			part({ type = pt.FILT, x = x + 11, y = y_incr, tmp = 7, ctype = 0x10000 })
			part({ type = pt.FILT, x = x + 12, y = y_incr, tmp = 1, ctype = 0x10000 })
			part({ type = pt.FILT, x = x + 13, y = y_incr, ctype = 0x1001FFFF })
			return decr, underflow
		end
		local decr_1, underflow_1 = emit_incr(x_incr     , 0x1001BEEF, true)
		local decr_2, underflow_2 = emit_incr(x_incr + 14, 0x1001DEAD, false)
		cray(underflow_1.x - 7, y_base + 5, underflow_1.x,  underflow_1.y, pt.SPRK, 1, pt.PSCN)
		cray(     decr_2.x    , y_base + 5,      decr_2.x,       decr_2.y, pt.SPRK, 1, pt.PSCN)
		cray(underflow_2.x    , y_base + 5, underflow_2.x,  underflow_2.y, pt.SPRK, 1, pt.PSCN)
		part({ type = pt.FILT, x = x_base + 3, y = y_base + 5 })
		part({ type = pt.FILT, x = x_base + 3, y = y_base + 6 })
		part({ type = pt.DTEC, x = x_base + 3, y = y_base + 7 })
		part({ type = pt.FILT, x = x_base + 7, y = y_base + 5 })
		part({ type = pt.FILT, x = x_base + 7, y = y_base + 6 })
		part({ type = pt.BRAY, x = x_base + 8, y = y_base + 6 })
		part({ type = pt.DTEC, x = x_base + 7, y = y_base + 7 })
		part({ type = pt.DMND, x = x_base + 6, y = y_base + 6 })
		part({ type = pt.DMND, x = x_base + 5, y = y_base + 7 })
		part({ type = pt.BRAY, x = x_base + 4, y = y_base + 7 })
		part({ type = pt.STOR, x = x_base + 3, y = y_base + 7 })
		ldtc(x_base + 2, y_base + 6, x_base + 2, y_base - 2)
		part({ type = pt.FILT, x = x_base + 2, y = y_base + 7, tmp = 7 })
		part({ type = pt.STOR, x = x_base + 1, y = y_base + 7 })
		part({ type = pt.FILT, x = x_base    , y = y_base + 7, ctype = 0x1FFFF })
		aray(x_base - 1, y_base + 7, -1, 0, pt.METL)
		for x = x_base + 9, x_base + 19 do
			part({ type = pt.STOR, x = x, y = y_base + 6, unstack = true })
		end
		part({ type = pt.FILT, x = x_base + 17, y = y_base + 6, tmp = 7, ctype = 0x1FFFF })
		do
			local source = part({ type = pt.FILT, x = x_base + 24, y = y_base + 1 })
			ldtc(x_base + 20, y_base + 5, source.x, source.y)
			ldtc(source.x - 1, source.y - 1, source.x - 3, source.y - 3)
		end
		part({ type = pt.FILT, x = x_base + 19, y = y_base + 6 })
		aray(x_base + 20, y_base + 6, 1, 0, pt.INST)
	end

	local interface = {
		type = "solid",
		name = "body",
		x    = xoff - 4,
		y    = params.bus.y - 5,
		w    = width + 6,
		h    = 15,
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

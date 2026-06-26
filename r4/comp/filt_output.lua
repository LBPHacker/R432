local bitx     = require("spaghetti.bitx")
local plot     = require("spaghetti.plot")
local check    = require("spaghetti.check")

local pt = plot.pt
local peripheral_mask = 0xFFFFFFFF

local function build_internal(params)
	local width = params.width

	local parts = {}
	local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
	local cray  = ucontext.cray
	local dray  = ucontext.dray
	local part  = ucontext.part
	local aray  = ucontext.aray
	local ldtc  = ucontext.ldtc
	local spark = ucontext.spark

	local x = params.x
	local y = params.bus.y

	local y_bottom = y + 6
	do
		local x_top = x + 2
		local y_top = y

		local bus_0_in, bus_1_in, bus_2_in
		for x = -2, -1 do
			for y = 0, 4 do
				local p = part({ type = pt.FILT, x = x_top + x, y = y_top + y })
				local do_ldtc = false
				if x == -1 then
					if y == 0 then
						bus_0_in = p
						do_ldtc = true
					end
					if y == 1 then
						bus_1_in = p
						do_ldtc = true
					end
					if y == 2 then
						bus_2_in = p
						do_ldtc = true
					end
				end
				if do_ldtc then
					local q = ldtc(x_top - x + width - 5, y_top + y, p.x, p.y)
					q.dcolour = 0xFF007F7F
				else
					part({ type = pt.FILT, x = x_top - x + width - 5, y = y_top + y })
				end
			end
		end
		for x = 0, width - 5 do
			part({ type = pt.FILT, x = x_top + x, y = y_top + 3, unstack = true })
			part({ type = pt.FILT, x = x_top + x, y = y_top + 4, unstack = true })
		end

		ldtc(x_top + 2, y_top, bus_0_in.x, bus_0_in.y)
		aray(x_top + 2, y_top, -1, 0, pt.METL, nil, 1)

		part({ type = pt.FILT, x = x_top +  3, y = y_top })
		part({ type = pt.BRAY, x = x_top +  4, y = y_top, life = 1 })
		part({ type = pt.FILT, x = x_top +  5, y = y_top, tmp = 1, ctype = bitx.bor(0x13000000, bitx.band(params.peripheral_mask, 0xFFFFFF)) })
		part({ type = pt.STOR, x = x_top +  6, y = y_top })
		part({ type = pt.DTEC, x = x_top +  7, y = y_top, tmp2 = 3 })
		part({ type = pt.STOR, x = x_top +  7, y = y_top })
		part({ type = pt.STOR, x = x_top +  8, y = y_top })
		part({ type = pt.FILT, x = x_top +  9, y = y_top, tmp = 7, ctype = bitx.bor(0x22000000, bitx.band(params.peripheral_base, 0xFFFFFF)) })
		part({ type = pt.BRAY, x = x_top + 10, y = y_top, life = 1 })
		part({ type = pt.DMND, x = x_top + 11, y = y_top })

		ldtc(x_top + 1, y_top + 1, bus_1_in.x, bus_1_in.y)
		aray(x_top + 1, y_top + 1, -1, 0, pt.METL, nil, 1)

		part ({ type = pt.FILT, x = x_top +  2, y = y_top + 1 })
		part ({ type = pt.BRAY, x = x_top +  3, y = y_top + 1, life = 1 })
		part ({ type = pt.FILT, x = x_top +  4, y = y_top + 1, tmp = 1, ctype = bitx.bor(0x13000000, bitx.band(bitx.rshift(params.peripheral_mask, 8), 0xFF0000)) })
		part ({ type = pt.FILT, x = x_top +  5, y = y_top + 1, tmp = 7, ctype = bitx.bor(0x22000000, bitx.band(bitx.rshift(params.peripheral_base, 8), 0xFF0000)) })
		part ({ type = pt.STOR, x = x_top +  6, y = y_top + 1 })
		part ({ type = pt.FILT, x = x_top +  7, y = y_top + 1, tmp = 2 })
		part ({ type = pt.STOR, x = x_top +  8, y = y_top + 1 })
		part ({ type = pt.FILT, x = x_top +  9, y = y_top + 1, tmp = 1, ctype = 0x07FFFFFF })
		part ({ type = pt.FILT, x = x_top + 10, y = y_top + 1, ctype = 0x10000004 })
		part ({ type = pt.BRAY, x = x_top + 14, y = y_top, ctype = 0x10000003, life = 1000 })
		part ({ type = pt.DTEC, x = x_top + 13, y = y_top + 1 })
		part ({ type = pt.LDTC, x = x_top + 13, y = y_top + 1, tmp = 1, life = 1 })
		aray(x_top + 13, y_top + 1, -1, 0, pt.METL, nil, 1)
		part ({ type = pt.FILT, x = x_top + 14, y = y_top + 1 })
		part ({ type = pt.DTEC, x = x_top + 15, y = y_top + 1 })
		part ({ type = pt.LSNS, x = x_top + 15, y = y_top + 1, tmp = 3 })
		cray(x_top + 15, y_top + 1, x_top + 13, y_top + 3, pt.DTEC, 1, false)
		cray(x_top + 15, y_top + 1, x_top + 13, y_top + 3, pt.DTEC, 1, false)
		part ({ type = pt.STOR, x = x_top + 15, y = y_top + 1 })
		part ({ type = pt.DMND, x = x_top + 13, y = y_top     })
		part ({ type = pt.DMND, x = x_top + 12, y = y_top     })
		spark({ type = pt.PSCN, x = x_top + 16, y = y_top     })
		part ({ type = pt.CONV, x = x_top + 13, y = y_top + 3, tmp = pt.INSL, ctype = pt.FILT })
		part ({ type = pt.INSL, x = x_top + 13, y = y_top + 3 })
		part ({ type = pt.CONV, x = x_top + 11, y = y_top + 5, tmp = pt.FILT, ctype = pt.INSL })
		dray(x_top + 11, y_top + 5, x_top + 13, y_top + 3, 1, pt.PSCN)
		part ({ type = pt.CONV, x = x_top + 11, y = y_top + 5, tmp = pt.INSL, ctype = pt.FILT })
		part ({ type = pt.BRAY, x = x_top + 14, y = y_top + 5, ctype = 0x1001FFFF, life = 1000 })
		part ({ type = pt.LSNS, x = x_top + 13, y = y_top + 5, tmp = 3 })
		part ({ type = pt.FILT, x = x_top + 14, y = y_top + 6, ctype = 0x10001000 })

		do
			local target = part({ type = pt.BRAY, x = x_top + 16, y = y_top + 1, life = 3 })
			cray(target.x + 2, target.y - 2, target.x, target.y, pt.SPRK, 1, pt.PSCN)
		end
		do
			local target = { x = x_top + 17, y = y_top + 1 }
			dray(x_top + 1, target.y, target.x, target.y, 1, pt.METL)
			dray(x_top + 22, target.y, target.x, target.y, 1, pt.PSCN)
		end
		part({ type = pt.FILT, x = x_top + 18, y = y_top + 1, tmp = 1, ctype = 0x1000FFFF })
		part({ type = pt.BRAY, x = x_top + 19, y = y_top + 1 })
		part({ type = pt.DTEC, x = x_top + 20, y = y_top + 1 })
		part({ type = pt.DMND, x = x_top + 20, y = y_top + 1 })
		part({ type = pt.FILT, x = x_top + 19, y = y_top + 2 })

		part ({ type = pt.FILT, x = x_top + 16, y = y_top + 2 })
		part ({ type = pt.FILT, x = x_top + 17, y = y_top + 2, tmp = 1, ctype = 1 })
		part ({ type = pt.STOR, x = x_top + 18, y = y_top + 2 })
		part ({ type = pt.DTEC, x = x_top + 21, y = y_top + 2 })
		part ({ type = pt.DTEC, x = x_top + 25, y = y_top + 2 })
		local initial_value_lo = bitx.bor(0x10000000, bitx.band(            params.initial_value     , 0xFFFF))
		local initial_value_hi = bitx.bor(0x10000000, bitx.band(bitx.rshift(params.initial_value, 16), 0xFFFF))
		local data_lo = part({ type = pt.FILT, x = x_top + 18, y = y_top + 5, ctype = initial_value_lo })
		local data_hi = part({ type = pt.FILT, x = x_top + 22, y = y_top + 5, ctype = initial_value_hi })
		part ({ type = pt.STOR, x = x_top + 21, y = y_top + 2 })
		part ({ type = pt.STOR, x = x_top + 22, y = y_top + 2 })
		part ({ type = pt.DMND, x = x_top + 24, y = y_top + 1 })
		part ({ type = pt.STOR, x = x_top + 13, y = y_top + 2 })
		part ({ type = pt.STOR, x = x_top + 14, y = y_top + 2 })
		part ({ type = pt.FILT, x = x_top + 15, y = y_top + 2 })
		aray(x_top + 12, y_top + 2, -1, 0, pt.METL, nil, 1)
		cray(x_top + 20, y_top + 5, x_top + 20, y_top + 2, pt.SPRK, 1, pt.PSCN)
		cray(x_top + 24, y_top + 5, x_top + 24, y_top + 2, pt.SPRK, 1, pt.PSCN)
		part ({ type = pt.DMND, x = x_top + 12, y = y_top + 5 })

		ldtc(x_top + 7, bus_2_in.y, bus_2_in.x, bus_2_in.y)
		do
			local target = part({ type = pt.FILT, x = x_top + 23, y = y_top + 2 })
			dray(x_top + 7, y_top + 2, target.x, target.y, 1, pt.PSCN)
		end
		part({ type = pt.FILT, x = x_top + 8, y = y_top + 2 })

		part({ type = pt.FILT, x = data_lo.x, y = y_top - 4, ctype = initial_value_lo })
		do
			local p = ldtc(data_lo.x, y_top - 3, data_lo.x, data_lo.y)
			p.dcolour = 0xFF007F7F
		end
		part({ type = pt.FILT, x = data_lo.x, y = y_top + 8, ctype = initial_value_lo })
		do
			local p = ldtc(data_lo.x, y_top + 7, data_lo.x, data_lo.y)
			p.dcolour = 0xFF007F7F
		end
		part({ type = pt.FILT, x = data_hi.x, y = y_top - 4, ctype = initial_value_hi })
		do
			local p = ldtc(data_hi.x, y_top - 3, data_hi.x, data_hi.y)
			p.dcolour = 0xFF007F7F
		end
		part({ type = pt.FILT, x = data_hi.x, y = y_top + 8, ctype = initial_value_hi })
		do
			local p = ldtc(data_hi.x, y_top + 7, data_hi.x, data_hi.y)
			p.dcolour = 0xFF007F7F
		end

		cray(x_top + 7, y_bottom - 1, x_top + 11, y_top + 1, pt.SPRK, 1, pt.PSCN)
	end

	return parts
end

local function build(params, params_name, component)
	local areas = {}

	local initial_value = 0
	if params.initial_value ~= nil then
		check.integer_range(params_name .. ".initial_value", params.initial_value, 0, 0xFFFFFFFF)
		initial_value = params.initial_value
	end

	local xoff
	if params.x.which == "left" then
		xoff = params.x.value
	else
		xoff = params.x.value - width + 1
	end

	local peripheral_base = params.base_address

	local parts = {}
	local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)

	local width = 30
	local internal_parts = build_internal({
		x               = xoff,
		debug_stacks    = params.debug_stacks,
		bus             = params.bus,
		peripheral_mask = peripheral_mask,
		peripheral_base = peripheral_base,
		width           = width,
		initial_value   = initial_value,
	})
	plot.merge_parts(0, 0, parts, internal_parts)

	local interface = {
		type = "solid",
		name = "body",
		x    = xoff,
		y    = params.bus.y - 4,
		w    = width,
		h    = 13,
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
	build          = build,
	param_types    = param_types,
	build_internal = build_internal,
}

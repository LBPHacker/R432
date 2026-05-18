local bitx = require("spaghetti.bitx")
local plot = require("spaghetti.plot")

local pt = plot.pt

local function build(params)
	local ucontext = plot.common_structures(params.parts, params.debug_stacks and true or false)
	local cray  = ucontext.cray
	local dray  = ucontext.dray
	local part  = ucontext.part
	local aray  = ucontext.aray
	local ldtc  = ucontext.ldtc
	local spark = ucontext.spark

	local x = params.x
	local y = params.bus.y
	local width = 30

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
		part({ type = pt.FILT, x = x_top +  5, y = y_top, tmp = 1, ctype = bitx.bor(0x13000000, bitx.band(params.tap_mask, 0xFFFFFF)) })
		part({ type = pt.STOR, x = x_top +  6, y = y_top })
		part({ type = pt.DTEC, x = x_top +  7, y = y_top, tmp2 = 3 })
		part({ type = pt.STOR, x = x_top +  7, y = y_top })
		part({ type = pt.STOR, x = x_top +  8, y = y_top })
		part({ type = pt.FILT, x = x_top +  9, y = y_top, tmp = 7, ctype = bitx.bor(0x22000000, bitx.band(params.tap_base, 0xFFFFFF)) })
		part({ type = pt.BRAY, x = x_top + 10, y = y_top, life = 1 })
		part({ type = pt.DMND, x = x_top + 11, y = y_top })

		ldtc(x_top + 1, y_top + 1, bus_1_in.x, bus_1_in.y)
		aray(x_top + 1, y_top + 1, -1, 0, pt.METL, nil, 1)

		part ({ type = pt.FILT, x = x_top +  2, y = y_top + 1 })
		part ({ type = pt.BRAY, x = x_top +  3, y = y_top + 1, life = 1 })
		part ({ type = pt.FILT, x = x_top +  4, y = y_top + 1, tmp = 1, ctype = bitx.bor(0x13000000, bitx.band(bitx.rshift(params.tap_mask, 8), 0xFF0000)) })
		part ({ type = pt.FILT, x = x_top +  5, y = y_top + 1, tmp = 7, ctype = bitx.bor(0x22000000, bitx.band(bitx.rshift(params.tap_base, 8), 0xFF0000)) })
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
		part ({ type = pt.LSNS, x = x_top + 15, y = y_top + 1, tmp = 3 })
		cray(x_top + 15, y_top + 1, x_top + 13, y_top + 3, pt.DTEC, 1, false)
		cray(x_top + 15, y_top + 1, x_top + 13, y_top + 3, pt.DTEC, 1, false)
		part ({ type = pt.STOR, x = x_top + 15, y = y_top + 1 })
		part ({ type = pt.DMND, x = x_top + 13, y = y_top     })
		spark({ type = pt.PSCN, x = x_top + 16, y = y_top     })
		part ({ type = pt.CONV, x = x_top + 13, y = y_top + 3, tmp = pt.INSL, ctype = pt.FILT })
		part ({ type = pt.INSL, x = x_top + 13, y = y_top + 3 })
		part ({ type = pt.CONV, x = x_top + 11, y = y_top + 5, tmp = pt.FILT, ctype = pt.INSL })
		dray(x_top + 11, y_top + 5, x_top + 13, y_top + 3, 1, pt.PSCN)
		part ({ type = pt.CONV, x = x_top + 11, y = y_top + 5, tmp = pt.INSL, ctype = pt.FILT })
		part ({ type = pt.BRAY, x = x_top + 14, y = y_top + 5, ctype = 0x1001FFFF, life = 1000 })
		part ({ type = pt.LSNS, x = x_top + 14, y = y_top + 6, tmp = 3 })
		part ({ type = pt.FILT, x = x_top + 13, y = y_top + 6, ctype = 0x10001000 })

		part({ type = pt.DTEC, x = x_top + 17, y = y_top + 1 })
		for y = y_top - 4, y_top do
			part({ type = pt.FILT, x = x_top + 17, y = y })
		end
		part({ type = pt.CONV, x = x_top + 18, y = y_top + 1, tmp = pt.BRAY, ctype = pt.FILT })
		part({ type = pt.DTEC, x = x_top + 18, y = y_top })
		do
			local target = { x = x_top + 19, y = y_top }
			dray(x_top + 2, target.y, target.x - 1, target.y, 2, pt.METL)
		end
		for y = y_top - 4, y_top - 1 do
			part({ type = pt.FILT, x = x_top + 18, y = y })
		end
		part({ type = pt.CONV, x = x_top + 20, y = y_top + 2, tmp = pt.BRAY, ctype = pt.FILT })
		part({ type = pt.DTEC, x = x_top + 19, y = y_top + 1 })
		do
			local target = { x = x_top + 20, y = y_top + 1 }
			dray(x_top + 1, target.y, target.x - 1, target.y, 2, pt.METL)
		end
		for y = y_top - 4, y_top - 1 do
			part({ type = pt.FILT, x = x_top + 19, y = y })
		end
		part({ type = pt.DTEC, x = x_top + 20, y = y_top + 2, tmp2 = 2 })
		for y = y_top - 4, y_top do
			part({ type = pt.FILT, x = x_top + 20, y = y })
		end
		part({ type = pt.FILT, x = x_top +  8, y = y_top + 2 })
		part({ type = pt.BRAY, x = x_top +  9, y = y_top + 2 })
		part({ type = pt.INSL, x = x_top + 10, y = y_top + 2 })
		part({ type = pt.HEAC, x = x_top + 14, y = y_top + 2 })
		do
			local target = part({ type = pt.STOR, x = x_top + 16, y = y_top + 2 })
			local source = part({ type = pt.FILT, x = x_top +  5, y = y_top + 2, ctype = 0x1002FFFF })
			dray(source.x - 1, source.y, target.x, target.y, 1, pt.PSCN)
		end
		part({ type = pt.STOR, x = x_top + 17, y = y_top + 2 })
		part({ type = pt.BRAY, x = x_top + 18, y = y_top + 2 })
		part({ type = pt.STOR, x = x_top + 19, y = y_top + 2 })
		part({ type = pt.STOR, x = x_top + 20, y = y_top + 2 })
		part({ type = pt.STOR, x = x_top + 21, y = y_top + 2 })
		ldtc(x_top + 7, y_top + 2, bus_2_in.x, bus_2_in.y)
		aray(x_top + 7, y_top + 2, -1, 0, pt.METL, nil, 1)
		do
			local target = { x = x_top + 18, y = y_top + 2 }
			dray(x_top + 7, target.y, target.x - 1, target.y, 2, pt.METL)
		end
		for y = y_top - 4, y_top - 1 do
			part({ type = pt.FILT, x = x_top + 21, y = y })
		end
		part({ type = pt.LDTC, x = x_top + 23, y = y_top - 1 })
		part({ type = pt.FILT, x = x_top + 24, y = y_top - 1 })
		part({ type = pt.FILT, x = x_top + 25, y = y_top - 1 })
		part({ type = pt.LDTC, x = x_top + 24, y = y_top     })
		part({ type = pt.FILT, x = x_top + 23, y = y_top + 1 })
		part({ type = pt.FILT, x = x_top + 22, y = y_top + 2, tmp = 1 })
		part({ type = pt.FILT, x = x_top + 23, y = y_top + 2, ctype = 0x10000 })
		aray(x_top + 24, y_top + 2, 1, 0, pt.INST, nil, 1)
		aray(x_top + 24, y_top + 2, 1, 0, pt.INST, nil, 1)

		part({ type = pt.CONV, x = x_top + 24, y = y_top + 5, ctype = pt.INSL, tmp = pt.FILT })
		dray(x_top + 24, y_top + 5, x_top + 20, y_top + 1, 1, pt.PSCN)
		dray(x_top + 24, y_top + 5, x_top + 19, y_top    , 1, pt.PSCN)
		cray(x_top + 24, y_top + 5, x_top + 20, y_top + 1, pt.SPRK, 2, pt.PSCN)
		part({ type = pt.CONV, x = x_top + 24, y = y_top + 5, ctype = pt.FILT, tmp = pt.INSL })

		part({ type = pt.CONV, x = x_top + 16, y = y_top + 5, ctype = pt.STOR, tmp = pt.FILT })
		dray(x_top + 16, y_top + 5, x_top + 16, y_top + 2, 1, pt.PSCN)
		part({ type = pt.CONV, x = x_top + 16, y = y_top + 5, ctype = pt.FILT, tmp = pt.STOR })
		cray(x_top + 16, y_top + 5, x_top + 16, y_top + 1, pt.SPRK, 1, pt.PSCN)

		cray(x_top + 7, y_bottom - 1, x_top + 11, y_top + 1, pt.SPRK, 1, pt.PSCN)
		cray(x_top + 18, y_bottom - 1, x_top + 15, y_top + 2, pt.SPRK, 1, pt.PSCN)
	end

	local interface = {
		type = "solid",
		name = params.area_name,
		x    = params.x,
		y    = params.bus.y - 4,
		w    = width,
		h    = 13,
	}
	table.insert(params.areas, interface)
	table.insert(params.bus.through_areas, interface)

	ucontext.frame(interface.x + 1, interface.y + 1, interface.x + interface.w - 2, interface.y + interface.h - 2, -1, 1, 0xFF00FFFF)
end

return {
	build = build,
}

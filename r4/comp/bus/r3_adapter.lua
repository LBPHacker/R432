local bitx            = require("spaghetti.bitx")
local plot            = require("spaghetti.plot")
local misc            = require("spaghetti.misc")
local check           = require("spaghetti.check")
local r4_check        = require("r4.check")
local bus_termination = require("r4.comp.bus.termination")

local pt = plot.pt

local function build(params, params_name, component)
	local memory_base = params.bus_0.cpu.memory_base
	local memory_mask = params.bus_0.cpu.memory_mask

	local adapter_base = params.base_address
	local adapter_mask = 0xFFFC0000
	r4_check.base_address(params_name .. ".base_address", params.base_address, adapter_mask)
	local areas = {}

	if params.bus_0.cpu ~= params.bus_1.cpu or
	   params.bus_0.y + 16 ~= params.bus_1.y then
		misc.user_error(("%s.bus_0 and %s.bus_1 must be consecutive buses of the same CPU, in this order"):format(params_name, params_name))
	end

	local parts = {}
	local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
	local part        = ucontext.part
	local aray        = ucontext.aray
	local dray        = ucontext.dray
	local cray        = ucontext.cray
	local ldtc        = ucontext.ldtc

	local width = 35
	local height = 25

	for x = width - 2, width - 1 do
		for y = 8, 11 do
			part({ type = pt.FILT, x = x, y = y })
		end
	end

	do
		local termination_0_parts = {}
		part({ type = pt.FILT, x = 0, y = 2 })
		part({ type = pt.FILT, x = 1, y = 2 })
		part({ type = pt.FILT, x = 2, y = 2 })
		part({ type = pt.FILT, x = 0, y = 3 })
		part({ type = pt.FILT, x = 0, y = 4 })
		bus_termination.build_internal(termination_0_parts, {
			debug_stacks = params.debug_stacks,
			memory_base  = memory_base,
			memory_mask  = memory_mask,
		})
		plot.merge_parts(1, 0, parts, termination_0_parts)
	end
	do
		part({ type = pt.INSL, x = 16, y = 17 })
		part({ type = pt.DMND, x = 15, y = 16, z = 2 })
		local termination_1_parts = {}
		bus_termination.build_internal(termination_1_parts, {
			debug_stacks = params.debug_stacks,
			memory_base  = memory_base,
			memory_mask  = memory_mask,
		})
		plot.merge_parts(0, 16, parts, termination_1_parts)
	end
	for x = -2, -1 do
		for y = 0, 4 do
			part({ type = pt.FILT, x = x, y = y })
			part({ type = pt.FILT, x = x, y = y + 16 })
		end
	end

	do
		local x_top = 17
		local y_top = 0

		ldtc(x_top + 2, y_top, -1, y_top)
		aray(x_top + 2, y_top, -1, 0, pt.METL, nil, 1)

		part({ type = pt.FILT, x = x_top +  3, y = y_top })
		part({ type = pt.BRAY, x = x_top +  4, y = y_top, life = 1 })
		part({ type = pt.FILT, x = x_top +  5, y = y_top, tmp = 1, ctype = bitx.bor(0x10000000, bitx.band(adapter_mask, 0xFFFFFF)) })
		part({ type = pt.STOR, x = x_top +  6, y = y_top })
		part({ type = pt.DTEC, x = x_top +  7, y = y_top, tmp2 = 3 })
		part({ type = pt.STOR, x = x_top +  7, y = y_top })
		part({ type = pt.STOR, x = x_top +  8, y = y_top })
		part({ type = pt.FILT, x = x_top +  9, y = y_top, tmp = 7, ctype = bitx.bor(0x20000000, bitx.band(adapter_base, 0xFFFFFF)) })
		part({ type = pt.BRAY, x = x_top + 10, y = y_top, life = 1 })
		part({ type = pt.DMND, x = x_top + 11, y = y_top })

		ldtc(x_top + 1, y_top + 1, -1, y_top + 1)
		aray(x_top + 1, y_top + 1, -1, 0, pt.METL, nil, 1)

		part({ type = pt.FILT, x = x_top +  2, y = y_top + 1 })
		part({ type = pt.BRAY, x = x_top +  3, y = y_top + 1, life = 1 })
		part({ type = pt.FILT, x = x_top +  4, y = y_top + 1, tmp = 1, ctype = bitx.bor(0x10000000, bitx.band(bitx.rshift(adapter_mask, 8), 0xFF0000)) })
		part({ type = pt.FILT, x = x_top +  5, y = y_top + 1, tmp = 7, ctype = bitx.bor(0x20000000, bitx.band(bitx.rshift(adapter_base, 8), 0xFF0000)) })
		part({ type = pt.STOR, x = x_top +  6, y = y_top + 1 })
		part({ type = pt.FILT, x = x_top +  7, y = y_top + 1, tmp = 2 })
		part({ type = pt.STOR, x = x_top +  8, y = y_top + 1 })
		part({ type = pt.FILT, x = x_top +  9, y = y_top + 1, tmp = 1, ctype = 0xFFFFFF })
		part({ type = pt.STOR, x = x_top + 10, y = y_top + 1 })
		part({ type = pt.FILT, x = x_top + 11, y = y_top + 1, ctype = 0x10000000 })
		part({ type = pt.INSL, x = x_top + 13, y = y_top + 1 })
		part({ type = pt.FILT, x = x_top + 13, y = y_top, ctype = 0x10000001 })

		cray(x_top + 12, 19, x_top + 12, y_top + 1, pt.SPRK, 1, pt.PSCN)
	end

	do
		local x_r3_0 = 19
		local y_r3_0 = 3

		local source_1 = { x = x_r3_0 + 5, y = y_r3_0 }
		local source_2 = { x = x_r3_0 + 9, y = y_r3_0 }
		dray(x_r3_0, y_r3_0, source_1.x, source_1.y, 1, pt.METL)
		dray(x_r3_0, y_r3_0, source_2.x, source_2.y, 1, pt.METL)
		aray(x_r3_0, y_r3_0, -1, 0, pt.METL, nil, 1)
		part({ type = pt.LDTC, x = x_r3_0 +  1, y = y_r3_0 - 1, life = 1, tmp = 1 })
		part({ type = pt.FILT, x = x_r3_0 +  1, y = y_r3_0 })
		part({ type = pt.FILT, x = x_r3_0 +  2, y = y_r3_0, tmp = 11, ctype = 4 })
		part({ type = pt.FILT, x = x_r3_0 +  3, y = y_r3_0, tmp =  1, ctype = 0x0400FFFF })
		part({ type = pt.BRAY, x = x_r3_0 +  4, y = y_r3_0, life = 1 })
		part({ type = pt.FILT, x = x_r3_0 +  6, y = y_r3_0, tmp = 11, ctype = 0x20 })
		part({ type = pt.FILT, x = x_r3_0 +  7, y = y_r3_0, tmp =  1, ctype = 0x00880000 })
		part({ type = pt.BRAY, x = x_r3_0 +  8, y = y_r3_0, life = 1 })
		part({ type = pt.FILT, x = x_r3_0 + 10, y = y_r3_0, tmp = 11, ctype = 0x100 })
		part({ type = pt.FILT, x = x_r3_0 + 11, y = y_r3_0, tmp =  1, ctype = 0x00120000 })
		part({ type = pt.BRAY, x = x_r3_0 + 12, y = y_r3_0, life = 1 })
		part({ type = pt.INSL, x = x_r3_0 + 13, y = y_r3_0 })

		aray(x_r3_0 + 11, y_r3_0 + 2, 1, 0, pt.METL, nil, 1)
		part({ type = pt.INSL, x = x_r3_0 -  1, y = y_r3_0 + 2 })
		part({ type = pt.BRAY, x = x_r3_0     , y = y_r3_0 + 2, life = 1 })
		part({ type = pt.FILT, x = x_r3_0 +  1, y = y_r3_0 + 2, tmp = 1, ctype = 0x100AFFFF })
		part({ type = pt.FILT, x = x_r3_0 +  2, y = y_r3_0 + 2, tmp = 2, ctype = 0x10000000 })
		part({ type = pt.STOR, x = x_r3_0 +  3, y = y_r3_0 + 2 })
		part({ type = pt.LDTC, x = x_r3_0 +  4, y = y_r3_0 + 1, tmp = 1 })
		part({ type = pt.FILT, x = x_r3_0 +  4, y = y_r3_0 + 2, tmp = 2 })
		part({ type = pt.STOR, x = x_r3_0 +  5, y = y_r3_0 + 2 })
		part({ type = pt.LDTC, x = x_r3_0 +  7, y = y_r3_0 + 1, tmp = 1 })
		part({ type = pt.FILT, x = x_r3_0 +  6, y = y_r3_0 + 2, tmp = 2 })
		part({ type = pt.STOR, x = x_r3_0 +  7, y = y_r3_0 + 2 })
		part({ type = pt.STOR, x = x_r3_0 +  8, y = y_r3_0 + 2 })
		part({ type = pt.STOR, x = x_r3_0 +  9, y = y_r3_0 + 2 })
		part({ type = pt.LDTC, x = x_r3_0 + 11, y = y_r3_0 + 1, tmp = 1 })
		part({ type = pt.FILT, x = x_r3_0 + 10, y = y_r3_0 + 2, tmp = 2 })

		part({ type = pt.LDTC, x = x_r3_0 + 11, y = y_r3_0 + 5 })
		for x = x_r3_0 + 12, width - 3 do
			part({ type = pt.FILT, x = x, y = y_r3_0 + 5 })
		end

		part({ type = pt.LDTC, x = x_r3_0 + 4, y = y_r3_0 + 4, life = 0, tmp = 1 })
		part({ type = pt.LDTC, x = x_r3_0 + 4, y = y_r3_0 + 4, life = 5, tmp = 1 })
		part({ type = pt.FILT, x = x_r3_0 + 3, y = y_r3_0 + 5 })

		part({ type = pt.DTEC, x = x_r3_0 -  1, y = y_r3_0 + 3 })
		for x = 0, 5 do
			part({ type = pt.FILT, x = x_r3_0 + x, y = y_r3_0 + 3 })
		end

		dray(source_1.x, 19, source_1.x, source_1.y, 1, pt.PSCN)
		dray(source_2.x, 18, source_2.x, source_2.y, 1, pt.PSCN)
	end

	do
		local x_r3_1 = 0
		local y_r3_1 = 9

		part({ type = pt.LDTC, x = x_r3_1, y = y_r3_1 - 3, life = 3 })
		part({ type = pt.FILT, x = x_r3_1, y = y_r3_1 - 2, ctype = 0x1000DEAD })
		local source_2_a = part({ type = pt.FILT, x = x_r3_1, y = y_r3_1 - 1, ctype = 0x1000DEAD })
		local source_2_b = part({ type = pt.FILT, x = x_r3_1, y = y_r3_1, ctype = 0x1000DEAD })

		aray(x_r3_1 + 2, y_r3_1 - 3, -1, 0, pt.METL, nil, 1)

		for i = 0, 3 do
			part({ type = pt.FILT, x = x_r3_1 + 32 - i, y = y_r3_1 - 3, ctype = bitx.bor(bitx.lshift(i, 30), 1) })
		end
		part({ type = pt.LDTC, x = x_r3_1 +  2, y = y_r3_1 - 4, life = 3, tmp = 1 })
		part({ type = pt.FILT, x = x_r3_1 +  3, y = y_r3_1 - 3 })
		part({ type = pt.FILT, x = x_r3_1 +  4, y = y_r3_1 - 3, tmp = 1, ctype = 0x1000FFFF })
		part({ type = pt.BRAY, x = x_r3_1 +  5, y = y_r3_1 - 3, life = 1 })
		part({ type = pt.LDTC, x = x_r3_1 +  5, y = y_r3_1 - 4, life = 2, tmp = 1 })
		part({ type = pt.FILT, x = x_r3_1 +  6, y = y_r3_1 - 3 })
		part({ type = pt.FILT, x = x_r3_1 +  7, y = y_r3_1 - 3, tmp = 11, ctype = 0x4000 })
		part({ type = pt.FILT, x = x_r3_1 +  8, y = y_r3_1 - 3, tmp =  7, ctype = 0x0FFFBFEC })
		part({ type = pt.BRAY, x = x_r3_1 +  9, y = y_r3_1 - 3, life = 1 })
		part({ type = pt.DTEC, x = x_r3_1 + 10, y = y_r3_1 - 3 })
		part({ type = pt.FILT, x = x_r3_1 + 11, y = y_r3_1 - 3 })
		part({ type = pt.LSNS, x = x_r3_1 + 12, y = y_r3_1 - 3, tmp = 3 })
		part({ type = pt.LDTC, x = x_r3_1 + 13, y = y_r3_1 - 3 })
		part({ type = pt.FILT, x = x_r3_1 + 14, y = y_r3_1 - 3, ctype = 0x80000001 })

		local x_second = x_r3_1 + 2

		local target_a = { x = x_second + 9, y = y_r3_1 - 1}
		part({ type = pt.DTEC, x = x_second + 3, y = y_r3_1 - 1, tmp2 = 2 })
		dray(x_second + 3, y_r3_1 - 1, target_a.x, target_a.y, 1, pt.METL)
		ldtc(x_second + 3, y_r3_1 - 1, source_2_a.x, source_2_a.y, nil, 1)
		aray(x_second + 3, y_r3_1 - 1, -1, 0, pt.METL, nil, 1)
		part({ type = pt.LDTC, x = x_second + 3, y = y_r3_1 - 1, life = 1 })

		part({ type = pt.FILT, x = x_second +  4, y = y_r3_1 - 1, tmp =  2 })
		part({ type = pt.BRAY, x = x_second +  5, y = y_r3_1 - 1, life = 1 })
		part({ type = pt.FILT, x = x_second +  6, y = y_r3_1 - 1, tmp =  2, ctype = 0x10000 })
		part({ type = pt.FILT, x = x_second +  7, y = y_r3_1 - 1, tmp = 10, ctype = 4 })
		part({ type = pt.STOR, x = x_second +  8, y = y_r3_1 - 1 })
		part({ type = pt.LDTC, x = x_second + 10, y = y_r3_1 - 1, life = 1, tmp = 1 })
		part({ type = pt.STOR, x = x_second + 10, y = y_r3_1 - 1 })
		part({ type = pt.FILT, x = x_second + 11, y = y_r3_1 - 1, tmp =  1, ctype = 0xFFFF })
		part({ type = pt.DTEC, x = x_second + 14, y = y_r3_1 - 1 })
		part({ type = pt.STOR, x = x_second + 14, y = y_r3_1 - 1 })
		part({ type = pt.FILT, x = x_second + 12, y = y_r3_1 - 1, ctype = 0x10000000 })
		part({ type = pt.STOR, x = x_second + 13, y = y_r3_1 - 1 })
		part({ type = pt.FILT, x = x_second + 14, y = y_r3_1 - 4, ctype = 0x10001000 })
		part({ type = pt.LSNS, x = x_second + 14, y = y_r3_1 - 3, tmp = 3 })
		part({ type = pt.BRAY, x = x_second + 14, y = y_r3_1 - 2, ctype = 0x30000000, life = 1000 })
		local output = { x = x_second + 15, y = y_r3_1 - 1 }
		part({ type = pt.INSL, x = x_second + 16, y = y_r3_1 - 1 })
		part({ type = pt.DMND, x = x_second + 15, y = y_r3_1 - 2 })

		local target_b = { x = x_second + 16, y = y_r3_1 }
		dray(x_second + 2, y_r3_1, target_b.x, target_b.y, 1, pt.METL)
		ldtc(x_second + 2, y_r3_1, source_2_b.x, source_2_b.y)
		aray(x_second + 2, y_r3_1, -1, 0, pt.METL, nil, 1)

		part({ type = pt.FILT, x = x_second +  3, y = y_r3_1, tmp =  7 })
		part({ type = pt.BRAY, x = x_second +  4, y = y_r3_1, life = 1 })
		part({ type = pt.FILT, x = x_second +  5, y = y_r3_1, tmp =  2, ctype = 0x10000 })
		part({ type = pt.FILT, x = x_second +  6, y = y_r3_1, tmp = 10, ctype = 0x100 })
		part({ type = pt.FILT, x = x_second +  7, y = y_r3_1, tmp =  2, ctype = 1 })
		part({ type = pt.FILT, x = x_second +  8, y = y_r3_1, tmp = 10, ctype = 0x100 })
		part({ type = pt.FILT, x = x_second +  9, y = y_r3_1, tmp =  2, ctype = 0xC0000001 })
		part({ type = pt.STOR, x = x_second + 10, y = y_r3_1 })
		part({ type = pt.STOR, x = x_second + 11, y = y_r3_1 })
		part({ type = pt.FILT, x = x_second + 12, y = y_r3_1, tmp =  3, ctype = 0xFFFE })
		part({ type = pt.STOR, x = x_second + 13, y = y_r3_1 })
		part({ type = pt.FILT, x = x_second + 14, y = y_r3_1, tmp =  7, ctype = 0x30000000 })
		part({ type = pt.STOR, x = x_second + 15, y = y_r3_1 })
		part({ type = pt.STOR, x = x_second + 17, y = y_r3_1 })
		part({ type = pt.FILT, x = x_second + 18, y = y_r3_1, tmp =  7, ctype = 1 })
		part({ type = pt.BRAY, x = x_second + 19, y = y_r3_1, life = 1 })
		part({ type = pt.LDTC, x = x_second + 20, y = y_r3_1 })
		for x = 21, width - 5 do
			part({ type = pt.FILT, x = x_second + x, y = y_r3_1 })
		end

		dray(target_a.x, 14, target_a.x, target_a.y, 1, pt.PSCN)
		dray(target_b.x, 18, target_b.x, target_b.y, 1, pt.PSCN)
		cray(output.x, 19, output.x, output.y, pt.SPRK, 1, pt.PSCN)
	end

	do
		local x_bottom = 3
		local y_bottom = 12

		aray(x_bottom, y_bottom, -1, 0, pt.METL, nil, 1)
		part({ type = pt.FILT, x = x_bottom + 1, y = y_bottom })
		ldtc(x_bottom + 1, y_bottom - 1, x_bottom + 1, 0)
		part({ type = pt.STOR, x = x_bottom + 2, y = y_bottom })
		part({ type = pt.FILT, x = x_bottom + 3, y = y_bottom, tmp = 1, ctype = 0x03000000 })
		part({ type = pt.FILT, x = x_bottom + 4, y = y_bottom, ctype = 0x10000001 })
		part({ type = pt.LDTC, x = x_bottom + 6, y = y_bottom - 1, tmp = 1 })
		part({ type = pt.FILT, x = x_bottom + 5, y = y_bottom, tmp = 1 })
		for x = 6, 13 do
			part({ type = pt.STOR, x = x_bottom + x, y = y_bottom })
		end

		part({ type = pt.FILT, x = x_bottom + 14, y = y_bottom, tmp = 7, ctype = 1 })
		part({ type = pt.LDTC, x = x_bottom + 16, y = y_bottom -  1, life = 9, tmp = 2 })
		part({ type = pt.FILT, x = x_bottom + 15, y = y_bottom, tmp = 1 })
		part({ type = pt.STOR, x = x_bottom + 16, y = y_bottom })
		part({ type = pt.FILT, x = x_bottom + 17, y = y_bottom, tmp = 7, ctype = 2 })
		part({ type = pt.DMND, x = x_bottom + 18, y = y_bottom - 1 })
		local output = { x = x_bottom + 18, y = y_bottom }
		part({ type = pt.INSL, x = x_bottom + 19, y = y_bottom })
		part({ type = pt.FILT, x = x_bottom + 20, y = y_bottom, ctype = 0x10000002 })

		local target = { type = pt.STOR, x = x_bottom + 27, y = y_bottom }
		part({ type = pt.LDTC, x = x_bottom + 22, y = y_bottom, life = 1, tmp = 1 })
		part({ type = pt.LDTC, x = x_bottom + 22, y = y_bottom, life = 3, tmp = 1 })
		dray(x_bottom + 22, y_bottom, target.x - 1, target.y, 2, pt.METL)
		aray(x_bottom + 22, y_bottom, -1, 0, pt.METL, nil, 1)
		part({ type = pt.FILT, x = x_bottom + 23, y = y_bottom })
		part({ type = pt.FILT, x = x_bottom + 24, y = y_bottom, tmp = 10 })
		part({ type = pt.BRAY, x = x_bottom + 25, y = y_bottom, life = 1 })
		part({ type = pt.FILT, x = x_bottom + 26, y = y_bottom, ctype = 0x10000 })
		part({ type = pt.BRAY, x = x_bottom + 28, y = y_bottom, life = 1 })
		part({ type = pt.INSL, x = x_bottom + 29, y = y_bottom })

		part({ type = pt.FILT, x = x_bottom - 2, y = y_bottom - 2, ctype = 0x10000000 })
		part({ type = pt.LDTC, x = x_bottom    , y = y_bottom - 2 })
		for x = 1, width - 6 do
			part({ type = pt.FILT, x = x_bottom + x, y = y_bottom - 2 })
		end

		aray(x_bottom + 16, y_bottom + 2, -1, 0, pt.METL, nil, 1)
		part({ type = pt.LDTC, x = x_bottom + 18, y = y_bottom + 1, life = 1, tmp = 1 })
		part({ type = pt.FILT, x = x_bottom + 17, y = y_bottom + 2 })
		part({ type = pt.STOR, x = x_bottom + 18, y = y_bottom + 2 })
		part({ type = pt.STOR, x = x_bottom + 19, y = y_bottom + 2 })
		part({ type = pt.STOR, x = x_bottom + 20, y = y_bottom + 2 })
		part({ type = pt.STOR, x = x_bottom + 21, y = y_bottom + 2 })
		part({ type = pt.STOR, x = x_bottom + 22, y = y_bottom + 2 })
		part({ type = pt.STOR, x = x_bottom + 23, y = y_bottom + 2 })
		part({ type = pt.FILT, x = x_bottom + 24, y = y_bottom + 2, tmp = 2, ctype = 0x10000000 })
		part({ type = pt.FILT, x = x_bottom + 25, y = y_bottom + 2, tmp = 1, ctype = 0x1000FFFF })
		part({ type = pt.LDTC, x = x_bottom + 27, y = y_bottom + 1, tmp = 1 })
		part({ type = pt.FILT, x = x_bottom + 26, y = y_bottom + 2, tmp = 2 })
		part({ type = pt.BRAY, x = x_bottom + 27, y = y_bottom + 2, life = 1 })

		do
			local source = part({ type = pt.BRAY, x = x_bottom + 14, y = y_bottom + 2, life = 1 })
			part({ type = pt.LDTC, x = x_bottom + 12, y = y_bottom + 4, z = 1 })
			dray(x_bottom + 28, y_bottom + 2, source.x, source.y, 1, pt.PSCN)
		end

		for x = 20, width - 6 do
			part({ type = pt.FILT, x = x_bottom + x, y = y_bottom - 1 })
		end

		part({ type = pt.FILT, x = x_bottom + 16, y = y_bottom + 3 })
		aray(x_bottom + 14, y_bottom + 4, -1, 0, pt.METL, nil, 1)
		part({ type = pt.FILT, x = x_bottom + 15, y = y_bottom + 4 })
		part({ type = pt.FILT, x = x_bottom + 16, y = y_bottom + 4 })
		part({ type = pt.FILT, x = x_bottom + 17, y = y_bottom + 4 })
		part({ type = pt.FILT, x = x_bottom + 18, y = y_bottom + 4, tmp =  2, ctype = 0x100 })
		part({ type = pt.FILT, x = x_bottom + 19, y = y_bottom + 4, tmp =  3, ctype = 0xFF })
		part({ type = pt.FILT, x = x_bottom + 20, y = y_bottom + 4, tmp = 11, ctype = 0x100 })
		part({ type = pt.FILT, x = x_bottom + 21, y = y_bottom + 4, tmp =  2, ctype = 0x10000000 })
		part({ type = pt.FILT, x = x_bottom + 22, y = y_bottom + 4, tmp =  3, ctype = 0xFF })
		part({ type = pt.FILT, x = x_bottom + 23, y = y_bottom + 4, tmp = 11, ctype = 0x100 })
		part({ type = pt.FILT, x = x_bottom + 24, y = y_bottom + 4, tmp =  2, ctype = 0x10000000 })
		part({ type = pt.FILT, x = x_bottom + 25, y = y_bottom + 4, tmp =  1, ctype = 0x1000FFFF })
		part({ type = pt.BRAY, x = x_bottom + 26, y = y_bottom + 4, life = 1 })
		part({ type = pt.INSL, x = x_bottom + 27, y = y_bottom + 4 })

		part({ type = pt.LDTC, x = x_bottom + 23, y = y_bottom + 7 })
		part({ type = pt.FILT, x = x_bottom + 22, y = y_bottom + 8 })
		part({ type = pt.LDTC, x = x_bottom -  1, y = y_bottom + 8 })

		dray(target.x, 18, target.x, target.y, 1, pt.PSCN)
		cray(output.x, 19, output.x, output.y, pt.SPRK, 1, pt.PSCN)
	end

	for x = -1, width - 2 do
		part({ type = pt.DMND, x = x, y = -2        , unstack = true })
		part({ type = pt.DMND, x = x, y = -1        , unstack = true })
		part({ type = pt.DMND, x = x, y = height - 4, unstack = true })
		part({ type = pt.DMND, x = x, y = height - 3, unstack = true })
	end
	for y = -1, height - 4 do
		part({ type = pt.DMND, x = width - 2, y = y, unstack = true })
		part({ type = pt.DMND, x = width - 1, y = y, unstack = true })
		part({ type = pt.DMND, x = -2       , y = y, unstack = true })
		part({ type = pt.DMND, x = -1       , y = y, unstack = true })
	end

	for _, part in ipairs(parts) do
		part.dcolour = 0xFF007F7F
		if part.type == pt.DMND then
			part.dcolour = 0xFFFFFFFF
		end
		if part.type == pt.FILT then
			part.dcolour = 0xFF00FFFF
		end
	end

	local xoff
	if params.x.which == "left" then
		xoff = params.x.value
	else
		xoff = params.x.value - width + 1
	end
	local interface = {
		type           = "solid",
		name           = "interface",
		x              = xoff - 2,
		y              = params.bus_0.y - 2,
		w              = width + 2,
		h              = height,
		terminates_bus = true,
	}
	table.insert(areas, interface)
	table.insert(params.bus_0.through_areas, interface)
	table.insert(params.bus_1.through_areas, interface)
	local parts_out = {}
	plot.merge_parts(xoff, params.bus_0.y, parts_out, parts)
	return {
		parts = parts_out,
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
		bus_0 = {
			type = "cpu_bus",
		},
		bus_1 = {
			type = "cpu_bus",
		},
	}
end

return {
	build       = build,
	param_types = param_types,
}

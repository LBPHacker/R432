local bitx       = require("spaghetti.bitx")
local plot       = require("spaghetti.plot")
local check      = require("spaghetti.check")
local filt_input = require("r4.comp.filt_input")

local pt = plot.pt
local peripheral_mask = 0xFFFFFFFF

local function build(params, params_name, component)
	local width = 29
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
	local dray  = ucontext.dray
	local part  = ucontext.part
	local aray  = ucontext.aray
	local ldtc  = ucontext.ldtc
	local spark = ucontext.spark

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
		--[[
		#include <cmath>
		#include <iostream>

		int transform(int life)
		{
			float supposedly_one = (((float(-11) + 294.15f) - 273.15f) / 10.f); /* D = 2^-23 (???) */ 
			float Vm = sqrt(supposedly_one * supposedly_one /* D = 2^-22 */ ) /* D = 2^-22 (???) */;
			float vel = float(life) / Vm; /* D = a * 2^-22 < 2^-12 */
			vel *= (1.0f + (float(50) / 100.0f /* D = 0     */ ) /* D = 0     */ ); /* D = vel * 0     + 1.5  * D_vel < 0     + 2^-11 = 2^-11 */
			vel *= (1.0f + (float(12) / 100.0f /* D = 2^-27 */ ) /* D = 2^-23 */ ); /* D = vel * 2^-23 + 1.12 * D_vel < 2^-12 + 2^-10 < 2^-9  */
			vel *= (1.0f + (float(27) / 100.0f /* D = 2^-25 */ ) /* D = 2^-23 */ ); /* D = vel * 2^-23 + 1.27 * D_vel < 2^-12 + 2^-9  < 2^-8  */
			// at this point vel is off by at most 2^-8 from the ideal value of life * 1.5 * 1.12 * 1.27 = life * 2.1336something evaluated at infinite precision
			// the question then is how far off life * 2.1336something is from the ideal value of life * 32 / 15 evaluated at infinite precision
			// with life in the [480, 960) range, it's at worst off by 0.3516something
			// the sum of these errors is less than 0.5 so we're good
			int result = int(vel + 0.5f);
			return (result >> 5) - 32;
		}

		int main()
		{
			bool all_ok = true;
			for (int life = 480; life < 960; ++life)
			{
				if (transform(life) != life / 15 - 32)
				{
					std::cout << life << std::endl;
					all_ok = false;
				}
			}
			return all_ok ? 0 : 1;
		}
		]]
		local x_stack = x_base - 1
		local y_stack = y_base - 2
		spark({ type = pt.PSCN, x = x_stack - 1, y = y_stack     })
		part ({ type = pt.CRMC, x = x_stack    , y = y_stack - 1 })
		part ({ type = pt.INSL, x = x_stack    , y = y_stack + 1 })
		part ({ type = pt.FILT, x = x_stack + 1, y = y_stack    , ctype = 0x10000000 + (13 * 15 + 480) })
		part ({ type = pt.FILT, x = x_stack + 2, y = y_stack - 1, ctype = 0x10000003 })
		part ({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.INSL, ctype = pt.STNE })
		for _, item in ipairs({
			{ tmp = 0, distance =  4 },
			{ tmp = 7, distance =  7 },
			{ tmp = 7, distance = 10 },
			{ tmp = 7, distance = 13 },
			{ tmp = 0, distance = 17 },
			{ tmp = 7, distance = 20 },
			{ tmp = 7, distance = 23 },
			{ tmp = 7, distance = 26 },
		}) do
			local target = part({ type = pt.FILT, x = x_stack + item.distance, y = y_stack, tmp = item.tmp })

			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.STNE, ctype = pt.NEUT })
			part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 1, tmp2 = 1 })
			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.NEUT, ctype = pt.STNE })
			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = pt.HEAC })
			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.CRMC, ctype = pt.METL })
			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.METL, ctype = pt.SPRK })
			part({ type = pt.FRAY, x = x_stack, y = y_stack, temp = 10 + 273.15 })
			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SPRK, ctype = pt.CRMC })
			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.HEAC, ctype = pt.PSCN })
			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.PSCN, ctype = pt.SPRK })
			part({ type = pt.LSNS, x = x_stack, y = y_stack, tmp = 3, tmp2 = 2 })
			part({ type = pt.VSNS, x = x_stack, y = y_stack, tmp = 3, tmp2 = 1 })
			part({ type = pt.ACEL, x = x_stack, y = y_stack, life = 50 })
			part({ type = pt.ACEL, x = x_stack, y = y_stack, life = 12 })
			part({ type = pt.ACEL, x = x_stack, y = y_stack, life = 27 })
			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.FILT, ctype = pt.SWCH })
			part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.SWCH, ctype = bitx.bor(pt.FILT, bitx.lshift(item.tmp, sim.PMAPBITS)) })
			part({ type = pt.VSNS, x = x_stack, y = y_stack, tmp = 1, tmp2 = 1 })
			dray(x_stack, y_stack, target.x, target.y, 1, false)
		end
		part({ type = pt.CONV, x = x_stack, y = y_stack, tmp = pt.STNE, ctype = pt.INSL })

		aray(x_stack + 3, y_stack, -1, 0, pt.METL)
		do
			part({ type = pt.FILT, x = x_stack +  5, y = y_stack, tmp = 10, ctype = 0x20 })
			part({ type = pt.FILT, x = x_stack +  6, y = y_stack, tmp =  3, ctype = 0x7BFF })
			part({ type = pt.FILT, x = x_stack +  8, y = y_stack, tmp = 10, ctype = 0x20 })
			part({ type = pt.FILT, x = x_stack +  9, y = y_stack, tmp =  3, ctype = 0x3FF })
			part({ type = pt.FILT, x = x_stack + 11, y = y_stack, tmp = 10, ctype = 0x20 })
			part({ type = pt.FILT, x = x_stack + 12, y = y_stack, tmp =  3, ctype = 0x3FF })
			part({ type = pt.FILT, x = x_stack + 14, y = y_stack, tmp = 11, ctype = 0x20 })
			part({ type = pt.FILT, x = x_stack + 15, y = y_stack, tmp =  7, ctype = 0x10908420 })
			local source_1 = part({ type = pt.BRAY, x = x_stack + 16, y = y_stack })
			ldtc(x_stack + 23, y_base + 5, source_1.x, source_1.y)
			local source_2 = part({ type = pt.FILT, x = x_stack + 24, y = y_base + 6, ctype = 0x10000000 })
			ldtc(x_base + 4, source_2.y, source_2.x, source_2.y)
			part({ type = pt.LDTC, x = x_base + 3, y = y_base + 5 })
			part({ type = pt.FILT, x = x_base + 3, y = y_base + 6, ctype = 0x10000000 })
		end
		do
			part({ type = pt.FILT, x = x_stack + 18, y = y_stack, tmp = 10, ctype = 0x20 })
			part({ type = pt.FILT, x = x_stack + 19, y = y_stack, tmp =  3, ctype = 0x7BFF })
			part({ type = pt.FILT, x = x_stack + 21, y = y_stack, tmp = 10, ctype = 0x20 })
			part({ type = pt.FILT, x = x_stack + 22, y = y_stack, tmp =  3, ctype = 0x3FF })
			part({ type = pt.FILT, x = x_stack + 24, y = y_stack, tmp = 10, ctype = 0x20 })
			part({ type = pt.FILT, x = x_stack + 25, y = y_stack, tmp =  3, ctype = 0x3FF })
			part({ type = pt.FILT, x = x_stack + 27, y = y_stack, tmp = 11, ctype = 0x20 })
			part({ type = pt.FILT, x = x_stack + 28, y = y_stack, tmp =  7, ctype = 0x10908420 })
			local source_1 = part({ type = pt.BRAY, x = x_stack + 29, y = y_stack })
			ldtc(x_stack + 29, y_base + 5, source_1.x, source_1.y)
			local source_2 = part({ type = pt.FILT, x = x_stack + 29, y = y_base + 6, ctype = 0x10000000 })
			ldtc(x_base + 8, source_2.y, source_2.x, source_2.y)
			part({ type = pt.LDTC, x = x_base + 7, y = y_base + 5 })
			part({ type = pt.FILT, x = x_base + 7, y = y_base + 6, ctype = 0x10000000 })
		end
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

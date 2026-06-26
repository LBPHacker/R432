local plot            = require("spaghetti.plot")
local check           = require("spaghetti.check")
local misc            = require("spaghetti.misc")
local bitx            = require("spaghetti.bitx")
local bus_termination = require("r4.comp.bus.termination")
local r4_check        = require("r4.check")

local pt = plot.pt
local audited_pairs = pairs

local components_by_type = {
	cpu           = require("r4.comp.cpu"),
	r3_bus        = require("r4.comp.bus.r3_adapter"),
	terminal      = require("r4.comp.terminal"),
	filt_input    = require("r4.comp.filt_input"),
	filt_output   = require("r4.comp.filt_output"),
	inst_input    = require("r4.comp.inst_input"),
	inst_output   = require("r4.comp.inst_output"),
	random_source = require("r4.comp.random_source"),
	frame_clock   = require("r4.comp.frame_clock"),
}
local valid_types = {}
for key in audited_pairs(components_by_type) do
	table.insert(valid_types, key)
end

local function tagged_print(err, message)
	print(("\b%s[r4plot]\14 %s"):format(err and "l" or "t", message))
end

local function place_components(x_top, y_top, components_name, components, debug_stacks, debug_areas)
	local memory_mask = 0xFFFF8000
	local name_to_component_index = {}
	local buses = {}
	for ix_component, component in ipairs(components) do
		local component_name = ("%s[%i]"):format(components_name, ix_component)
		check.table(component_name, component)
		check.string(component_name .. ".name", component.name)
		check.one_of(component_name .. ".type", component.type, valid_types)
		if name_to_component_index[component.name] then
			misc.user_error("%s is not unique", component_name .. ".name")
		end
		name_to_component_index[component.name] = ix_component
		if component.type == "cpu" then
			check.integer_range(component_name .. ".memory_base", component.memory_base, 0, r4_check.address_max)
			r4_check.base_address(component_name .. ".memory_base", component.memory_base, memory_mask)
			component.memory_mask = memory_mask
			component.mmio_ranges = {}
			check.string(component_name .. ".cores", component.cores)
			local component_buses = {}
			for ix_core = 1, #component.cores do
				table.insert(component_buses, {
					through_areas = {},
					cpu           = component,
				})
			end
			buses[ix_component] = component_buses
		end
	end
	local component_to_new_params = {}
	local component_order_forward = {}
	local component_order_backward = {}
	for ix_component = 1, #components do
		component_order_forward[ix_component] = {}
		component_order_backward[ix_component] = {}
	end
	local function mark_depends(dependent, dependee)
		component_order_forward[dependent][dependee] = true
		component_order_backward[dependee][dependent] = true
	end
	local mmio_ranges = {}
	for ix_component, component in ipairs(components) do
		local component_name = ("%s[%i]"):format(components_name, ix_component)
		local new_params = {
			debug_stacks = debug_stacks and true,
		}
		for key, value in audited_pairs(component) do
			new_params[key] = value
		end
		local param_types = components_by_type[component.type].param_types
		if param_types then
			for param_name, param_type in audited_pairs(param_types()) do
				local param_bus_name = component_name .. "." .. param_name
				if param_type.type == "lowhigh" then
					if (component[param_type.low] or component[param_type.high]) or not param_type.optional then
						new_params[param_name] = r4_check.lowhigh(component_name, component, param_type.low, param_type.high)
					end
				elseif param_type.type == "cpu_bus" then
					if component[param_name] ~= nil or not param_type.optional then
						check.table(param_bus_name, component[param_name])
						check.string(param_bus_name .. ".cpu", component[param_name].cpu)
						check.integer(param_bus_name .. ".bus_index", component[param_name].bus_index)
						local component_buses = buses[name_to_component_index[component[param_name].cpu]]
						local bus = component_buses and component_buses[component[param_name].bus_index + 1]
						if not bus then
							misc.user_error("%s does not refer to a known bus", param_bus_name)
						end
						new_params[param_name] = bus
						local cpu_index = name_to_component_index[component[param_name].cpu]
						mark_depends(ix_component, cpu_index)
					end
				elseif param_type.type == "base_address" then
					if component[param_name] ~= nil or not param_type.optional then
						r4_check.base_address(param_bus_name, component[param_name], param_type.mask)
					end
					local mmio_key = ("%i.%s"):format(ix_component, param_name)
					table.insert(mmio_ranges, {
						ix_component = ix_component,
						name         = param_bus_name,
						buses        = param_type.buses,
						base         = component[param_name],
						size         = bitx.bxor(param_type.mask, 0xFFFFFFFF) + 1,
					})
				else
					error("bad param type")
				end
			end
		end
		component_to_new_params[component] = new_params
	end
	for _, mmio_range in ipairs(mmio_ranges) do
		local component = components[mmio_range.ix_component]
		for _, bus_name in ipairs(mmio_range.buses) do
			local bus = component_to_new_params[component][bus_name]
			bus.cpu.mmio_ranges[mmio_range] = true
		end
	end
	local relative_parts = {}
	local areas = {}
	local function add_area(area)
		area.x = area.x + x_top
		area.y = area.y + y_top
		table.insert(areas, area)
		area.r, area.g, area.b = misc.colour_hash(area.name)
	end
	do
		local to_visit = {}
		for ix_component = 1, #components do
			if not next(component_order_forward[ix_component]) then
				table.insert(to_visit, ix_component)
			end
		end
		while #to_visit > 0 do
			local next_to_visit = {}
			for _, ix_component in ipairs(to_visit) do
				local component = components[ix_component]
				local component_name = ("%s[%i]"):format(components_name, ix_component)
				local build_info = components_by_type[component.type].build(component_to_new_params[component], component_name)
				for _, area in ipairs(build_info.areas) do
					local new_area = {
						type      = area.type,
						name      = component.name .. "." .. area.name,
						x         = area.x,
						y         = area.y,
						w         = area.w,
						h         = area.h,
						filt_wire = area.filt_wire,
					}
					add_area(new_area)
					area.successor = new_area
				end
				plot.merge_parts(0, 0, relative_parts, build_info.parts)
				if component.type == "cpu" then
					do
						local ranges_by_address = {}
						for mmio_ranges in audited_pairs(component.mmio_ranges) do
							table.insert(ranges_by_address, mmio_ranges)
						end
						table.sort(ranges_by_address, function(lhs, rhs)
							return lhs.base < rhs.base
						end)
						for ix_range = 1, #ranges_by_address - 1 do
							local curr_range = ranges_by_address[ix_range]
							local next_range = ranges_by_address[ix_range + 1]
							if curr_range.base + curr_range.size > next_range.base then
								misc.user_error(
									"%s address space: %s spanning [0x%08X, 0x%08X] overlaps with %s spanning [0x%08X, 0x%08X]",
									component.name,
									curr_range.name,
									curr_range.base,
									curr_range.base + curr_range.size - 1,
									next_range.name,
									next_range.base,
									next_range.base + next_range.size - 1
								)
							end
						end
					end
					local component_buses = buses[name_to_component_index[component.name]]
					for ix_bus, bus in ipairs(build_info.buses) do
						component_buses[ix_bus].x = bus.x
						component_buses[ix_bus].y = bus.y
					end
					if build_info.memory_stats then
						local used      = build_info.memory_stats.used
						local available = build_info.memory_stats.available
						local overflow  = used > available
						tagged_print(overflow, ("%s memory usage: %i out of %i bytes (%.2f%%%s)"):format(component.name, used * 4, available * 4, used / available * 100, overflow and ", overflow!" or ""))
					end
				end
				for dependent_index in audited_pairs(component_order_backward[ix_component]) do
					component_order_forward[dependent_index][ix_component] = nil
					if not next(component_order_forward[dependent_index]) then
						table.insert(next_to_visit, dependent_index)
					end
				end
			end
			to_visit = next_to_visit
		end
		for ix_component = 1, #components do
			assert(not next(component_order_forward[ix_component]), "circular dependency")
		end
	end
	for ix_component, component in ipairs(components) do
		local component_buses = buses[ix_component]
		if component_buses then
			local last_empty = false
			for ix_bus, bus in ipairs(component_buses) do
				local bus_parts = {}
				local ucontext = plot.common_structures(bus_parts, debug_stacks and true or false)
				local part = ucontext.part
				local function add_section(x_from, x_to, index, shift)
					for x = x_from, x_to + shift do
						for y = bus.y, bus.y + 4 do
							part({ type = pt.FILT, x = x, y = y, dcolour = 0xFF00FFFF, unstack = true })
						end
					end
					add_area({
						type      = "solid",
						name      = component.name .. ".bus" .. (ix_bus - 1) .. ".section" .. index,
						x         = x_from,
						y         = bus.y,
						w         = x_to - x_from + 1,
						h         = 5,
						filt_wire = true,
					})
				end
				table.sort(bus.through_areas, function(lhs, rhs)
					return lhs.x < rhs.x
				end)
				local last_x = bus.x
				local needs_termination = true
				for ix_area, area in ipairs(bus.through_areas) do
					add_section(last_x, area.x - 1, ix_area - 1, 0)
					last_x = area.x + area.w
					if area.terminates_bus then
						if ix_area ~= #bus.through_areas then
							area.successor.terminates_bus_wrong = true
						end
						needs_termination = false
					end
				end
				local termination_parts = bus_termination.build({
					debug_stacks = debug_stacks,
					memory_mask  = component.memory_mask,
					memory_base  = component.memory_base,
				})
				local bus_termination_x = last_x
				local bus_termination_w = 18
				local bus_termination_shift = 0
				if needs_termination then
					if #bus.through_areas > 0 then
						local extra_width = 4
						add_section(last_x, last_x + extra_width - 1, #bus.through_areas, 2)
						bus_termination_x = bus_termination_x + extra_width
						bus_termination_w = bus_termination_w + 2
						bus_termination_shift = 2
					end
					plot.merge_parts(bus_termination_x + bus_termination_shift, bus.y, bus_parts, termination_parts)
					add_area({
						type = "solid",
						name = component.name .. ".bus" .. (ix_bus - 1) .. ".termination",
						x    = bus_termination_x,
						y    = bus.y - 2,
						w    = bus_termination_w,
						h    = 9,
					})
				end
				plot.merge_parts(0, 0, relative_parts, bus_parts)
				last_empty = #bus.through_areas == 0
			end
		end
	end
	do
		local err
		local coverage = {}
		for ix_area, area in ipairs(areas) do
			if area.terminates_bus_wrong then
				err = ("area %s terminates its bus wrong"):format(area.name)
				break
			end
			if area.w < 0 or area.h < 0 then
				err = ("area %s has negative dimensions"):format(area.name)
				break
			end
			if area.x          < sim.CELL            or
			   area.y          < sim.CELL            or
			   area.x + area.w > sim.XRES - sim.CELL or
			   area.y + area.h > sim.YRES - sim.CELL then
				err = ("area %s is outside simulation bounds"):format(area.name)
				break
			end
			for y = area.y, area.y + area.h - 1 do
				for x = area.x, area.x + area.w - 1 do
					local key = plot.xy_key(x, y)
					local other_area = coverage[key]
					if other_area and not (other_area.filt_wire and area.filt_wire) then
						err = ("area %s overlaps with area %s"):format(area.name, other_area.name)
						break
					end
					coverage[key] = area
				end
				if err then
					break
				end
			end
		end
		if err then
			tagged_print(true, err)
			if not debug_areas then
				tagged_print(false, "area debug view enabled automatically")
				debug_areas = true
			end
			for _, part in ipairs(relative_parts) do
				part.type = pt.DMND
				part.unstack = true
			end
		end
	end
	return relative_parts, areas, debug_areas
end

local function run(params)
	if rawget(_G, "r4plot") then
		r4plot.unregister()
	end
	check.table("params", params)
	check.table("params.components", params.components)
	if params.debug_stacks ~= nil then
		check.table("params.debug_stacks", params.debug_stacks)
		check.integer("params.debug_stacks.x", params.debug_stacks.x)
		check.integer("params.debug_stacks.y", params.debug_stacks.y)
	end
	local x, y = 0, 0
	if params.x ~= nil then
		check.integer("params.x", params.x)
		x = params.x
	end
	if params.y ~= nil then
		check.integer("params.y", params.y)
		y = params.y
	end

	local relative_parts, areas, debug_areas = place_components(x, y, "params.components", params.components, params.debug_stacks, params.debug_areas)
	local parts = {}
	plot.merge_parts(x, y, parts, relative_parts)

	local aftersimdraw
	local tick
	if params.debug_stacks then
		local aftersimdraw_user_stacks = plot.aftersimdraw_user_stacks(params.debug_stacks.x, params.debug_stacks.y, 0, 0, parts)
		local prev_tick = tick
		tick = function()
			aftersimdraw_user_stacks()
			if not prev_tick then
				return
			end
			return prev_tick()
		end
	end

	if params.clear_sim then
		sim.clearSim()
		sim.paused(true)
		sim.heatSim(false)
		sim.newtonianGravity(false)
		sim.ambientHeatSim(false)
		sim.waterEqualization(0)
		sim.airMode(sim.AIR_OFF)
		sim.gravityMode(sim.GRAV_OFF)
	end
	for _, part in audited_pairs(parts) do
		if part.debug_dcolour then
			if params.debug_dcolours then
				part.dcolour = part.debug_dcolour
			end
			part.debug_dcolour = nil
		end
	end
	if params.extra_parts then
		plot.merge_parts(0, 0, parts, params.extra_parts)
	end
	plot.create_parts(0, 0, parts)

	if debug_areas then
		local prev_aftersimdraw = aftersimdraw
		aftersimdraw = function()
			for _, area in ipairs(areas) do
				gfx.fillRect(area.x, area.y, area.w, area.h, area.r, area.g, area.b, 150)
				gfx.drawRect(area.x, area.y, area.w, area.h, area.r, area.g, area.b)
			end
			local mx, my = sim.adjustCoords(ui.mousePosition())
			for _, area in ipairs(areas) do
				if mx >= area.x          and
				   my >= area.y          and
				   mx <  area.x + area.w and
				   my <  area.y + area.h then
					local tw, th = gfx.textSize(area.name)
					local tx, ty = mx - tw - 8, my - th - 6
					gfx.fillRect(tx, ty, tw + 7, th + 5, 0, 0, 0, 200)
					gfx.drawText(tx + 4, ty + 4, area.name, area.r, area.g, area.b)
				end
			end
			if not prev_aftersimdraw then
				return
			end
			return prev_aftersimdraw()
		end
	end

	local function unregister()
		if aftersimdraw then
			event.unregister(event.AFTERSIMDRAW, aftersimdraw)
		end
		if tick then
			event.unregister(event.TICK, tick)
		end
		rawset(_G, "r4plot", nil)
	end
	if aftersimdraw then
		event.register(event.AFTERSIMDRAW, aftersimdraw)
	end
	if tick then
		event.register(event.TICK, tick)
	end
	local r4plot = {
		unregister = unregister,
	}
	rawset(_G, "r4plot", r4plot)
	tagged_print(false, "done")
end

return {
	run = misc.user_wrap(run),
}

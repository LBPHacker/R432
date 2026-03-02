local plot  = require("spaghetti.plot")
local check = require("spaghetti.check")
local misc  = require("spaghetti.misc")
local cpu   = require("r4.comp.cpu")

local audited_pairs = pairs

local function run(params)
	if rawget(_G, "r4plot") then
		r4plot.unregister()
	end
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

	local parts = cpu.build_internal(params)

	local aftersimdraw
	local tick
	if params.debug_stacks then
		local aftersimdraw_user_stacks = plot.aftersimdraw_user_stacks(params.debug_stacks.x, params.debug_stacks.y, x, y, parts)
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
	end
	for _, part in audited_pairs(parts) do
		if part.debug_dcolour then
			if params.debug_dcolours then
				part.dcolour = part.debug_dcolour
			end
			part.debug_dcolour = nil
		end
	end
	plot.create_parts(x, y, parts)
	if params.clear_sim then
		sim.paused(true)
		sim.heatSim(false)
		sim.newtonianGravity(false)
		sim.ambientHeatSim(false)
		sim.waterEqualization(0)
		sim.airMode(sim.AIR_OFF)
		sim.gravityMode(sim.GRAV_OFF)
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
	print("\bt[r4plot]\14 done")
end

return {
	run = misc.user_wrap(run),
}

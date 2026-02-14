local plot  = require("spaghetti.plot")
local check = require("spaghetti.check")
local misc  = require("spaghetti.misc")
local bitx  = require("spaghetti.bitx")

local function run(params)
	if rawget(_G, "r4plot") then
		r4plot.unregister()
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

	local parts = {}

	do
		local pt = plot.pt
		local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
		-- local sig_magn      = ucontext.sig_magn
		-- local mutate        = ucontext.mutate
		-- local piston_extend = ucontext.piston_extend
		local part          = ucontext.part
		-- local spark         = ucontext.spark
		local solid_spark   = ucontext.solid_spark
		-- local lsns_taboo    = ucontext.lsns_taboo
		-- local lsns_spark    = ucontext.lsns_spark
		-- local dray          = ucontext.dray
		local ldtc          = ucontext.ldtc
		-- local cray          = ucontext.cray
		-- local aray          = ucontext.aray


		local width_order = 7
		local height_order = 3

		local width  = bitx.lshift(1, width_order)
		local height = bitx.lshift(1, height_order)
		for y = 0, height - 1 do
			for x = 0, width - 1 do
				part({ type = pt.FILT, x = x, y =                  y })
				part({ type = pt.FILT, x = x, y = 2 * height - 1 - y })
			end
		end

		-- register writer
		local registers = 32
		local writes = { 0, 7, 12, 5 }
		local regs_x = 10
		local write_x = regs_x + 10 + registers * 2
		local src_y = 20
		local dst_y = 40
		local write_filts = {}
		for i = 1, #writes do
			table.insert(write_filts, part({ type = pt.FILT, x = write_x + i * 2, y = dst_y, ctype = 0x200BEEF0 + i }))
		end
		write_filts[0] = part({ type = pt.INSL, x = write_x, y = dst_y })
		for i = 1, registers - 1 do
			local source
			do
				source = part({ type = pt.FILT, x = regs_x + i * 2    , y = src_y, ctype = 0x2DEAD000 + i }) -- from above
				         part({ type = pt.CRMC, x = regs_x + i * 2 + 1, y = src_y, ctype = 0x2DEAD000 + i }) -- from above, LDTC
			end
			part({ type = pt.LSNS, x = regs_x + i * 2 + 2, y = dst_y - 1, tmp = 3 })
			ldtc(regs_x + i * 2 + 2, dst_y - 1, source.x + 2, source.y)
			-- part({ type = pt.INSL, x = regs_x + i * 2 + 2, y = dst_y - 1 })
			do
				local target = 0
				for ix_write, write in ipairs(writes) do
					if write == i then
						target = ix_write
					end
				end
				local dist = target * 2 + (write_x - (regs_x + i * 2)) - 2
				part({ type = pt.FILT, x = regs_x + i * 2 + 3, y = dst_y - 1, ctype = 0x10000000 + dist })
			end
			part({ type = pt.FILT, x = regs_x + i * 2    , y = dst_y })
			part({ type = pt.LDTC, x = regs_x + i * 2 + 1, y = dst_y })
			part({ type = pt.LDTC, x = regs_x + i * 2 + 1, y = dst_y, tmp = 1 })
			-- part({ type = pt.CONV, x = regs_x + i * 2 + 1, y = dst_y, tmp = pt.LDTC, ctype = pt.INSL })
		end
		part({ type = pt.FILT, x = regs_x + registers * 2, y = dst_y })

		solid_spark(regs_x - 2, src_y + 2, 1, -1, pt.PSCN)
		part({ type = pt.FILT, x = regs_x + registers * 2, y = src_y }) -- from above
		part({ type = pt.PSTN, x = regs_x - 1, y = src_y, extend = 0, tmp = 1000 })
		part({ type = pt.PSTN, x = regs_x    , y = src_y, extend = 0, tmp = 1000 })
		part({ type = pt.PSTN, x = regs_x + 1, y = src_y, extend = 3 })
	end

	if params.clear_sim then
		sim.clearSim()
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
		rawset(_G, "r4plot", nil)
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

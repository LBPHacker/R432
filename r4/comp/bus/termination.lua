local bitx = require("spaghetti.bitx")
local plot = require("spaghetti.plot")

local pt = plot.pt

local function build_internal(parts, params)
	local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
	local dray = ucontext.dray
	local part = ucontext.part
	local aray = ucontext.aray
	local ldtc = ucontext.ldtc
	local cray = ucontext.cray

	local source = { x = 12, y = 0 }
	ldtc(2, 0, -1, 0)
	dray(2, 0, source.x, source.y, 1, pt.METL)
	aray(2, 0, -1, 0, pt.METL, nil, 1)

	part({ type = pt.FILT, x =  3, y = 0 })
	part({ type = pt.BRAY, x =  4, y = 0, life = 1 })
	part({ type = pt.FILT, x =  5, y = 0, tmp = 1, ctype = bitx.bor(0x10000000, bitx.band(params.memory_mask, 0xFFFFFF)) })
	part({ type = pt.STOR, x =  6, y = 0 })
	part({ type = pt.DTEC, x =  7, y = 0, tmp2 = 3 })
	part({ type = pt.STOR, x =  7, y = 0 })
	part({ type = pt.STOR, x =  8, y = 0 })
	part({ type = pt.FILT, x =  9, y = 0, tmp = 7, ctype = bitx.bor(0x20000000, bitx.band(params.memory_base, 0xFFFFFF)) })
	part({ type = pt.BRAY, x = 10, y = 0, life = 1 })
	part({ type = pt.DTEC, x = 11, y = 0, tmp2 = 2 })
	part({ type = pt.STOR, x = 11, y = 0 })
	part({ type = pt.BRAY, x = 13, y = 0, life = 1 })
	part({ type = pt.DMND, x = 14, y = 0 })

	ldtc(1, 1, -1, 1)
	aray(1, 1, -1, 0, pt.METL, nil, 1)

	part({ type = pt.FILT, x =  2, y = 1 })
	part({ type = pt.BRAY, x =  3, y = 1, life = 1 })
	part({ type = pt.FILT, x =  4, y = 1, tmp = 1, ctype = bitx.bor(0x10000000, bitx.band(bitx.rshift(params.memory_mask, 8), 0xFF0000)) })
	part({ type = pt.FILT, x =  5, y = 1, tmp = 7, ctype = bitx.bor(0x20000000, bitx.band(bitx.rshift(params.memory_base, 8), 0xFF0000)) })
	part({ type = pt.STOR, x =  6, y = 1 })
	part({ type = pt.FILT, x =  7, y = 1, tmp = 2 })
	part({ type = pt.STOR, x =  8, y = 1 })
	part({ type = pt.FILT, x =  9, y = 1, tmp = 1, ctype = 0xFFFFFF })
	part({ type = pt.STOR, x = 10, y = 1 })
	part({ type = pt.FILT, x = 11, y = 1 })
	part({ type = pt.STOR, x = 12, y = 1 })
	part({ type = pt.FILT, x = 13, y = 1, tmp = 1, ctype = 0x3000000 })
	part({ type = pt.FILT, x = 14, y = 1, ctype = 0x1002FFFF })

	part({ type = pt.BRAY, x = 14, y = 2, ctype = 0x1000FFFF, life = 0x1000 })
	part({ type = pt.LSNS, x = 13, y = 2, tmp = 3 })
	part({ type = pt.FILT, x = 14, y = 3, ctype = 0x10001000 })
	cray(15, 3, 15, 1, pt.SPRK, 1, pt.PSCN)

	for x = 0, 11 do
		part({ type = pt.FILT, x = x, y = 3 })
	end
	part({ type = pt.DTEC, x = 12, y = 3, tmp2 = 3 })
	dray(source.x, 3, source.x, source.y, 1, pt.PSCN)

	part({ type = pt.FILT, x = 0, y = 4 })
	part({ type = pt.FILT, x = 1, y = 4 })
	part({ type = pt.LDTC, x = 2, y = 4, life = 1, tmp = 1 })
	part({ type = pt.FILT, x = 4, y = 4, ctype = 0x1000FFFF })
end

local function build(params)
	local parts = {}
	local ucontext = plot.common_structures(parts, params.debug_stacks and true or false)
	build_internal(parts, {
		debug_stacks = params.debug_stacks,
		memory_mask  = params.memory_mask,
		memory_base  = params.memory_base,
	})
	ucontext.frame(-1, -1, 16, 5, -1, 1, 0xFF00FFFF)
	return parts
end

return {
	build_internal = build_internal,
	build          = build,
}

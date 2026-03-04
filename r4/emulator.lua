local check  = require("spaghetti.check")
local strict = require("spaghetti.strict")
local bitx   = require("spaghetti.bitx")
local misc   = require("spaghetti.misc")

local emu_context_m, emu_context_i = strict.make_mt("r4.emu_context")

local row_size     = 128
local reg_count    = 32
local sub_eu_count = 4

function emu_context_i:fetch_()
	local pc_row = math.min(bitx.band(bitx.rshift(self.pc, 9), 0x3F), self.mem_row_count_ - 1)
	local pc_col =          bitx.band(bitx.rshift(self.pc, 2), 0x7F)
	local result = {}
	for ix_subeu = 0, sub_eu_count - 1 do
		if bitx.band(pc_col, 0x3F) + ix_subeu > 0x3F then
			result[ix_subeu] = 0x0000006F
		else
			result[ix_subeu] = bitx.bor(self.mem[(pc_col + ix_subeu + pc_row * 128) * 4], 1)
		end
	end
	return result
end

local function sign_extend(value, bit)
	if bitx.rshift(value, bit) ~= 0 then
		value = bitx.bor(value, bitx.lshift(0xFFFFFFFE, bit))
	end
	return value
end

local function clamp32(value)
	return value % 0x100000000
end

local function signed32(value)
	if value >= 0x80000000 then
		value = value - 0x100000000
	end
	return value
end

local function alu_op(op, lhs, rhs, shamt, sra)
	if op == 0 then
		return clamp32(lhs + rhs)
	elseif op == 1 then
		return bitx.lshift(lhs, bitx.band(rhs, 0x1F))
	elseif op == 2 then
		return signed32(lhs) < signed32(rhs) and 1 or 0
	elseif op == 3 then
		return lhs < rhs and 1 or 0
	elseif op == 4 then
		return bitx.bxor(lhs, rhs)
	elseif op == 5 then
		if sra then
			return bitx.arshift(lhs, bitx.band(rhs, 0x1F))
		end
		return bitx.rshift(lhs, bitx.band(rhs, 0x1F))
	elseif op == 6 then
		return bitx.bor(lhs, rhs)
	end
	return bitx.band(lhs, rhs)
end

function emu_context_i:eu_()
	local instrs = self:fetch_()
	for ix_subeu = 0, sub_eu_count - 1 do
		local instr = instrs[ix_subeu]
		local rd    = bitx.band(bitx.rshift(instr,  7), 0x1F)
		local rs1   = bitx.band(bitx.rshift(instr, 15), 0x1F)
		local rs2   = bitx.band(bitx.rshift(instr, 20), 0x1F)
		local imm_i = sign_extend(         bitx.band(bitx.rshift(instr, 20), 0x00000FFF) , 11)
		local imm_s = sign_extend(bitx.bor(bitx.band(bitx.rshift(instr, 20), 0x00000FE0),
		                                   bitx.band(bitx.rshift(instr,  7), 0x0000001F)), 11)
		local imm_b = sign_extend(bitx.bor(bitx.band(bitx.rshift(instr, 19), 0x00001000),
		                                   bitx.band(bitx.rshift(instr, 20), 0x000007E0),
		                                   bitx.band(bitx.rshift(instr,  6), 0x0000001E),
		                                   bitx.band(bitx.lshift(instr,  4), 0x00000800)), 12)
		local imm_u =                      bitx.band(            instr     , 0xFFFFF000)
		local imm_j = sign_extend(bitx.bor(bitx.band(bitx.rshift(instr, 11), 0x00100000),
		                                   bitx.band(bitx.rshift(instr, 20), 0x000007FE),
		                                   bitx.band(bitx.rshift(instr,  9), 0x00000800),
		                                   bitx.band(            instr     , 0x000FF000)), 20)
		local rd_value
		if bitx.band(instr, 0x00000074) == 0x00000010 then
			rd_value = alu_op(
				bitx.band(bitx.rshift(instr, 12), 7),
				self.regs[rs1],
				imm_i,
				bitx.band(bitx.rshift(instr, 20), 0x1F),
				bitx.band(instr, 0x40000000) ~= 0
			)
		else
			error("nyi")
		end
		if self.started then
			if rd ~= 0 then
				self.regs[rd] = rd_value
				self.reg_writes_[rd] = rd_value
			end
		end
		self.pc = clamp32(self.pc + 4)
	end
end

emu_context_i.frame = misc.user_wrap(function(self, start_action)
	check.one_of("start_action", start_action, { "start", "stop", "none" })
	for ix_eu = 0, self.core_count_ - 1 do
		self:eu_()
		-- if start_action == "start" then -- TODO: enable
		-- 	self.started = true
		-- end
		-- if start_action == "stop" then
		-- 	self.started = false
		-- end
		start_action = "none"
	end
	local result = {
		started    = self.started,
		reg_writes = self.reg_writes_,
		mem_writes = self.mem_writes_,
	}
	self.reg_writes_ = {}
	self.mem_writes_ = {}
	return result
end)

local mem_m = {
	__newindex = function()
		error("unaligned access", 2)
	end,
	__index = function()
		error("unaligned access", 2)
	end,
}
local make_context = misc.user_wrap(function(params)
	check.integer_range("params.mem_row_count", params.mem_row_count, 1, 64)
	check.integer_range("params.core_count", params.core_count, 1, 50)
	if params.bus_access ~= nil then
		check.func("params.bus_access", params.bus_access)
	end
	local pc = 0x00000000
	local mem = {}
	local mem_size = params.mem_row_count * 128
	for i = 0, (mem_size - 1) * 4, 4 do
		mem[i] = 0x00000000
	end
	setmetatable(mem, mem_m)
	local regs = {}
	for i = 0, reg_count - 1 do
		regs[i] = 0x00000000
	end
	return setmetatable({
		started        = false,
		pc            = pc,
		mem            = mem,
		regs           = regs,
		mem_size_      = mem_size,
		mem_row_count_ = params.mem_row_count,
		bus_access_    = params.bus_access,
		core_count_    = params.core_count,
		reg_writes_    = {},
		mem_writes_    = {},
	}, emu_context_m)
end)

return {
	make_context = make_context,
	row_size     = row_size,
	reg_count    = reg_count,
	sub_eu_count = sub_eu_count,
}

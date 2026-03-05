local check  = require("spaghetti.check")
local strict = require("spaghetti.strict")
local bitx   = require("spaghetti.bitx")
local misc   = require("spaghetti.misc")

local emu_context_m, emu_context_i = strict.make_mt("r4.emu_context")

local row_size     = 128
local reg_count    = 32
local sub_eu_count = 4

function emu_context_i:rowcol_(address)
	local row = bitx.band(bitx.rshift(address, 9), 0x3F)
	local col = bitx.band(bitx.rshift(address, 2), 0x7F)
	return math.min(row, self.mem_row_count_ - 1), col, row
end

function emu_context_i:fetch_()
	local row, col = self:rowcol_(self.pc)
	local result = {}
	for ix_subeu = 0, sub_eu_count - 1 do
		if bitx.band(col, 0x3F) + ix_subeu > 0x3F then
			result[ix_subeu] = 0x0000006F
		else
			result[ix_subeu] = bitx.bor(self.mem[(col + ix_subeu + row * 128) * 4], 1)
		end
	end
	return result
end

function emu_context_i:store_(address, value)
	local row, col, real_row = self:rowcol_(address)
	if real_row ~= row then
		return
	end
	local aligned = (col + row * 128) * 4
	self.mem[aligned] = value
	self.mem_writes_[aligned] = value
end

function emu_context_i:load_(address)
	local row, col = self:rowcol_(address)
	return self.mem[(col + row * 128) * 4]
end

local function sign_extend(value, bit)
	if bitx.band(bitx.rshift(value, bit), 1) ~= 0 then
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

local function alu_op(op, lhs, rhs, shamt, sra, sub)
	if op == 0 then
		if sub then
			return clamp32(lhs - rhs)
		end
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

local function cond_op(op, lhs, rhs)
	local taken
	local op_high = bitx.band(bitx.rshift(op, 1), 3)
	if op_high == 2 then
		taken = signed32(lhs) < signed32(rhs)
	elseif op_high == 3 then
		taken = lhs < rhs
	else
		taken = lhs == rhs
	end
	if bitx.band(op, 1) ~= 0 then
		taken = not taken
	end
	return taken
end

local function access_size(size_op)
	if size_op == 0 then
		return 1
	elseif size_op == 1 then
		return 2
	end
	return 4
end

local function imm_i(instr)
	return sign_extend(         bitx.band(bitx.rshift(instr, 20), 0x00000FFF) , 11)
end

local function imm_s(instr)
	return sign_extend(bitx.bor(bitx.band(bitx.rshift(instr, 20), 0x00000FE0),
	                            bitx.band(bitx.rshift(instr,  7), 0x0000001F)), 11)
end

local function imm_b(instr)
	return sign_extend(bitx.bor(bitx.band(bitx.rshift(instr, 19), 0x00001000),
	                            bitx.band(bitx.rshift(instr, 20), 0x000007E0),
	                            bitx.band(bitx.rshift(instr,  7), 0x0000001E),
	                            bitx.band(bitx.lshift(instr,  4), 0x00000800)), 12)
end

local function imm_u(instr)
	return                      bitx.band(            instr     , 0xFFFFF000)
end

local function imm_j(instr)
	return sign_extend(bitx.bor(bitx.band(bitx.rshift(instr, 11), 0x00100000),
	                            bitx.band(bitx.rshift(instr, 20), 0x000007FE),
	                            bitx.band(bitx.rshift(instr,  9), 0x00000800),
	                            bitx.band(            instr     , 0x000FF000)), 20)
end

function emu_context_i:eu_(ix_eu)
	local instrs = self:fetch_()
	local defer_shift = 0
	local function defer()
		defer_shift = defer_shift + 1
	end
	for ix_subeu = 0, sub_eu_count - 1 do repeat
		local bus_access_done = false
		if not self.started then
			defer()
			break
		end
		local last_subeu = ix_subeu == sub_eu_count - 1
		local instr = instrs[ix_subeu - defer_shift]
		local rd    = bitx.band(bitx.rshift(instr,  7), 0x1F)
		local rs1   = bitx.band(bitx.rshift(instr, 15), 0x1F)
		local rs2   = bitx.band(bitx.rshift(instr, 20), 0x1F)
		local rd_value
		local next_pc = clamp32(self.pc + 4)
		if bitx.band(instr, 0x00000074) == 0x00000010 then
			rd_value = alu_op(
				bitx.band(bitx.rshift(instr, 12), 7),
				self.regs[rs1],
				imm_i(instr),
				bitx.band(bitx.rshift(instr, 20), 0x1F),
				bitx.band(instr, 0x40000000) ~= 0,
				false
			)
		elseif bitx.band(instr, 0x00000074) == 0x00000030 then
			rd_value = alu_op(
				bitx.band(bitx.rshift(instr, 12), 7),
				self.regs[rs1],
				self.regs[rs2],
				self.regs[rs2],
				bitx.band(instr, 0x40000000) ~= 0,
				bitx.band(instr, 0x40000000) ~= 0
			)
			if bitx.band(instr, 0x02000000) ~= 0 then -- TODO: implement mul
				if not last_subeu then
					defer()
					break
				end
			end
		elseif bitx.band(instr, 0x00000050) == 0x00000050 then
			if not last_subeu then
				defer()
				break
			end
			self.started = false
		elseif bitx.band(instr, 0x00000054) == 0x00000014 then
			local lui = bitx.band(instr, 0x00000020) ~= 0
			rd_value = clamp32(imm_u(instr) + (lui and 0 or self.pc))
		elseif bitx.band(instr, 0x00000058) == 0x00000048 then
			if not last_subeu then
				defer()
				break
			end
			rd_value = next_pc
			next_pc = clamp32(self.pc + imm_j(instr))
		elseif bitx.band(instr, 0x0000005C) == 0x00000044 then
			if not last_subeu then
				defer()
				break
			end
			rd_value = next_pc
			next_pc = clamp32(self.regs[rs1] + imm_i(instr))
		elseif bitx.band(instr, 0x0000005C) == 0x00000040 then
			if cond_op(
				bitx.band(bitx.rshift(instr, 12), 7),
				self.regs[rs1],
				self.regs[rs2]
			) then
				if not last_subeu then
					defer()
					break
				end
				next_pc = clamp32(self.pc + imm_b(instr))
			end
		elseif bitx.band(instr, 0x00000070) == 0x00000020 then
			if not last_subeu then
				defer()
				break
			end
			local address = clamp32(self.regs[rs1] + imm_s(instr))
			local size = access_size(bitx.band(bitx.rshift(instr, 12), 3))
			local handled = false
			local wait = false
			if self.bus_access_ then
				local _
				_, handled, wait = self.bus_access_(ix_eu, true, false, false, size, address, self.regs[rs2])
			end
			bus_access_done = true
			if wait then
				defer()
				break
			end
			if not handled then
				local from_mem = self:load_(address)
				local write_mask = 0xFFFFFFFF
				local to_mem = self.regs[rs2]
				if size == 1 then
					write_mask = bitx.lshift(          0xFF, bitx.band(address, 3) * 8)
					to_mem     = bitx.lshift(self.regs[rs2], bitx.band(address, 3) * 8)
				elseif size == 2 then
					write_mask = bitx.lshift(        0xFFFF, bitx.band(address, 2) * 8)
					to_mem     = bitx.lshift(self.regs[rs2], bitx.band(address, 2) * 8)
				end
				self:store_(address, bitx.bor(bitx.band(from_mem, bitx.bxor(write_mask, 0xFFFFFFFF)),
				                              bitx.band(to_mem  ,           write_mask             )))
			end
		elseif bitx.band(instr, 0x00000074) == 0x00000000 then
			if not last_subeu then
				defer()
				break
			end
			local address = clamp32(self.regs[rs1] + imm_i(instr))
			local size = access_size(bitx.band(bitx.rshift(instr, 12), 3))
			local op_sign_extend = bitx.band(instr, 0x4000) == 0
			local handled = false
			local wait = false
			if self.bus_access_ then
				rd_value, handled, wait = self.bus_access_(ix_eu, false, true, op_sign_extend, size, address, 0x00000000)
			end
			bus_access_done = true
			if wait then
				defer()
				break
			end
			if not handled then
				local from_mem = self:load_(address)
				rd_value = from_mem
				if size == 1 then
					rd_value = bitx.band(bitx.rshift(from_mem, bitx.band(address, 3) * 8), 0xFF)
					if op_sign_extend then
						rd_value = sign_extend(rd_value, 7)
					end
				elseif size == 2 then
					rd_value = bitx.band(bitx.rshift(from_mem, bitx.band(address, 2) * 8), 0xFFFF)
					if op_sign_extend then
						rd_value = sign_extend(rd_value, 15)
					end
				end
			end
		else
			-- assert(bitx.band(instr, 0x00000074) == 0x00000004)
			if not last_subeu then
				defer()
				break
			end
		end
		if last_subeu and not bus_access_done then
			local wait = false
			if self.bus_access_ then
				local _
				_, _, wait = self.bus_access_(ix_eu, false, false, false, 4, 0x00000000, 0x00000000)
			end
			if wait then
				defer()
				break
			end
		end
		if rd_value and rd ~= 0 then
			self.regs[rd] = rd_value
			self.reg_writes_[rd] = rd_value
		end
		self.pc = next_pc
	until true end
end

emu_context_i.frame = misc.user_wrap(function(self, start_action)
	check.one_of("start_action", start_action, { "start", "stop", "none" })
	for ix_eu = 0, self.core_count_ - 1 do
		self:eu_(ix_eu)
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
		-- value, handled, wait = bus_access(ix_eu, store, load, sign_extend, size, address, value)
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
		mem_row_count_ = params.mem_row_count,
		bus_access_    = params.bus_access or false,
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

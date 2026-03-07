local check  = require("spaghetti.check")
local strict = require("spaghetti.strict")
local bitx   = require("spaghetti.bitx")
local misc   = require("spaghetti.misc")
local common = require("r4.common")

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

local function czero_op(op, lhs, rhs)
	if bitx.band(op, 2) ~= 0 then
		return rhs ~= 0 and 0 or lhs
	end
	return rhs == 0 and 0 or lhs
end

local function mul_op(op, lhs, rhs)
	local lhs_lo, lhs_hi = common.split32(lhs)
	local rhs_lo, rhs_hi = common.split32(rhs)
	local lo32       = bitx.band(op, 0x3) == 0x0
	local lhs_signed = bitx.band(op, 0x3) ~= 0x3
	local rhs_signed = bitx.band(op, 0x2) == 0x0
	if lhs_signed and lhs_hi >= 0x8000 then
		lhs_hi = lhs_hi - 0x10000
	end
	if rhs_signed and rhs_hi >= 0x8000 then
		rhs_hi = rhs_hi - 0x10000
	end
	local r00_lo, r00_hi = common.split32(lhs_lo * rhs_lo % 0x100000000)
	local r01_lo, r01_hi = common.split32(lhs_lo * rhs_hi % 0x100000000)
	local r10_lo, r10_hi = common.split32(lhs_hi * rhs_lo % 0x100000000)
	local r11_lo, r11_hi = common.split32(lhs_hi * rhs_hi % 0x100000000)
	local r10_sx = (lhs_signed and r10_hi >= 0x8000) and 0xFFFF or 0x0000
	local r01_sx = (rhs_signed and r01_hi >= 0x8000) and 0xFFFF or 0x0000
	local res_0 = r00_lo
	local res_1, carry_2 = common.split32(r00_hi + r01_lo + r10_lo)
	local res_2, carry_3 = common.split32(r01_hi + r10_hi + r11_lo + carry_2)
	local res_3 = (r11_hi + carry_3 + r01_sx + r10_sx) % 0x10000
	local res_lo32 = common.merge32(res_0, res_1)
	local res_hi32 = common.merge32(res_2, res_3)
	return lo32 and res_lo32 or res_hi32, res_lo32
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
	local mulstate_instr, mulstate_value = self.mulstate_instr, self.mulstate_value
	local function fuse_mul(instr)
		local diff = bitx.bxor(instr, mulstate_instr)
		local same = bitx.band(diff, 0x3FFF8074) == 0
		local lo32 = bitx.band(instr, 0x00003000) == 0x00000000
		local rs1_rd_diff = bitx.band(bitx.rshift(mulstate_instr, 15), 0x1F) ~= bitx.band(bitx.rshift(mulstate_instr, 7), 0x1F)
		local rs2_rd_diff = bitx.band(bitx.rshift(mulstate_instr, 20), 0x1F) ~= bitx.band(bitx.rshift(mulstate_instr, 7), 0x1F)
		local can_fuse = same and lo32 and rs1_rd_diff and rs2_rd_diff
		if can_fuse then
			return mulstate_value
		end
	end
	local poison_mulstate = self.core_types_[ix_eu] ~= "m"
	local function defer(set_poison_mulstate)
		defer_shift = defer_shift + 1
		poison_mulstate = poison_mulstate or set_poison_mulstate
	end
	local bus_access_done = false
	local mul_failed = false
	for ix_subeu = 0, sub_eu_count - 1 do repeat
		local last_subeu = ix_subeu == sub_eu_count - 1
		if not self.started then
			defer(last_subeu)
			break
		end
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
			if bitx.band(instr, 0x06000000) == 0x06000000 then
				rd_value = czero_op(
					bitx.band(bitx.rshift(instr, 12), 7),
					self.regs[rs1],
					self.regs[rs2]
				)
			elseif bitx.band(instr, 0x02000000) ~= 0 then
				local fused_mul = false
				if ix_subeu == 0 then
					local lo32 = fuse_mul(instr)
					if lo32 then
						rd_value = lo32
						fused_mul = true
					end
				end
				if not fused_mul then
					if not last_subeu then
						defer(false) -- not the last sub-EU
						break
					end
					self.mulstate_instr = bitx.bor(instr, 8)
					self.mulstate_value = 0x00000000
					if self.core_types_[ix_eu] == "m" then
						rd_value, self.mulstate_value = mul_op(
							bitx.band(bitx.rshift(instr, 12), 7),
							self.regs[rs1],
							self.regs[rs2]
						)
					else
						mul_failed = true
					end
				end
			else
				rd_value = alu_op(
					bitx.band(bitx.rshift(instr, 12), 7),
					self.regs[rs1],
					self.regs[rs2],
					self.regs[rs2],
					bitx.band(instr, 0x40000000) ~= 0,
					bitx.band(instr, 0x40000000) ~= 0
				)
			end
		elseif bitx.band(instr, 0x00000050) == 0x00000050 then
			if not last_subeu then
				defer(false) -- not the last sub-EU
				break
			end
			self.started = false
		elseif bitx.band(instr, 0x00000054) == 0x00000014 then
			local lui = bitx.band(instr, 0x00000020) ~= 0
			rd_value = clamp32(imm_u(instr) + (lui and 0 or self.pc))
		elseif bitx.band(instr, 0x00000058) == 0x00000048 then
			if not last_subeu then
				defer(false) -- not the last sub-EU
				break
			end
			rd_value = next_pc
			next_pc = clamp32(self.pc + imm_j(instr))
		elseif bitx.band(instr, 0x0000005C) == 0x00000044 then
			if not last_subeu then
				defer(false) -- not the last sub-EU
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
					defer(false) -- not the last sub-EU
					break
				end
				next_pc = clamp32(self.pc + imm_b(instr))
			end
		elseif bitx.band(instr, 0x00000070) == 0x00000020 then
			if not last_subeu then
				defer(false) -- not the last sub-EU
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
				defer(false) -- last sub-EU, but this is a memory access
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
				defer(false) -- not the last sub-EU
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
				defer(false) -- last sub-EU, but this is a memory access
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
				defer(false) -- not the last sub-EU
				break
			end
		end
		if last_subeu and not bus_access_done then
			local wait = false
			if self.bus_access_ then
				local _
				_, _, wait = self.bus_access_(ix_eu, false, false, false, 4, 0x00000000, 0x00000000)
			end
			bus_access_done = true
			if wait then
				-- quirk: requesting a wait cycle when the last sub-EU is executing a mul is UB
				--        because wait cycles are only valid in response to memory accesses. the
				--        quirk here is that this produces a valid mulstate, so a subsequent mul
				--        (indeed, possibly one being delayed to the next sub-EU by the wait cycle)
				--        may act on it.
				defer(false) -- last sub-EU *and* this is not a memory access, and yet the mulstate is not poisoned!
				break
			end
		end
		if mul_failed then
			defer(false) -- EU doesn't support mul, mulstate already poisoned
			break
		end
		if rd_value and rd ~= 0 then
			self.regs[rd] = rd_value
			self.reg_writes_[rd] = rd_value
		end
		self.pc = next_pc
	until true end
	if not bus_access_done then
		if self.bus_access_ then
			self.bus_access_(ix_eu, false, false, false, 4, 0x00000000, 0x00000000)
		end
	end
	if poison_mulstate then
		self.mulstate_instr = bitx.bor(self.mulstate_instr, 4)
	end
end

emu_context_i.frame = misc.user_wrap(function(self, start_action)
	check.one_of("start_action", start_action, { "start", "stop", "none" })
	for ix_eu = 0, self.core_count_ - 1 do
		self:eu_(ix_eu)
	end
	if start_action == "start" then
		self.started = true
	end
	if start_action == "stop" then
		self.started = false
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
	check.string("params.core_types", params.core_types)
	check.integer_range("#params.core_types", #params.core_types, 1, 50)
	for ix_core = 1, #params.core_types do
		local core_type = params.core_types:sub(ix_core, ix_core)
		check.one_of(("params.core_types character %i"):format(ix_core), core_type, { "i", "m" })
	end
	if params.bus_access ~= nil then
		-- value, handled, wait = bus_access(ix_eu, store, load, sign_extend, size, address, value)
		check.func("params.bus_access", params.bus_access)
	end
	local pc = 0x00000000
	local mulstate_instr = 0x0000000F
	local mulstate_value = 0x00000000
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
	local core_types = {}
	for ix_eu = 0, #params.core_types - 1 do
		core_types[ix_eu] = params.core_types:sub(ix_eu + 1, ix_eu + 1)
	end
	return setmetatable({
		started        = false,
		pc             = pc,
		mulstate_instr = mulstate_instr,
		mulstate_value = mulstate_value,
		mem            = mem,
		regs           = regs,
		mem_row_count_ = params.mem_row_count,
		bus_access_    = params.bus_access or false,
		core_count_    = #params.core_types,
		core_types_    = core_types,
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

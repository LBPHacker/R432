local bitx = require("spaghetti.bitx")

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

local function alu_op(op, lhs, rhs, shamt, sra, sub, dest)
	if op == 0 then
		if sub then
			return ("sub %s, %s, %s"):format(dest, lhs, rhs)
		end
		if type(rhs) == "number" then
			return ("addi %s, %s, %+i"):format(dest, lhs, signed32(rhs))
		end
		return ("add %s, %s, %s"):format(dest, lhs, rhs)
	elseif op == 1 then
		if type(rhs) == "number" then
			return ("slli %s, %s, %i"):format(dest, lhs, bitx.band(rhs, 0x1F))
		end
		return ("sll %s, %s, %s"):format(dest, lhs, rhs)
	elseif op == 2 then
		if type(rhs) == "number" then
			return ("sltiu %s, %s, %i"):format(dest, lhs, rhs)
		end
		return ("sltu %s, %s, %s"):format(dest, lhs, rhs)
	elseif op == 3 then
		if type(rhs) == "number" then
			return ("slti %s, %s, %i"):format(dest, lhs, rhs)
		end
		return ("slt %s, %s, %s"):format(dest, lhs, rhs)
	elseif op == 4 then
		if type(rhs) == "number" then
			return ("xori %s, %s, 0x%08X"):format(dest, lhs, rhs)
		end
		return ("xor %s, %s, %s"):format(dest, lhs, rhs)
	elseif op == 5 then
		local variant = sra and "sra" or "srl"
		if type(rhs) == "number" then
			return ("%si %s, %s, %i"):format(variant, dest, lhs, bitx.band(rhs, 0x1F))
		end
		return ("%s %s, %s, %s"):format(variant, dest, lhs, rhs)
	elseif op == 6 then
		if type(rhs) == "number" then
			return ("ori %s, %s, 0x%08X"):format(dest, lhs, rhs)
		end
		return ("or %s, %s, %s"):format(dest, lhs, rhs)
	end
	if type(rhs) == "number" then
		return ("andi %s, %s, 0x%08X"):format(dest, lhs, rhs)
	end
	return ("and %s, %s, %s"):format(dest, lhs, rhs)
end

local function czero_op(op, lhs, rhs, dest)
	if bitx.band(op, 2) ~= 0 then
		return ("czero.nez %s, %s, %s"):format(dest, lhs, rhs)
	end
	return ("czero.eqz %s, %s, %s"):format(dest, lhs, rhs)
end

local function cond_op(op, lhs, rhs, target)
	local invert = bitx.band(op, 1) ~= 0
	local op_high = bitx.band(bitx.rshift(op, 1), 3)
	if op_high == 2 then
		if invert then
			return ("bge %s, %s, 0x%08X"):format(lhs, rhs, target)
		end
		return ("blt %s, %s, 0x%08X"):format(lhs, rhs, target)
	elseif op_high == 3 then
		if invert then
			return ("bgeu %s, %s, 0x%08X"):format(lhs, rhs, target)
		end
		return ("bltu %s, %s, 0x%08X"):format(lhs, rhs, target)
	end
	if invert then
		return ("bne %s, %s, 0x%08X"):format(lhs, rhs, target)
	end
	return ("beq %s, %s, 0x%08X"):format(lhs, rhs, target)
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

local function reg_name(index)
	return ("x%0i"):format(index)
end

local function disassemble(instr, pc)
	local rd  = bitx.band(bitx.rshift(instr,  7), 0x1F)
	local rs1 = bitx.band(bitx.rshift(instr, 15), 0x1F)
	local rs2 = bitx.band(bitx.rshift(instr, 20), 0x1F)
	if bitx.band(instr, 0x00000074) == 0x00000010 then
		return alu_op(
			bitx.band(bitx.rshift(instr, 12), 7),
			reg_name(rs1),
			imm_i(instr),
			bitx.band(bitx.rshift(instr, 20), 0x1F),
			bitx.band(instr, 0x40000000) ~= 0,
			false,
			reg_name(rd)
		)
	elseif bitx.band(instr, 0x00000074) == 0x00000030 then
		if bitx.band(instr, 0x06000000) == 0x06000000 then
			return czero_op(
				bitx.band(bitx.rshift(instr, 12), 7),
				reg_name(rs1),
				reg_name(rs2),
				reg_name(rd)
			)
		end
		if bitx.band(instr, 0x02000000) ~= 0 then
			local mul_op = bitx.band(bitx.rshift(instr, 12), 7)
			if mul_op == 3 then
				return ("mulhu %s, %s, %s"):format(reg_name(rd), reg_name(rs1), reg_name(rs2))
			elseif mul_op == 2 then
				return ("mulhsu %s, %s, %s"):format(reg_name(rd), reg_name(rs1), reg_name(rs2))
			elseif mul_op == 1 then
				return ("mulh %s, %s, %s"):format(reg_name(rd), reg_name(rs1), reg_name(rs2))
			end
			return ("mul %s, %s, %s"):format(reg_name(rd), reg_name(rs1), reg_name(rs2))
		end
		return alu_op(
			bitx.band(bitx.rshift(instr, 12), 7),
			reg_name(rs1),
			reg_name(rs2),
			reg_name(rs2),
			bitx.band(instr, 0x40000000) ~= 0,
			bitx.band(instr, 0x40000000) ~= 0,
			reg_name(rd)
		)
	elseif bitx.band(instr, 0x00000050) == 0x00000050 then
		return "hlt"
	elseif bitx.band(instr, 0x00000054) == 0x00000014 then
		local lui = bitx.band(instr, 0x00000020) ~= 0
		local value = clamp32(imm_u(instr) + (lui and 0 or pc))
		if lui then
			return ("lui %s, %+i"):format(reg_name(rd), value)
		end
		return ("auipc %s, 0x%08X"):format(reg_name(rd), value)
	elseif bitx.band(instr, 0x00000058) == 0x00000048 then
		return ("jal %s, 0x%08X"):format(reg_name(rd), clamp32(pc + imm_j(instr)))
	elseif bitx.band(instr, 0x0000005C) == 0x00000044 then
		return ("jalr %s, %s, %+i"):format(reg_name(rd), reg_name(rs1), imm_i(instr))
	elseif bitx.band(instr, 0x0000005C) == 0x00000040 then
		return cond_op(
			bitx.band(bitx.rshift(instr, 12), 7),
			reg_name(rs1),
			reg_name(rs2),
			clamp32(pc + imm_b(instr))
		)
	elseif bitx.band(instr, 0x00000070) == 0x00000020 then
		local size = access_size(bitx.band(bitx.rshift(instr, 12), 3))
		if size == 1 then
			return ("sb %s%+i, %s"):format(reg_name(rs1), imm_s(instr), reg_name(rs2))
		elseif size == 2 then
			return ("sh %s%+i, %s"):format(reg_name(rs1), imm_s(instr), reg_name(rs2))
		end
		return ("sw %s%+i, %s"):format(reg_name(rs1), imm_s(instr), reg_name(rs2))
	elseif bitx.band(instr, 0x00000074) == 0x00000000 then
		local size = access_size(bitx.band(bitx.rshift(instr, 12), 3))
		local op_sign_extend = bitx.band(instr, 0x4000) == 0
		if size == 1 then
			if op_sign_extend then
				return ("lb %s, %s%+i"):format(reg_name(rd), reg_name(rs1), imm_s(instr))
			else
				return ("lbu %s, %s%+i"):format(reg_name(rd), reg_name(rs1), imm_s(instr))
			end
		elseif size == 2 then
			if op_sign_extend then
				return ("lh %s, %s%+i"):format(reg_name(rd), reg_name(rs1), imm_s(instr))
			else
				return ("lhu %s, %s%+i"):format(reg_name(rd), reg_name(rs1), imm_s(instr))
			end
		end
		return ("lw %s, %s%+i"):format(reg_name(rd), reg_name(rs1), imm_s(instr))
	end
	if bitx.band(instr, 0x00001000) == 0x00001000 then
		return "fence.i"
	end
	return "fence"
end

return {
	disassemble = disassemble,
}

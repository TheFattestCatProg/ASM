if __compilerCodegenLoaded then return end
__compilerCodegenLoaded = true

Codegen = class()

function Codegen.new()
    local o = Codegen()
    o.codePtr = 0
    o.labels = {}
    o.requiredLabelsAt = {}
    o.jumps = {}
    o.ram = nil
    o.errors = {}
    return o
end

function Codegen:reset()
    self.codePtr = 0
    self.labels = {}
    self.requiredLabelsAt = {}
    self.jumps = {}
    self.ram = nil
    self.errors = {}
end

function Codegen:setRam(ram)
    self.ram = ram
end

function Codegen:incPtr(i)
    self.prevCodePtr = self.codePtr
    self.codePtr = self.codePtr + i
end

function Codegen:push_error(msg)
    self.errors[#self.errors+1] = msg
    print(msg)
end

Codegen.RegToNum = {
    ["%ip"] = 0,
    ["%sp"] = 1,
    ["%bsp"] = 2,
    ["%ax"] = 3,
    ["%bx"] = 4,
    ["%cx"] = 5,
    ["%dx"] = 6,

    ["%al"] = 7,
    ["%ah"] = 8,
    ["%bl"] = 9,
    ["%bh"] = 10,
    ["%cl"] = 11,
    ["%ch"] = 12,
    ["%dl"] = 13,
    ["%dh"] = 14,
}

function Codegen:generate_rr(act)
    self.ram:write(self.codePtr, act[2])
    local r1 = Codegen.RegToNum[act[3]]
    local r2 = Codegen.RegToNum[act[4]]
    self.ram:write(self.codePtr + 1, __or(__lshift(r1, 4), r2))
    self:incPtr(2)
end

function Codegen:generate_rrr(act)
    self.ram:write(self.codePtr, act[2])
    local r1 = Codegen.RegToNum[act[3]]
    local r2 = Codegen.RegToNum[act[4]]
    local r3 = Codegen.RegToNum[act[5]]
    self.ram:write(self.codePtr + 1, __or(__lshift(r1, 4), r2))
    self.ram:write(self.codePtr + 2, __lshift(r3, 4))
    self:incPtr(3)
end

function Codegen:generate_rv(act)
    self.ram:write(self.codePtr, act[2])
    local r = Codegen.RegToNum[act[3]]
    local baseVal = act[4]
    self.ram:write(self.codePtr + 1, r)
    if Parser.isRegSmall(r) then
        self.ram:write(self.codePtr + 2, baseVal)
        self:incPtr(3)
    else
        local v1 = __rshift(baseVal, 8)
        local v2 = __and(baseVal, 0xFF)
        self.ram:write(self.codePtr + 2, v1)
        self.ram:write(self.codePtr + 3, v2)
        self:incPtr(4)
    end
end

function Codegen:generate_rv8(act)
    self.ram:write(self.codePtr, act[2])
    local r = Codegen.RegToNum[act[3]]
    local baseVal = act[4]
    self.ram:write(self.codePtr + 1, r)

    self.ram:write(self.codePtr + 2, baseVal)
    self:incPtr(3)
end

function Codegen:generate_rv16(act) -- values always 16 bit
    self.ram:write(self.codePtr, act[2])
    local r = Codegen.RegToNum[act[3]]
    local baseVal = act[4]
    self.ram:write(self.codePtr + 1, r)

    local v1 = __rshift(baseVal, 8)
    local v2 = __and(baseVal, 0xFF)
    self.ram:write(self.codePtr + 2, v1)
    self.ram:write(self.codePtr + 3, v2)
    self:incPtr(4)
end

function Codegen:generate_rrv16(act)
    self.ram:write(self.codePtr, act[2])

    local r1 = Codegen.RegToNum[act[3]]
    local r2 = Codegen.RegToNum[act[4]]
    local baseVal = act[5]

    self.ram:write(self.codePtr + 1, __or(__lshift(r1, 4), r2))

    local v1 = __rshift(baseVal, 8)
    local v2 = __and(baseVal, 0xFF)
    self.ram:write(self.codePtr + 2, v1)
    self.ram:write(self.codePtr + 3, v2)
    self:incPtr(4)
end

function Codegen:generate_v16(act)
    self.ram:write(self.codePtr, act[2])
    local baseVal = act[3]

    local v1 = __rshift(baseVal, 8)
    local v2 = __and(baseVal, 0xFF)
    self.ram:write(self.codePtr + 2, v1)
    self.ram:write(self.codePtr + 3, v2)
    self:incPtr(3)
end

function Codegen:generate_r(act)
    self.ram:write(self.codePtr, act[2])

    local reg = Codegen.RegToNum[act[3]]
    self.ram:write(self.codePtr + 1, reg)
    self:incPtr(2)
end

function Codegen:generate_(act)
    self.ram:write(self.codePtr, act[2])
    self:incPtr(1)
end

function Codegen:generate_jump(act)
    local t = {
        [VmVOp.JP_W] = VmOp.MOV_RV,
        [VmVOp.JPE_W] = VmOp.CMOVE_RV,
        [VmVOp.JPNE_W] = VmOp.CMOVNE_RV,
        [VmVOp.JPG_W] = VmOp.CMOVG_RV,
        [VmVOp.JPL_W] = VmOp.CMOVL_RV,
        [VmVOp.JPGE_W] = VmOp.CMOVGE_RV,
        [VmVOp.JPLE_W] = VmOp.CMOVLE_RV,
        [VmVOp.JPA_W] = VmOp.CMOVA_RV,
        [VmVOp.JPB_W] = VmOp.CMOVB_RV,
        [VmVOp.JPAE_W] = VmOp.CMOVAE_RV,
        [VmVOp.JPBE_W] = VmOp.CMOVBE_RV,
    }

    local newOp = t[act[2]]
    local lbl = act[3]
    local genTable = Codegen.OpGenerate

    local l = self.requiredLabelsAt
    l[#l+1] = {self.codePtr + 2, lbl}

    local mv = {Parser.AstType.OP, newOp, "%ip", 0} -- cmovX %ip, LBL
    genTable[newOp](self, mv)
end

function Codegen:generate_call(act)
    local newOp = VmOp.CALL_V
    local lbl = act[3]
    local genTable = Codegen.OpGenerate

    local l = self.requiredLabelsAt
    l[#l+1] = {self.codePtr + 1, lbl}

    local call = {Parser.AstType.OP, newOp, 0} -- call LBL
    genTable[newOp](self, call)
end

function Codegen:generate_loop(act)
    local newOp = VmOp.LOOP_RV
    local r = act[3]
    local lbl = act[4]

    local l = self.requiredLabelsAt
    l[#l+1] = {self.codePtr + 2, lbl}

    local loop = {Parser.AstType.OP, newOp, r, 0} -- loop REG, LBL
    Codegen.OpGenerate[newOp](self, loop)
end

Codegen.OpGenerate = {
    [VmOp.HLT] = Codegen.generate_,

    [VmOp.MOV_RR] = Codegen.generate_rr,
    [VmOp.MOV_RV] = Codegen.generate_rv,

    [VmOp.ADD_RR] = Codegen.generate_rr,
    [VmOp.ADD_RV] = Codegen.generate_rv,
    [VmOp.SUB_RR] = Codegen.generate_rr,
    [VmOp.SUB_RV] = Codegen.generate_rv,
    [VmOp.MUL_RR] = Codegen.generate_rr,
    [VmOp.MUL_RV] = Codegen.generate_rv,
    [VmOp.DIV_RR] = Codegen.generate_rr,
    [VmOp.DIV_RV] = Codegen.generate_rv,
    [VmOp.IDIV_RR] = Codegen.generate_rr,
    [VmOp.IDIV_RV] = Codegen.generate_rv,

    [VmOp.RD_RR] = Codegen.generate_rr,
    [VmOp.RD_RV] = Codegen.generate_rv16,
    [VmOp.RD_RRR] = Codegen.generate_rrr,
    [VmOp.RD_RRV] = Codegen.generate_rrv16,
    [VmOp.WR_RR] = Codegen.generate_rr,
    [VmOp.WR_RV] = Codegen.generate_rv16,
    [VmOp.WR_RRR] = Codegen.generate_rrr,
    [VmOp.WR_RRV] = Codegen.generate_rrv16,

    [VmOp.PUSH_R] = Codegen.generate_r,
    [VmOp.POP_R] = Codegen.generate_r,

    [VmOp.CMP_RR] = Codegen.generate_rr,
    [VmOp.CMP_RV] = Codegen.generate_rv,

    [VmOp.CMOVE_RR] = Codegen.generate_rr,
    [VmOp.CMOVE_RV] = Codegen.generate_rv,
    [VmOp.CMOVNE_RR] = Codegen.generate_rr,
    [VmOp.CMOVNE_RV] = Codegen.generate_rv,
    [VmOp.CMOVG_RR] = Codegen.generate_rr,
    [VmOp.CMOVG_RV] = Codegen.generate_rv,
    [VmOp.CMOVL_RR] = Codegen.generate_rr,
    [VmOp.CMOVL_RV] = Codegen.generate_rv,
    [VmOp.CMOVGE_RR] = Codegen.generate_rr,
    [VmOp.CMOVGE_RV] = Codegen.generate_rv,
    [VmOp.CMOVLE_RR] = Codegen.generate_rr,
    [VmOp.CMOVLE_RV] = Codegen.generate_rv,
    [VmOp.CMOVA_RR] = Codegen.generate_rr,
    [VmOp.CMOVA_RV] = Codegen.generate_rv,
    [VmOp.CMOVB_RR] = Codegen.generate_rr,
    [VmOp.CMOVB_RV] = Codegen.generate_rv,
    [VmOp.CMOVAE_RR] = Codegen.generate_rr,
    [VmOp.CMOVAE_RV] = Codegen.generate_rv,
    [VmOp.CMOVBE_RR] = Codegen.generate_rr,
    [VmOp.CMOVBE_RV] = Codegen.generate_rv,

    [VmOp.CALL_V] = Codegen.generate_v16,
    [VmOp.RET] = Codegen.generate_,

    [VmOp.SHR_RR] = Codegen.generate_rr,
    [VmOp.SHR_RV] = Codegen.generate_rv8,
    [VmOp.SHL_RR] = Codegen.generate_rr,
    [VmOp.SHL_RV] = Codegen.generate_rv8,

    [VmOp.AND_RR] = Codegen.generate_rr,
    [VmOp.AND_RV] = Codegen.generate_rv,
    [VmOp.OR_RR] = Codegen.generate_rr,
    [VmOp.OR_RV] = Codegen.generate_rv,
    [VmOp.XOR_RR] = Codegen.generate_rr,
    [VmOp.XOR_RV] = Codegen.generate_rv,

    [VmOp.NOT_R] = Codegen.generate_r,
    [VmOp.NEG_R] = Codegen.generate_r,
    [VmOp.ABS_R] = Codegen.generate_r,

    [VmOp.MOD_RR] = Codegen.generate_rr,
    [VmOp.MOD_RV] = Codegen.generate_rv,
    [VmOp.IMOD_RR] = Codegen.generate_rr,
    [VmOp.IMOD_RV] = Codegen.generate_rv,

    [VmOp.OUT_RR] = Codegen.generate_rr,
    [VmOp.OUT_RV] = Codegen.generate_rv8,
    [VmOp.IN_RR] = Codegen.generate_rr,
    [VmOp.IN_RV] = Codegen.generate_rv8,

    [VmOp.INC_R] = Codegen.generate_r,
    [VmOp.DEC_R] = Codegen.generate_r,

    [VmOp.LOOP_RV] = Codegen.generate_rv16,

    [VmVOp.JP_W] = Codegen.generate_jump,
    [VmVOp.JPE_W] = Codegen.generate_jump,
    [VmVOp.JPNE_W] = Codegen.generate_jump,
    [VmVOp.JPG_W] = Codegen.generate_jump,
    [VmVOp.JPL_W] = Codegen.generate_jump,
    [VmVOp.JPGE_W] = Codegen.generate_jump,
    [VmVOp.JPLE_W] = Codegen.generate_jump,
    [VmVOp.JPA_W] = Codegen.generate_jump,
    [VmVOp.JPB_W] = Codegen.generate_jump,
    [VmVOp.JPAE_W] = Codegen.generate_jump,
    [VmVOp.JPBE_W] = Codegen.generate_jump,

    [VmVOp.CALL_W] = Codegen.generate_call,
    [VmVOp.LOOP_RW] = Codegen.generate_loop,
}

assert(#Codegen.OpGenerate == VmVOp.LAST - 1)

function Codegen:generate(actions)
    -- 1 step: generate prelude
    local genTable = Codegen.OpGenerate
    local stackStart = {Parser.AstType.OP, VmOp.MOV_RV, "%sp", 0} -- mov %sp, XX where XX start of stack
    genTable[stackStart[2]](self, stackStart)

    local stackBaseStart = {Parser.AstType.OP, VmOp.MOV_RV, "%bsp", 0} -- mov %bsp, XX where XX start of stack
    genTable[stackStart[2]](self, stackBaseStart)

    -- 2 step: generate main code
    for i, v in ipairs(actions) do
        if v[1] == Parser.AstType.LABEL then
            self.labels[v[2]] = self.codePtr
        elseif v[1] == Parser.AstType.OP then
            if v[2] == VmOp.MOV_RV and v[3] == 0 and type(v[4]) == "string" then -- v[3] == %ip && v[4] = label
                self.jumps[v[4]] = self.codePtr
                self:incPtr(4)
            else
                genTable[v[2]](self, v)
            end
        else
            error("unknown type in codegen "..v[1])
        end
    end
    -- *3 step: add hlt to the end
    --local hlt = {Parser.AstType.OP, VmOp.HLT}
    --genTable[hlt[2]](self, hlt)

    -- 4 step: put stack start addr
    local cp = self.codePtr
    self.ram:write(2, __rshift(cp, 8))
    self.ram:write(3, __and(cp, 0xFF))
    self.ram:write(6, __rshift(cp, 8))
    self.ram:write(7, __and(cp, 0xFF))

    -- 5 step: insert labels
    for i, v in ipairs(self.requiredLabelsAt) do
        local where = v[1]
        local lblVal = self.labels[v[2]]

        if lblVal then
            self.ram:write(where, __rshift(lblVal, 8))
            self.ram:write(where + 1, __and(lblVal, 0xFF))
        else
            self:push_error("cannot find label '"..v[2].."'")
        end
    end
end
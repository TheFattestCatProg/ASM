if __vmModuleLoaded then return end
__vmModuleLoaded = true
dofile("ram.lua")
dofile("parser.lua")
dofile('op_enum.lua')

AsmVm = class()

function AsmVm.new()
    local obj = AsmVm()
    obj.regs = {
        [0] = 0, -- %ip     16 bits  instruction pointer
        [1] = 0, -- %sp     16 bits  stack pointer ; stack grows to up
        [2] = 0, -- %bsp    16 bits  base stack pointer
        [3] = 0, -- %ax     16 bits
        [4] = 0, -- %bx     16 bits
        [5] = 0, -- %cx     16 bits
        [6] = 0, -- %dx     16 bits
      --[7, 8] = %al, %ah   8 bits
      --[9, 10] = %bl, %bh  8 bits
      --[11, 12] = %cl, %ch 8 bits
      --[13, 14] = %dl, %dh 8 bits
    }
    obj.cmpResult = {
        signed = 0,     -- reg1-reg2 signed
        unsigned = 0,   -- reg1-reg2 unsigned
    }

    obj.ram = nil
    obj.status = AsmVm.Status.STOPPED

    obj.onOut = nil -- (where, val) -> void
    obj.onIn = nil -- (from) -> val

    return obj
end

function AsmVm:reset()
    for k in pairs(self.regs) do
        self.regs[k] = 0
    end
    self.cmpResult = {
        signed = 0,     -- reg1-reg2 signed
        unsigned = 0,   -- reg1-reg2 unsigned
    }

    self.status = AsmVm.Status.STOPPED
end

function AsmVm:getReg(r)
    assert(r >= 0 and r <= 14)
    local v = self.regs[r]
    if v then return v end
    -- now get xl or xh reg
    local baseRegVal = self.regs[__floor(r / 2 - 0.5)]
    if r % 2 == 1 then
        return __and(baseRegVal, 0xFF)
    else
        return __rshift(baseRegVal, 8)
    end
end

function AsmVm:getRegSigned(r)
    if self:isRegSmall(r) then
        return __toSigned8(self:getReg(r))
    else
        return __toSigned16(self:getReg(r))
    end
end

function AsmVm:setReg(r, val)
    local regs = self.regs
    if regs[r] then
        regs[r] = __and(val, 0xFFFF)
        return
    end

    -- write to xl or xh
    val = __and(val, 0xFF)

    local baseReg = __floor(r / 2 - 0.5)
    local baseRegVal = self.regs[baseReg]
    if r % 2 == 1 then
        regs[baseReg] = __or(__and(baseRegVal, 0xFF00), val)
    else
        regs[baseReg] = __or(__and(baseRegVal, 0x00FF), __lshift(val, 8))
    end
end

function AsmVm:interpret(instr)
    local f = AsmVm.Instruction[instr]
    if not f then
        self:stop()
        return
    end
    f(self)
end

function AsmVm:update()
    if self.status == AsmVm.Status.STOPPED or self.status == AsmVm.Status.ERROR then return end

    local r, err = pcall(function () self:interpret(self:ipRead(0)) end)
    if not r then self.status = AsmVm.Status.ERROR end
end

function AsmVm:incIp(v)
    local regs = self.regs
    regs[0] = regs[0] + v
end

function AsmVm:ipRead(offset)
    return self.ram:read(self.regs[0] + offset)
end

function AsmVm:isRegSmall(r)
    return r >= 7 and r <= 14
end

function AsmVm:stop()
    self.status = AsmVm.Status.STOPPED
end

function AsmVm:canWork()
    return self.status ~= AsmVm.Status.STOPPED and self.status ~= AsmVm.Status.ERROR
end

function AsmVm:hasError()
    return self.status == AsmVm.Status.ERROR
end

function AsmVm:start()
    assert(self.status == AsmVm.Status.STOPPED)
    self.status = AsmVm.Status.RUNNING
end

function AsmVm:wait()
    assert(self.status == AsmVm.Status.RUNNING)
    self.status = AsmVm.Status.WAITING
end

function AsmVm:stopWaiting()
    assert(self.status == AsmVm.Status.WAITING)
    self.status = AsmVm.Status.RUNNING
end

function AsmVm:push8(v)
    local ptr = self.regs[1]
    self.ram:write(ptr, v)
    self.regs[1] = ptr + 1
end

function AsmVm:push16(v)
    local ram = self.ram
    local ptr = self.regs[1]
    ram:write(ptr, __rshift(v, 8))
    ram:write(ptr + 1, __and(v, 0xFF))

    self.regs[1] = ptr + 2
end

function AsmVm:pop8()
    local ptr = self.regs[1]
    local resVal = self.ram:read(ptr - 1)
    self.regs[1] = ptr - 1
    return resVal
end

function AsmVm:pop16()
    local ptr = self.regs[1]
    local ram = self.ram
    local resVal = __or(__lshift(ram:read(ptr - 2), 8), ram:read(ptr - 1))
    self.regs[1] = ptr - 2
    return resVal
end

-- IMPORTANT: call setReg after incrementing %ip
AsmVm.Instruction = {
    [VmOp.HLT] = AsmVm.stop,       -- 0 bytes
    [VmOp.MOV_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)

        local val = vm:getReg(r2)
        vm:incIp(2)

        vm:setReg(r1, val)
    end,
    [VmOp.MOV_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            local val = vm:ipRead(2)
            vm:incIp(3)
            vm:setReg(r, val)
        else
            local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
            vm:incIp(4)
            vm:setReg(r, val)
        end
    end,
    [VmOp.ADD_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local val = vm:getReg(r1) + vm:getReg(r2)
        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.ADD_RV] = function(vm)      -- 3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            local val = vm:getReg(r) + vm:ipRead(2)
            vm:incIp(3)
            vm:setReg(r, val)
        else
            local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
            vm:incIp(4)
            vm:setReg(r, vm:getReg(r) + val)
        end
    end,
    [VmOp.SUB_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local val = vm:getReg(r1) - vm:getReg(r2)
        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.SUB_RV] = function(vm)      -- 3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            local val = vm:getReg(r) - vm:ipRead(2)
            vm:incIp(3)
            vm:setReg(r, val)
        else
            local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
            vm:incIp(4)
            vm:setReg(r, vm:getReg(r) - val)
        end
    end,
    [VmOp.MUL_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local val = vm:getReg(r1) * vm:getReg(r2)
        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.MUL_RV] = function(vm)      -- 3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            local val = vm:getReg(r) * vm:ipRead(2)
            vm:incIp(3)
            vm:setReg(r, val)
        else
            local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
            vm:incIp(4)
            vm:setReg(r, vm:getReg(r) * val)
        end
    end,
    [VmOp.DIV_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local val = __floor(vm:getReg(r1) / vm:getReg(r2))
        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.DIV_RV] = function(vm)     -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            local val = __floor(vm:getReg(r) / vm:ipRead(2))
            vm:incIp(3)
            vm:setReg(r, val)
        else
            local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
            local resVal = __floor(vm:getReg(r) / val)
            vm:incIp(4)
            vm:setReg(r, resVal)
        end
    end,
    [VmOp.IDIV_RR] = function(vm)     -- 2-3 bytes
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local val = __floor(vm:getRegSigned(r1) / vm:getRegSigned(r2))
        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.IDIV_RV] = function(vm)     -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            local val = __toSigned8(vm:ipRead(2))
            local resVal = __floor(vm:getRegSigned(r) / val)
            vm:incIp(3)
            vm:setReg(r, resVal)
        else
            local val = __toSigned16(__or(__lshift(vm:ipRead(2), 8), vm:ipRead(3)))
            local resVal = __floor(vm:getRegSigned(r) / val)
            vm:incIp(4)
            vm:setReg(r, resVal)
        end
    end,
    [VmOp.RD_RR] = function(vm)     -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local ptr = vm:getReg(__and(b, 0xF))

        local val = 0
        if vm:isRegSmall(r1) then
            val = vm.ram:read(ptr)
        else
            val = __or(__lshift(vm.ram:read(ptr), 8), vm.ram:read(ptr + 1))
        end

        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.RD_RV] = function(vm)     -- 3 bytes
        local r = vm:ipRead(1)
        local ptr = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))

        local val = 0
        if vm:isRegSmall(r) then
            val = vm.ram:read(ptr)
        else
            val = __or(__lshift(vm.ram:read(ptr), 8), vm.ram:read(ptr + 1))
        end

        vm:incIp(4)
        vm:setReg(r, val)
    end,
    [VmOp.RD_RRR] = function(vm)    -- 2 bytes
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)

        local ptr = vm:getReg(__and(b, 0xF))
        local offset = vm:getReg(__rshift(vm:ipRead(2), 4))
        ptr = __and(ptr + offset, 0xFFFF)
        

        local val = 0
        if vm:isRegSmall(r1) then
            val = vm.ram:read(ptr)
        else
            val = __or(__lshift(vm.ram:read(ptr), 8), vm.ram:read(ptr + 1))
        end

        vm:incIp(3)
        vm:setReg(r1, val)
    end,
    [VmOp.RD_RRV] = function(vm)    -- 3 bytes
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)

        local ptr = vm:getReg(__and(b, 0xF))
        local offset = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
        ptr = __and(ptr + offset, 0xFFFF)
        

        local val = 0
        if vm:isRegSmall(r1) then
            val = vm.ram:read(ptr)
        else
            val = __or(__lshift(vm.ram:read(ptr), 8), vm.ram:read(ptr + 1))
        end

        vm:incIp(4)
        vm:setReg(r1, val)
    end,
    [VmOp.WR_RR] = function(vm)     -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local ptr = vm:getReg(__and(b, 0xF))

        if vm:isRegSmall(r1) then
            vm.ram:write(ptr, vm:getReg(r1))
        else
            local rv = vm:getReg(r1)
            local ram = vm.ram
            ram:write(ptr, __rshift(rv, 8))
            ram:write(ptr + 1, __and(rv, 0xFF))
        end

        vm:incIp(2)
    end,
    [VmOp.WR_RV] = function(vm)     -- 3 bytes
        local r = vm:ipRead(1)
        local ptr = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))

        if vm:isRegSmall(r) then
            vm.ram:write(ptr, vm:getReg(r))
        else
            local rv = vm:getReg(r)
            local ram = vm.ram
            ram:write(ptr, __rshift(rv, 8))
            ram:write(ptr + 1, __and(rv, 0xFF))
        end

        vm:incIp(4)
    end,
    [VmOp.WR_RRR] = function(vm)    -- 2 bytes
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)

        local ptr = vm:getReg(__and(b, 0xF))
        local offset = vm:getReg(__rshift(vm:ipRead(2), 4))
        ptr = __and(ptr + offset, 0xFFFF)

        if vm:isRegSmall(r1) then
            vm.ram:write(ptr, vm:getReg(r1))
        else
            local rv = vm:getReg(r1)
            local ram = vm.ram
            ram:write(ptr, __rshift(rv, 8))
            ram:write(ptr + 1, __and(rv, 0xFF))
        end

        vm:incIp(3)
    end,
    [VmOp.WR_RRV] = function(vm)    -- 3 bytes
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)

        local ptr = vm:getReg(__and(b, 0xF))
        local offset = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
        ptr = __and(ptr + offset, 0xFFFF)

        if vm:isRegSmall(r1) then
            vm.ram:write(ptr, vm:getReg(r1))
        else
            local rv = vm:getReg(r1)
            local ram = vm.ram
            ram:write(ptr, __rshift(rv, 8))
            ram:write(ptr + 1, __and(rv, 0xFF))
        end

        vm:incIp(4)
    end,
    [VmOp.PUSH_R] = function(vm)     -- 1 byte
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            vm:push8(vm:getReg(r))
        else
            vm:push16(vm:getReg(r))
        end

        vm:incIp(2)
    end,
    [VmOp.POP_R] = function(vm)     -- 1 byte
        local r = vm:ipRead(1)

        local resVal = 0
        if vm:isRegSmall(r) then
            resVal = vm:pop8()
        else
            resVal = vm:pop16()
        end

        vm:incIp(2)
        vm:setReg(r, resVal)
    end,
    [VmOp.CMP_RR] = function (vm)   -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)

        local r1u = vm:getReg(r1)
        local r2u = vm:getReg(r2)
        local r1s = 0
        local r2s = 0

        if vm:isRegSmall(r1) then
            r1s = __toSigned8(r1u)
        else
            r1s = __toSigned16(r1u)
        end

        if vm:isRegSmall(r2) then
            r2s = __toSigned8(r2u)
        else
            r2s = __toSigned16(r2u)
        end

        vm.cmpResult.signed = r1s - r2s
        vm.cmpResult.unsigned = r1u - r2u

        vm:incIp(2)
    end,
    [VmOp.CMP_RV] = function (vm)   -- 2-3 bytes
        local r = vm:ipRead(1)

        local vu = 0
        local vs = 0
        if vm:isRegSmall(r) then
            vu = vm:ipRead(2)
            vs = __toSigned8(vu)

            vm:incIp(3)
        else
            vu = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
            vs = __toSigned16(vu)

            vm:incIp(4)
        end

        local ru = vm:getReg(r)
        local rs = 0
        if vm:isRegSmall(r) then
            rs = __toSigned8(ru)
        else
            rs = __toSigned16(ru)
        end

        vm.cmpResult.signed = rs - vs
        vm.cmpResult.unsigned = ru - vu
    end,
    [VmOp.CMOVE_RR] = function(vm)      -- 1 byte
        if vm.cmpResult.unsigned == 0 then
            local b = vm:ipRead(1)
            local r1 = __rshift(b, 4)
            local r2 = __and(b, 0xF)
            local val = vm:getReg(r2)
            vm:incIp(2)
            vm:setReg(r1, val)
        else
            vm:incIp(2)
        end
    end,
    [VmOp.CMOVE_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            if vm.cmpResult.unsigned == 0 then
                local val = vm:ipRead(2)
                vm:incIp(3)
                vm:setReg(r, val)
            else
                vm:incIp(3)
            end
        else
            if vm.cmpResult.unsigned == 0 then
                local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
                vm:incIp(4)
                vm:setReg(r, val)
            else
                vm:incIp(4)
            end
        end
    end,
    [VmOp.CMOVNE_RR] = function(vm)      -- 1 byte
        if vm.cmpResult.unsigned ~= 0 then
            local b = vm:ipRead(1)
            local r1 = __rshift(b, 4)
            local r2 = __and(b, 0xF)
            local val = vm:getReg(r2)
            vm:incIp(2)
            vm:setReg(r1, val)
        else
            vm:incIp(2)
        end
    end,
    [VmOp.CMOVNE_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            if vm.cmpResult.unsigned ~= 0 then
                local val = vm:ipRead(2)
                vm:incIp(3)
                vm:setReg(r, val)
            else
                vm:incIp(3)
            end
        else
            if vm.cmpResult.unsigned ~= 0 then
                local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
                vm:incIp(4)
                vm:setReg(r, val)
            else
                vm:incIp(4)
            end
        end
    end,
    [VmOp.CMOVG_RR] = function(vm)      -- 1 byte
        if vm.cmpResult.signed > 0 then
            local b = vm:ipRead(1)
            local r1 = __rshift(b, 4)
            local r2 = __and(b, 0xF)
            local val = vm:getReg(r2)
            vm:incIp(2)
            vm:setReg(r1, val)
        else
            vm:incIp(2)
        end
    end,
    [VmOp.CMOVG_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            if vm.cmpResult.signed > 0 then
                local val = vm:ipRead(2)
                vm:incIp(3)
                vm:setReg(r, val)
            else
                vm:incIp(3)
            end
        else
            if vm.cmpResult.signed > 0 then
                local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
                vm:incIp(4)
                vm:setReg(r, val)
            else
                vm:incIp(4)
            end
        end
    end,
    [VmOp.CMOVL_RR] = function(vm)      -- 1 byte
        if vm.cmpResult.signed < 0 then
            local b = vm:ipRead(1)
            local r1 = __rshift(b, 4)
            local r2 = __and(b, 0xF)
            local val = vm:getReg(r2)
            vm:incIp(2)
            vm:setReg(r1, val)
        else
            vm:incIp(2)
        end
    end,
    [VmOp.CMOVL_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            if vm.cmpResult.signed < 0 then
                local val = vm:ipRead(2)
                vm:incIp(3)
                vm:setReg(r, val)
            else
                vm:incIp(3)
            end
        else
            if vm.cmpResult.signed < 0 then
                local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
                vm:incIp(4)
                vm:setReg(r, val)
            else
                vm:incIp(4)
            end
        end
    end,
    [VmOp.CMOVGE_RR] = function(vm)      -- 1 byte
        if vm.cmpResult.signed >= 0 then
            local b = vm:ipRead(1)
            local r1 = __rshift(b, 4)
            local r2 = __and(b, 0xF)
            local val = vm:getReg(r2)
            vm:incIp(2)
            vm:setReg(r1, val)
        else
            vm:incIp(2)
        end
    end,
    [VmOp.CMOVGE_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            if vm.cmpResult.signed >= 0 then
                local val = vm:ipRead(2)
                vm:incIp(3)
                vm:setReg(r, val)
            else
                vm:incIp(3)
            end
        else
            if vm.cmpResult.signed >= 0 then
                local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
                vm:incIp(4)
                vm:setReg(r, val)
            else
                vm:incIp(4)
            end
        end
    end,
    [VmOp.CMOVLE_RR] = function(vm)      -- 1 byte
        if vm.cmpResult.signed <= 0 then
            local b = vm:ipRead(1)
            local r1 = __rshift(b, 4)
            local r2 = __and(b, 0xF)
            local val = vm:getReg(r2)
            vm:incIp(2)
            vm:setReg(r1, val)
        else
            vm:incIp(2)
        end
    end,
    [VmOp.CMOVLE_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            if vm.cmpResult.signed <= 0 then
                local val = vm:ipRead(2)
                vm:incIp(3)
                vm:setReg(r, val)
            else
                vm:incIp(3)
            end
        else
            if vm.cmpResult.signed <= 0 then
                local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
                vm:incIp(4)
                vm:setReg(r, val)
            else
                vm:incIp(4)
            end
        end
    end,
    [VmOp.CMOVA_RR] = function(vm)      -- 1 byte
        if vm.cmpResult.unsigned > 0 then
            local b = vm:ipRead(1)
            local r1 = __rshift(b, 4)
            local r2 = __and(b, 0xF)
            local val = vm:getReg(r2)
            vm:incIp(2)
            vm:setReg(r1, val)
        else
            vm:incIp(2)
        end
    end,
    [VmOp.CMOVA_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            if vm.cmpResult.unsigned > 0 then
                local val = vm:ipRead(2)
                vm:incIp(3)
                vm:setReg(r, val)
            else
                vm:incIp(3)
            end
        else
            if vm.cmpResult.unsigned > 0 then
                local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
                vm:incIp(4)
                vm:setReg(r, val)
            else
                vm:incIp(4)
            end
        end
    end,
    [VmOp.CMOVB_RR] = function(vm)      -- 1 byte
        if vm.cmpResult.unsigned < 0 then
            local b = vm:ipRead(1)
            local r1 = __rshift(b, 4)
            local r2 = __and(b, 0xF)
            local val = vm:getReg(r2)
            vm:incIp(2)
            vm:setReg(r1, val)
        else
            vm:incIp(2)
        end
    end,
    [VmOp.CMOVB_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            if vm.cmpResult.unsigned < 0 then
                local val = vm:ipRead(2)
                vm:incIp(3)
                vm:setReg(r, val)
            else
                vm:incIp(3)
            end
        else
            if vm.cmpResult.unsigned < 0 then
                local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
                vm:incIp(4)
                vm:setReg(r, val)
            else
                vm:incIp(4)
            end
        end
    end,
    [VmOp.CMOVAE_RR] = function(vm)      -- 1 byte
        if vm.cmpResult.unsigned >= 0 then
            local b = vm:ipRead(1)
            local r1 = __rshift(b, 4)
            local r2 = __and(b, 0xF)
            local val = vm:getReg(r2)
            vm:incIp(2)
            vm:setReg(r1, val)
        else
            vm:incIp(2)
        end
    end,
    [VmOp.CMOVAE_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            if vm.cmpResult.unsigned >= 0 then
                local val = vm:ipRead(2)
                vm:incIp(3)
                vm:setReg(r, val)
            else
                vm:incIp(3)
            end
        else
            if vm.cmpResult.unsigned >= 0 then
                local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
                vm:incIp(4)
                vm:setReg(r, val)
            else
                vm:incIp(4)
            end
        end
    end,
    [VmOp.CMOVBE_RR] = function(vm)      -- 1 byte
        if vm.cmpResult.unsigned <= 0 then
            local b = vm:ipRead(1)
            local r1 = __rshift(b, 4)
            local r2 = __and(b, 0xF)
            local val = vm:getReg(r2)
            vm:incIp(2)
            vm:setReg(r1, val)
        else
            vm:incIp(2)
        end
    end,
    [VmOp.CMOVBE_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            if vm.cmpResult.unsigned <= 0 then
                local val = vm:ipRead(2)
                vm:incIp(3)
                vm:setReg(r, val)
            else
                vm:incIp(3)
            end
        else
            if vm.cmpResult.unsigned <= 0 then
                local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
                vm:incIp(4)
                vm:setReg(r, val)
            else
                vm:incIp(4)
            end
        end
    end,
    [VmOp.CALL_V] = function (vm)      -- 2 bytes
        local regs = vm.regs
        local jmp = __or(__lshift(vm:ipRead(1), 8), vm:ipRead(2))

        vm:push16(regs[0])

        regs[0] = jmp
    end,
    [VmOp.RET] = function (vm)      -- 0 bytes
        local regs = vm.regs
        local jmp = vm:pop16() + 3 -- magic offset (len of call_v)
        regs[0] = jmp
    end,
    [VmOp.AND_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local val = __and(vm:getReg(r1), vm:getReg(r2))
        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.AND_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            local val = __and(vm:getReg(r), vm:ipRead(2))
            vm:incIp(3)
            vm:setReg(r, val)
        else
            local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
            vm:incIp(4)
            vm:setReg(r, __and(vm:getReg(r), val))
        end
    end,
    [VmOp.OR_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local val = __or(vm:getReg(r1), vm:getReg(r2))
        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.OR_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            local val = __or(vm:getReg(r), vm:ipRead(2))
            vm:incIp(3)
            vm:setReg(r, val)
        else
            local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
            vm:incIp(4)
            vm:setReg(r, __or(vm:getReg(r), val))
        end
    end,
    [VmOp.XOR_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local val = __xor(vm:getReg(r1), vm:getReg(r2))
        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.XOR_RV] = function(vm)      -- 3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            local val = __xor(vm:getReg(r), vm:ipRead(2))
            vm:incIp(3)
            vm:setReg(r, val)
        else
            local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
            vm:incIp(4)
            vm:setReg(r, __xor(vm:getReg(r), val))
        end
    end,
    [VmOp.NOT_R] = function(vm)      -- 1 byte
        local r = vm:ipRead(1)
        local val = 0
        if vm:isRegSmall(r) then
            val = __not(vm:getReg(r))
        else
            val = __not(vm:getReg(r))
        end
        vm:incIp(2)
        vm:setReg(r, val)
    end,
    [VmOp.NEG_R] = function(vm)      -- 1 byte
        local r = vm:ipRead(1)
        local val = 0
        if vm:isRegSmall(r) then
            val = -vm:getReg(r)
        else
            val = -vm:getReg(r)
        end
        vm:incIp(2)
        vm:setReg(r, val)
    end,
    [VmOp.SHR_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local s = vm:getReg(r2)

        local val = __rshift(vm:getReg(r1), s)
        if s > 16 then val = 0 end

        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.SHR_RV] = function(vm)      -- 2 bytes
        local r = vm:ipRead(1)
        local s = vm:ipRead(2)

        local val = __rshift(vm:getReg(r), s)
        if s > 16 then val = 0 end

        vm:incIp(3)
        vm:setReg(r, val)
    end,
    [VmOp.SHL_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local s = vm:getReg(r2)

        local val = __lshift(vm:getReg(r1), s)
        if s > 16 then val = 0 end

        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.SHL_RV] = function(vm)      -- 2 bytes
        local r = vm:ipRead(1)
        local s = vm:ipRead(2)

        local val = __lshift(vm:getReg(r), s)
        if s > 16 then val = 0 end

        vm:incIp(3)
        vm:setReg(r, val)
    end,
    [VmOp.ABS_R] = function(vm)      -- 1 byte
        local r = vm:ipRead(1)
        local val = __abs(vm:getRegSigned(r))

        vm:incIp(2)
        vm:setReg(r, val)
    end,
    [VmOp.MOD_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local val = vm:getReg(r1) % vm:getReg(r2)
        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.MOD_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            local val = vm:getReg(r) % vm:ipRead(2)
            vm:incIp(3)
            vm:setReg(r, val)
        else
            local val = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
            vm:incIp(4)
            vm:setReg(r, vm:getReg(r) % val)
        end
    end,
    [VmOp.IMOD_RR] = function(vm)      -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)
        local val = vm:getRegSigned(r1) % vm:getRegSigned(r2)
        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.IMOD_RV] = function(vm)      -- 2-3 bytes
        local r = vm:ipRead(1)
        if vm:isRegSmall(r) then
            local val = vm:getRegSigned(r) % __toSigned8(vm:ipRead(2))
            vm:incIp(3)
            vm:setReg(r, val)
        else
            local val = __toSigned16(__or(__lshift(vm:ipRead(2), 8), vm:ipRead(3)))
            vm:incIp(4)
            vm:setReg(r, vm:getRegSigned(r) % val)
        end
    end,
    [VmOp.OUT_RR] = function(vm)        -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)

        local what = vm:getReg(r1)
        local where = __and(vm:getReg(r2), 0xFF)

        vm.onOut(where, what)

        vm:incIp(2)
    end,
    [VmOp.OUT_RV] = function(vm)        -- 2 bytes
        local r = vm:ipRead(1)

        local what = vm:getReg(r)
        local where = vm:ipRead(2)

        vm.onOut(where, what)

        vm:incIp(3)
    end,
    [VmOp.IN_RR] = function(vm)         -- 1 byte
        local b = vm:ipRead(1)
        local r1 = __rshift(b, 4)
        local r2 = __and(b, 0xF)

        local from = __and(vm:getReg(r2), 0xFF)
        local val = vm.onIn(from)

        vm:incIp(2)
        vm:setReg(r1, val)
    end,
    [VmOp.IN_RV] = function(vm)         -- 2 bytes
        local r = vm:ipRead(1)

        local from = vm:ipRead(2)
        local val = vm.onIn(from)

        vm:incIp(3)
        vm:setReg(r, val)
    end,
    [VmOp.INC_R] = function(vm)         -- 1 byte
        local r = vm:ipRead(1)
        local val = vm:getReg(r) + 1

        vm:incIp(2)
        vm:setReg(r, val)
    end,
    [VmOp.DEC_R] = function(vm)         -- 1 byte
        local r = vm:ipRead(1)
        local val = vm:getReg(r) - 1

        vm:incIp(2)
        vm:setReg(r, val)
    end,
    [VmOp.LOOP_RV] = function (vm)      -- 3 bytes
        local r = vm:ipRead(1)
        local val = vm:getReg(r)

        if val ~= 0 then
            vm.regs[0] = __or(__lshift(vm:ipRead(2), 8), vm:ipRead(3))
            vm:setReg(r, val - 1)
        else
            vm:incIp(4)
        end
    end
}

assert(#AsmVm.Instruction == VmOp.LAST - 1)

AsmVm.Status = {
    STOPPED = 1,
    WAITING = 2,
    RUNNING = 3,
    ERROR = 4,
}
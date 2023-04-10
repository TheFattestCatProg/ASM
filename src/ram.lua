if __vmRamModuleLoaded then return end
__vmRamModuleLoaded = true

dofile('util.lua')

VmRam = class()

function VmRam.new(size)
    assert(type(size) == "number" and size >= 0 and size % 1 == 0)

    local obj = VmRam()
    obj.pool = {}
    obj.size = size
    return obj
end

function VmRam:isAddrValid(addr)
    if type(addr) == "number" and addr % 1 == 0 and addr >= 0 and addr < self.size then
        return true
    end
    return false
end

function VmRam:read(addr)
    assert(self:isAddrValid(addr), "bad address "..addr)

    local d = __floor(addr / 3)
    local shift = addr % 3 * 8

    local v = self.pool[d + 1] or 0

    return __and(__rshift(v, shift), 0xFF)
end

function VmRam:write(addr, what)
    assert(self:isAddrValid(addr), "bad address "..addr)
    --assert(type(what) == "number" and what % 1 == 0 and what >= 0 and what <= 255)

    local d = __floor(addr / 3)
    local shift = addr % 3 * 8
    local v = self.pool[d + 1] or 0

    local mask = __not(__lshift(0xFF, shift))
    self.pool[d + 1] = __or(__and(v, mask), __lshift(what, shift))
end

function VmRam:serialize() -- returns memory in this format {[0] = "ab..."}
    local function convert(v)
        local v1 = __and(v, 0xFF)
        local v2 = __and(__rshift(v, 8), 0xFF)
        local v3 = __rshift(v, 16)
        return __format("%02x", v1)..__format("%02x", v2)..__format("%02x", v3)
    end

    local chunks = {}

    local lastAddr = -1
    local prevAddr = -1
    for addr, v in pairs(self.pool) do
        if addr - prevAddr == 1 then
            prevAddr = addr
            chunks[lastAddr] = chunks[lastAddr] .. convert(v)
        else
            lastAddr = addr
            prevAddr = addr

            chunks[addr] = convert(v)
        end
    end

    return chunks
end

function VmRam:deserialize(chunks)
    for addr, v in pairs(chunks) do
        local offset = 0
        for w in __gmatch(v, "......") do
            local v1 = tonumber(__sub(w, 1, 2), 16)
            local v2 = tonumber(__sub(w, 3, 4), 16)
            local v3 = tonumber(__sub(w, 5, 6), 16)
            self.pool[addr + offset] = __or(__or(__lshift(v3, 16), __lshift(v2, 8)), v1)
            offset = offset + 1
        end
    end
end
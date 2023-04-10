if __vmUtilModuleLoaded then return end
__vmUtilModuleLoaded = true

function class(super)

    local klass = {}

    -- Copy members from super.
    if super then
        for k,v in pairs(super) do
            klass[k] = v
        end
    end

    local meta = {}

    -- Emulate constructor syntax.
    -- Triggers when a value is called like a function.
    meta.__call = function(self, ...)
        local instance = setmetatable({}, self)

        return instance
    end

    -- Emulate classes using prototyping.
    setmetatable(klass, meta)
    klass.__index = klass

    return klass
end

bit = require('bit')
__or = bit.bor
__and = bit.band
__xor = bit.bxor
__rshift = bit.rshift
__lshift = bit.lshift
__not = bit.bnot
__floor = math.floor
__chr = string.char
__byte = string.byte
__format = string.format
__gmatch = string.gmatch
__match = string.match
__sub = string.sub
__abs = math.abs
__join = table.concat

__tonumber = function (s) 
    if __sub(s, 1, 2) ~= "0b" then
        return tonumber(s)
    else
        local num = 0
        s = __sub(s, 3)
        for n in __gmatch(s, '.') do
            num = __lshift(num, 1)
            if n == '1' then
                num = num + 1
            end
        end
        return num
    end
end

function __keys(t)
    local r = {}
    for k in pairs(t) do
        r[#r + 1] = k
    end
    return r
end

function __values(t)
    local r = {}
    for k, v in pairs(t) do
        r[#r + 1] = v
    end
    return r
end

function __toSigned8(v)
    local sign = __rshift(v, 7)
    if sign == 0 then return v end

    local n = __and(__not(v), 0xFF)
    return -(n + 1)
end

function __toSigned16(v)
    local sign = __rshift(v, 15)
    if sign == 0 then return v end

    local n = __and(__not(v), 0xFFFF)
    return -(n + 1)
end
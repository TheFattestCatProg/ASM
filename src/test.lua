dofile('tokenizer.lua')
dofile('parser.lua')
dofile('codegen.lua')
dofile('ram.lua')
dofile('vm.lua')

local function read_file(path)
    local file = io.open(path, "rb") -- r read mode and b binary mode
    if not file then return nil end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end

local code = read_file('../examples/test.asm')
local tokens = Tokenizer.tokenize(code)

--for i, v in ipairs(tokens) do
--    print("TOKEN", v[1], v[2])
--end

local parser = Parser.new()
parser:setTokens(tokens)
local actions = parser:parse()

if #parser.errors > 0 then return end

local r = VmRam.new(256)
local cg = Codegen.new()
cg:setRam(r)
cg:generate(actions)

if #cg.errors > 0 then return end

print("Code:")
for k, v in pairs(r:serialize()) do
    print((k - 1) * 3, v)
end

local vm = AsmVm.new()
vm.ram = r
vm.onOut = function (where, what)
    print("out to "..where..": "..what)
end

vm.onIn = function (from)
    return from
end

vm:start()

while vm:canWork() do
    vm:update()
end

if vm:hasError() then
    print("ERROR")
end

print("Reg values:")
local rgs = {
    [0] = "%ip",
    [1] = "%sp",
    [2] = "%bsp",
    [3] = "%ax",
    [4] = "%bx",
    [5] = "%cx",
    [6] = "%dx"
}

for k, v in pairs(vm.regs) do
    print(rgs[k], v)
end

print("Memory after:")
for k, v in pairs(r:serialize()) do
    print((k - 1) * 3, v)
end
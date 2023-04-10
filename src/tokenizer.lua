if __compilerTokenizerLoaded then return end
__compilerTokenizerLoaded = true
dofile('util.lua')

Tokenizer = {}

Tokenizer.TokenType = {
    WORD = 1,
    COMMA = 2,
    REG = 3,
    NUMBER = 4,
    NEWLINE = 5,
    COLON = 6,
    OP = 7,
}

Tokenizer.Op = {
    HLT = "hlt",
    MOV = "mv",
    ADD = "add",
    SUB = "sub",
    MUL = "mul",
    DIV = "div",
    IDIV = "idiv",
    RD = "rd",
    WR = "wr",
    PUSH = "psh",
    POP = "pop",

    CMP = "cmp",

    CMOVE = "mve",
    CMOVNE = "mvne",
    CMOVG = "mvg",
    CMOVL = "mvl",
    CMOVGE = "mvge",
    CMOVLE = "mvle",
    CMOVA = "mva",
    CMOVB = "mvb",
    CMOVAE = "mvae",
    CMOVBE = "mvbe",

    JP = "jp",
    JPE = "jpe",
    JPNE = "jpne",
    JPG = "jpg",
    JPL = "jpl",
    JPGE = "jpge",
    JPLE = "jple",
    JPA = "jpa",
    JPB = "jpb",
    JPAE = "jpae",
    JPBE = "jpbe",

    CALL = "call",
    RET = "ret",

    AND = "and",
    OR = "or",
    XOR = "xor",
    NOT = "not",
    NEG = "neg",

    SHR = "shr",
    SHL = "shl",

    ABS = "abs",
    MOD = "mod",
    IMOD = "imod",

    OUT = "out",
    IN = "in",

    INC = "inc",
    DEC = "dec",
    LOOP = "loop",
}

Tokenizer.s_Op = {}
for k, v in pairs(Tokenizer.Op) do
    Tokenizer.s_Op[v] = true
end

function Tokenizer.tokenize(code)
    local r = {}

    local function token(t, src, line)
        return {t, src, line}
    end

    local lineCounter = 1
    for line in __gmatch(code, "([^\n]*)\n?") do
        local semicolon = string.find(line, ';') 
        if semicolon then
            line = __sub(line, 1, semicolon - 1)
        end
        for word in __gmatch(line, "%S+") do
            local separated = {}
            for sword in __gmatch(word, "[^,]*") do
                if #sword ~= 0 then
                    for sword1 in __gmatch(sword, "[^:]*") do
                        if #sword1 ~= 0 then
                            separated[#separated+1] = sword1
                        else
                            separated[#separated+1] = ':'
                        end
                    end
                    separated[#separated] = nil
                else
                    separated[#separated+1] = ','
                end
            end
            separated[#separated] = nil
            for i, v in ipairs(separated) do
                if v == "," then
                    r[#r+1] = token(Tokenizer.TokenType.COMMA, v, lineCounter)
                elseif v == ":" then
                    r[#r+1] = token(Tokenizer.TokenType.COLON, v, lineCounter)
                elseif __sub(v, 1, 1) == "%" then
                    r[#r+1] = token(Tokenizer.TokenType.REG, v, lineCounter)
                elseif __match(v, "-?%d+") == v or __match(v, "0x[0-9a-fA-F]+") == v or __match(v, "0b[01]+") then
                    r[#r+1] = token(Tokenizer.TokenType.NUMBER, v, lineCounter)
                elseif Tokenizer.s_Op[v] then
                    r[#r+1] = token(Tokenizer.TokenType.OP, v, lineCounter)
                else
                    r[#r+1] = token(Tokenizer.TokenType.WORD, v, lineCounter)
                end
            end
        end
        r[#r+1] = token(Tokenizer.TokenType.NEWLINE, 'NEWLINE', lineCounter)
        lineCounter = lineCounter + 1
    end

    return r
end
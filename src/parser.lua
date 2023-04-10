if __compilerParserLoaded then return end
__compilerParserLoaded = true
dofile('util.lua')
dofile('tokenizer.lua')
dofile('op_enum.lua')
dofile('codegen.lua')

Parser = class()
Parser.TokenType = Tokenizer.TokenType
Parser.AstType = {
    LABEL = 1,
    OP = 2,
}

function Parser.new()
    local obj = Parser()
    obj.tokens = nil
    obj.position = 1
    obj.errors = {}
    return obj
end

function Parser:reset()
    self.position = 1
    self.errors = {}
end

function Parser:setTokens(tokens)
    self.tokens = tokens
end

function Parser:current()
    return self.tokens[self.position]
end

function Parser:prev()
    return self.tokens[self.position - 1]
end

function Parser:advance()
    self.position = self.position + 1
    --print("advanced "..(self:current() and self:current()[2] or 'EOF'))
end

function Parser:check(type)
    return self:current()[1] == type
end

function Parser:match(type)
    if self:check(type) then
        self:advance()
        return true
    end
    return false
end

function Parser:consume(type, err)
    if self:match(type) then
        return true
    end
    self:push_error(err)
    return false
end

function Parser:push_error(err)
    self.errors[#self.errors+1] = err
    print(err)
end

function Parser:skipToNextLine()
    local t = Parser.TokenType.NEWLINE
    while not self:check(t) do
        self:advance()
    end
    self:advance()
end

function Parser:isValidReg(r)
    local validNames = Codegen.RegToNum
    return validNames[r]
end

function Parser.isRegSmall(r)
    if type(r) == "string" then
        r = __sub(r, 2, #r)
        local small = {
            ["al"] = true,
            ["ah"] = true,

            ["bl"] = true,
            ["bh"] = true,

            ["cl"] = true,
            ["ch"] = true,

            ["dl"] = true,
            ["dh"] = true,
        }
        return small[r]
    else
        return r >= 7 and r <= 14
    end
end

function Parser:parse_label() -- word : newline
    local lbl = self:current()[2]
    self:advance()
    if not self:consume(Parser.TokenType.COLON, "expected ':' after label name or invalid op '"..lbl.."' at line "..self:line()) then
        self:skipToNextLine()
        return
    end
    return { Parser.AstType.LABEL, lbl }
end

function Parser:line()
    return self:current()[3]
end

Parser.TokenOpToVmOp = {
    [Tokenizer.Op.HLT.."_"] = VmOp.HLT,

    [Tokenizer.Op.MOV.."_rr"] = VmOp.MOV_RR,
    [Tokenizer.Op.MOV.."_rv"] = VmOp.MOV_RV,

    [Tokenizer.Op.ADD.."_rr"] = VmOp.ADD_RR,
    [Tokenizer.Op.ADD.."_rv"] = VmOp.ADD_RV,
    [Tokenizer.Op.SUB.."_rr"] = VmOp.SUB_RR,
    [Tokenizer.Op.SUB.."_rv"] = VmOp.SUB_RV,
    [Tokenizer.Op.MUL.."_rr"] = VmOp.MUL_RR,
    [Tokenizer.Op.MUL.."_rv"] = VmOp.MUL_RV,
    [Tokenizer.Op.DIV.."_rr"] = VmOp.DIV_RR,
    [Tokenizer.Op.DIV.."_rv"] = VmOp.DIV_RV,
    [Tokenizer.Op.IDIV.."_rr"] = VmOp.IDIV_RR,
    [Tokenizer.Op.IDIV.."_rv"] = VmOp.IDIV_RV,

    [Tokenizer.Op.RD.."_rr"] = VmOp.RD_RR,
    [Tokenizer.Op.RD.."_rv"] = VmOp.RD_RV,
    [Tokenizer.Op.RD.."_rrr"] = VmOp.RD_RRR,
    [Tokenizer.Op.RD.."_rrv"] = VmOp.RD_RRV,
    [Tokenizer.Op.WR.."_rr"] = VmOp.WR_RR,
    [Tokenizer.Op.WR.."_rv"] = VmOp.WR_RV,
    [Tokenizer.Op.WR.."_rrr"] = VmOp.WR_RRR,
    [Tokenizer.Op.WR.."_rrv"] = VmOp.WR_RRV,

    [Tokenizer.Op.PUSH.."_r"] = VmOp.PUSH_R,
    [Tokenizer.Op.POP.."_r"] = VmOp.POP_R,

    [Tokenizer.Op.CMP.."_rr"] = VmOp.CMP_RR,
    [Tokenizer.Op.CMP.."_rv"] = VmOp.CMP_RV,

    [Tokenizer.Op.CMOVE.."_rr"] = VmOp.CMOVE_RR,
    [Tokenizer.Op.CMOVE.."_rv"] = VmOp.CMOVE_RV,
    [Tokenizer.Op.CMOVNE.."_rr"] = VmOp.CMOVNE_RR,
    [Tokenizer.Op.CMOVNE.."_rv"] = VmOp.CMOVNE_RV,
    [Tokenizer.Op.CMOVG.."_rr"] = VmOp.CMOVG_RR,
    [Tokenizer.Op.CMOVG.."_rv"] = VmOp.CMOVG_RV,
    [Tokenizer.Op.CMOVL.."_rr"] = VmOp.CMOVL_RR,
    [Tokenizer.Op.CMOVL.."_rv"] = VmOp.CMOVL_RV,
    [Tokenizer.Op.CMOVGE.."_rr"] = VmOp.CMOVGE_RR,
    [Tokenizer.Op.CMOVGE.."_rv"] = VmOp.CMOVGE_RV,
    [Tokenizer.Op.CMOVLE.."_rr"] = VmOp.CMOVLE_RR,
    [Tokenizer.Op.CMOVLE.."_rv"] = VmOp.CMOVLE_RV,
    [Tokenizer.Op.CMOVA.."_rr"] = VmOp.CMOVA_RR,
    [Tokenizer.Op.CMOVA.."_rv"] = VmOp.CMOVA_RV,
    [Tokenizer.Op.CMOVB.."_rr"] = VmOp.CMOVB_RR,
    [Tokenizer.Op.CMOVB.."_rv"] = VmOp.CMOVB_RV,
    [Tokenizer.Op.CMOVAE.."_rr"] = VmOp.CMOVAE_RR,
    [Tokenizer.Op.CMOVAE.."_rv"] = VmOp.CMOVAE_RV,
    [Tokenizer.Op.CMOVBE.."_rr"] = VmOp.CMOVBE_RR,
    [Tokenizer.Op.CMOVBE.."_rv"] = VmOp.CMOVBE_RV,

    [Tokenizer.Op.RET.."_"] = VmOp.RET,

    [Tokenizer.Op.AND.."_rr"] = VmOp.AND_RR,
    [Tokenizer.Op.AND.."_rv"] = VmOp.AND_RV,
    [Tokenizer.Op.OR.."_rr"] = VmOp.OR_RR,
    [Tokenizer.Op.OR.."_rv"] = VmOp.OR_RV,
    [Tokenizer.Op.XOR.."_rr"] = VmOp.XOR_RR,
    [Tokenizer.Op.XOR.."_rv"] = VmOp.XOR_RV,

    [Tokenizer.Op.NOT.."_r"] = VmOp.NOT_R,
    [Tokenizer.Op.NEG.."_r"] = VmOp.NEG_R,

    [Tokenizer.Op.SHR.."_rr"] = VmOp.SHR_RR,
    [Tokenizer.Op.SHR.."_rv"] = VmOp.SHR_RV,
    [Tokenizer.Op.SHL.."_rr"] = VmOp.SHL_RR,
    [Tokenizer.Op.SHL.."_rv"] = VmOp.SHL_RV,

    [Tokenizer.Op.ABS.."_r"] = VmOp.ABS_R,

    [Tokenizer.Op.MOD.."_rr"] = VmOp.MOD_RR,
    [Tokenizer.Op.MOD.."_rv"] = VmOp.MOD_RV,
    [Tokenizer.Op.IMOD.."_rr"] = VmOp.IMOD_RR,
    [Tokenizer.Op.IMOD.."_rv"] = VmOp.IMOD_RV,

    [Tokenizer.Op.OUT.."_rr"] = VmOp.OUT_RR,
    [Tokenizer.Op.OUT.."_rv"] = VmOp.OUT_RV,
    [Tokenizer.Op.IN.."_rr"] = VmOp.IN_RR,
    [Tokenizer.Op.IN.."_rv"] = VmOp.IN_RV,

    [Tokenizer.Op.INC.."_r"] = VmOp.INC_R,
    [Tokenizer.Op.DEC.."_r"] = VmOp.DEC_R,

    [Tokenizer.Op.JP.."_w"] = VmVOp.JP_W,
    [Tokenizer.Op.JPE.."_w"] = VmVOp.JPE_W,
    [Tokenizer.Op.JPNE.."_w"] = VmVOp.JPNE_W,
    [Tokenizer.Op.JPG.."_w"] = VmVOp.JPG_W,
    [Tokenizer.Op.JPL.."_w"] = VmVOp.JPL_W,
    [Tokenizer.Op.JPGE.."_w"] = VmVOp.JPGE_W,
    [Tokenizer.Op.JPLE.."_w"] = VmVOp.JPLE_W,
    [Tokenizer.Op.JPA.."_w"] = VmVOp.JPA_W,
    [Tokenizer.Op.JPB.."_w"] = VmVOp.JPB_W,
    [Tokenizer.Op.JPAE.."_w"] = VmVOp.JPAE_W,
    [Tokenizer.Op.JPBE.."_w"] = VmVOp.JPBE_W,
    [Tokenizer.Op.CALL.."_w"] = VmVOp.CALL_W,
    [Tokenizer.Op.LOOP.."_rw"] = VmVOp.LOOP_RW,
}

function Parser:consume_newline()
    if not self:consume(Parser.TokenType.NEWLINE, "expected newline, got '"..self:current()[2].."' at line "..self:line()) then
        self:skipToNextLine()
        return
    end
    return true
end

function Parser:parse_op() -- op [reg|num], ..., [reg|num]? newline
    local op = self:current()[2]
    local maskBuilder = {}
    local values = {}

    self:advance()
    if not self:match(Tokenizer.TokenType.NEWLINE) then
        local l = {
            [Tokenizer.TokenType.NUMBER] = function (tok) 
                values[#values+1] = __tonumber(tok[2])
                maskBuilder[#maskBuilder+1] = "v"
                return true
            end,
            [Tokenizer.TokenType.REG] = function (tok)
                local r = tok[2]
                values[#values+1] = r
                maskBuilder[#maskBuilder+1] = "r"
                if not self:isValidReg(r) then
                    self:push_error("invalid reg '"..r.."' at line "..tok[3])
                    return
                end
                return true
            end,
            [Tokenizer.TokenType.WORD] = function (tok) 
                values[#values+1] = tok[2]
                maskBuilder[#maskBuilder+1] = "w"
                return true
            end,
        }

        local curr = self:current()

        if not l[curr[1]] then
            self:push_error("bad parameter token '"..curr[2].."' at line "..self:line())
            self:skipToNextLine()
            return
        end
        l[curr[1]](curr)

        self:advance()

        while true do
            if self:match(Tokenizer.TokenType.NEWLINE) then
                break
            elseif not self:match(Tokenizer.TokenType.COMMA) then
                self:push_error("expected ',' or '\\n' at line "..self:line())
                self:skipToNextLine()
                break
            end

            local curr = self:current()
            if l[curr[1]] then
                if not l[curr[1]](curr) then
                    self:skipToNextLine()
                    break
                end
                self:advance()
            else
                self:push_error("bad parameter token '"..curr[2].."' at line "..self:line())
                self:skipToNextLine()
                break
            end
        end
    end

    local mask = __join(maskBuilder)
    local op2 = Parser.TokenOpToVmOp[op.."_"..mask]

    if not op2 then
        self:push_error("op '"..op.."' with parameter mask '"..mask.."' doesn't exist at line "..self:line())
        return
    end

    return {Parser.AstType.OP, op2, unpack(values)}
end

function Parser:parse_line() -- something newline
    if self:check(Parser.TokenType.WORD) then
        return self:parse_label()
    elseif self:check(Parser.TokenType.OP) then
        return self:parse_op()
    elseif self:check(Parser.TokenType.NEWLINE) then
        self:advance()
    else
        error("beda "..self:current()[2])
    end
end

function Parser:parse()
    local r = {}
    while self.position <= #self.tokens do
        r[#r+1] = self:parse_line()
    end
    return r
end
if __compilerOpEnumLoaded then return end
__compilerOpEnumLoaded = true

VmOp = {
    HLT = 1,

    MOV_RR = 2,
    MOV_RV = 3,

    ADD_RR = 4,
    ADD_RV = 5,
    SUB_RR = 6,
    SUB_RV = 7,
    MUL_RR = 8,
    MUL_RV = 9,
    DIV_RR = 10,
    DIV_RV = 11,

    RD_RR = 12,
    RD_RV = 13,
    WR_RR = 14,
    WR_RV = 15,

    PUSH_R = 16,
    POP_R = 17,

    IDIV_RR = 18,
    IDIV_RV = 19,

    CMP_RR = 20,
    CMP_RV = 21,

    CMOVE_RR = 22,
    CMOVE_RV = 23,
    CMOVNE_RR = 24,
    CMOVNE_RV = 25,
    CMOVG_RR = 26,
    CMOVG_RV = 27,
    CMOVL_RR = 28,
    CMOVL_RV = 29,
    CMOVGE_RR = 30,
    CMOVGE_RV = 31,
    CMOVLE_RR = 32,
    CMOVLE_RV = 33,
    CMOVA_RR = 34,
    CMOVA_RV = 35,
    CMOVB_RR = 36,
    CMOVB_RV = 37,
    CMOVAE_RR = 38,
    CMOVAE_RV = 39,
    CMOVBE_RR = 40,
    CMOVBE_RV = 41,

    CALL_V = 42,
    RET = 43,

    AND_RR = 44,
    AND_RV = 45,
    OR_RR = 46,
    OR_RV = 47,
    XOR_RR = 48,
    XOR_RV = 49,
    NOT_R = 50,
    NEG_R = 51,

    SHR_RR = 52,
    SHR_RV = 53,
    SHL_RR = 54,
    SHL_RV = 55,

    ABS_R = 56,
    MOD_RR = 57,
    MOD_RV = 58,
    IMOD_RR = 59,
    IMOD_RV = 60,

    OUT_RR = 61,
    OUT_RV = 62,
    IN_RR = 63,
    IN_RV = 64,

    INC_R = 65,
    DEC_R = 66,

    LOOP_RV = 67,

    RD_RRR = 68,
    RD_RRV = 69,
    WR_RRR = 70,
    WR_RRV = 71,
}
VmOp.LAST = #__values(VmOp) + 1
VmVOp = {
    JP_W = VmOp.LAST + 0,
    JPE_W = VmOp.LAST + 1,
    JPNE_W = VmOp.LAST + 2,
    JPG_W = VmOp.LAST + 3,
    JPL_W = VmOp.LAST + 4,
    JPGE_W = VmOp.LAST + 5,
    JPLE_W = VmOp.LAST + 6,
    JPA_W = VmOp.LAST + 7,
    JPB_W = VmOp.LAST + 8,
    JPAE_W = VmOp.LAST + 9,
    JPBE_W = VmOp.LAST + 10,
    CALL_W = VmOp.LAST + 11,
    LOOP_RW = VmOp.LAST + 12,
}

VmVOp.LAST = #__values(VmVOp) + VmOp.LAST
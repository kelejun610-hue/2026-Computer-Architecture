// CP3：用 .insn 把自訂指令 CLIP 直接組成機器碼
// .insn r 的格式：.insn r opcode, funct3, funct7, rd, rs1, rs2
// CLIP：opcode = 0x0B（custom-0），funct3 = 0，funct7 = 0，rs2 固定 x0
// 這個檔只拿來組譯和看機器碼；QEMU 的 CPU 不認得這條指令，真的執行會 Illegal instruction

    .macro clip rd, rs1
    .insn r 0x0B, 0, 0, \rd, \rs1, x0
    .endm

    .text
    .globl clip_examples
clip_examples:              // 順序要和 clip_enc.py 的 EXAMPLES 一致
    clip  a0, a1            // 預期 0x0005850B
    clip  a0, a0            // 預期 0x0005050B
    clip  t0, t1            // 預期 0x0003028B

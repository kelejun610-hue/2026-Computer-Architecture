"""CLIP 自訂指令的編碼器、解碼器與黃金模型（golden model）

格式：R-type，opcode = custom-0（0001011），funct3 = 000，funct7 = 0000000，rs2 固定 x0
語意：rd = min(max(rs1, -128), 127)

用法：
  python3 clip_enc.py                    印出編碼表，並模擬執行每個範例
  python3 clip_enc.py --check insn.bin   比對組譯器產生的機器碼和這裡算的是否一致
"""
import argparse
import struct
import sys

OPCODE = 0b0001011
FUNCT3 = 0b000
FUNCT7 = 0b0000000

ABI = ["zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "s1",
       "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
       "s2", "s3", "s4", "s5", "s6", "s7", "s8", "s9", "s10", "s11",
       "t3", "t4", "t5", "t6"]
REG = {name: i for i, name in enumerate(ABI)}

# (rd, rs1, 執行前 rs1 的值)：順序要和 clip_insn.S 一致
EXAMPLES = [("a0", "a1", 200), ("a0", "a0", 50), ("t0", "t1", -129)]


def encode(rd, rs1, rs2=0):
    return (FUNCT7 << 25) | (rs2 << 20) | (rs1 << 15) | (FUNCT3 << 12) | (rd << 7) | OPCODE


def decode(word):
    """是 CLIP 就回傳 (rd, rs1, rs2)，不是就回傳 None"""
    if word & 0x7F != OPCODE or (word >> 12) & 0x7 != FUNCT3 or word >> 25 != FUNCT7:
        return None
    return (word >> 7) & 0x1F, (word >> 15) & 0x1F, (word >> 20) & 0x1F


def to_signed32(v):
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


def clip(x):
    return min(max(to_signed32(x), -128), 127)


def execute(word, regs):
    """模擬 CPU 執行一條 CLIP：解碼 → 讀 rs1 → 比較並選擇 → 寫回 rd（x0 不能寫）"""
    fields = decode(word)
    if fields is None:
        raise ValueError(f"0x{word:08X} 不是 CLIP")
    rd, rs1, _ = fields
    if rd != 0:
        regs[rd] = clip(regs[rs1]) & 0xFFFFFFFF


def split_fields(word):
    b = f"{word:032b}"
    return f"{b[0:7]} {b[7:12]} {b[12:17]} {b[17:20]} {b[20:25]} {b[25:32]}"


def expected_words():
    return [encode(REG[rd], REG[rs1]) for rd, rs1, _ in EXAMPLES]


def show():
    print("組合語言       機器碼       funct7  rs2   rs1   f3  rd    opcode")
    for (rd, rs1, value), word in zip(EXAMPLES, expected_words()):
        print(f"clip {rd}, {rs1:<4} 0x{word:08X}   {split_fields(word)}")

    print("\n模擬執行（黃金模型）：")
    for (rd, rs1, value), word in zip(EXAMPLES, expected_words()):
        regs = [0] * 32
        regs[REG[rs1]] = value & 0xFFFFFFFF
        execute(word, regs)
        print(f"  {rs1} = {value:>5}  →  clip {rd}, {rs1}  →  {rd} = {to_signed32(regs[REG[rd]])}")

    # 每一種 rd/rs1 組合都要能編碼後解回原值
    for rd in range(32):
        for rs1 in range(32):
            assert decode(encode(rd, rs1)) == (rd, rs1, 0)
    print("\n自我檢查：32 × 32 種 rd/rs1 組合編碼後都能正確解碼")


def check(path):
    data = open(path, "rb").read()
    got = [w for (w,) in struct.iter_unpack("<I", data[: len(data) // 4 * 4])]
    ok = True
    for (rd, rs1, _), want, have in zip(EXAMPLES, expected_words(), got):
        mark = "OK " if want == have else "不一致"
        ok &= want == have
        print(f"  {mark} clip {rd}, {rs1:<4} 組譯器 0x{have:08X} / 手算 0x{want:08X}")
    if len(got) < len(EXAMPLES):
        print(f"  機器碼只有 {len(got)} 個字，預期 {len(EXAMPLES)} 個")
        ok = False
    print("機器碼比對：" + ("全部一致" if ok else "有不一致"))
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", metavar="BIN", help="objcopy 出來的 .text 二進位檔")
    args = ap.parse_args()
    if args.check:
        sys.exit(0 if check(args.check) else 1)
    show()


if __name__ == "__main__":
    main()

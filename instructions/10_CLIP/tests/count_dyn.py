"""從 QEMU 的逐指令追蹤檔，算出各 CLIP 實作的靜態與動態指令數、分支數

用法：python3 count_dyn.py trace.log prog.dis prog.nm test_output.txt
  trace.log        qemu-riscv32 -one-insn-per-tb -d nochain,exec 的輸出，一行 Trace = 執行一條指令
  prog.dis         objdump -d 的輸出，用來查每個位址是什麼指令
  prog.nm          nm -S 的輸出，用來查每個函式的位址範圍
  test_output.txt  測試程式的輸出，用來把第 n 次呼叫對回第 n 筆測資
"""
import re
import sys

# 順序要和 test_clip.c 的 impls[] 一致
FUNCS = [
    ("clip_c", "gcc -O2 編譯 C 參考實作"),
    ("clip_cmp2", "先比上界、再比下界"),
    ("clip_range", "一次判斷範圍 + 正負號算飽和值"),
    ("clip_slt_mask", "兩次比較換成遮罩（無分支）"),
    ("clip_sign_mask", "一次判斷範圍 + 遮罩（無分支）"),
    ("clip_mul_select", "一次判斷範圍 + 乘法選擇（無分支）"),
]
BRANCHES = {"beq", "bne", "blt", "bge", "bltu", "bgeu", "beqz", "bnez", "blez",
            "bgez", "bltz", "bgtz", "bgt", "ble", "bgtu", "bleu"}
KINDS = [("high", "上飽和 x > 127"), ("in", "範圍內"), ("low", "下飽和 x < −128")]


def load_symbols(path):
    syms = {}
    for line in open(path, encoding="utf-8"):
        parts = line.split()
        if len(parts) == 4:
            addr, size, _, name = parts
            syms[name] = (int(addr, 16), int(addr, 16) + int(size, 16))
    return syms


def load_disasm(path):
    pat = re.compile(r"^\s*([0-9a-f]+):\s+[0-9a-f]{8}\s+(\S+)")
    insn = {}
    for line in open(path, encoding="utf-8"):
        m = pat.match(line)
        if m:
            insn[int(m.group(1), 16)] = m.group(2)
    return insn


def load_trace(path):
    # 例：Trace 0: 0x7f12... [00000000/00010094/00000000/ff020000] clip_c，第二欄是 PC
    pat = re.compile(r"Trace \d+: \S+ \[[0-9a-fA-F]+/([0-9a-fA-F]+)/")
    pcs = []
    for line in open(path, encoding="utf-8", errors="replace"):
        m = pat.search(line)
        if m:
            pcs.append(int(m.group(1), 16))
    return pcs


def load_tests(path):
    pat = re.compile(r"^x = (-?\d+)\texpect (-?\d+)")
    return [(int(m.group(1)), int(m.group(2)))
            for m in map(pat.match, open(path, encoding="utf-8")) if m]


def kind(x):
    return "high" if x > 127 else "low" if x < -128 else "in"


def invocations(pcs, lo, hi, insn):
    """把落在 [lo, hi) 的連續 PC 切成一次一次的呼叫，回傳 [(指令數, 分支數), ...]"""
    runs = []
    inside = False
    for pc in pcs:
        if lo <= pc < hi:
            if not inside:
                runs.append([0, 0])
                inside = True
            runs[-1][0] += 1
            runs[-1][1] += insn.get(pc) in BRANCHES
        else:
            inside = False
    return [tuple(r) for r in runs]


def span(values):
    lo, hi = min(values), max(values)
    return f"{lo}" if lo == hi else f"{lo}–{hi}"


def summary_table(funcs, runs, tests, minus):
    """依輸入類型彙整；minus = 1 時扣掉 ret，代表 inline 使用的成本"""
    head = "| 實作 | " + " | ".join(label for _, label in KINDS) + " | 10 筆平均 |"
    print(head)
    print("|---" * (len(KINDS) + 2) + "|")
    for name, _ in funcs:
        cells = []
        for k, _ in KINDS:
            got = [runs[name][i] for i, (x, _) in enumerate(tests)
                   if kind(x) == k and i < len(runs[name])]
            if not got:
                cells.append("—")
                continue
            ins = span([c - minus for c, _ in got])
            cells.append(ins if minus else f"{ins} ({span([b for _, b in got])})")
        counts = [c - minus for c, _ in runs[name]]
        avg = f"{sum(counts) / len(counts):.1f}" if counts else "?"
        print(f"| {name} | " + " | ".join(cells) + f" | {avg} |")
    one = "1" if minus else "1 (0)"
    print("| **CLIP 自訂指令** | " + " | ".join([one] * len(KINDS)) + " | 1 |")


def main():
    trace, dis, nm, out = sys.argv[1:5]
    syms = load_symbols(nm)
    insn = load_disasm(dis)
    pcs = load_trace(trace)
    tests = load_tests(out)
    funcs = [(name, idea) for name, idea in FUNCS if name in syms]

    print("### 靜態指令數（函式裡寫了幾條，含 ret）\n")
    print("| 實作 | 想法 | 靜態指令數 | 靜態分支數 |")
    print("|---|---|---|---|")
    for name, idea in funcs:
        lo, hi = syms[name]
        addrs = range(lo, hi, 4)
        print(f"| {name} | {idea} | {len(addrs)} | {sum(insn.get(a) in BRANCHES for a in addrs)} |")
    print("| **CLIP 自訂指令** | 一條指令完成 | 1 | 0 |")

    if not pcs:
        print("\n> 追蹤檔裡沒有 Trace 行（QEMU 可能不支援 -d exec），動態指令數請改用手算。")
        return

    runs = {name: invocations(pcs, *syms[name], insn) for name, _ in funcs}
    n_kind = {k: sum(kind(x) == k for x, _ in tests) for k, _ in KINDS}
    print("\n### 動態指令數（依輸入類型，含 ret；括號內為其中的分支數）\n")
    print("10 筆測資中：" + "、".join(f"{label} {n_kind[k]} 筆" for k, label in KINDS) + "\n")
    summary_table(funcs, runs, tests, minus=0)

    print("\n### 實際使用成本（inline，不需要 call / ret，所以扣掉 1 個 ret）\n")
    summary_table(funcs, runs, tests, minus=1)

    print("\n### 每筆測資的動態指令數（含 ret；括號內為分支數）\n")
    print("| x | 預期 | " + " | ".join(name for name, _ in funcs) + " | CLIP |")
    print("|---" * (len(funcs) + 3) + "|")
    for i, (x, expect) in enumerate(tests):
        cells = [f"{runs[n][i][0]} ({runs[n][i][1]})" if i < len(runs[n]) else "?" for n, _ in funcs]
        print(f"| {x} | {expect} | " + " | ".join(cells) + " | 1 (0) |")

    for name, _ in funcs:
        if len(runs[name]) != len(tests):
            print(f"\n> 注意：{name} 在追蹤中被呼叫 {len(runs[name])} 次，但測資有 {len(tests)} 筆，對應可能錯位。")
    print(f"\n追蹤用的測試程式總共執行 {len(pcs)} 條指令（大部分花在印字）。")


if __name__ == "__main__":
    main()

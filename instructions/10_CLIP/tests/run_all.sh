#!/bin/bash
# 10_CLIP 一鍵流程（全部在 Kali 執行）：編譯 → 測試 → 算指令數 → 驗證機器碼
# 用法（在倉庫根目錄）：bash instructions/10_CLIP/tests/run_all.sh
# 結果寫到 ~/clip-out（放在倉庫外面，不會被 commit）
set -euo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
CLIP="$(dirname "$TESTS")"                  # instructions/10_CLIP
OUT="${1:-$HOME/clip-out}"
BUILD="$OUT/build"
CROSS=riscv64-unknown-elf-
ARCH=(-march=rv32im -mabi=ilp32)
# 沒有 C 函式庫：自己提供 _start 和系統呼叫，所以要 -nostdlib，也不讓 gcc 偷偷呼叫 memset/strlen
CFLAGS=("${ARCH[@]}" -O2 -ffreestanding -fno-builtin -fno-tree-loop-distribute-patterns)
LDFLAGS=(-nostdlib -static -Wl,--no-relax)
SOURCES=("$TESTS/start.S" "$TESTS/test_clip.c" "$TESTS/clip_ref.c" "$CLIP/rv32im/clip_rv32im.S")

for tool in ${CROSS}gcc qemu-riscv32 python3; do
    command -v "$tool" > /dev/null || { echo "找不到 $tool，請先照 03-kali-setup.md 安裝工具"; exit 1; }
done

mkdir -p "$OUT" "$BUILD"
exec > >(tee "$OUT/run.log") 2>&1
echo "結果資料夾：$OUT"

step() { printf '\n=== %s ===\n' "$*"; }

step "1/7 記錄工具版本"
{
    echo "日期：$(date '+%F %T')"
    echo "系統：$(. /etc/os-release && echo "$PRETTY_NAME")，$(uname -sr)"
    echo "編譯器：$(${CROSS}gcc --version | head -1)"
    echo "組譯器：$(${CROSS}as --version | head -1)"
    echo "模擬器：$(qemu-riscv32 --version | head -1)"
    echo "Python：$(python3 --version)"
} | tee "$OUT/versions.txt"

step "2/7 C → 組合語言（看編譯器怎麼翻 clip_c）"
for opt in O0 O2; do
    ${CROSS}gcc "${ARCH[@]}" -$opt -S "$TESTS/clip_ref.c" -o "$OUT/clip_c_$opt.s"
done
sed -n '/^clip_c:/,/\.size/p' "$OUT/clip_c_O2.s"

step "3/7 編譯測試程式"
# riscv64-unknown-elf-gcc 預設套用 picolibc 的裸機記憶體配置（程式放在 0x80000000），
# qemu-riscv32 跑的是 Linux 使用者程式，要改用 ld 內建的標準配置（程式從 0x10000 開始）
${CROSS}ld -m elf32lriscv --verbose | sed -n '/^=====/,/^=====/{/^=====/d;p}' > "$BUILD/linux.ld"
build() {   # build <輸出檔> <SWEEP 0/1>
    ${CROSS}gcc "${CFLAGS[@]}" "${LDFLAGS[@]}" -T "$BUILD/linux.ld" -DSWEEP="$2" \
        -I"$TESTS" -o "$1" "${SOURCES[@]}"
}
build "$BUILD/test_clip" 1          # 完整測試：測資 + 大量輸入比對
build "$BUILD/test_clip_trace" 0    # 只跑 10 筆測資，給逐指令追蹤用
${CROSS}objdump -d "$BUILD/test_clip_trace" > "$OUT/test_clip.dis"
${CROSS}nm -S --defined-only "$BUILD/test_clip_trace" > "$OUT/test_clip.nm"
echo "編譯完成：$BUILD/test_clip、$BUILD/test_clip_trace"

step "4/7 在 QEMU 上執行測試"
status=0
qemu-riscv32 "$BUILD/test_clip" | tee "$OUT/test_output.txt" || status=$?

step "5/7 逐指令追蹤，算動態指令數"
# 一個 TB 只放一條指令，再關掉 TB 串接，每執行一條指令就會記一行 Trace
qemu-riscv32 -one-insn-per-tb -d nochain,exec -D "$BUILD/trace.log" \
    "$BUILD/test_clip_trace" > "$BUILD/trace_output.txt" || true
python3 "$TESTS/count_dyn.py" "$BUILD/trace.log" "$OUT/test_clip.dis" "$OUT/test_clip.nm" \
    "$BUILD/trace_output.txt" | tee "$OUT/counts.md"

step "6/7 組譯自訂指令 CLIP，對照機器碼"
${CROSS}gcc "${ARCH[@]}" -c "$CLIP/spec/clip_insn.S" -o "$BUILD/clip_insn.o"
${CROSS}objdump -d "$BUILD/clip_insn.o" | tee "$OUT/clip_insn.dis"
${CROSS}objcopy -O binary -j .text "$BUILD/clip_insn.o" "$BUILD/clip_insn.bin"
python3 "$CLIP/spec/clip_enc.py" --check "$BUILD/clip_insn.bin" || status=1

step "7/7 黃金模型：編碼表 + 模擬執行"
python3 "$CLIP/spec/clip_enc.py" | tee "$OUT/encoding.txt"

echo
if [ "$status" -eq 0 ]; then
    echo "完成：全部通過，結果在 $OUT"
else
    echo "注意：有步驟沒過（status $status），請看 $OUT/run.log"
fi
exit "$status"

// CP2：CLIP 的手寫 RV32IM 實作（只用 RV32IM 指令），從直覺版一步一步優化
// 呼叫慣例：輸入 x 在 a0，結果也放回 a0（RISC-V 標準 ABI）
//
// 版本              想法                              分支  動態指令數（不含 ret）
// clip_cmp2         先比上界、再比下界                   2     3–5
// clip_range        一次判斷是否在範圍內                 1     3 或 5
// clip_slt_mask     兩次比較都換成遮罩（無分支）          0     12
// clip_sign_mask    範圍判斷 + 用正負號算飽和值（無分支）  0     8
// clip_mul_select   同上，但用乘法做選擇（無分支）        0     7
//
// 兩個關鍵觀察：
// 1. x 在 [-128, 127] ⇔ x + 128 在 [0, 255] ⇔ (x + 128) 當成無號數 < 256
//    x 太小時 x + 128 是負數，當成無號數是很大的數，所以一次無號比較就能同時檢查上下界
// 2. 超出範圍時的飽和值 = (x >> 31) ^ 127（算術右移）
//    x 是正數：x >> 31 = 0，0 ^ 127 = 127
//    x 是負數：x >> 31 = -1（全 1），-1 ^ 127 = -128

    .text

// 版本 1：直覺版，先比上界再比下界
    .globl clip_cmp2
    .type  clip_cmp2, @function
clip_cmp2:
    li    t0, 127
    blt   t0, a0, 1f        // 127 < x：上飽和，t0 = 127 直接當答案
    li    t0, -128
    bge   a0, t0, 2f        // x >= -128：在範圍內，a0 不用動
1:  mv    a0, t0            // a0 = 127 或 -128
2:  ret
    .size clip_cmp2, .-clip_cmp2

// 版本 2：一次判斷範圍（觀察 1），超出時用正負號算飽和值（觀察 2）
    .globl clip_range
    .type  clip_range, @function
clip_range:
    addi  t0, a0, 128
    sltiu t0, t0, 256       // t0 = 1：在範圍內
    bnez  t0, 1f            // 在範圍內：a0 不用動
    srai  a0, a0, 31        // 正數 → 0，負數 → -1
    xori  a0, a0, 127       // 0 → 127，-1 → -128
1:  ret
    .size clip_range, .-clip_range

// 版本 3：直覺版改成無分支，把比較結果變成全 0 / 全 1 的遮罩
    .globl clip_slt_mask
    .type  clip_slt_mask, @function
clip_slt_mask:
    li    t0, 127
    slt   t1, t0, a0        // t1 = (127 < x) ? 1 : 0
    neg   t1, t1            // 1 → 0xFFFFFFFF，0 → 0
    sub   t2, t0, a0        // t2 = 127 - x
    and   t2, t2, t1        // 不飽和時 t2 = 0
    add   a0, a0, t2        // 飽和時 a0 = x + (127 - x) = 127
    li    t0, -128
    slt   t1, a0, t0        // t1 = (x < -128) ? 1 : 0
    neg   t1, t1
    sub   t2, t0, a0        // t2 = -128 - x
    and   t2, t2, t1
    add   a0, a0, t2        // 飽和時 a0 = -128
    ret
    .size clip_slt_mask, .-clip_slt_mask

// 版本 4：版本 2 的想法改成無分支
    .globl clip_sign_mask
    .type  clip_sign_mask, @function
clip_sign_mask:
    addi  t0, a0, 128
    sltiu t0, t0, 256       // t0 = 1：在範圍內
    addi  t0, t0, -1        // 遮罩：在範圍內 0，超出範圍 -1（全 1）
    srai  t1, a0, 31
    xori  t1, t1, 127       // t1 = 飽和值（127 或 -128）
    xor   t1, t1, a0        // t1 = 飽和值 ^ x
    and   t1, t1, t0        // 在範圍內 → 0
    xor   a0, a0, t1        // 在範圍內：x ^ 0 = x；超出：x ^ 飽和值 ^ x = 飽和值
    ret
    .size clip_sign_mask, .-clip_sign_mask

// 版本 5：用乘法（M 擴充）做選擇，指令最少；但乘法在硬體上通常比加減法慢
    .globl clip_mul_select
    .type  clip_mul_select, @function
clip_mul_select:
    addi  t0, a0, 128
    sltiu t0, t0, 256       // t0 = 1：在範圍內，0：超出
    srai  t1, a0, 31
    xori  t1, t1, 127       // t1 = 飽和值
    sub   t2, a0, t1        // t2 = x - 飽和值
    mul   t2, t2, t0        // 在範圍內保留，超出歸 0
    add   a0, t1, t2        // 在範圍內：飽和值 + (x - 飽和值) = x；超出：飽和值
    ret
    .size clip_mul_select, .-clip_mul_select

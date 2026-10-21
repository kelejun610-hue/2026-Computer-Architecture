.globl main
.text

# 10_CLIP 組合語言實作: rd = min(max(rs1, -128), 127)
main:
    # 測試輸入值（可以修改這裡的數字來測試不同測資，例如 200, -200, 50）
    li      a0, 200             
    
    # --- CLIP 核心邏輯 ---
    li      t0, 127             # t0 = 上界 127
    bge     a0, t0, clip_max    # 若 a0 >= 127，跳轉至上限

    li      t1, -128            # t1 = 下界 -128
    blt     a0, t1, clip_min    # 若 a0 < -128，跳轉至下限
    
    j       end                 # 在安全範圍內，直接結束

clip_max:
    mv      a0, t0              # 裁切為 127
    j       end

clip_min:
    mv      a0, t1              # 裁切為 -128
    j       end

end:
    nop                         # 結束點
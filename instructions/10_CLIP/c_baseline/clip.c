#include <stdio.h>

// CLIP 核心邏輯函式：將 rs1 裁切在 [-128, 127] 之間
int clip_instruction(int rs1) {
    if (rs1 > 127) {
        return 127;
    } else if (rs1 < -128) {
        return -128;
    }
    return rs1;
}

int main() {
    int test_inputs[10] = {-200, -128, -127, -50, 0, 50, 126, 127, 128, 1000};
    int expected_outputs[10] = {-128, -128, -127, -50, 0, 50, 126, 127, 127, 127};

    printf("=== CLIP CP1 測試向量驗證 ===\n");
    for (int i = 0; i < 10; i++) {
        int result = clip_instruction(test_inputs[i]);
        printf("Test %02d: Input = %5d -> Got = %4d | Expected = %4d [%s]\n",
               i + 1, test_inputs[i], result, expected_outputs[i],
               (result == expected_outputs[i]) ? "PASS" : "FAIL");
    }
    return 0;
}

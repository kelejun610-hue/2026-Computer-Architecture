/* 測試程式：
 * 1. 10 筆測資逐筆比對預期輸出（count_dyn.py 也用這段算動態指令數）
 * 2. SWEEP = 1 時，再拿大量輸入比對每個實作和 C 參考實作是否一致
 */
#include "clip.h"

#ifndef SWEEP
#define SWEEP 1
#endif

long sys_write(int fd, const void *buf, unsigned long len);   /* start.S */
int clip_cmp2(int x);                                         /* clip_rv32im.S */
int clip_range(int x);
int clip_slt_mask(int x);
int clip_sign_mask(int x);
int clip_mul_select(int x);

typedef int (*clip_fn)(int);

/* 呼叫順序固定，count_dyn.py 依這個順序把追蹤結果對回每筆測資 */
static const struct {
    const char *name;
    clip_fn fn;
} impls[] = {
    { "clip_c", clip_c },
    { "clip_cmp2", clip_cmp2 },
    { "clip_range", clip_range },
    { "clip_slt_mask", clip_slt_mask },
    { "clip_sign_mask", clip_sign_mask },
    { "clip_mul_select", clip_mul_select },
};
#define N_IMPLS (int)(sizeof impls / sizeof impls[0])

/* 前 3 筆是 HOMEWORK.md 6.2 的官方向量，其餘是邊界值 */
static const struct {
    int x;
    int expect;
} tests[] = {
    {  200,  127 },
    { -200, -128 },
    {   50,   50 },
    {  127,  127 },              /* 上界：剛好不飽和 */
    {  128,  127 },              /* 上界：剛好飽和 */
    { -128, -128 },              /* 下界：剛好不飽和 */
    { -129, -128 },              /* 下界：剛好飽和 */
    {    0,    0 },
    {  2147483647,      127 },   /* INT32_MAX */
    { -2147483647 - 1, -128 },   /* INT32_MIN */
};
#define N_TESTS (int)(sizeof tests / sizeof tests[0])

static void put_str(const char *s)
{
    unsigned long n = 0;

    while (s[n])
        n++;
    sys_write(1, s, n);
}

static void put_int(int v)
{
    char buf[11];
    int i = sizeof buf;
    unsigned u = v < 0 ? 0u - (unsigned)v : (unsigned)v;

    do {
        buf[--i] = (char)('0' + u % 10);
        u /= 10;
    } while (u);
    if (v < 0)
        buf[--i] = '-';
    sys_write(1, buf + i, sizeof buf - i);
}

static int run_vectors(void)
{
    int fail = 0;

    for (int t = 0; t < N_TESTS; t++) {
        put_str("x = ");
        put_int(tests[t].x);
        put_str("\texpect ");
        put_int(tests[t].expect);
        for (int k = 0; k < N_IMPLS; k++) {
            int got = impls[k].fn(tests[t].x);

            put_str("\t");
            put_str(impls[k].name);
            put_str(" = ");
            put_int(got);
            if (got != tests[t].expect) {
                put_str(" FAIL");
                fail++;
            }
        }
        put_str("\n");
    }
    return fail;
}

#if SWEEP
static unsigned xorshift32(unsigned *s)
{
    unsigned x = *s;

    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return *s = x;
}

/* 每個 RV32IM 實作都要和 clip_c 一樣；回傳不一致的筆數，並印出第一筆 */
static int sweep_one(int x, int *reported)
{
    int want = clip_c(x);
    int bad = 0;

    for (int k = 1; k < N_IMPLS; k++) {
        int got = impls[k].fn(x);

        if (got == want)
            continue;
        bad++;
        if (!*reported) {
            put_str("SWEEP FAIL: ");
            put_str(impls[k].name);
            put_str("(");
            put_int(x);
            put_str(") = ");
            put_int(got);
            put_str(", clip_c = ");
            put_int(want);
            put_str("\n");
            *reported = 1;
        }
    }
    return bad;
}

static int run_sweep(void)
{
    unsigned seed = 2026;
    int bad = 0, reported = 0, count = 0;

    for (int x = -1000; x <= 1000; x++, count++)            /* 兩個邊界附近的每一個值 */
        bad += sweep_one(x, &reported);
    for (unsigned i = 0; i < 1000; i++, count += 2) {       /* INT32 兩端 */
        bad += sweep_one((int)(0x80000000u + i), &reported);
        bad += sweep_one((int)(0x7FFFFFFFu - i), &reported);
    }
    for (int i = 0; i < 100000; i++, count++)               /* 隨機 32 位元值 */
        bad += sweep_one((int)xorshift32(&seed), &reported);

    put_str("SWEEP: ");
    put_int(count);
    put_str(" inputs x ");
    put_int(N_IMPLS - 1);
    put_str(" implementations vs clip_c, mismatches = ");
    put_int(bad);
    put_str("\n");
    return bad;
}
#endif

int main(void)
{
    int fail = run_vectors();

#if SWEEP
    fail += run_sweep();
#endif
    put_str(fail ? "RESULT: FAIL\n" : "RESULT: ALL PASS\n");
    return fail != 0;   /* exit code 只有 8 位元，失敗筆數直接回傳可能剛好變 0 */
}

/* CLIP 的 C 參考實作（給測試程式用，不含 printf），所有其他版本都拿它當標準答案 */
#include "clip.h"

int clip_c(int x)
{
    if (x > CLIP_MAX)
        return CLIP_MAX;
    if (x < CLIP_MIN)
        return CLIP_MIN;
    return x;
}

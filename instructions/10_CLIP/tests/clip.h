#ifndef CLIP_H
#define CLIP_H

#define CLIP_MIN (-128)
#define CLIP_MAX 127

/* CLIP 的 C 參考實作：rd = min(max(rs1, -128), 127)（HOMEWORK.md 6.2） */
int clip_c(int x);

#endif

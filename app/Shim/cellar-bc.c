/*
 * cellar-bc — the next mip level of a BC1 (DXT1) or BC3 (DXT5) image: decode, average each 2x2
 * pixels, encode again. Used by cellar-mipfix.c, since Metal cannot generate mips for compressed
 * textures. The encoder is the quick kind (bounding-box endpoints, nearest palette entry): mip
 * levels are seen small and at a distance, so speed matters more than the last bit of quality.
 */
#include <stdlib.h>
#include <string.h>

typedef unsigned char u8;

static void unpack565(unsigned c, u8 *rgb)
{
    rgb[0] = (u8)(((c >> 11) & 31) * 255 / 31);
    rgb[1] = (u8)(((c >> 5) & 63) * 255 / 63);
    rgb[2] = (u8)((c & 31) * 255 / 31);
}

static unsigned pack565(const int *rgb)
{
    return (unsigned)((rgb[0] * 31 + 127) / 255) << 11 | (unsigned)((rgb[1] * 63 + 127) / 255) << 5 | (unsigned)((rgb[2] * 31 + 127) / 255);
}

/* Colour part of a BC1/BC3 block -> 16 RGBA pixels (alpha set only by BC1's transparent entry). */
static void decode_color(const u8 *b, u8 px[16][4], int bc1)
{
    unsigned c0 = b[0] | b[1] << 8, c1 = b[2] | b[3] << 8;
    u8 pal[4][4];
    unpack565(c0, pal[0]); unpack565(c1, pal[1]);
    pal[0][3] = pal[1][3] = pal[2][3] = 255; pal[3][3] = 255;
    for (int k = 0; k < 3; k++) {
        if (c0 > c1 || !bc1) {
            pal[2][k] = (u8)((2 * pal[0][k] + pal[1][k]) / 3);
            pal[3][k] = (u8)((pal[0][k] + 2 * pal[1][k]) / 3);
        } else {
            pal[2][k] = (u8)((pal[0][k] + pal[1][k]) / 2);
            pal[3][k] = 0;
        }
    }
    if (bc1 && c0 <= c1) pal[3][3] = 0;
    unsigned idx = b[4] | b[5] << 8 | b[6] << 16 | (unsigned)b[7] << 24;
    for (int i = 0; i < 16; i++) memcpy(px[i], pal[(idx >> (2 * i)) & 3], 4);
}

static void decode_alpha(const u8 *b, u8 px[16][4])
{
    int a[8] = { b[0], b[1] };
    for (int i = 2; i < 8; i++)
        a[i] = b[0] > b[1] ? ((8 - i) * b[0] + (i - 1) * b[1]) / 7
                           : i < 6 ? ((6 - i) * b[0] + (i - 1) * b[1]) / 5 : (i == 6 ? 0 : 255);
    unsigned long long idx = 0;
    for (int i = 0; i < 6; i++) idx |= (unsigned long long)b[2 + i] << (8 * i);
    for (int i = 0; i < 16; i++) px[i][3] = (u8)a[(idx >> (3 * i)) & 7];
}

static void encode_color(u8 px[16][4], u8 *out, int bc1)
{
    int lo[3] = { 255, 255, 255 }, hi[3] = { 0, 0, 0 }, transparent = 0;
    for (int i = 0; i < 16; i++) {
        if (bc1 && px[i][3] < 128) { transparent = 1; continue; }
        for (int k = 0; k < 3; k++) {
            if (px[i][k] < lo[k]) lo[k] = px[i][k];
            if (px[i][k] > hi[k]) hi[k] = px[i][k];
        }
    }
    if (lo[0] > hi[0]) { memset(lo, 0, sizeof lo); memset(hi, 0, sizeof hi); }  /* all transparent */
    for (int k = 0; k < 3; k++) {  /* inset the box a little, as fast encoders do */
        int inset = (hi[k] - lo[k]) / 16;
        lo[k] += inset; hi[k] -= inset;
    }
    unsigned c0 = pack565(hi), c1 = pack565(lo);
    if (transparent ? c0 > c1 : c0 < c1) { unsigned t = c0; c0 = c1; c1 = t; }
    out[0] = (u8)c0; out[1] = (u8)(c0 >> 8); out[2] = (u8)c1; out[3] = (u8)(c1 >> 8);
    u8 block[8] = { out[0], out[1], out[2], out[3] }, pal[16][4];
    block[4] = 0xE4;  /* pixels 0..3 take palette entries 0..3, so decoding gives the palette */
    decode_color(block, pal, bc1);
    unsigned idx = 0;
    for (int i = 0; i < 16; i++) {
        int best = 0, best_d = 1 << 30;
        for (int p = 0; p < 4; p++) {
            if (bc1 && (pal[p][3] == 0) != (px[i][3] < 128)) continue;
            int d = 0;
            for (int k = 0; k < 3; k++) d += (px[i][k] - pal[p][k]) * (px[i][k] - pal[p][k]);
            if (d < best_d) { best_d = d; best = p; }
        }
        idx |= (unsigned)best << (2 * i);
    }
    out[4] = (u8)idx; out[5] = (u8)(idx >> 8); out[6] = (u8)(idx >> 16); out[7] = (u8)(idx >> 24);
}

static void encode_alpha(u8 px[16][4], u8 *out)
{
    int lo = 255, hi = 0;
    for (int i = 0; i < 16; i++) { if (px[i][3] < lo) lo = px[i][3]; if (px[i][3] > hi) hi = px[i][3]; }
    out[0] = (u8)hi; out[1] = (u8)lo;
    int a[8] = { hi, lo };
    for (int i = 2; i < 8; i++) a[i] = hi > lo ? ((8 - i) * hi + (i - 1) * lo) / 7 : hi;
    unsigned long long idx = 0;
    for (int i = 0; i < 16; i++) {
        int best = 0, best_d = 1 << 30;
        for (int p = 0; p < 8; p++) { int d = abs(px[i][3] - a[p]); if (d < best_d) { best_d = d; best = p; } }
        idx |= (unsigned long long)best << (3 * i);
    }
    for (int i = 0; i < 6; i++) out[2 + i] = (u8)(idx >> (8 * i));
}

/* src: a w x h BC1 (bc3 = 0) or BC3 (bc3 = 1) image; dst gets the next level, max(w/2,1) x max(h/2,1).
 * Returns 0 if out of memory. */
int cellar_bc_next_level(const u8 *src, unsigned long w, unsigned long h, u8 *dst, int bc3)
{
    unsigned long bw = (w + 3) / 4, bh = (h + 3) / 4, block = bc3 ? 16 : 8;
    unsigned long pw = bw * 4, ph = bh * 4;
    u8 (*rgba)[4] = malloc(pw * ph * 4);
    if (!rgba) return 0;
    for (unsigned long by = 0; by < bh; by++)
        for (unsigned long bx = 0; bx < bw; bx++) {
            const u8 *b = src + (by * bw + bx) * block;
            u8 px[16][4];
            decode_color(bc3 ? b + 8 : b, px, !bc3);
            if (bc3) decode_alpha(b, px);
            for (int i = 0; i < 16; i++) memcpy(rgba[(by * 4 + i / 4) * pw + bx * 4 + i % 4], px[i], 4);
        }
    unsigned long lw = w / 2 ? w / 2 : 1, lh = h / 2 ? h / 2 : 1, lbw = (lw + 3) / 4, lbh = (lh + 3) / 4;
    for (unsigned long by = 0; by < lbh; by++)
        for (unsigned long bx = 0; bx < lbw; bx++) {
            u8 px[16][4];
            for (int i = 0; i < 16; i++) {
                unsigned long x = bx * 4 + i % 4, y = by * 4 + i / 4;
                if (x >= lw) x = lw - 1;
                if (y >= lh) y = lh - 1;
                unsigned long sx = 2 * x < w ? 2 * x : w - 1, sy = 2 * y < h ? 2 * y : h - 1;
                unsigned long sx1 = sx + 1 < w ? sx + 1 : sx, sy1 = sy + 1 < h ? sy + 1 : sy;
                for (int k = 0; k < 4; k++)
                    px[i][k] = (u8)((rgba[sy * pw + sx][k] + rgba[sy * pw + sx1][k] + rgba[sy1 * pw + sx][k] + rgba[sy1 * pw + sx1][k] + 2) / 4);
            }
            u8 *out = dst + (by * lbw + bx) * block;
            if (bc3) { encode_alpha(px, out); encode_color(px, out + 8, 0); }
            else encode_color(px, out, 1);
        }
    free(rgba);
    return 1;
}

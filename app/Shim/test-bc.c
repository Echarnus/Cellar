/* Self-check of cellar-bc.c: a flat colour survives a BC1 and a BC3 level step.
 * cc -o /tmp/test-bc Shim/test-bc.c Shim/cellar-bc.c && /tmp/test-bc */
#include <assert.h>
#include <stdio.h>
#include <string.h>
int cellar_bc_next_level(const unsigned char *src, unsigned long w, unsigned long h, unsigned char *dst, int bc3);
int main(void)
{
    /* 8x8 BC1, every block solid pure red (0xF800, both endpoints, indices 0) */
    unsigned char bc1[4 * 8], out1[8];
    for (int i = 0; i < 4; i++) { unsigned char b[8] = { 0x00, 0xF8, 0x00, 0xF8, 0, 0, 0, 0 }; memcpy(bc1 + 8 * i, b, 8); }
    assert(cellar_bc_next_level(bc1, 8, 8, out1, 0));
    assert((out1[0] | out1[1] << 8) == 0xF800);  /* red endpoint */
    /* 8x8 BC3, half-transparent blue */
    unsigned char bc3[4 * 16], out3[16];
    for (int i = 0; i < 4; i++) { unsigned char b[16] = { 128, 128, 0, 0, 0, 0, 0, 0, 0x1F, 0, 0x1F, 0, 0, 0, 0, 0 }; memcpy(bc3 + 16 * i, b, 16); }
    assert(cellar_bc_next_level(bc3, 8, 8, out3, 1));
    assert(out3[0] == 128 && out3[1] == 128);           /* alpha kept */
    assert((out3[8] | out3[9] << 8) == 0x001F);         /* blue endpoint */
    puts("cellar-bc: ok");
    return 0;
}

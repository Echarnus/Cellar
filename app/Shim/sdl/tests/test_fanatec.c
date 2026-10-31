/* Unit tests for Cellar's Fanatec force-feedback engine, against a fake base that records commands. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "SDL_cellar_fanatec.h"

typedef struct { Uint8 cmds[512][7]; int n; SDL_Mutex *m; } Rec;
static bool record(void *u, const Uint8 cmd[7]) {
    Rec *r = u; if (r->m) SDL_LockMutex(r->m);
    if (r->n < 512) memcpy(r->cmds[r->n++], cmd, 7);
    if (r->m) SDL_UnlockMutex(r->m);
    return true;
}
static bool fail_send(void *u, const Uint8 cmd[7]) { (void)u; (void)cmd; return false; }

static int failures = 0;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); failures++; } } while (0)
static bool eq(const Uint8 *a, Uint8 b0, Uint8 b1, Uint8 b2, Uint8 b3, Uint8 b4, Uint8 b5, Uint8 b6) {
    Uint8 e[7] = {b0,b1,b2,b3,b4,b5,b6};
    if (memcmp(a, e, 7)) { printf("  got %02x %02x %02x %02x %02x %02x %02x\n", a[0],a[1],a[2],a[3],a[4],a[5],a[6]); return false; }
    return true;
}
static SDL_HapticEffect constant(Sint16 level) {
    SDL_HapticEffect e; SDL_zero(e);
    e.type = SDL_HAPTIC_CONSTANT; e.constant.direction.type = SDL_HAPTIC_STEERING_AXIS;
    e.constant.length = SDL_HAPTIC_INFINITY; e.constant.level = level; return e;
}
/* Starts one constant effect and returns the constant-slot command one tick produces. */
static void play_constant(Uint16 pid, int cap, int gain, Sint16 level, Uint8 out[7]) {
    Rec r = {0}; CellarFanatec *d = CellarFanatec_Create(pid, record, &r, cap, false);
    SDL_HapticEffect e = constant(level);
    if (gain >= 0) CellarFanatec_SetGain(d, gain);
    int id = CellarFanatec_NewEffect(d, &e);
    CellarFanatec_RunEffect(d, id, 1);
    r.n = 0; CellarFanatec_Tick(d, SDL_GetTicks() + 5);
    memcpy(out, r.n ? r.cmds[0] : (Uint8[7]){0}, 7);
    CellarFanatec_Destroy(d);
}

static void test_device_table(void) {
    CHECK(CellarFanatec_IsSupported(0x0eb7, 0x0020));
    CHECK(CellarFanatec_IsSupported(0x0eb7, 0x0e03));
    CHECK(!CellarFanatec_IsSupported(0x046d, 0x0020));
    CHECK(!CellarFanatec_IsSupported(0x0eb7, 0x1839)); /* pedals: no FFB */
    CHECK(CellarFanatec_IsHighRes(0x0020) && !CellarFanatec_IsHighRes(0x0001));
    CHECK(CellarFanatec_AutoRange(0x0020) == 2530 && CellarFanatec_AutoRange(0x0001) == 900 && CellarFanatec_AutoRange(0x0e03) == 1090);
}
static void test_cap_from_env(void) {
    SDL_unsetenv_unsafe("CELLAR_FFB_MAX_PERCENT"); CHECK(CellarFanatec_MaxPercentFromEnv() == 50);
    SDL_setenv_unsafe("CELLAR_FFB_MAX_PERCENT", "80", 1); CHECK(CellarFanatec_MaxPercentFromEnv() == 80);
    SDL_setenv_unsafe("CELLAR_FFB_MAX_PERCENT", "500", 1); CHECK(CellarFanatec_MaxPercentFromEnv() == 100);
    SDL_setenv_unsafe("CELLAR_FFB_MAX_PERCENT", "0", 1); CHECK(CellarFanatec_MaxPercentFromEnv() == 1);
    SDL_setenv_unsafe("CELLAR_FFB_MAX_PERCENT", "abc", 1); CHECK(CellarFanatec_MaxPercentFromEnv() == 1);
    SDL_unsetenv_unsafe("CELLAR_FFB_MAX_PERCENT");
}
static void test_init_sequence(void) {
    Rec r = {0}; CellarFanatec *d = CellarFanatec_Create(0x0020, record, &r, 50, false);
    CHECK(d && r.n == 11);
    CHECK(eq(r.cmds[0], 0xf8,0x09,0x01,0x06,0xff,0x01,0x00));
    CHECK(eq(r.cmds[1], 0xf8,0x09,0x01,0x06,0xff,0x00,0x00));
    CHECK(eq(r.cmds[2], 0xf8,0x09,0x01,0x06,0xff,0x04,0x00));
    CHECK(eq(r.cmds[3], 0xf5,0,0,0,0,0,0));
    CHECK(eq(r.cmds[4], 0xf8,0x09,0x01,0x06,0x01,0x00,0x00));
    CHECK(eq(r.cmds[5], 0xf8,0x81,0xe2,0x09,0,0,0)); /* 2530 */
    CHECK(eq(r.cmds[6], 0x03,0x08,0,0,0,0,0));      /* constant off */
    CHECK(eq(r.cmds[7], 0x13,0x0b,0,0,0,0,0));      /* spring off */
    CHECK(eq(r.cmds[8], 0x23,0x0c,0,0,0,0,0xff));   /* damper off */
    CHECK(eq(r.cmds[9], 0x33,0x0c,0,0,0,0,0xff));   /* inertia off */
    CHECK(eq(r.cmds[10],0x43,0x0c,0,0,0,0,0xff));   /* friction off */
    /* Nothing playing: a tick changes nothing, so it sends nothing. */
    r.n = 0; CellarFanatec_Tick(d, SDL_GetTicks()); CHECK(r.n == 0);
    CellarFanatec_Destroy(d);
}
static void test_init_failure(void) {
    CHECK(CellarFanatec_Create(0x0020, fail_send, NULL, 50, false) == NULL);
}
static void test_constant_highres_and_cap(void) {
    Uint8 c[7];
    play_constant(0x0020, 100, -1, 0x4000, c); CHECK(eq(c, 0x01,0x08,0x00,0xc0,0,0,0x01)); /* +half: 0xC000 */
    play_constant(0x0020, 50, -1, 0x4000, c);  CHECK(eq(c, 0x01,0x08,0x00,0xa0,0,0,0x01)); /* capped: 0xA000 */
    play_constant(0x0020, 50, 50, 0x4000, c);  CHECK(eq(c, 0x01,0x08,0x00,0x90,0,0,0x01)); /* gain too: 0x9000 */
    play_constant(0x0020, 100, -1, -0x4000, c); CHECK(eq(c, 0x01,0x08,0x00,0x40,0,0,0x01)); /* the other way */
    play_constant(0x0020, 50, 0, 0x4000, c);   CHECK(eq(c, 0,0,0,0,0,0,0));               /* gain 0: no change from off */
}
static void test_constant_lowres(void) {
    Uint8 c[7];
    play_constant(0x0001, 100, -1, 0x4000, c); CHECK(eq(c, 0x01,0x08,0xc0,0,0,0,0));
    play_constant(0x0001, 50, -1, 0x7fff, c);  CHECK(eq(c, 0x01,0x08,0xbf,0,0,0,0));
}
static void test_full_scale_never_exceeds_cap(void) {
    /* Two full-strength effects summed still land at the cap, not twice it. */
    Rec r = {0}; CellarFanatec *d = CellarFanatec_Create(0x0020, record, &r, 50, false);
    SDL_HapticEffect e = constant(0x7fff);
    int a = CellarFanatec_NewEffect(d, &e), b = CellarFanatec_NewEffect(d, &e);
    CellarFanatec_RunEffect(d, a, 1); CellarFanatec_RunEffect(d, b, 1);
    r.n = 0; CellarFanatec_Tick(d, SDL_GetTicks() + 1);
    CHECK(r.n == 1);
    Uint32 v = r.cmds[0][2] | (r.cmds[0][3] << 8);
    CHECK(v <= 0x8000 + 0x4000); /* 50% of positive full scale */
    CellarFanatec_Destroy(d);
}
static void test_spring_and_damper(void) {
    Rec r = {0}; CellarFanatec *d = CellarFanatec_Create(0x0020, record, &r, 100, false);
    SDL_HapticEffect s; SDL_zero(s); s.type = SDL_HAPTIC_SPRING; s.condition.length = SDL_HAPTIC_INFINITY;
    s.condition.right_sat[0] = 0xffff; s.condition.left_sat[0] = 0xffff;
    s.condition.right_coeff[0] = 0x7fff; s.condition.left_coeff[0] = 0x7fff;
    SDL_HapticEffect dm = s; dm.type = SDL_HAPTIC_DAMPER;
    CellarFanatec_RunEffect(d, CellarFanatec_NewEffect(d, &s), 1);
    CellarFanatec_RunEffect(d, CellarFanatec_NewEffect(d, &dm), 1);
    r.n = 0; CellarFanatec_Tick(d, SDL_GetTicks() + 1);
    CHECK(r.n == 2);
    CHECK(eq(r.cmds[0], 0x11,0x0b,0x80,0x80,0xff,0x00,0xff)); /* centred, full coeffs, full clip */
    CHECK(eq(r.cmds[1], 0x21,0x0c,0x0f,0x00,0x0f,0x00,0xff));
    CellarFanatec_Destroy(d);
}
static void test_effect_ends_after_length(void) {
    Rec r = {0}; CellarFanatec *d = CellarFanatec_Create(0x0020, record, &r, 100, false);
    SDL_HapticEffect e = constant(0x4000); e.constant.length = 10;
    int id = CellarFanatec_NewEffect(d, &e);
    Uint64 t0 = SDL_GetTicks();
    CellarFanatec_RunEffect(d, id, 1);
    r.n = 0; CellarFanatec_Tick(d, t0 + 2); CHECK(r.n == 1 && r.cmds[0][0] == 0x01);
    CHECK(CellarFanatec_GetEffectStatus(d, id) == 1);
    r.n = 0; CellarFanatec_Tick(d, t0 + 50); CHECK(r.n == 1 && eq(r.cmds[0], 0x03,0x08,0,0,0,0,0));
    CHECK(CellarFanatec_GetEffectStatus(d, id) == 0);
    CellarFanatec_Destroy(d);
}
static void test_stop_pause_and_destroy(void) {
    Rec r = {0}; CellarFanatec *d = CellarFanatec_Create(0x0020, record, &r, 100, false);
    SDL_HapticEffect e = constant(0x4000);
    int id = CellarFanatec_NewEffect(d, &e);
    CellarFanatec_RunEffect(d, id, SDL_HAPTIC_INFINITY);
    CellarFanatec_Tick(d, SDL_GetTicks() + 1);
    CellarFanatec_Pause(d); r.n = 0; CellarFanatec_Tick(d, SDL_GetTicks() + 2);
    CHECK(r.n == 1 && eq(r.cmds[0], 0x03,0x08,0,0,0,0,0));
    CellarFanatec_Resume(d); r.n = 0; CellarFanatec_Tick(d, SDL_GetTicks() + 3);
    CHECK(r.n == 1 && r.cmds[0][0] == 0x01);
    CellarFanatec_StopEffect(d, id); r.n = 0; CellarFanatec_Tick(d, SDL_GetTicks() + 4);
    CHECK(r.n == 1 && r.cmds[0][0] == 0x03);
    /* Destroy while playing: the slot goes off, then stop-all is the last thing sent. */
    CellarFanatec_RunEffect(d, id, 1); CellarFanatec_Tick(d, SDL_GetTicks() + 5);
    r.n = 0; CellarFanatec_Destroy(d);
    CHECK(r.n == 2 && eq(r.cmds[0], 0x03,0x08,0,0,0,0,0) && eq(r.cmds[1], 0xf3,0,0,0,0,0,0));
}
static void test_rejects_bad_effects(void) {
    Rec r = {0}; CellarFanatec *d = CellarFanatec_Create(0x0020, record, &r, 100, false);
    SDL_HapticEffect e; SDL_zero(e); e.type = SDL_HAPTIC_SINE; e.periodic.period = 0;
    CHECK(CellarFanatec_NewEffect(d, &e) == -1);
    e.type = SDL_HAPTIC_LEFTRIGHT; CHECK(CellarFanatec_NewEffect(d, &e) == -1);
    CHECK(!CellarFanatec_RunEffect(d, 3, 1));
    SDL_HapticEffect c = constant(1); int n = 0;
    while (CellarFanatec_NewEffect(d, &c) >= 0) n++;
    CHECK(n == CELLAR_FANATEC_MAX_EFFECTS);
    CellarFanatec_Destroy(d);
}
static void test_sine_moves(void) {
    Rec r = {0}; CellarFanatec *d = CellarFanatec_Create(0x0020, record, &r, 100, false);
    SDL_HapticEffect e; SDL_zero(e); e.type = SDL_HAPTIC_SINE; e.periodic.direction.type = SDL_HAPTIC_STEERING_AXIS;
    e.periodic.length = SDL_HAPTIC_INFINITY; e.periodic.period = 100; e.periodic.magnitude = 0x4000;
    int id = CellarFanatec_NewEffect(d, &e); Uint64 t0 = SDL_GetTicks();
    CellarFanatec_RunEffect(d, id, 1);
    r.n = 0; CellarFanatec_Tick(d, t0 + 25); CellarFanatec_Tick(d, t0 + 75);
    CHECK(r.n == 2);
    if (r.n == 2) { CHECK(r.cmds[0][3] > 0x80 && r.cmds[1][3] < 0x80); } /* a quarter period pushes, three quarters pulls */
    CellarFanatec_Destroy(d);
}
static void test_thread(void) {
    Rec r = {0}; r.m = SDL_CreateMutex();
    CellarFanatec *d = CellarFanatec_Create(0x0020, record, &r, 50, true);
    SDL_HapticEffect e = constant(0x4000);
    CellarFanatec_RunEffect(d, CellarFanatec_NewEffect(d, &e), SDL_HAPTIC_INFINITY);
    SDL_Delay(30);
    SDL_LockMutex(r.m); int sent = r.n; SDL_UnlockMutex(r.m);
    CHECK(sent == 12); /* init + one change, not one per tick */
    CellarFanatec_Destroy(d);
    CHECK(eq(r.cmds[r.n - 1], 0xf3,0,0,0,0,0,0));
    SDL_DestroyMutex(r.m);
}

int main(void) {
    test_device_table(); test_cap_from_env(); test_init_sequence(); test_init_failure();
    test_constant_highres_and_cap(); test_constant_lowres(); test_full_scale_never_exceeds_cap();
    test_spring_and_damper(); test_effect_ends_after_length(); test_stop_pause_and_destroy();
    test_rejects_bad_effects(); test_sine_moves(); test_thread();
    printf(failures ? "%d FAILED\n" : "all passed\n", failures);
    return failures != 0;
}

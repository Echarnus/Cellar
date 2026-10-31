/* Unit tests for Cellar's Thrustmaster force-feedback engine, against a fake wheel that records commands. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "SDL_cellar_thrustmaster.h"

#define MAXB CELLAR_THRUSTMASTER_MAX_BUFFER
typedef struct { Uint8 cmds[256][MAXB]; int lens[256]; int n; SDL_Mutex *m; } Rec;
static bool record(void *u, const Uint8 *buf, int len) {
    Rec *r = u; if (r->m) SDL_LockMutex(r->m);
    if (r->n < 256) { memcpy(r->cmds[r->n], buf, (size_t)len); r->lens[r->n++] = len; }
    if (r->m) SDL_UnlockMutex(r->m);
    return true;
}
static bool fail_send(void *u, const Uint8 *buf, int len) { (void)u; (void)buf; (void)len; return false; }

static int failures = 0;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); failures++; } } while (0)
/* Compares the start of a command; every byte after `n` must be zero. */
static bool starts(const Uint8 *a, int n, const Uint8 *e) {
    for (int i = 0; i < MAXB; i++) {
        Uint8 want = i < n ? e[i] : 0;
        if (a[i] != want) {
            printf("  byte %d: got %02x, want %02x\n  got", i, a[i], want);
            for (int j = 0; j < 32; j++) printf(" %02x", a[j]);
            printf("\n");
            return false;
        }
    }
    return true;
}
#define IS(cmd, ...) starts((cmd), (int)sizeof((Uint8[]){__VA_ARGS__}), (Uint8[]){__VA_ARGS__})
static Uint16 at16(const Uint8 *c, int i) { return (Uint16)(c[i] | (c[i + 1] << 8)); }

static SDL_HapticEffect constant(Sint16 level, Uint32 length) {
    SDL_HapticEffect e; SDL_zero(e);
    e.type = SDL_HAPTIC_CONSTANT; e.constant.direction.type = SDL_HAPTIC_STEERING_AXIS;
    e.constant.length = length; e.constant.level = level; return e;
}
static CellarThrustmaster *open_t300(Rec *r, int cap) {
    CellarThrustmaster *d = CellarThrustmaster_Create(0xb66e, record, r, cap, false);
    r->n = 0; return d;
}

static void test_device_table(void) {
    CHECK(CellarThrustmaster_IsSupported(0x044f, 0xb66e));
    CHECK(CellarThrustmaster_IsSupported(0x044f, 0xb66f));
    CHECK(CellarThrustmaster_IsSupported(0x044f, 0xb66d));
    CHECK(CellarThrustmaster_IsSupported(0x044f, 0xb696));
    CHECK(CellarThrustmaster_IsSupported(0x044f, 0xb669));
    CHECK(CellarThrustmaster_IsSupported(0x044f, 0xb692));
    CHECK(CellarThrustmaster_IsSupported(0x044f, 0xb689));
    CHECK(!CellarThrustmaster_IsSupported(0x044f, 0xb65d)); /* the generic mode before the switch */
    CHECK(!CellarThrustmaster_IsSupported(0x0eb7, 0xb66e));
    CHECK(CellarThrustmaster_BufferLength(0xb66d) == 31 && CellarThrustmaster_BufferLength(0xb66e) == 63);
}
static void test_switch_value(void) {
    Uint8 a[16] = {0x49,0x00, 0,0, 0,0, 0x06,0x02};             /* a T300RS, the long answer */
    Uint8 b[16] = {0x47,0x00, 0,0, 0,0, 0x09,0x02};             /* open wheel rim, the short one */
    Uint8 t150[16] = {0x49,0x00, 0,0, 0,0, 0x06,0x03};
    Uint8 junk[16] = {0x13,0x00, 0,0, 0,0, 0x06,0x02};
    CHECK(CellarThrustmaster_SwitchValue(a, 16) == 5);
    CHECK(CellarThrustmaster_SwitchValue(b, 8) == 5);
    CHECK(CellarThrustmaster_SwitchValue(t150, 16) == 0);  /* not a wheel this engine drives */
    CHECK(CellarThrustmaster_SwitchValue(junk, 16) == 0);
    CHECK(CellarThrustmaster_SwitchValue(a, 7) == 0 && CellarThrustmaster_SwitchValue(NULL, 16) == 0);
}
static void test_cap_from_env(void) {
    SDL_unsetenv_unsafe("CELLAR_FFB_MAX_PERCENT"); CHECK(CellarThrustmaster_MaxPercentFromEnv() == 100);
    SDL_setenv_unsafe("CELLAR_FFB_MAX_PERCENT", "40", 1); CHECK(CellarThrustmaster_MaxPercentFromEnv() == 40);
    SDL_setenv_unsafe("CELLAR_FFB_MAX_PERCENT", "500", 1); CHECK(CellarThrustmaster_MaxPercentFromEnv() == 100);
    SDL_setenv_unsafe("CELLAR_FFB_MAX_PERCENT", "0", 1); CHECK(CellarThrustmaster_MaxPercentFromEnv() == 1);
    SDL_unsetenv_unsafe("CELLAR_FFB_MAX_PERCENT");
}
static void test_open_sequences(void) {
    Rec r = {0};
    CellarThrustmaster *d = CellarThrustmaster_Create(0xb66e, record, &r, 50, false);
    CHECK(d && r.n == 3);
    CHECK(IS(r.cmds[0], 0x01, 0x05));
    CHECK(IS(r.cmds[1], 0x08, 0x11, 0xf0, 0xd2)); /* 900 degrees * 0x3c */
    CHECK(IS(r.cmds[2], 0x02, 0x7f));             /* half strength through the wheel's gain */
    CHECK(r.lens[0] == 63);
    CellarThrustmaster_Destroy(d);
    CHECK(r.n == 4 && IS(r.cmds[3], 0x01, 0x00));

    Rec t = {0};
    d = CellarThrustmaster_Create(0xb696, record, &t, 100, false);
    CHECK(d && t.n == 4);
    CHECK(IS(t.cmds[0], 0x01, 0x04) && IS(t.cmds[1], 0x01, 0x05));
    CHECK(IS(t.cmds[3], 0x02, 0xff));
    CellarThrustmaster_Destroy(d);
    CHECK(t.n == 6 && IS(t.cmds[4], 0x01, 0x05) && IS(t.cmds[5], 0x01, 0x00));

    Rec p = {0};
    d = CellarThrustmaster_Create(0xb66d, record, &p, 100, false);
    CHECK(d && p.lens[0] == 31);
    CellarThrustmaster_Destroy(d);
}
static void test_open_failure(void) {
    CHECK(CellarThrustmaster_Create(0xb66e, fail_send, NULL, 100, false) == NULL);
}
static void test_constant_upload_and_play(void) {
    Rec r = {0}; CellarThrustmaster *d = open_t300(&r, 100);
    SDL_HapticEffect e = constant(0x4000, SDL_HAPTIC_INFINITY);
    int id = CellarThrustmaster_NewEffect(d, &e);
    CHECK(id == 0);
    CHECK(CellarThrustmaster_RunEffect(d, id, SDL_HAPTIC_INFINITY));
    CHECK(CellarThrustmaster_GetEffectStatus(d, id) == 1);
    CellarThrustmaster_Tick(d, 1000);
    CHECK(r.n == 2);
    /* level 0x4000 to the right, halved to the driver's range; timing: infinite, no delay */
    CHECK(IS(r.cmds[0], 0x00, 0x01, 0x6a, 0x00, 0x20, 0,0,0,0,0,0,0,0, 0x00, 0x4f, 0xff, 0xff, 0,0, 0,0, 0, 0xff, 0xff));
    CHECK(IS(r.cmds[1], 0x00, 0x01, 0x89, 0x41, 0x00, 0x00));
    CellarThrustmaster_Tick(d, 1008);
    CHECK(r.n == 2); /* nothing new, nothing sent */
    CellarThrustmaster_Destroy(d);
}
static void test_direction(void) {
    Rec r = {0}; CellarThrustmaster *d = open_t300(&r, 100);
    SDL_HapticEffect e = constant(0x4000, SDL_HAPTIC_INFINITY);
    e.constant.direction.type = SDL_HAPTIC_POLAR; e.constant.direction.dir[0] = 27000; /* to the left */
    CellarThrustmaster_NewEffect(d, &e);
    CellarThrustmaster_Tick(d, 0);
    CHECK(r.n == 1 && (Sint16)at16(r.cmds[0], 3) == -0x2000);
    CellarThrustmaster_Destroy(d);
}
static void test_update_only_on_change(void) {
    Rec r = {0}; CellarThrustmaster *d = open_t300(&r, 100);
    SDL_HapticEffect e = constant(0x4000, 500);
    int id = CellarThrustmaster_NewEffect(d, &e);
    CellarThrustmaster_Tick(d, 0); r.n = 0;
    CHECK(CellarThrustmaster_UpdateEffect(d, id, &e));
    CellarThrustmaster_Tick(d, 8);
    CHECK(r.n == 0);
    e.constant.level = -0x4000;
    CHECK(CellarThrustmaster_UpdateEffect(d, id, &e));
    CellarThrustmaster_Tick(d, 16);
    CHECK(r.n == 1);
    CHECK(IS(r.cmds[0], 0x00, 0x01, 0x6a, 0x00, 0xe0, 0,0,0,0,0,0,0,0, 0x00, 0x45, 0xf4, 0x01, 0x00, 0x00));
    /* an update before the first upload went out is folded into that upload */
    SDL_HapticEffect f = constant(0x1000, SDL_HAPTIC_INFINITY);
    int id2 = CellarThrustmaster_NewEffect(d, &f);
    f.constant.level = 0x2000;
    CellarThrustmaster_UpdateEffect(d, id2, &f);
    r.n = 0; CellarThrustmaster_Tick(d, 24);
    CHECK(r.n == 1 && r.cmds[0][2] == 0x6a && at16(r.cmds[0], 3) == 0x1000);
    CellarThrustmaster_Destroy(d);
}
static void test_stop_and_expiry(void) {
    Rec r = {0}; CellarThrustmaster *d = open_t300(&r, 100);
    SDL_HapticEffect e = constant(0x4000, 100);
    int id = CellarThrustmaster_NewEffect(d, &e);
    CellarThrustmaster_RunEffect(d, id, 2);
    CellarThrustmaster_Tick(d, 1000);
    CHECK(r.n == 2 && IS(r.cmds[1], 0x00, 0x01, 0x89, 0x41, 0x02, 0x00));
    CellarThrustmaster_Tick(d, 1150);
    CHECK(CellarThrustmaster_GetEffectStatus(d, id) == 1);
    CellarThrustmaster_Tick(d, 1200);
    CHECK(CellarThrustmaster_GetEffectStatus(d, id) == 0); /* two 100 ms runs are over */
    CHECK(r.n == 2); /* the wheel ends it itself */

    CellarThrustmaster_RunEffect(d, id, 1);
    CellarThrustmaster_Tick(d, 2000);
    CHECK(CellarThrustmaster_StopEffect(d, id));
    CellarThrustmaster_Tick(d, 2008);
    CHECK(r.n == 4 && IS(r.cmds[3], 0x00, 0x01, 0x89));
    CHECK(CellarThrustmaster_GetEffectStatus(d, id) == 0);
    CellarThrustmaster_Destroy(d);
    CHECK(r.n == 5 && IS(r.cmds[4], 0x01, 0x00)); /* nothing playing: only the close */
}
static void test_conditions(void) {
    Rec r = {0}; CellarThrustmaster *d = open_t300(&r, 100);
    SDL_HapticEffect e; SDL_zero(e);
    e.type = SDL_HAPTIC_SPRING; e.condition.length = SDL_HAPTIC_INFINITY;
    e.condition.right_coeff[0] = 0x7fff; e.condition.left_coeff[0] = 0x7fff;
    CellarThrustmaster_NewEffect(d, &e);
    e.type = SDL_HAPTIC_DAMPER; e.condition.right_sat[0] = 0xffff; e.condition.left_sat[0] = 0x7fff;
    CellarThrustmaster_NewEffect(d, &e);
    CellarThrustmaster_Tick(d, 0);
    CHECK(r.n == 2);
    const Uint8 *s = r.cmds[0], *m = r.cmds[1];
    CHECK(s[2] == 0x64 && at16(s, 3) == 0x2666 && at16(s, 5) == 0x2666); /* 30% of full */
    CHECK(at16(s, 7) == 0 && at16(s, 9) == 0);                            /* centred, no deadband */
    CHECK(at16(s, 11) == 0x6aa6 && at16(s, 13) == 0x6aa6);                /* 0 saturation = the spring's max */
    CHECK(s[15] == 0xfe && s[22] == 0xff && at16(s, 23) == 0x6aa6 && s[27] == 0x06 && s[28] == 0x4f);
    CHECK(m[1] == 0x02 && at16(m, 11) == 0x7ffc && at16(m, 13) == 0x3ffe && m[27] == 0x07);
    CellarThrustmaster_Destroy(d);
}
static void test_ramp_and_periodic(void) {
    Rec r = {0}; CellarThrustmaster *d = open_t300(&r, 100);
    SDL_HapticEffect e; SDL_zero(e);
    e.type = SDL_HAPTIC_RAMP; e.ramp.direction.type = SDL_HAPTIC_STEERING_AXIS;
    e.ramp.length = 1000; e.ramp.start = 0; e.ramp.end = 0x4000;
    CellarThrustmaster_NewEffect(d, &e);
    SDL_zero(e);
    e.type = SDL_HAPTIC_SINE; e.periodic.direction.type = SDL_HAPTIC_STEERING_AXIS;
    e.periodic.length = SDL_HAPTIC_INFINITY; e.periodic.period = 50; e.periodic.magnitude = -0x4000;
    e.periodic.offset = 0x7000;
    int id = CellarThrustmaster_NewEffect(d, &e);
    CellarThrustmaster_Tick(d, 0);
    CHECK(r.n == 2);
    const Uint8 *ramp = r.cmds[0], *sine = r.cmds[1];
    CHECK(ramp[2] == 0x6b && at16(ramp, 3) == 0x2000 && at16(ramp, 5) == 0x2000 && at16(ramp, 9) == 1000);
    CHECK(at16(ramp, 11) == 0x8000 && ramp[21] == 0x04 && ramp[22] == 0x4f);
    /* a negative magnitude becomes a positive one half a turn later; the offset keeps within headroom */
    CHECK(sine[2] == 0x6b && at16(sine, 3) == 0x4000 && at16(sine, 5) == 0x3fff && at16(sine, 7) == 16339);
    CHECK(at16(sine, 9) == 50 && sine[21] == 3 && at16(sine, 23) == 0xffff);
    /* a periodic modify carries its own type byte */
    e.periodic.period = 100;
    CellarThrustmaster_UpdateEffect(d, id, &e);
    r.n = 0; CellarThrustmaster_Tick(d, 8);
    CHECK(r.n == 1 && r.cmds[0][2] == 0x6e && r.cmds[0][3] == 0x0f && at16(r.cmds[0], 10) == 100 && r.cmds[0][21] == 0x45);
    CellarThrustmaster_Destroy(d);
}
static void test_gain_never_exceeds_cap(void) {
    Rec r = {0}; CellarThrustmaster *d = open_t300(&r, 50);
    CHECK(CellarThrustmaster_SetGain(d, 100) && IS(r.cmds[0], 0x02, 0x7f));
    CHECK(CellarThrustmaster_SetGain(d, 500) && IS(r.cmds[1], 0x02, 0x7f));
    CHECK(CellarThrustmaster_SetGain(d, 50) && IS(r.cmds[2], 0x02, 0x3f));
    CHECK(CellarThrustmaster_SetGain(d, 0) && IS(r.cmds[3], 0x02, 0x00));
    CHECK(CellarThrustmaster_SetAutocenter(d, 100));
    CHECK(IS(r.cmds[4], 0x08, 0x04, 0x01, 0x00) && IS(r.cmds[5], 0x08, 0x03, 0xff, 0xff));
    CellarThrustmaster_Destroy(d);
}
static void test_destroy_stops_everything(void) {
    Rec r = {0}; CellarThrustmaster *d = open_t300(&r, 100);
    SDL_HapticEffect e = constant(0x4000, SDL_HAPTIC_INFINITY);
    int a = CellarThrustmaster_NewEffect(d, &e), b = CellarThrustmaster_NewEffect(d, &e);
    int c = CellarThrustmaster_NewEffect(d, &e);
    CellarThrustmaster_RunEffect(d, a, 1); CellarThrustmaster_RunEffect(d, b, 1);
    CellarThrustmaster_Tick(d, 0);
    /* destroying an effect that plays stops it at once: its slot is gone before the next tick */
    r.n = 0; CellarThrustmaster_DestroyEffect(d, a);
    CHECK(r.n == 1 && IS(r.cmds[0], 0x00, 0x01, 0x89));
    CHECK(CellarThrustmaster_GetEffectStatus(d, a) == -1);
    CHECK(CellarThrustmaster_StopAll(d));
    CellarThrustmaster_RunEffect(d, c, 1); /* asked, not yet sent */
    /* b's queued stop and c's queued start never reach a tick: Destroy stops both, then closes */
    r.n = 0; CellarThrustmaster_Destroy(d);
    CHECK(r.n == 3 && IS(r.cmds[0], 0x00, 0x02, 0x89) && IS(r.cmds[1], 0x00, 0x03, 0x89) && IS(r.cmds[2], 0x01, 0x00));
}
static void test_rejects_bad_effects(void) {
    Rec r = {0}; CellarThrustmaster *d = open_t300(&r, 100);
    SDL_HapticEffect e; SDL_zero(e); e.type = SDL_HAPTIC_LEFTRIGHT;
    CHECK(CellarThrustmaster_NewEffect(d, &e) == -1);
    SDL_zero(e); e.type = SDL_HAPTIC_SINE; /* period 0 */
    CHECK(CellarThrustmaster_NewEffect(d, &e) == -1);
    SDL_HapticEffect c = constant(1, SDL_HAPTIC_INFINITY);
    for (int i = 0; i < CELLAR_THRUSTMASTER_MAX_EFFECTS; i++) CHECK(CellarThrustmaster_NewEffect(d, &c) == i);
    CHECK(CellarThrustmaster_NewEffect(d, &c) == -1);
    SDL_zero(e); e.type = SDL_HAPTIC_SPRING;
    CHECK(!CellarThrustmaster_UpdateEffect(d, 0, &e)); /* a constant stays a constant */
    CHECK(!CellarThrustmaster_RunEffect(d, 99, 1) && !CellarThrustmaster_StopEffect(d, -1));
    CellarThrustmaster_DestroyEffect(d, 3);
    CHECK(CellarThrustmaster_NewEffect(d, &c) == 3); /* a freed slot is reused */
    CellarThrustmaster_Destroy(d);
}
static void test_thread(void) {
    Rec r = {0}; r.m = SDL_CreateMutex();
    CellarThrustmaster *d = CellarThrustmaster_Create(0xb66e, record, &r, 100, true);
    SDL_HapticEffect e = constant(0x4000, SDL_HAPTIC_INFINITY);
    CellarThrustmaster_RunEffect(d, CellarThrustmaster_NewEffect(d, &e), SDL_HAPTIC_INFINITY);
    SDL_Delay(40);
    SDL_LockMutex(r.m); int sent = r.n; SDL_UnlockMutex(r.m);
    CHECK(sent == 5); /* open, range, gain, upload, play: not one per tick */
    CellarThrustmaster_Destroy(d);
    CHECK(r.n == 7 && IS(r.cmds[5], 0x00, 0x01, 0x89) && IS(r.cmds[6], 0x01, 0x00));
    SDL_DestroyMutex(r.m);
}

int main(void) {
    test_device_table(); test_switch_value(); test_cap_from_env(); test_open_sequences(); test_open_failure();
    test_constant_upload_and_play(); test_direction(); test_update_only_on_change();
    test_stop_and_expiry(); test_conditions(); test_ramp_and_periodic(); test_gain_never_exceeds_cap();
    test_destroy_stops_everything(); test_rejects_bad_effects(); test_thread();
    printf(failures ? "%d FAILED\n" : "all passed\n", failures);
    return failures != 0;
}

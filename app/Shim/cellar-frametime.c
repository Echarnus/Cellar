/*
 * cellar-frametime — records when each frame is handed to Core Animation, for 1% low measurements.
 *
 * D3DMetal's frames reach neither the Metal HUD's log nor Instruments' per-frame tables, so frame
 * pacing is measured where every Metal game ends up: Core Animation. Each -[CAMetalLayer
 * nextDrawable] (one per frame) and each drawable -present* call is timestamped.
 *
 * Off unless CELLAR_FRAME_LOG names a directory (`cellar launch --frame-log <dir>` sets it; a
 * profile cannot). Then each process writes
 * <dir>/frames-<pid>.txt: one line per event, "<n|p> <nanoseconds since boot>"
 * (n = nextDrawable, p = present). Lines are buffered and written every 256 events, so a killed
 * process loses at most that many. Part of the dock shim's library because that library is already
 * inserted into every Wine process Cellar starts for a game.
 *
 * CELLAR_DISPLAY_SYNC (`cellar launch --display-sync`) is separate: it sets displaySyncEnabled on
 * the layer at each nextDrawable, so frames are paced to the display, with or without a log.
 */
#include <dlfcn.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <os/lock.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int log_fd = -1;
static char buffer[256 * 24];
static size_t used;
static mach_timebase_info_data_t timebase;
/* nextDrawable and present can come from different threads; a torn line would be a wrong timestamp. */
static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;

static void flush_log(void)
{
    os_unfair_lock_lock(&lock);
    if (log_fd >= 0 && used) { (void)write(log_fd, buffer, used); used = 0; }
    os_unfair_lock_unlock(&lock);
}

static void note(char kind)
{
    if (log_fd < 0) return;
    unsigned long long ns = mach_absolute_time() * timebase.numer / timebase.denom;
    os_unfair_lock_lock(&lock);
    int n = snprintf(buffer + used, sizeof buffer - used, "%c %llu\n", kind, ns);
    if (n > 0) used += (size_t)n;
    int full = used > sizeof buffer - 32;
    os_unfair_lock_unlock(&lock);
    if (full) flush_log();
}

typedef id (*next_fn)(id, SEL);
typedef void (*present_fn)(id, SEL);
typedef void (*present_at_fn)(id, SEL, double);
static next_fn original_next;
static present_fn original_present;
static present_at_fn original_present_at, original_present_after;

/* Pace frames to the display: AC's own frame cap and VSYNC do not hold under Wine + D3DMetal. */
static int display_sync;
static id frametime_next(id self, SEL cmd)
{
    if (display_sync) ((void (*)(id, SEL, signed char))objc_msgSend)(self, sel_registerName("setDisplaySyncEnabled:"), 1);
    note('n');
    return original_next(self, cmd);
}
static void frametime_present(id self, SEL cmd) { note('p'); original_present(self, cmd); }
static void frametime_present_at(id self, SEL cmd, double t) { note('p'); original_present_at(self, cmd, t); }
static void frametime_present_after(id self, SEL cmd, double t) { note('p'); original_present_after(self, cmd, t); }

static void hook(const char *class_name, const char *selector, IMP replacement, void *original)
{
    Class cls = objc_getClass(class_name);
    Method method = cls ? class_getInstanceMethod(cls, sel_registerName(selector)) : NULL;
    if (method) *(IMP *)original = method_setImplementation(method, replacement);
}

__attribute__((constructor))
static void cellar_frametime_init(void)
{
    const char *dir = getenv("CELLAR_FRAME_LOG");
    const char *sync = getenv("CELLAR_DISPLAY_SYNC");
    display_sync = sync && *sync && strcmp(sync, "0") != 0;
    int logging = dir && *dir;
    if (!logging && !display_sync) return;
    if (!dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_LAZY)) return;
    if (logging) {
        char path[1024];
        if (snprintf(path, sizeof path, "%s/frames-%d.txt", dir, getpid()) < (int)sizeof path)
            log_fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
        mach_timebase_info(&timebase);
        atexit(flush_log);
    }
    hook("CAMetalLayer", "nextDrawable", (IMP)frametime_next, &original_next);
    if (log_fd < 0) return;
    hook("CAMetalDrawable", "present", (IMP)frametime_present, &original_present);
    hook("CAMetalDrawable", "presentAtTime:", (IMP)frametime_present_at, &original_present_at);
    hook("CAMetalDrawable", "presentAfterMinimumDuration:", (IMP)frametime_present_after, &original_present_after);
}

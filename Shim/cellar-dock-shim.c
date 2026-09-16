/*
 * cellar-dock-shim — keeps a bottle's storefront client out of the macOS Dock.
 *
 * Wine's Mac driver gives every Windows process that shows a window a Dock icon: it calls
 * -[NSApplication setActivationPolicy:NSApplicationActivationPolicyRegular] the first time a
 * window is ordered front. That is right for a game and wrong for Steam or Battle.net, which
 * Cellar starts on the player's behalf and which they never asked to see. There is no Wine
 * setting for it — the driver's whole option list (`Software\Wine\Mac Driver`) has no dock key —
 * so the only place the decision can be changed is inside the process making it.
 *
 * Cellar therefore inserts this library (DYLD_INSERT_LIBRARIES) when it starts a store client and
 * names the client's own executables in CELLAR_DOCK_HIDE. In a process whose Windows executable is
 * on that list, the transform to "Regular" is redirected to "Accessory": the app keeps its windows,
 * its focus and its keyboard, and loses only its Dock tile and its ⌘-Tab entry. Every other
 * process — the game above all — is left completely alone, so a name Cellar does not know about
 * still gets its icon.
 *
 * The same library can also keep a process's windows off screen entirely, for the one start Cellar
 * wants to happen unseen: Steam's first self-update. Its bootstrapper refuses to run without a
 * window ("failed to initialize update status ui") — Wine's null display driver is not enough — so
 * the window is created as normal and simply never ordered onto the screen. A process named in
 * CELLAR_WINDOW_HIDE gets that treatment; Cellar reads the update's progress from Steam's log and
 * shows it in its own window, and ends that session once the update is done.
 *
 * Built by Scripts/build-dock-shim.sh for both architectures, because a runner may be x86_64
 * (running under Rosetta) or arm64.
 */

#include <crt_externs.h>
#include <dlfcn.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

/* NSApplicationActivationPolicy, from AppKit — not linked, so spelled out here. */
#define POLICY_REGULAR   0L
#define POLICY_ACCESSORY 1L

static bool transformed = false;
static BOOL (*original_set_policy)(id, SEL, long) = NULL;
static long (*original_policy)(id, SEL) = NULL;

/* Wine asks for Regular; give it Accessory. Reporting success keeps the driver on its normal
 * path — it goes on to build the menu bar and activate the app, which is what makes the client's
 * window usable once it does appear. */
static BOOL cellar_set_activation_policy(id self, SEL cmd, long policy)
{
    if (policy == POLICY_REGULAR) {
        BOOL ok = original_set_policy(self, cmd, POLICY_ACCESSORY);
        transformed = true;
        return ok;
    }
    return original_set_policy(self, cmd, policy);
}

/* The driver only transforms when it sees a policy other than Regular, so an honest answer here
 * would make it retry — and re-activate the app — on every window it ever shows. Answer Regular
 * once the first transform has been through, and it settles. */
static long cellar_activation_policy(id self, SEL cmd)
{
    return transformed ? POLICY_REGULAR : original_policy(self, cmd);
}

/* The last path component of a Windows ("C:\...\steam.exe") or unix argument. */
static const char *executable_name(const char *path)
{
    const char *name = path;
    for (const char *p = path; *p; p++) {
        if (*p == '\\' || *p == '/') name = p + 1;
    }
    return name;
}

/* Case-insensitive membership in a comma-separated list. */
static bool name_is_listed(const char *name, const char *list)
{
    size_t length = strlen(name);
    for (const char *entry = list; *entry; ) {
        const char *end = strchr(entry, ',');
        size_t entry_length = end ? (size_t)(end - entry) : strlen(entry);
        if (entry_length == length && strncasecmp(entry, name, length) == 0) return true;
        if (!end) break;
        entry = end + 1;
    }
    return false;
}

static void swap(Class cls, SEL selector, IMP replacement, void *original)
{
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;
    IMP previous = method_setImplementation(method, replacement);
    if (original) *(IMP *)original = previous;
}

/* Every way a window gets onto the screen, made to do nothing. Wine's window class overrides some
 * of these and calls through to NSWindow, so replacing NSWindow's is enough. */
static void cellar_order_window(id self, SEL cmd, long place, long other) { (void)self; (void)cmd; (void)place; (void)other; }
static void cellar_order_sender(id self, SEL cmd, id sender) { (void)self; (void)cmd; (void)sender; }
static void cellar_order_plain(id self, SEL cmd) { (void)self; (void)cmd; }

static bool this_process_is_listed(const char *variable)
{
    const char *list = getenv(variable);
    if (!list || !*list) return false;
    /* Wine runs one unix process per Windows process, with the .exe as its first argument. */
    if (*_NSGetArgc() < 2) return false;
    return name_is_listed(executable_name((*_NSGetArgv())[1]), list);
}

__attribute__((constructor))
static void cellar_dock_shim_init(void)
{
    bool hide_dock = this_process_is_listed("CELLAR_DOCK_HIDE");
    bool hide_windows = this_process_is_listed("CELLAR_WINDOW_HIDE");
    if (!hide_dock && !hide_windows) return;

    /* AppKit is not linked: a process that never draws should not pay for it. */
    if (!dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_LAZY)) return;

    if (hide_dock) {
        Class application = objc_getClass("NSApplication");
        if (application) {
            swap(application, sel_registerName("setActivationPolicy:"),
                 (IMP)cellar_set_activation_policy, &original_set_policy);
            swap(application, sel_registerName("activationPolicy"),
                 (IMP)cellar_activation_policy, &original_policy);
        }
    }

    if (hide_windows) {
        Class window = objc_getClass("NSWindow");
        if (window) {
            swap(window, sel_registerName("orderWindow:relativeTo:"), (IMP)cellar_order_window, NULL);
            swap(window, sel_registerName("orderFront:"), (IMP)cellar_order_sender, NULL);
            swap(window, sel_registerName("makeKeyAndOrderFront:"), (IMP)cellar_order_sender, NULL);
            swap(window, sel_registerName("orderFrontRegardless"), (IMP)cellar_order_plain, NULL);
        }
    }
}

/*
 * Hide every monitor but the streaming one from Steam.
 *
 * Steam Remote Play on Linux does not size its capture from the PipeWire
 * stream the portal hands it. Measured on this host: the portal source was the
 * 1280x800 virtual output, niri negotiated a 1280x800 node and kept it, and
 * Steam still announced "Capture resolution set to 1280x360" 150ms later --
 * 5120x1440 (the ultrawide) fitted to the client's width. It asks X instead,
 * and picks the largest monitor it can see.
 *
 * Neither the RandR primary flag nor the Xinerama head order changes that;
 * both were tested and Steam ignored them. With the ultrawide absent the
 * capture is correct, so the only lever left is what X reports. This filters
 * the monitor lists so that while a stream is running Steam sees exactly one
 * monitor: the one being streamed.
 *
 * It is deliberately inert when nothing is streaming. The stream target file
 * is written by the host-side watcher only for the duration of a session, so
 * ordinary desktop use sees the real monitor list and Steam behaves normally.
 */

#define _GNU_SOURCE

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <stdarg.h>
#include <time.h>

#include <X11/Xlib.h>
#include <X11/extensions/Xinerama.h>
#include <X11/extensions/Xrandr.h>

/* The output being streamed, as published by the watcher. */
struct target {
    char name[128];
    int width;
    int height;
};

/*
 * Only the Steam client itself gets a filtered view of the monitors.
 *
 * LD_PRELOAD is inherited by every descendant, and Steam starts a great many:
 * gamescope, the pressure-vessel container, wine, and the game itself all
 * arrive here with the shim loaded. None of them need it. The number this
 * exists to correct is read by the process that maps steamui.so -- the
 * ubuntu12_32/steam client, which emits "Desktop state changed" -- and
 * lying to anything else is pure blast radius.
 *
 * It is not merely untidy. gamescope is launched with `--prefer-output steam`
 * and its own -W/-H, so handing it a display list with the ultrawide removed
 * makes it negotiate against a view that does not match the compositor's,
 * while the game underneath initialises against the same filtered list. A
 * stream started this way wedged during game launch with Steam's main loop
 * stalled.
 *
 * Matched on the executable name rather than an environment variable so it
 * cannot be defeated by the many wrapper layers between the client and the
 * game, each of which rewrites the environment.
 */
static int process_is_steam_client(void)
{
    static int cached = -1;
    char exe[4096];
    const char *name;
    ssize_t len;

    if (cached >= 0)
        return cached;

    len = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (len <= 0) {
        /* Unreadable /proc: stay out of the way rather than guess. */
        cached = 0;
        return cached;
    }
    exe[len] = '\0';

    name = strrchr(exe, '/');
    name = name ? name + 1 : exe;
    cached = strcmp(name, "steam") == 0 || strcmp(name, "steamwebhelper") == 0;
    return cached;
}

static const char *target_path(void)
{
    static char buf[4096];
    const char *explicit_path = getenv("STEAM_COMMAND_RUNNER_STREAM_TARGET");
    const char *runtime_dir;
    const char *home;

    /*
     * An explicit path wins, but only if it names a file that is actually
     * there. Returning it unconditionally made a mis-set variable
     * indistinguishable from "nothing is streaming": buildFHSEnv writes
     * extraEnv values verbatim, so an unexpanded "$HOME/..." arrived here as a
     * literal path, every lookup failed, and the filter silently did nothing
     * while appearing configured.
     */
    if (explicit_path && *explicit_path) {
        struct stat st;

        if (stat(explicit_path, &st) == 0)
            return explicit_path;
    }

    /*
     * Home rather than the runtime directory, because Steam's own helpers do
     * not share ours. steamwebhelper runs inside a pressure-vessel container
     * that mounts a filtered /run/user/1000 -- the directory is there, but
     * nothing this service writes into it is -- so a target published under
     * XDG_RUNTIME_DIR is invisible to precisely the process whose view of the
     * desktop needs correcting. $HOME is passed through intact.
     */
    home = getenv("HOME");
    if (home && *home &&
        snprintf(buf, sizeof(buf), "%s/.local/state/stream-mode/target.json", home)
            < (int)sizeof(buf)) {
        struct stat st;

        if (stat(buf, &st) == 0)
            return buf;
    }

    runtime_dir = getenv("XDG_RUNTIME_DIR");
    if (!runtime_dir || !*runtime_dir)
        return NULL;

    if (snprintf(buf, sizeof(buf), "%s/stream-mode/target.json", runtime_dir) >= (int)sizeof(buf))
        return NULL;
    return buf;
}

/*
 * Read the streamed output's size, or report that nothing is streaming.
 *
 * Deliberately a hand-rolled scan rather than a JSON parser: this runs inside
 * every X client Steam starts, so it must not drag a library in, and the file
 * is written by one known producer. Anything unparseable is treated as "not
 * streaming", because leaving the monitor list alone is always the safe
 * outcome -- the worst case is the letterboxing this exists to remove, rather
 * than a Steam that cannot see any monitor at all.
 */
static int read_target(struct target *out)
{
    const char *path;
    char buf[1024];
    const char *w, *h, *n;
    size_t got;
    FILE *f;

    /*
     * The single choke point every hook already consults, so gating here
     * makes the whole shim inert outside the Steam client rather than
     * needing a check bolted onto each wrapper.
     */
    if (!process_is_steam_client())
        return 0;

    path = target_path();
    if (!path)
        return 0;

    f = fopen(path, "re");
    if (!f)
        return 0;
    got = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[got] = '\0';

    w = strstr(buf, "\"width\"");
    h = strstr(buf, "\"height\"");
    if (!w || !h)
        return 0;
    w = strchr(w, ':');
    h = strchr(h, ':');
    if (!w || !h)
        return 0;

    out->width = atoi(w + 1);
    out->height = atoi(h + 1);

    /* The output's name, which is how RandR identifies it. */
    out->name[0] = '\0';
    n = strstr(buf, "\"output\"");
    if (n && (n = strchr(n, ':')) && (n = strchr(n, '"'))) {
        const char *end = strchr(++n, '"');
        if (end && (size_t)(end - n) < sizeof(out->name)) {
            memcpy(out->name, n, (size_t)(end - n));
            out->name[end - n] = '\0';
        }
    }

    return out->width > 0 && out->height > 0 && out->name[0] != '\0';
}

/*
 * Record which display APIs the host process actually calls.
 *
 * Worth having permanently: Steam's display code lives in stripped shared
 * libraries, and two different plausible interception points were implemented
 * and shipped before it became clear which one it really uses. A log that says
 * what was called, rather than what ought to have been called, is the only way
 * to tell an interception that is wired up wrong from one that is wired up
 * right and simply not consulted.
 *
 * Off unless STEAM_DISPLAY_FILTER_LOG names a file. Appended to, and opened per
 * call, so several processes can share it without stepping on each other.
 */
static void flog(const char *fmt, ...)
{
    /*
     * The log file is held open. It used to be opened and closed per line,
     * which is synchronous disk I/O on whatever thread happens to be calling
     * -- and one of those is Steam's main loop. At the rate the SDL hooks
     * fire (thousands of lines a minute) that was enough to trip Steam's own
     * "BMainLoop appears to have stalled > 15 seconds" assertion and fail the
     * stream launch outright. Diagnostics must not cost more than the thing
     * being diagnosed.
     */
    static FILE *out;
    static int tried;
    /*
     * Consecutive identical messages are counted rather than written. The
     * polling hooks repeat the same line tens of times a second and it buries
     * the handful of lines that carry information.
     */
    static char last[512];
    static unsigned long repeats;

    char msg[512];
    struct timespec ts;
    struct tm tm;
    char stamp[32];
    va_list ap;

    if (!out) {
        const char *path;

        if (tried)
            return;
        tried = 1;
        /*
         * Nothing outside the Steam client is filtered, so nothing outside it
         * has anything to report. Without this every game, gamescope and
         * container process opens and writes the shared log too.
         */
        if (!process_is_steam_client())
            return;
        path = getenv("STEAM_DISPLAY_FILTER_LOG");
        if (!path || !*path)
            return;
        out = fopen(path, "ae");
        if (!out)
            return;
        /* Line buffered: a crash must not lose the lines that explain it. */
        setvbuf(out, NULL, _IOLBF, 0);
    }

    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);

    if (strcmp(msg, last) == 0) {
        repeats++;
        return;
    }

    /*
     * Wall-clock to the millisecond, because the whole point of this log is
     * lining it up against Steam's own streaming_log.txt, which timestamps the
     * same way. Without that, "the filter ran" and "Steam decided" cannot be
     * put in order, and ordering is what several of these bugs turned on.
     */
    if (clock_gettime(CLOCK_REALTIME, &ts) == 0 && localtime_r(&ts.tv_sec, &tm))
        strftime(stamp, sizeof(stamp), "%H:%M:%S", &tm);
    else
        snprintf(stamp, sizeof(stamp), "??:??:??");

    if (repeats)
        fprintf(out, "%s.%03ld pid %-7d   (previous line x%lu)\n",
                stamp, ts.tv_nsec / 1000000, (int)getpid(), repeats + 1);
    repeats = 0;
    snprintf(last, sizeof(last), "%s", msg);

    fprintf(out, "%s.%03ld pid %-7d %s\n",
            stamp, ts.tv_nsec / 1000000, (int)getpid(), msg);
}

/* Whether a target is published, and what it says, for logging context. */
static const char *armed_desc(void)
{
    static char desc[192];
    struct target want;

    if (!read_target(&want))
        return "INERT(no target)";
    snprintf(desc, sizeof(desc), "ARMED(%s %dx%d)", want.name, want.width, want.height);
    return desc;
}

static void note(const char *what, int kept, int of)
{
    flog("%-28s saw %6d kept %6d  %s", what, of, kept, armed_desc());
}

/*
 * Hand our wrappers to callers that resolve X through dlopen/dlsym.
 *
 * This is what defeated every earlier interception. steamui.so -- which is
 * what emits "Desktop state changed", from gamestreamsystemlinux.cpp -- does
 * not link libXrandr. It dlopens "libXrandr.so.2" and "libX11.so.6" (both
 * appear as plain strings in the binary alongside dlopen/dlsym imports) and
 * resolves each entry point by name against that handle. A handle-scoped
 * dlsym searches only that object, so LD_PRELOAD never gets a look in: Steam
 * received the genuine XRRGetCrtcInfo while our copy sat unused in the same
 * process.
 *
 * The filter log made this look like the opposite conclusion. The hooks did
 * fire, repeatedly, from the very pid that has steamui.so mapped -- but from
 * SDL and other PLT-bound callers, never from the gamestream code. "Called
 * but not consulted" was a misreading; it was a different caller entirely.
 *
 * Only the names we already implement are redirected. Everything else is
 * delegated untouched, so a caller asking libXrandr for the rest of its API
 * gets the real thing and RandR keeps working.
 */
static void *(*real_dlsym)(void *, const char *);

/*
 * dlsym cannot be used to find dlsym, so the real one comes from dlvsym,
 * which we do not interpose. The version differs by ABI -- i386 kept
 * GLIBC_2.0, x86-64 has GLIBC_2.2.5, and both moved to GLIBC_2.34 when
 * libdl was folded into libc -- so probe rather than assume.
 */
__attribute__((constructor)) static void resolve_real_dlsym(void)
{
    static const char *const versions[] = {"GLIBC_2.34", "GLIBC_2.2.5", "GLIBC_2.0"};
    size_t i;

    for (i = 0; i < sizeof(versions) / sizeof(versions[0]); i++) {
        real_dlsym = dlvsym(RTLD_NEXT, "dlsym", (char *)versions[i]);
        if (real_dlsym)
            return;
    }
    flog("could not resolve the real dlsym; dlopen-based lookups are untouched");
}

/*
 * Resolve a symbol past our own definitions.
 *
 * Every hook below needs the genuine X function, and the obvious
 * dlsym(RTLD_NEXT, ...) no longer reaches it: that call now enters the dlsym
 * we interpose, matches the redirect table, and hands the hook back its own
 * address. Each wrapper became its own "real" and recursed until the stack
 * ran out -- a segfault whose faulting address equalled the stack pointer.
 * Going straight to the real dlsym keeps interposition one-way.
 */
static void *next_sym(const char *name)
{
    /*
     * RTLD_NEXT only searches the global scope, and the X libraries do not
     * have to be in it: a caller that dlopens libX11 without RTLD_GLOBAL --
     * which is exactly what Steam does -- leaves them invisible to it. Then
     * every hook would find no real function and cheerfully report a zero
     * width. Falling back to the already-loaded object by name keeps the
     * pass-through honest however X got into the process. RTLD_NOLOAD never
     * loads anything; it only returns a handle if the library is already
     * there.
     */
    static const char *const providers[] = {
        "libX11.so.6", "libXrandr.so.2", "libXinerama.so.1",
    };
    void *fn;
    size_t i;

    if (!real_dlsym)
        resolve_real_dlsym();
    if (!real_dlsym)
        return NULL;

    fn = real_dlsym(RTLD_NEXT, name);
    if (fn)
        return fn;

    for (i = 0; i < sizeof(providers) / sizeof(providers[0]); i++) {
        void *lib = dlopen(providers[i], RTLD_NOLOAD | RTLD_NOW);

        if (!lib)
            continue;
        fn = real_dlsym(lib, name);
        dlclose(lib);
        if (fn)
            return fn;
    }

    flog("could not resolve the real %s; leaving that reading alone", name);
    return NULL;
}

/*
 * Both list types are one allocation: libXinerama and libXrandr hand back a
 * single block that the caller frees with one call, and the per-monitor output
 * arrays live inside it. So moving the wanted entry to the front and shortening
 * the count is safe -- the whole block is still freed exactly once, and nothing
 * is left dangling.
 */
XineramaScreenInfo *XineramaQueryScreens(Display *dpy, int *number)
{
    static XineramaScreenInfo *(*real)(Display *, int *);
    XineramaScreenInfo *screens;
    struct target want;
    int i;

    if (!real)
        real = next_sym("XineramaQueryScreens");
    if (!real)
        return NULL;

    screens = real(dpy, number);
    note("XineramaQueryScreens", -1, number ? *number : -1);
    if (!screens || !number || *number <= 1)
        return screens;
    if (!read_target(&want))
        return screens;

    for (i = 0; i < *number; i++) {
        if (screens[i].width != want.width || screens[i].height != want.height)
            continue;

        if (i != 0) {
            XineramaScreenInfo tmp = screens[0];
            screens[0] = screens[i];
            screens[i] = tmp;
        }
        note("XineramaQueryScreens", 1, *number);
        *number = 1;
        return screens;
    }

    /* The streamed output is not in the list yet; leave it untouched. */
    flog("XineramaQueryScreens: no %dx%d among %d screens, leaving alone",
         want.width, want.height, *number);
    return screens;
}

XRRMonitorInfo *XRRGetMonitors(Display *dpy, Window window, Bool get_active, int *nmonitors)
{
    static XRRMonitorInfo *(*real)(Display *, Window, Bool, int *);
    XRRMonitorInfo *monitors;
    struct target want;
    int i;

    if (!real)
        real = next_sym("XRRGetMonitors");
    if (!real)
        return NULL;

    monitors = real(dpy, window, get_active, nmonitors);
    note("XRRGetMonitors", -1, nmonitors ? *nmonitors : -1);
    if (!monitors || !nmonitors || *nmonitors <= 1)
        return monitors;
    if (!read_target(&want))
        return monitors;

    for (i = 0; i < *nmonitors; i++) {
        if (monitors[i].width != want.width || monitors[i].height != want.height)
            continue;

        if (i != 0) {
            XRRMonitorInfo tmp = monitors[0];
            monitors[0] = monitors[i];
            monitors[i] = tmp;
        }
        /* Sole monitor, so it is the primary one by definition. */
        monitors[0].primary = 1;
        note("XRRGetMonitors", 1, *nmonitors);
        *nmonitors = 1;
        return monitors;
    }

    return monitors;
}

/*
 * Report every output but the streamed one as disconnected.
 *
 * This is the interception that actually reaches Steam. Its display code uses
 * the low-level RandR path -- steamclient.so and steamui.so import
 * XRRGetScreenResources, XRRGetOutputInfo, XRRGetCrtcInfo and
 * XRRGetOutputPrimary, and neither XRRGetMonitors nor Xinerama -- so filtering
 * the monitor lists above left its view of the desktop untouched.
 *
 * Marking an output disconnected rather than removing it from the resources
 * array keeps every RROutput id that Steam already holds valid, so nothing it
 * looks up afterwards dangles; it simply sees a display that is not plugged in.
 */
XRROutputInfo *XRRGetOutputInfo(Display *dpy, XRRScreenResources *resources, RROutput output)
{
    static XRROutputInfo *(*real)(Display *, XRRScreenResources *, RROutput);
    XRROutputInfo *info;
    struct target want;

    if (!real)
        real = next_sym("XRRGetOutputInfo");
    if (!real)
        return NULL;

    info = real(dpy, resources, output);
    note(info && info->name ? info->name : "XRRGetOutputInfo", -1, 1);
    if (!info || !read_target(&want))
        return info;
    if (info->name && strcmp(info->name, want.name) == 0) {
        /*
         * Give the virtual output a plausible physical size. niri reports
         * 0mm x 0mm for it, which is honest -- there is no panel -- but a
         * consumer that treats zero dimensions as a bogus display would drop
         * it, and Steam's desktop reading is exactly DP-2 alone rather than
         * either the union or the virtual output. 1280x800 at roughly 96dpi.
         */
        if (info->mm_width == 0 || info->mm_height == 0) {
            info->mm_width = (unsigned long)(want.width * 254 / 960);
            info->mm_height = (unsigned long)(want.height * 254 / 960);
            flog("  gave %s a physical size of %lumm x %lumm",
                 want.name, info->mm_width, info->mm_height);
        }
        return info;
    }

    if (info->connection == RR_Connected) {
        note("XRRGetOutputInfo", 0, 1);
        info->connection = RR_Disconnected;
        /* A disconnected output drives no CRTC and advertises no modes. */
        info->crtc = None;
        info->nmode = 0;
        info->npreferred = 0;
    }
    return info;
}

/*
 * Blank the CRTCs that are not driving the streamed output.
 *
 * A CRTC reports its geometry regardless of what its output's connection field
 * says, so marking outputs disconnected is not enough on its own: measured
 * here, Steam saw a single Xinerama screen and DP-2 disconnected, and still
 * sized its capture to 5120x1440 fitted to the client's width. Geometry read
 * straight off the CRTCs is the only remaining explanation, and the only
 * RandR surface left untouched.
 *
 * Matched on size rather than on the CRTC's output list, because resolving
 * that list back to a name would mean re-entering XRRGetOutputInfo. A blanked
 * CRTC is described exactly as an unused one: no mode, no size, no outputs.
 */
XRRCrtcInfo *XRRGetCrtcInfo(Display *dpy, XRRScreenResources *resources, RRCrtc crtc)
{
    static XRRCrtcInfo *(*real)(Display *, XRRScreenResources *, RRCrtc);
    XRRCrtcInfo *info;
    struct target want;

    if (!real)
        real = next_sym("XRRGetCrtcInfo");
    if (!real)
        return NULL;

    info = real(dpy, resources, crtc);
    if (!info)
        return NULL;
    note("XRRGetCrtcInfo", (int)info->width, (int)info->height);
    if (!read_target(&want))
        return info;
    if ((int)info->width == want.width && (int)info->height == want.height)
        return info;
    if (info->width == 0 && info->height == 0)
        return info;

    info->mode = None;
    info->width = 0;
    info->height = 0;
    info->x = 0;
    info->y = 0;
    info->noutput = 0;
    info->npossible = 0;
    return info;
}

/*
 * Report the X screen as the size of the streamed output.
 *
 * This is what Steam's "Desktop state changed: desktop: { size: 6400,1440 }"
 * line is reading: steamclient.so imports XDisplayWidth and XDisplayHeight as
 * functions, and they return the whole screen -- the bounding box of every
 * output, which on this host is the ultrawide plus the streaming output side
 * by side.
 *
 * Easy to overlook because Xlib also defines both as macros, so a caller that
 * includes Xlib.h normally never emits a call at all. steamclient.so does, and
 * a symbol scan of every bundled library is what found it, after three
 * interceptions aimed at the monitor-enumeration APIs each turned out to be
 * called but not consulted for this number.
 */
int XDisplayWidth(Display *dpy, int screen)
{
    static int (*real)(Display *, int);
    struct target want;

    if (!real)
        real = next_sym("XDisplayWidth");
    if (!real)
        return 0;
    if (!read_target(&want))
        return real(dpy, screen);

    note("XDisplayWidth", want.width, real(dpy, screen));
    return want.width;
}

int XDisplayHeight(Display *dpy, int screen)
{
    static int (*real)(Display *, int);
    struct target want;

    if (!real)
        real = next_sym("XDisplayHeight");
    if (!real)
        return 0;
    if (!read_target(&want))
        return real(dpy, screen);

    note("XDisplayHeight", want.height, real(dpy, screen));
    return want.height;
}

/*
 * The root window's geometry is the same number by another route, so it has to
 * agree -- a caller that cross-checks one against the other would otherwise see
 * a desktop that contradicts itself. Only the root window is rewritten;
 * ordinary windows are none of this filter's business.
 */
Status XGetWindowAttributes(Display *dpy, Window w, XWindowAttributes *attrs)
{
    static Status (*real)(Display *, Window, XWindowAttributes *);
    struct target want;
    Status rc;

    if (!real)
        real = next_sym("XGetWindowAttributes");
    if (!real)
        return 0;

    rc = real(dpy, w, attrs);
    if (!rc || !attrs || !read_target(&want))
        return rc;
    if (w != DefaultRootWindow(dpy))
        return rc;

    note("XGetWindowAttributes(root)", want.width, attrs->width);
    attrs->width = want.width;
    attrs->height = want.height;
    return rc;
}

/*
 * SDL3 is where Steam's desktop geometry actually comes from.
 *
 * "Desktop state changed: desktop: { size: 6400,1440 }" is emitted by
 * steamui.so, and steamui.so is the one bundled library importing
 * SDL_GetDisplays, SDL_GetDisplayBounds and SDL_GetPrimaryDisplay. SDL keeps
 * its own display list through its own backend, so none of the Xlib
 * interceptions above can reach it -- they are called, by other Steam code,
 * for other purposes, which is exactly what made them look like plausible
 * culprits for so long.
 *
 * The types are declared here rather than pulled from SDL's headers to keep
 * this library free of an SDL dependency: it is preloaded into every process
 * Steam starts, and only these three entry points matter.
 */

/*
 * Find a symbol that may live in a library loaded after this one.
 *
 * RTLD_NEXT only searches objects that follow this one in the initial load
 * order, and Steam's SDL3 is dlopened later, so the lookup fails and there is
 * no real implementation to forward to. Returning NULL in that case is not a
 * harmless no-op: it tells Steam there are no displays at all, which it duly
 * reported as a desktop of size 0x0. Falling back to the already-loaded SDL by
 * name is what makes interposing on a dlopened library work.
 */
static void *late_sym(const char *name)
{
    /*
     * next_sym rather than dlsym: the pseudo-handle bypass in our dlsym makes
     * the bare call safe today, but the rule that no hook resolves through the
     * interposed dlsym is what keeps that true. Not worth leaving one
     * exception for a future reader to trip over.
     */
    void *fn = next_sym(name);
    void *handle;

    if (fn)
        return fn;

    /* NOLOAD: only bind to it if the process already has it open. */
    handle = dlopen("libSDL3.so.0", RTLD_NOLOAD | RTLD_LAZY);
    if (!handle)
        return NULL;
    fn = real_dlsym ? real_dlsym(handle, name) : NULL;
    dlclose(handle);
    return fn;
}

typedef unsigned int SDL_DisplayID;

struct sdl_rect {
    int x, y, w, h;
};

/*
 * Present only the streamed display.
 *
 * The array is SDL's own allocation, freed by the caller with SDL_free, so the
 * wanted entry is moved to the front and the count shortened rather than a new
 * array being handed back -- the block stays exactly as SDL made it.
 */
SDL_DisplayID *SDL_GetDisplays(int *count)
{
    static SDL_DisplayID *(*real)(int *);
    static _Bool (*real_bounds)(SDL_DisplayID, struct sdl_rect *);
    SDL_DisplayID *displays;
    struct target want;
    int i;

    if (!real)
        real = late_sym("SDL_GetDisplays");
    if (!real_bounds)
        real_bounds = late_sym("SDL_GetDisplayBounds");
    if (!real)
        return NULL;

    displays = real(count);
    flog("SDL_GetDisplays -> %d display(s)  %s",
         count ? *count : -1, armed_desc());
    if (displays && count && real_bounds) {
        for (i = 0; i < *count; i++) {
            struct sdl_rect r = { 0, 0, 0, 0 };

            if (real_bounds(displays[i], &r))
                flog("  display id=%u  %dx%d at %d,%d",
                     displays[i], r.w, r.h, r.x, r.y);
            else
                flog("  display id=%u  <bounds unavailable>", displays[i]);
        }
    }
    if (!displays || !count || *count <= 1 || !real_bounds)
        return displays;
    if (!read_target(&want)) {
        flog("SDL_GetDisplays: leaving %d alone (no target)", *count);
        return displays;
    }

    for (i = 0; i < *count; i++) {
        struct sdl_rect r = { 0, 0, 0, 0 };

        if (!real_bounds(displays[i], &r))
            continue;
        if (r.w != want.width || r.h != want.height)
            continue;

        if (i != 0) {
            SDL_DisplayID tmp = displays[0];
            displays[0] = displays[i];
            displays[i] = tmp;
        }
        flog("SDL_GetDisplays: kept id=%u (%dx%d), hid %d other(s)",
             displays[0], want.width, want.height, *count - 1);
        *count = 1;
        return displays;
    }

    flog("SDL_GetDisplays: NO MATCH for %dx%d among %d — leaving all visible",
         want.width, want.height, *count);
    return displays;
}

/*
 * Anchor the streamed display at the origin.
 *
 * Once it is the only display, a non-zero origin describes a desktop with a
 * gap in it, which is what the bounding-box arithmetic downstream would then
 * letterbox around.
 */
_Bool SDL_GetDisplayBounds(SDL_DisplayID display, struct sdl_rect *rect)
{
    static _Bool (*real)(SDL_DisplayID, struct sdl_rect *);
    struct target want;
    _Bool rc;

    if (!real)
        real = late_sym("SDL_GetDisplayBounds");
    if (!real)
        return 0;

    rc = real(display, rect);
    if (!rc || !rect || !read_target(&want))
        return rc;
    if (rect->w != want.width || rect->h != want.height)
        return rc;

    note("SDL_GetDisplayBounds", want.width, rect->w);
    rect->x = 0;
    rect->y = 0;
    return rc;
}

SDL_DisplayID SDL_GetPrimaryDisplay(void)
{
    static SDL_DisplayID (*real)(void);
    static SDL_DisplayID *(*real_displays)(int *);
    static _Bool (*real_bounds)(SDL_DisplayID, struct sdl_rect *);
    struct target want;
    SDL_DisplayID *displays;
    SDL_DisplayID chosen;
    int count = 0, i;

    if (!real)
        real = late_sym("SDL_GetPrimaryDisplay");
    if (!real_displays)
        real_displays = late_sym("SDL_GetDisplays");
    if (!real_bounds)
        real_bounds = late_sym("SDL_GetDisplayBounds");
    if (!real)
        return 0;

    chosen = real();
    if (!read_target(&want) || !real_displays || !real_bounds)
        return chosen;

    displays = real_displays(&count);
    if (!displays)
        return chosen;

    for (i = 0; i < count; i++) {
        struct sdl_rect r = { 0, 0, 0, 0 };

        if (real_bounds(displays[i], &r) && r.w == want.width && r.h == want.height) {
            note("SDL_GetPrimaryDisplay", (int)displays[i], (int)chosen);
            chosen = displays[i];
            break;
        }
    }
    return chosen;
}

/* Instrumentation only: which output Steam considers primary, and when. */
RROutput XRRGetOutputPrimary(Display *dpy, Window window)
{
    static RROutput (*real)(Display *, Window);
    RROutput out;

    if (!real)
        real = next_sym("XRRGetOutputPrimary");
    if (!real)
        return 0;
    out = real(dpy, window);
    flog("XRRGetOutputPrimary -> %lu  %s", (unsigned long)out, armed_desc());
    return out;
}

/* Instrumentation only: how many outputs and crtcs Steam is handed. */
XRRScreenResources *XRRGetScreenResources(Display *dpy, Window window)
{
    static XRRScreenResources *(*real)(Display *, Window);
    XRRScreenResources *res;

    if (!real)
        real = next_sym("XRRGetScreenResources");
    if (!real)
        return NULL;
    res = real(dpy, window);
    if (res)
        flog("XRRGetScreenResources -> %d output(s) %d crtc(s)  %s",
             res->noutput, res->ncrtc, armed_desc());
    return res;
}

/*
 * Instrumentation only: the cached twin of XRRGetScreenResources.
 *
 * Same signature, same signal to Steam's low-level RandR path -- whichever
 * of the two it actually resolves through dlsym is the one whose log lines
 * show up, and that is unproven, which is the whole reason both are hooked.
 */
XRRScreenResources *XRRGetScreenResourcesCurrent(Display *dpy, Window window)
{
    static XRRScreenResources *(*real)(Display *, Window);
    XRRScreenResources *res;

    if (!real)
        real = next_sym("XRRGetScreenResourcesCurrent");
    if (!real)
        return NULL;
    res = real(dpy, window);
    if (res)
        flog("XRRGetScreenResourcesCurrent -> %d output(s) %d crtc(s)  %s",
             res->noutput, res->ncrtc, armed_desc());
    return res;
}

/*
 * The legacy RandR 1.1 trio.
 *
 * steamui.so's dlsym request log names all three, but only one of them
 * carries a number worth faking. XRRGetScreenInfo just hands back an opaque
 * handle -- there is nothing in it to filter, only logging to confirm
 * whether Steam ever calls it.
 */
XRRScreenConfiguration *XRRGetScreenInfo(Display *dpy, Window window)
{
    static XRRScreenConfiguration *(*real)(Display *, Window);
    XRRScreenConfiguration *config;

    if (!real)
        real = next_sym("XRRGetScreenInfo");
    if (!real)
        return NULL;
    config = real(dpy, window);
    flog("XRRGetScreenInfo -> %p  %s", (void *)config, armed_desc());
    return config;
}

/*
 * Instrumentation only: NOT safe to filter, deliberately left unmodified.
 *
 * Unlike the Xinerama/XRRGetMonitors arrays above, this is not a fresh
 * allocation the caller owns -- it is storage cached inside the
 * XRRScreenConfiguration that XRRGetScreenInfo built, and
 * XRRConfigCurrentConfiguration (and XRRSetScreenConfig, which this filter
 * does not touch at all) read that same storage by index afterwards.
 * Reordering or truncating it the way the monitor lists are reordered would
 * corrupt state Xlib itself still relies on, for callers this filter never
 * sees. XRRConfigCurrentConfiguration below fakes the *index* instead --
 * a plain int copied out to the caller, not a pointer into Xlib's cache --
 * which is safe to substitute without touching this array.
 */
XRRScreenSize *XRRConfigSizes(XRRScreenConfiguration *config, int *nsizes)
{
    static XRRScreenSize *(*real)(XRRScreenConfiguration *, int *);
    XRRScreenSize *sizes;

    if (!real)
        real = next_sym("XRRConfigSizes");
    if (!real)
        return NULL;
    sizes = real(config, nsizes);
    flog("XRRConfigSizes -> %d size(s)  %s", nsizes ? *nsizes : -1, armed_desc());
    return sizes;
}

/*
 * Fake the SizeID rather than the array XRRConfigSizes returns.
 *
 * Finding the streamed output's entry means re-reading the real
 * XRRConfigSizes ourselves (read-only, via next_sym directly rather than
 * our own hook, so the lookup this function does on its own behalf does not
 * add a second log line). If the streamed size is not among the legacy
 * size list at all, the real index is returned untouched.
 */
SizeID XRRConfigCurrentConfiguration(XRRScreenConfiguration *config, Rotation *rotation)
{
    static SizeID (*real)(XRRScreenConfiguration *, Rotation *);
    static XRRScreenSize *(*real_sizes)(XRRScreenConfiguration *, int *);
    struct target want;
    XRRScreenSize *sizes;
    SizeID id, faked;
    int nsizes, i;

    if (!real)
        real = next_sym("XRRConfigCurrentConfiguration");
    if (!real_sizes)
        real_sizes = next_sym("XRRConfigSizes");
    if (!real)
        return 0;

    id = real(config, rotation);
    if (!read_target(&want) || !real_sizes) {
        note("XRRConfigCurrentConfiguration", (int)id, (int)id);
        return id;
    }

    faked = id;
    sizes = real_sizes(config, &nsizes);
    if (sizes) {
        for (i = 0; i < nsizes; i++) {
            if (sizes[i].width == want.width && sizes[i].height == want.height) {
                faked = (SizeID)i;
                break;
            }
        }
    }

    note("XRRConfigCurrentConfiguration", (int)faked, (int)id);
    return faked;
}

void *dlsym(void *handle, const char *symbol)
{
    static const struct {
        const char *name;
        void *fn;
    } redirected[] = {
        {"XineramaQueryScreens", (void *)XineramaQueryScreens},
        {"XRRGetMonitors", (void *)XRRGetMonitors},
        {"XRRGetOutputInfo", (void *)XRRGetOutputInfo},
        {"XRRGetCrtcInfo", (void *)XRRGetCrtcInfo},
        {"XRRGetScreenResources", (void *)XRRGetScreenResources},
        {"XRRGetScreenResourcesCurrent", (void *)XRRGetScreenResourcesCurrent},
        {"XRRGetScreenInfo", (void *)XRRGetScreenInfo},
        {"XRRConfigSizes", (void *)XRRConfigSizes},
        {"XRRConfigCurrentConfiguration", (void *)XRRConfigCurrentConfiguration},
        {"XRRGetOutputPrimary", (void *)XRRGetOutputPrimary},
        {"XDisplayWidth", (void *)XDisplayWidth},
        {"XDisplayHeight", (void *)XDisplayHeight},
        {"XGetWindowAttributes", (void *)XGetWindowAttributes},
    };
    size_t i;

    if (!real_dlsym)
        resolve_real_dlsym();
    if (!real_dlsym || !symbol)
        return NULL;

    /*
     * The pseudo-handles are never redirected. Interposing them is what
     * recursed: a hook asking RTLD_NEXT for its own real function would be
     * handed itself. Nothing is lost by declining -- RTLD_DEFAULT searches
     * the global scope, where a preloaded wrapper already wins on its own.
     */
    if (handle == RTLD_NEXT || handle == RTLD_DEFAULT)
        return real_dlsym(handle, symbol);

    for (i = 0; i < sizeof(redirected) / sizeof(redirected[0]); i++) {
        if (strcmp(symbol, redirected[i].name) == 0) {
            flog("dlsym(%s) -> our wrapper  %s", symbol, armed_desc());
            return redirected[i].fn;
        }
    }

    /*
     * Anything else geometry-shaped is logged but not touched: if Steam reads
     * a number we do not yet cover, the name shows up here rather than being
     * silently missed the way the dlopen path itself was.
     */
    if (strncmp(symbol, "XRR", 3) == 0 || strncmp(symbol, "Xinerama", 8) == 0)
        flog("dlsym(%s) -> real (not filtered)", symbol);

    return real_dlsym(handle, symbol);
}

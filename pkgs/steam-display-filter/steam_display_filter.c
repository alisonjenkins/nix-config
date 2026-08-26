/*
 * Make Steam Remote Play stream at the client's resolution, not the desktop's.
 *
 * Steam sizes its capture from its own idea of the desktop rather than from
 * the PipeWire stream the portal hands it. Stream a 1280x800 handheld from a
 * 5120x1440 ultrawide and the capture is set to the ultrawide's shape fitted
 * to the client's width -- a 1280x360 letterbox with the picture in a band
 * across the middle. Selecting the right portal source does not help; the
 * capture side was always correct.
 *
 * That idea of the desktop comes from SDL, and disassembling steamui.so is
 * what settles it. The routine that logs "Desktop state changed" does:
 *
 *     SDL_GetDisplays(NULL)                 -- note the NULL
 *     for each id until the array's NULL:
 *         SDL_GetDisplayBounds(id, &rect)
 *         SDL_GetRectUnion(&rect, &desktop, &desktop)
 *         if (first) primary = rect
 *     SDL_free(list)
 *
 * There is no Xlib in it. Earlier versions of this file hooked Xinerama and
 * most of RandR -- monitor lists, CRTCs, outputs, screen resources, the legacy
 * RandR 1.1 calls, even dlsym itself to reach the ones Steam resolves through
 * dlopen. Every one of them was verified being called and none of them changed
 * the number. They are gone. If a future Steam moves this to X, the way back is
 * to find the format string's call site with radare2 (`aa; aae; axt <addr>` --
 * plain analysis will not resolve it, the reference is PC-relative) and read
 * what the routine actually calls, rather than interposing likely-looking APIs.
 *
 * So two hooks, and only while a stream is running. Steam is told its desktop
 * is exactly the streamed output, at the origin. Everything else is left alone.
 *
 * Nothing here is compositor-specific: it needs the streamed size and nothing
 * more. See the env vars below for using it without the niri-specific watcher
 * this repository ships.
 */

#define _GNU_SOURCE

#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/*
 * SDL's types, rather than a build dependency on SDL headers. Both are part of
 * SDL3's public ABI: SDL_DisplayID is a Uint32 and SDL_Rect is four ints.
 */
typedef unsigned int SDL_DisplayID;

struct sdl_rect {
    int x, y, w, h;
};

/* The geometry being streamed. */
struct target {
    int width;
    int height;
};

/*
 * Only the Steam client itself gets a filtered view.
 *
 * LD_PRELOAD is inherited by every descendant, and Steam starts a great many:
 * gamescope, the pressure-vessel container, wine, and the game itself. None of
 * them need it, and lying to them is not merely untidy -- gamescope is launched
 * with its own idea of the output and its own -W/-H, so handing it a doctored
 * display list made it negotiate against a view that did not match the
 * compositor's. A stream started that way wedged during game launch with
 * Steam's main loop stalled for over fifteen seconds.
 *
 * Matched on the executable name because the wrapper layers between the client
 * and the game each rewrite the environment, so an env var cannot survive them.
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

/*
 * Where the streamed size comes from.
 *
 * STEAM_STREAM_SIZE ("1280x800") is the whole interface for anyone driving
 * this by hand or from another compositor's scripts: set it before starting
 * Steam and unset it afterwards.
 *
 * STEAM_STREAM_TARGET names a file holding the same thing, for a watcher that
 * learns the client's size at connect time and has to publish it to an already
 * running Steam. The file's presence is what arms the filter, so withdrawing it
 * is how a session ends.
 *
 * The file must be somewhere Steam can actually read: steamwebhelper runs in a
 * pressure-vessel container that mounts a filtered /run/user/<uid>, so a path
 * under XDG_RUNTIME_DIR is invisible to it. $HOME is passed through intact.
 */
static int parse_size(const char *s, struct target *out)
{
    int w = 0, h = 0;

    if (!s || !*s)
        return 0;
    if (sscanf(s, "%dx%d", &w, &h) != 2)
        return 0;
    if (w <= 0 || h <= 0)
        return 0;
    out->width = w;
    out->height = h;
    return 1;
}

static int read_target(struct target *out)
{
    const char *path;
    char buf[512];
    size_t got;
    FILE *f;

    /*
     * The single choke point both hooks consult, so gating here makes the
     * whole filter inert outside the Steam client.
     */
    if (!process_is_steam_client())
        return 0;

    if (parse_size(getenv("STEAM_STREAM_SIZE"), out))
        return 1;

    path = getenv("STEAM_STREAM_TARGET");
    if (!path || !*path)
        return 0;

    f = fopen(path, "re");
    if (!f)
        return 0;
    got = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[got] = '\0';

    return parse_size(buf, out);
}

/*
 * Diagnostics must not cost more than the fault they are for.
 *
 * The log file is held open. Opening and closing it per line -- at the rate
 * these hooks fire -- was enough synchronous I/O on Steam's main loop to trip
 * its own "BMainLoop appears to have stalled > 15 seconds" assertion and fail
 * stream launches outright. Consecutive identical lines are counted rather
 * than written, because the polling caller repeats one line tens of times a
 * second and buries everything that carries information.
 */
static void flog(const char *fmt, ...)
{
    static FILE *out;
    static int tried;
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
     * Wall-clock to the millisecond, to line this up against Steam's own
     * streaming_log.txt, which timestamps the same way. Several of these bugs
     * turned on which of the two happened first.
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

/*
 * Resolve the real SDL entry point.
 *
 * RTLD_NEXT alone is not enough: it searches the global scope, and Steam
 * dlopens the module that pulls SDL in, so SDL is not necessarily in it.
 * Falling back to the loaded object by name covers that. RTLD_NOLOAD never
 * loads anything -- it only returns a handle if the library is already there.
 */
static void *sdl_sym(const char *name)
{
    void *fn = dlsym(RTLD_NEXT, name);
    void *handle;

    if (fn)
        return fn;

    handle = dlopen("libSDL3.so.0", RTLD_NOLOAD | RTLD_LAZY);
    if (!handle)
        return NULL;
    fn = dlsym(handle, name);
    dlclose(handle);
    return fn;
}

/* The display presented to Steam as the streamed output. */
static SDL_DisplayID presented_display;

/*
 * Present exactly one display: the one being streamed.
 *
 * The count is an out-parameter and the caller that matters does not pass one
 * -- steamui.so calls SDL_GetDisplays(NULL) and walks the NULL-terminated
 * array. An earlier version returned early when no count was supplied and
 * otherwise only shortened the count, so the routine deciding the capture
 * geometry got the full list every time, while a different caller that does
 * pass a count produced log lines showing the filter working perfectly. Union
 * 1280x800 with 5120x1440 and you get exactly the wrong number Steam reported.
 *
 * So the array is terminated as well as the count shortened, and the length is
 * measured by walking to the NULL when no count is given.
 *
 * The entry kept is whichever display matches the streamed size, and failing
 * that simply the first: SDL enumerates its displays when it starts and need
 * not have noticed an output created afterwards. While a stream is running
 * exactly one display is being streamed and Steam must be told about that one,
 * whether or not SDL knows it exists. SDL_GetDisplayBounds below answers for
 * whatever id is kept, so the two cannot disagree.
 */
SDL_DisplayID *SDL_GetDisplays(int *count)
{
    static SDL_DisplayID *(*real)(int *);
    static _Bool (*real_bounds)(SDL_DisplayID, struct sdl_rect *);
    SDL_DisplayID *displays;
    struct target want;
    int i, n = 0;

    if (!real)
        real = sdl_sym("SDL_GetDisplays");
    if (!real_bounds)
        real_bounds = sdl_sym("SDL_GetDisplayBounds");
    if (!real)
        return NULL;

    displays = real(count);
    if (!displays)
        return displays;
    if (!read_target(&want))
        return displays;

    if (count) {
        n = *count;
    } else {
        while (displays[n])
            n++;
    }
    if (n < 1)
        return displays;

    if (real_bounds) {
        for (i = 0; i < n; i++) {
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
            break;
        }
    }

    presented_display = displays[0];
    if (n > 1)
        displays[1] = 0;
    if (count)
        *count = 1;

    flog("presenting display %u as %dx%d, hid %d other(s)",
         displays[0], want.width, want.height, n - 1);
    return displays;
}

/*
 * Answer for the presented display with the streamed geometry, at the origin.
 *
 * The other half of presenting one display: reporting a single display and
 * then handing back the desktop monitor's bounds for it would leave Steam with
 * the number it started with. The origin matters too -- once it is the only
 * display, a non-zero position describes a desktop with a gap in it, and the
 * bounding-box arithmetic downstream letterboxes around the gap.
 *
 * Reported as succeeding even where SDL itself failed: if SDL cannot describe
 * the display Steam was just told about, the geometry being streamed is still
 * the honest answer.
 */
_Bool SDL_GetDisplayBounds(SDL_DisplayID display, struct sdl_rect *rect)
{
    static _Bool (*real)(SDL_DisplayID, struct sdl_rect *);
    struct target want;
    _Bool rc;

    if (!real)
        real = sdl_sym("SDL_GetDisplayBounds");
    if (!real)
        return 0;

    rc = real(display, rect);
    if (!rect || !read_target(&want))
        return rc;
    if (presented_display && display != presented_display)
        return rc;

    rect->x = 0;
    rect->y = 0;
    rect->w = want.width;
    rect->h = want.height;
    return 1;
}

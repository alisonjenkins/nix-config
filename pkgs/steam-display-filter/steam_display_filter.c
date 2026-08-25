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

#include <X11/Xlib.h>
#include <X11/extensions/Xinerama.h>
#include <X11/extensions/Xrandr.h>

/* Geometry of the output being streamed, as published by the watcher. */
struct target {
    int width;
    int height;
};

static const char *target_path(void)
{
    static char buf[4096];
    const char *explicit_path = getenv("STEAM_COMMAND_RUNNER_STREAM_TARGET");
    const char *runtime_dir;

    if (explicit_path && *explicit_path)
        return explicit_path;

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
    const char *path = target_path();
    char buf[1024];
    const char *w, *h;
    size_t got;
    FILE *f;

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
    return out->width > 0 && out->height > 0;
}

static int quiet(void)
{
    const char *v = getenv("STEAM_DISPLAY_FILTER_DEBUG");
    return !(v && *v && strcmp(v, "0") != 0);
}

static void note(const char *what, int kept, int of)
{
    if (quiet())
        return;
    fprintf(stderr, "steam-display-filter: %s reported %d monitor(s), kept %d\n", what, of, kept);
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
        real = dlsym(RTLD_NEXT, "XineramaQueryScreens");
    if (!real)
        return NULL;

    screens = real(dpy, number);
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
    return screens;
}

XRRMonitorInfo *XRRGetMonitors(Display *dpy, Window window, Bool get_active, int *nmonitors)
{
    static XRRMonitorInfo *(*real)(Display *, Window, Bool, int *);
    XRRMonitorInfo *monitors;
    struct target want;
    int i;

    if (!real)
        real = dlsym(RTLD_NEXT, "XRRGetMonitors");
    if (!real)
        return NULL;

    monitors = real(dpy, window, get_active, nmonitors);
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

/*
 * Check the filter against the way Steam actually reaches RandR.
 *
 * steamui.so does not link libXrandr -- it dlopens it and resolves each entry
 * point with dlsym against that handle, which bypasses ordinary LD_PRELOAD
 * interposition. Six changes to the filter looked correct and did nothing
 * because they were only ever exercised through the PLT. This reproduces the
 * dlopen/dlsym path in a few lines so a change can be checked in seconds
 * rather than by launching Steam and reconnecting a Deck.
 *
 * Build and run (needs two outputs present to be meaningful):
 *
 *   gcc -o dlopen_probe dlopen_probe.c -ldl
 *   DISPLAY=:0 LD_PRELOAD=<multiarch>/lib64/libsteam-display-filter.so ./dlopen_probe
 *
 * Expected, with a stream target published for a 1280x800 output:
 *   - run as ./dlopen_probe  -> the real screen width. The filter is gated to
 *     the Steam client, and everything else must see the desktop untouched.
 *   - run as ./steam         -> 1280. Renaming the binary is what flips the
 *     gate, so both halves of it are covered.
 * With no target published, both must report the real width.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>

int main(void)
{
    void *x11 = dlopen("libX11.so.6", RTLD_NOW);
    void *xrr = dlopen("libXrandr.so.2", RTLD_NOW);
    if (!x11 || !xrr) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 1; }

    void *(*open_dpy)(const char *) = dlsym(x11, "XOpenDisplay");
    int (*disp_w)(void *, int) = dlsym(x11, "XDisplayWidth");
    unsigned long (*root)(void *, int) = dlsym(x11, "XRootWindow");
    void *(*get_res)(void *, unsigned long) = dlsym(xrr, "XRRGetScreenResources");
    if (!open_dpy || !disp_w || !get_res) { fprintf(stderr, "dlsym failed\n"); return 1; }

    void *dpy = open_dpy(":0");
    if (!dpy) { fprintf(stderr, "no display\n"); return 1; }

    printf("XDisplayWidth  = %d\n", disp_w(dpy, 0));
    void *res = get_res(dpy, root(dpy, 0));
    printf("XRRGetScreenResources = %s\n", res ? "returned" : "NULL");
    return 0;
}

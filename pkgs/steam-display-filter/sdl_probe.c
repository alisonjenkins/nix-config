/*
 * Check the filter the way Steam actually reads the desktop.
 *
 * Steam's desktop geometry comes from SDL, not from X: the routine in
 * steamui.so that logs "Desktop state changed" calls SDL_GetDisplays(NULL),
 * walks the NULL-terminated array calling SDL_GetDisplayBounds on each, and
 * unions the rectangles. Two details decide whether a test of this filter
 * means anything:
 *
 *   - The NULL. Steam never passes a count and never reads one, so a filter
 *     that only shortens the count leaves that routine reading the real
 *     desktop while looking perfectly healthy in a log.
 *   - The linkage. steamui.so has DT_NEEDED libSDL3.so.0, so its calls go
 *     through the PLT and LD_PRELOAD interposes them. A probe that dlopens SDL
 *     and resolves with a handle-scoped dlsym bypasses the preload entirely and
 *     will report "unfiltered" no matter how well the filter works.
 *
 * Both mistakes have already been made here. Six changes to this filter were
 * each confirmed working through a path Steam does not use, and changed
 * nothing; the first version of this probe repeated the trick.
 *
 * Build and run (two displays must exist for the result to mean anything):
 *
 *   gcc -o sdl_probe sdl_probe.c -lSDL3
 *   LD_PRELOAD=<multiarch>/lib64/libsteam-display-filter.so ./sdl_probe
 *
 * Expected with STEAM_STREAM_SIZE=1280x800 set:
 *   - run as ./sdl_probe -> the real displays, untouched. The filter is gated
 *     to the Steam client, and games and gamescope must see the desktop as it
 *     is.
 *   - run as ./steam     -> one display, 1280x800 at 0,0. Renaming the binary
 *     is what flips the gate, so both halves are covered.
 * With no size published, both must report the real displays.
 */
#include <stdio.h>

typedef unsigned int SDL_DisplayID;

struct sdl_rect {
    int x, y, w, h;
};

/*
 * Declared here rather than including SDL_video.h so the probe builds with
 * nothing but the shared library present.
 */
extern int SDL_Init(unsigned int flags);
extern const char *SDL_GetError(void);
extern SDL_DisplayID *SDL_GetDisplays(int *count);
extern int SDL_GetDisplayBounds(SDL_DisplayID display, struct sdl_rect *rect);

int main(void)
{
    SDL_DisplayID *ids;
    int i;

    /* 0x20 is SDL_INIT_VIDEO; the display list is empty until it runs. */
    if (!SDL_Init(0x20u)) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return 1;
    }

    /* NULL, exactly as steamui.so calls it. */
    ids = SDL_GetDisplays(NULL);
    if (!ids) {
        fprintf(stderr, "SDL_GetDisplays: %s\n", SDL_GetError());
        return 1;
    }

    for (i = 0; ids[i]; i++) {
        struct sdl_rect r = { 0, 0, 0, 0 };

        if (SDL_GetDisplayBounds(ids[i], &r))
            printf("display %u: %dx%d at %d,%d\n", ids[i], r.w, r.h, r.x, r.y);
        else
            printf("display %u: <bounds unavailable>\n", ids[i]);
    }
    printf("%d display(s) reported\n", i);
    return 0;
}

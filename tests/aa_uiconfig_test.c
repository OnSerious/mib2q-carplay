/*
 * Host test for aa_hook/aa_uiconfig.c: the per-view 0x8009 UpdateUiConfigRequest bytes (the
 * fork's car-validated viewport presets, sent in full 1920x1080 frame coordinates), the view
 * record Java writes, the density file, the insets override file and the opt-in day/night theme.
 * Build with -DAA_VIEW_PATH / -DAA_FILE_INSETS / -DAA_FILE_DPI / -DAA_THEME_PATH pointing at a
 * temp dir.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "../aa_hook/aa_uiconfig.c"

#undef NDEBUG
#include <assert.h>
#include <stdio.h>

void aa_log(const char *fmt, ...) { (void)fmt; }
static int daynight;          /* aa_cluster.daynight present */
int aa_marker(const char *path) { return daynight && !strcmp(path, AA_MARKER_DAYNIGHT); }

#define V2(v) (unsigned char)(0x80 | ((v) & 0x7f)), (unsigned char)((v) >> 7)

/* MessageRouter::queueOutgoing, found by relayout_send through dlsym like on the car. */
static int queued;
static unsigned char queued_msg[64];
static unsigned queued_len, queued_channel;
void _ZN13MessageRouter13queueOutgoingEhPvj(void *router, unsigned char channel, void *data, unsigned len)
{
    (void)router;
    queued++;
    queued_channel = channel;
    queued_len = len < sizeof(queued_msg) ? len : (unsigned)sizeof(queued_msg);
    memcpy(queued_msg, data, queued_len);
}

static void put(const char *path, const char *text)
{
    FILE *f = fopen(path, "w");
    assert(f);
    fputs(text, f);
    fclose(f);
}

/* want = the insets message (wn bytes) followed by the theme field (0x20 2). */
static void check_view(int view, const unsigned char *want, unsigned wn)
{
    unsigned char p[64];
    unsigned n = aa_relayout_message(p, sizeof(p), view, UI_THEME_DARK);
    assert(n == 4 + 2 + wn + 2);
    assert(p[0] == 0x80 && p[1] == 0x09 && p[2] == 0x0a && p[3] == 2 + wn + 2);   /* 0x8009, field 1 */
    assert(p[4] == 0x12 && p[5] == wn);                                          /* UiConfig.insets */
    assert(!memcmp(p + 6, want, wn + 2));
}

int main(void)
{
    /* insets top/bottom/left/right = preset + viewport origin (270 y, 240 x), then dark theme */
    static const unsigned char full[] = { 0x08, V2(97 + 270), 0x10, V2(167 + 270), 0x18, V2(350 + 240),
                                          0x20, V2(370 + 240), 0x20, 2 };
    static const unsigned char classic[] = { 0x08, V2(97 + 270), 0x10, V2(167 + 270), 0x18, V2(510 + 240),
                                             0x20, V2(510 + 240), 0x20, 2 };
    static const unsigned char sport[] = { 0x08, V2(78 + 270), 0x10, V2(146 + 270), 0x18, V2(484 + 240),
                                           0x20, V2(394 + 240), 0x20, 2 };
    unsigned char p[64];

    /* Presets are valid before any connect-time UiConfig ran. */
    check_view(0, full, sizeof(full) - 2);
    check_view(1, classic, sizeof(classic) - 2);
    check_view(2, sport, sizeof(sport) - 2);
    assert(aa_relayout_message(p, sizeof(p), 3, UI_THEME_DARK) == 0
        && aa_relayout_message(p, sizeof(p), -1, UI_THEME_DARK) == 0);
    assert(aa_relayout_message(p, 10, 0, UI_THEME_DARK) == 0);      /* no room: nothing */

    /* Light theme: same message, last byte 1. */
    {
        unsigned n = aa_relayout_message(p, sizeof(p), 0, UI_THEME_LIGHT);
        assert(n == 4 + 2 + sizeof(full) && p[n - 2] == 0x20 && p[n - 1] == 1);
    }

    /* Day/night record from Java (fixed 6 bytes), honoured only with the opt-in marker. */
    unlink(AA_THEME_PATH);
    daynight = 0;
    put(AA_THEME_PATH, "day  \n");    assert(aa_theme_state() == UI_THEME_DARK);   /* no marker */
    daynight = 1;
    assert(aa_theme_state() == UI_THEME_LIGHT);
    put(AA_THEME_PATH, "night\n");    assert(aa_theme_state() == UI_THEME_DARK);
    put(AA_THEME_PATH, "da");         assert(aa_theme_state() == UI_THEME_DARK);   /* mid-write */
    unlink(AA_THEME_PATH);            assert(aa_theme_state() == UI_THEME_DARK);   /* no record */
    daynight = 0;

    /* View record from Java (fixed 8 bytes); missing or garbled = unknown. */
    unlink(AA_VIEW_PATH);
    assert(aa_view_state() == -1);
    put(AA_VIEW_PATH, "full   \n");  assert(aa_view_state() == 0);
    put(AA_VIEW_PATH, "classic\n");  assert(aa_view_state() == 1);
    put(AA_VIEW_PATH, "sport  \n");  assert(aa_view_state() == 2);
    put(AA_VIEW_PATH, "spo");        assert(aa_view_state() == -1);

    /* Density: default 125 (1:1 physical size on the 125 PPI panel); file 80..400. */
    unlink(AA_FILE_DPI);
    assert(aa_dpi() == 125);
    put(AA_FILE_DPI, "140\n");       assert(aa_dpi() == 140);
    put(AA_FILE_DPI, "999\n");       assert(aa_dpi() == 125);

    /* Insets override: 12 numbers in viewport pixels, otherwise the presets stay. */
    put(AA_FILE_INSETS, "10 20 30 40  11 21 31 41  12 22 32 42\n");
    load_insets();
    {
        static const unsigned char want[] = { 0x08, V2(12 + 270), 0x10, V2(22 + 270), 0x18, V2(32 + 240),
                                              0x20, V2(42 + 240), 0x20, 2 };
        check_view(2, want, sizeof(want) - 2);
    }
    put(AA_FILE_INSETS, "10 20 30\n");                   /* too few: defaults back */
    load_insets();
    check_view(0, full, sizeof(full) - 2);
    put(AA_FILE_INSETS, "300 300 0 0  0 0 0 0  0 0 0 0\n");   /* leaves no area: rejected */
    load_insets();
    check_view(0, full, sizeof(full) - 2);
    unlink(AA_FILE_INSETS);
    unlink(AA_FILE_DPI);

    /* Issue #19: a theme change mid-session is never sent (the phone drops Android Auto);
     * a later view change still goes out, with the theme the session connected with. */
    {
        unsigned char sink[16] = {0};
        sink[4] = 1;                          /* channel open */
        sink[5] = 64;                         /* cluster video channel */
        wr(sink, 8, 0x1234u);                 /* router (opaque to the fake) */
        conn_view = 0;
        conn_theme = UI_THEME_DARK;           /* connected at night */
        daynight = 1;
        put(AA_VIEW_PATH, "full   \n");
        put(AA_THEME_PATH, "day  \n");       /* MMI switched to day */
        queued = 0;
        aa_relayout_tick(sink);               /* reads both records */
        aa_relayout_tick(sink);
        assert(queued == 0);                  /* theme change alone: nothing sent */
        usleep(350000);                       /* past the 300 ms read gate */
        put(AA_VIEW_PATH, "classic\n");
        aa_relayout_tick(sink);               /* view change picked up */
        aa_relayout_tick(sink);               /* ... and sent */
        assert(queued == 1 && queued_channel == 64);
        assert(queued_msg[0] == 0x80 && queued_msg[1] == 0x09);
        assert(queued_msg[queued_len - 2] == 0x20 && queued_msg[queued_len - 1] == UI_THEME_DARK);
        daynight = 0;
        unlink(AA_THEME_PATH);
    }
    unlink(AA_VIEW_PATH);

    printf("aa_uiconfig_test: full/classic/sport 0x8009 bytes, view record, density, insets file, day/night theme, no mid-session theme change (#19) PASS\n");
    return 0;
}

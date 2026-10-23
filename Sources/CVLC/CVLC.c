#include "CVLC.h"
#include <dlfcn.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

typedef struct Track { int id; char *name; struct Track *next; } Track;
struct LumaVLC {
    void *library, *instance, *player;
    void *(*create)(int, const char * const *);
    void (*release)(void *);
    void *(*player_new)(void *);
    void (*player_release)(void *);
    void *(*media_new)(void *, const char *);
    void (*media_release)(void *);
    void (*set_media)(void *, void *);
    void (*set_nsobject)(void *, void *);
    int (*play)(void *);
    void (*pause)(void *, int);
    void (*stop)(void *);
    int (*state)(void *);
    int64_t (*time)(void *), (*length)(void *);
    void (*seek)(void *, int64_t);
    int (*volume)(void *, int);
    int (*rate)(void *, float);
    Track *(*audio_tracks)(void *), *(*subtitle_tracks)(void *);
    void (*release_tracks)(Track *);
    int (*select_audio)(void *, int), (*select_subtitle)(void *, int);
    Track *tracks;
    int track_type;
};
#define LOAD(field, symbol) do { *(void **)(&v->field) = dlsym(lib, symbol); if (!v->field) { free(v); dlclose(lib); return NULL; } } while (0)
// The plugin bank must outlive Cocoa's queued view and rendering callbacks.
// Own one process-wide engine; individual media players are still released.
static LumaVLC *shared_runtime = NULL;
LumaVLC *luma_vlc_create(void) {
    if (shared_runtime) {
        LumaVLC *v = calloc(1, sizeof(LumaVLC));
        *v = *shared_runtime;
        v->player = v->player_new(v->instance);
        if (!v->player) { free(v); return NULL; }
        return v;
    }
    char path[4096];
    const char *roots[] = {getenv("LUMA_VLC_ROOT"), "/Applications/VLC.app/Contents/MacOS", "/opt/homebrew/lib"};
    void *lib = NULL;
    for (int i = 0; i < 3; i++) {
        if (!roots[i]) continue;
        // VLC's dylib references its core through @rpath. Preload the sibling
        // so the installed application works without changing its install names.
        snprintf(path, sizeof(path), "%s/lib/libvlccore.dylib", roots[i]);
        dlopen(path, RTLD_NOW | RTLD_GLOBAL);
        snprintf(path, sizeof(path), "%s/lib/libvlc.dylib", roots[i]);
        lib = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (!lib && i == 2) lib = dlopen("/opt/homebrew/lib/libvlc.dylib", RTLD_NOW | RTLD_LOCAL);
        if (lib) {
            snprintf(path, sizeof(path), "%s/plugins", roots[i]);
            setenv("VLC_PLUGIN_PATH", path, 1);
            // These modules register Objective-C classes and dispatch Cocoa work.
            // Pin their images so queued callbacks cannot jump into unmapped code.
            const char *cocoa_modules[] = {"libvout_macosx_plugin.dylib", "libcaopengllayer_plugin.dylib", "libauhal_plugin.dylib", "libvideotoolbox_plugin.dylib", "libglconv_cvpx_plugin.dylib"};
            for (int m = 0; m < 5; m++) {
                snprintf(path, sizeof(path), "%s/plugins/%s", roots[i], cocoa_modules[m]);
                dlopen(path, RTLD_NOW | RTLD_LOCAL | RTLD_NODELETE);
            }
            break;
        }
    }
    if (!lib) return NULL;
    LumaVLC *v = calloc(1, sizeof(LumaVLC));
    v->library = lib;
    LOAD(create, "libvlc_new"); LOAD(release, "libvlc_release");
    LOAD(player_new, "libvlc_media_player_new"); LOAD(player_release, "libvlc_media_player_release");
    LOAD(media_new, "libvlc_media_new_location"); LOAD(media_release, "libvlc_media_release");
    LOAD(set_media, "libvlc_media_player_set_media"); LOAD(set_nsobject, "libvlc_media_player_set_nsobject");
    LOAD(play, "libvlc_media_player_play"); LOAD(pause, "libvlc_media_player_set_pause"); LOAD(stop, "libvlc_media_player_stop");
    LOAD(state, "libvlc_media_player_get_state"); LOAD(time, "libvlc_media_player_get_time"); LOAD(length, "libvlc_media_player_get_length");
    LOAD(seek, "libvlc_media_player_set_time"); LOAD(volume, "libvlc_audio_set_volume"); LOAD(rate, "libvlc_media_player_set_rate");
    LOAD(audio_tracks, "libvlc_audio_get_track_description"); LOAD(subtitle_tracks, "libvlc_video_get_spu_description");
    LOAD(release_tracks, "libvlc_track_description_list_release"); LOAD(select_audio, "libvlc_audio_set_track"); LOAD(select_subtitle, "libvlc_video_set_spu");
    const char *args[] = {"--no-video-title-show", "--quiet", "--no-metadata-network-access", "--network-caching=1500", "--no-media-library"};
    v->instance = v->create(5, args);
    if (!v->instance) { free(v); dlclose(lib); return NULL; }
    v->player = v->player_new(v->instance);
    if (!v->player) { v->release(v->instance); free(v); dlclose(lib); return NULL; }
    shared_runtime = calloc(1, sizeof(LumaVLC));
    *shared_runtime = *v;
    shared_runtime->player = NULL;
    return v;
}
void luma_vlc_destroy(LumaVLC *v) { if (!v) return; v->stop(v->player); if (v->tracks) v->release_tracks(v->tracks); v->player_release(v->player); /* shared_runtime owns the instance until process exit. */ free(v); }
void luma_vlc_attach(LumaVLC *v, void *view) { if (v) v->set_nsobject(v->player, view); }
int luma_vlc_play(LumaVLC *v, const char *url) { if (!v) return -1; void *m = v->media_new(v->instance, url); if (!m) return -1; v->set_media(v->player, m); v->media_release(m); return v->play(v->player); }
void luma_vlc_pause(LumaVLC *v, int pause) { if (v) v->pause(v->player, pause); }
void luma_vlc_stop(LumaVLC *v) { if (v) v->stop(v->player); }
int luma_vlc_state(LumaVLC *v) { return v ? v->state(v->player) : 7; }
int64_t luma_vlc_time(LumaVLC *v) { return v ? v->time(v->player) : 0; }
int64_t luma_vlc_length(LumaVLC *v) { return v ? v->length(v->player) : 0; }
void luma_vlc_seek(LumaVLC *v, int64_t ms) { if (v) v->seek(v->player, ms); }
void luma_vlc_volume(LumaVLC *v, int volume) { if (v) v->volume(v->player, volume); }
void luma_vlc_rate(LumaVLC *v, float rate) { if (v) v->rate(v->player, rate); }
int luma_vlc_tracks(LumaVLC *v, int subtitles) {
    if (!v) return 0;
    if (v->tracks) v->release_tracks(v->tracks);
    v->tracks = subtitles ? v->subtitle_tracks(v->player) : v->audio_tracks(v->player); v->track_type = subtitles;
    int count = 0; for (Track *t = v->tracks; t; t = t->next) count++; return count;
}
static Track *track(LumaVLC *v, int index) { Track *t = v ? v->tracks : NULL; while (t && index-- > 0) t = t->next; return t; }
const char *luma_vlc_track_name(LumaVLC *v, int subtitles, int index) { Track *t = track(v, index); return t ? t->name : NULL; }
int luma_vlc_track_id(LumaVLC *v, int subtitles, int index) { Track *t = track(v, index); return t ? t->id : -1; }
void luma_vlc_select_track(LumaVLC *v, int subtitles, int id) { if (v) { if (subtitles) v->select_subtitle(v->player, id); else v->select_audio(v->player, id); } }

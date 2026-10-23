#ifndef CVLC_H
#define CVLC_H
#include <stdint.h>
typedef struct LumaVLC LumaVLC;
LumaVLC * luma_vlc_create(void);
void luma_vlc_destroy(LumaVLC *v);
void luma_vlc_attach(LumaVLC *v, void *view);
int luma_vlc_play(LumaVLC *v, const char *url);
void luma_vlc_pause(LumaVLC *v, int pause);
void luma_vlc_stop(LumaVLC *v);
int luma_vlc_state(LumaVLC *v);
int64_t luma_vlc_time(LumaVLC *v);
int64_t luma_vlc_length(LumaVLC *v);
void luma_vlc_seek(LumaVLC *v, int64_t ms);
void luma_vlc_volume(LumaVLC *v, int volume);
void luma_vlc_rate(LumaVLC *v, float rate);
int luma_vlc_tracks(LumaVLC *v, int subtitles);
const char * luma_vlc_track_name(LumaVLC *v, int subtitles, int index);
int luma_vlc_track_id(LumaVLC *v, int subtitles, int index);
void luma_vlc_select_track(LumaVLC *v, int subtitles, int id);
#endif

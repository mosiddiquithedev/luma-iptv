#!/usr/bin/env python3
"""Optional real decoder smoke check. Credentials come only from the environment."""
import ctypes as c
import json
import os
import sys
import time
import urllib.request
from urllib.parse import urlencode, quote

server = os.environ.get('LUMA_TEST_SERVER')
user = os.environ.get('LUMA_TEST_USER')
password = os.environ.get('LUMA_TEST_PASSWORD')
if not all([server, user, password]):
    sys.exit('Set LUMA_TEST_SERVER, LUMA_TEST_USER and LUMA_TEST_PASSWORD.')
root = '/Applications/VLC.app/Contents/MacOS'
os.environ['VLC_PLUGIN_PATH'] = root + '/plugins'
core = c.CDLL(root + '/lib/libvlccore.dylib', mode=c.RTLD_GLOBAL)
lib = c.CDLL(root + '/lib/libvlc.dylib')
def bind(name, result, *args):
    f = getattr(lib, name); f.restype = result; f.argtypes = list(args); return f
ptr = c.c_void_p
new = bind('libvlc_new', ptr, c.c_int, c.POINTER(c.c_char_p))
release = bind('libvlc_release', None, ptr)
media_new = bind('libvlc_media_new_location', ptr, ptr, c.c_char_p)
media_release = bind('libvlc_media_release', None, ptr)
player_new = bind('libvlc_media_player_new', ptr, ptr)
player_release = bind('libvlc_media_player_release', None, ptr)
set_media = bind('libvlc_media_player_set_media', None, ptr, ptr)
play = bind('libvlc_media_player_play', c.c_int, ptr)
stop = bind('libvlc_media_player_stop', None, ptr)
state = bind('libvlc_media_player_get_state', c.c_int, ptr)
get_time = bind('libvlc_media_player_get_time', c.c_int64, ptr)
class Stats(c.Structure):
    _fields_ = [('read_bytes',c.c_int),('input_bitrate',c.c_float),('demux_bytes',c.c_int),('demux_bitrate',c.c_float),('corrupted',c.c_int),('discontinuity',c.c_int),('decoded_video',c.c_int),('decoded_audio',c.c_int),('displayed',c.c_int),('lost_video',c.c_int),('audio_buffers',c.c_int),('lost_audio',c.c_int),('sent_packets',c.c_int),('sent_bytes',c.c_int),('send_bitrate',c.c_float)]
get_stats = bind('libvlc_media_get_stats', c.c_int, ptr, c.POINTER(Stats))
args = [b'--quiet', b'--vout=dummy', b'--aout=dummy', b'--no-video-title-show', b'--avcodec-hw=none', b'--network-caching=1500']
instance = new(len(args), (c.c_char_p * len(args))(*args))
if not instance: sys.exit('FAIL: VLC initialization')
player = player_new(instance)
api = server.rstrip('/') + '/player_api.php?' + urlencode({'username':user, 'password':password})
def fetch(action):
    req = urllib.request.Request(api + '&action=' + action, headers={'User-Agent':'Luma/1.0'})
    with urllib.request.urlopen(req, timeout=45) as response: return json.load(response)
success = True
try:
    for kind, action in [('movie','get_vod_streams'), ('live','get_live_streams')]:
        rows = fetch(action)
        passed = False
        # Providers can list offline entries, so allow up to three candidates.
        for row in [rows[i] for i in sorted(set([0, len(rows) // 3, len(rows) * 2 // 3]))]:
            extension = row.get('container_extension') or ('ts' if kind == 'live' else 'mp4')
            url = server.rstrip('/') + '/' + '/'.join(quote(str(v), safe='') for v in [kind,user,password,str(row['stream_id'])+'.'+extension])
            media = media_new(instance, url.encode())
            set_media(player, media); play(player)
            stats = Stats()
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline:
                time.sleep(0.5)
                get_stats(media, c.byref(stats))
                if stats.decoded_video > 10 and get_time(player) > 1000:
                    print(f'PASS: {kind} stream decoded {stats.decoded_video} video frames; playback clock advanced', flush=True)
                    passed = True; break
                if state(player) == 7: break
            stop(player); media_release(media)
            if passed: break
        if not passed:
            print(f'FAIL: {kind} candidates did not decode within timeout', flush=True); success = False
finally:
    stop(player); player_release(player); release(instance)
sys.exit(0 if success else 1)

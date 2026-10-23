package dev.luma.tv;

import android.app.*;
import android.content.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import androidx.media3.common.*;
import androidx.media3.exoplayer.*;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;
import androidx.media3.session.MediaSession;
import androidx.media3.ui.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Single hardware-decoding player, released whenever the TV app leaves the foreground. */
@androidx.annotation.OptIn(markerClass = androidx.media3.common.util.UnstableApi.class)
public class PlaybackActivity extends Activity {
  ExoPlayer player;
  PlayerView view;
  MediaSession mediaSession;
  DefaultTrackSelector tracks;
  Storage storage;
  Storage.State state;
  Catalog.Source source;
  List<Catalog.Item> queue = new ArrayList<>();
  int index = 0;
  final ExecutorService io = Executors.newSingleThreadExecutor();
  final Handler handler = new Handler(Looper.getMainLooper());
  FrameLayout root;
  LinearLayout top, bottom;
  TextView title, clock;
  Button next;
  boolean active = false, destroyed = false, restart = false, wasPlaying = true;
  long pausedPosition = 0;
  int countdown = 0;
  AlertDialog nextDialog;
  final Runnable progress =
      new Runnable() {
        public void run() {
          if (player == null) return;
          saveProgress(false);
          clock.setText(timeLabel());
          handler.postDelayed(this, 5000);
        }
      };
  final Runnable countdownTick =
      new Runnable() {
        public void run() {
          if (nextDialog == null || !active) return;
          if (countdown <= 0) {
            nextDialog.dismiss();
            nextDialog = null;
            advance();
            return;
          }
          nextDialog.setMessage("Next episode starts in " + countdown + " seconds.");
          countdown--;
          handler.postDelayed(this, 1000);
        }
      };

  @Override
  public void onCreate(Bundle b) {
    super.onCreate(b);
    storage = new Storage(this);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    getWindow().getDecorView().setSystemUiVisibility(5894);
    root = new FrameLayout(this);
    root.setBackgroundColor(0xff101211);
    setContentView(root);
    TextView loading = new TextView(this);
    loading.setText("Opening player…");
    loading.setTextColor(-1);
    loading.setTextSize(24);
    loading.setGravity(Gravity.CENTER);
    root.addView(loading, new FrameLayout.LayoutParams(-1, -1));
    io.execute(
        () -> {
          try {
            JSONObject j = storage.read("playback");
            source = Catalog.Source.from(j.getJSONObject("source"));
            JSONArray arr = j.getJSONArray("queue");
            for (int k = 0; k < arr.length(); k++) {
              Catalog.Item i = Catalog.Item.from(arr.getJSONObject(k));
              queue.add(i);
              if (i.id.equals(j.getString("selected"))) index = k;
            }
            state = new Storage.State(storage.read("state-" + source.scope()));
            restart = j.optBoolean("restart");
            runOnUiThread(
                () -> {
                  if (!destroyed) {
                    build();
                    if (active) startPlayer();
                  }
                });
          } catch (Exception e) {
            runOnUiThread(
                () ->
                    new AlertDialog.Builder(this)
                        .setTitle("Could not open playback")
                        .setMessage("Return to the library and try again.")
                        .setPositiveButton("Back", (d, w) -> finish())
                        .setOnCancelListener(d -> finish())
                        .show());
          }
        });
  }

  int dp(int n) {
    return Math.round(n * getResources().getDisplayMetrics().density);
  }

  Button button(String label, Runnable r) {
    Button b = new Button(this);
    b.setText(label);
    b.setTextSize(12);
    b.setAllCaps(false);
    b.setTextColor(0xfff5f7f4);
    b.setBackgroundTintList(android.content.res.ColorStateList.valueOf(0xff242b26));
    b.setOnFocusChangeListener(
        (v, f) -> {
          b.setBackgroundTintList(
              android.content.res.ColorStateList.valueOf(f ? 0xffbddfb7 : 0xff242b26));
          b.setTextColor(f ? 0xff101211 : 0xfff5f7f4);
        });
    b.setOnClickListener(v -> r.run());
    return b;
  }

  void build() {
    root.removeAllViews();
    view = new PlayerView(this);
    view.setControllerShowTimeoutMs(5000);
    view.setControllerHideOnTouch(true);
    view.setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING);
    view.setShowSubtitleButton(true);
    view.setShowNextButton(false);
    view.setShowPreviousButton(false);
    root.addView(view, new FrameLayout.LayoutParams(-1, -1));
    top = new LinearLayout(this);
    top.setGravity(Gravity.CENTER_VERTICAL);
    top.setPadding(dp(28), dp(12), dp(28), dp(12));
    top.setBackgroundColor(0xd9101211);
    top.addView(button("← Library", this::finish));
    title = new TextView(this);
    title.setText(queue.get(index).label());
    title.setTextSize(21);
    title.setTextColor(-1);
    title.setPadding(dp(18), 0, 0, 0);
    top.addView(title, new LinearLayout.LayoutParams(0, -2, 1));
    top.addView(
        button(
            "Info",
            () ->
                new AlertDialog.Builder(this)
                    .setTitle(queue.get(index).label())
                    .setMessage(
                        queue.get(index).summary.isEmpty()
                            ? "No description supplied by this source."
                            : queue.get(index).summary)
                    .setPositiveButton("Close", null)
                    .show()));
    root.addView(top, new FrameLayout.LayoutParams(-1, dp(68), Gravity.TOP));
    bottom = new LinearLayout(this);
    bottom.setGravity(Gravity.CENTER_VERTICAL);
    bottom.setPadding(dp(28), 0, dp(28), 0);
    bottom.setBackgroundColor(0xd9101211);
    bottom.addView(button("−10 sec", () -> seek(-10000)));
    bottom.addView(button("+10 sec", () -> seek(10000)));
    bottom.addView(button("Speed", this::speed));
    bottom.addView(button("Tracks", this::trackDialog));
    clock = new TextView(this);
    clock.setTextSize(14);
    clock.setTextColor(0xffbddfb7);
    clock.setPadding(dp(16), 0, dp(16), 0);
    clock.setFocusable(true);
    clock.setOnClickListener(
        v -> {
          try {
            state.root.put("clock", (state.root.optInt("clock") + 1) % 3);
          } catch (Exception ignored) {
          }
          clock.setText(timeLabel());
        });
    clock.setOnFocusChangeListener((v, f) -> v.setBackgroundColor(f ? 0xff405d50 : 0x00000000));
    bottom.addView(clock, new LinearLayout.LayoutParams(0, -2, 1));
    next = button("Next episode →", this::advance);
    bottom.addView(next);
    next.setVisibility(index + 1 < queue.size() ? View.VISIBLE : View.GONE);
    root.addView(bottom, new FrameLayout.LayoutParams(-1, dp(56), Gravity.BOTTOM));
    view.setControllerVisibilityListener(
        (PlayerView.ControllerVisibilityListener)
            visibility -> {
              top.setVisibility(visibility);
              bottom.setVisibility(visibility);
            });
    view.requestFocus();
  }

  void startPlayer() {
    if (player != null || queue.isEmpty() || !active) return;
    tracks = new DefaultTrackSelector(this);
    tracks.setParameters(
        tracks
            .buildUponParameters()
            .setMaxVideoSize(1920, 1080)
            .setAllowVideoMixedMimeTypeAdaptiveness(false));
    DefaultLoadControl buffer =
        new DefaultLoadControl.Builder()
            .setBufferDurationsMs(15000, 40000, 1500, 3000)
            .setTargetBufferBytes(24 * 1024 * 1024)
            .setPrioritizeTimeOverSizeThresholds(false)
            .build();
    player =
        new ExoPlayer.Builder(this)
            .setTrackSelector(tracks)
            .setLoadControl(buffer)
            .setSeekBackIncrementMs(10000)
            .setSeekForwardIncrementMs(10000)
            .build();
    player.setAudioAttributes(
        new AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .build(),
        true);
    player.setHandleAudioBecomingNoisy(true);
    mediaSession = new MediaSession.Builder(this, player).build();
    view.setPlayer(player);
    player.addListener(
        new Player.Listener() {
          public void onPlaybackStateChanged(int playbackState) {
            if (playbackState == Player.STATE_ENDED) {
              saveProgress(true);
              offerNext();
            }
          }

          public void onPlayerError(PlaybackException e) {
            saveProgress(false);
            new AlertDialog.Builder(PlaybackActivity.this)
                .setTitle("Stream unavailable")
                .setMessage(
                    "Your provider may be offline, or this device may not support the stream's"
                        + " codec. Retry or return to your library.")
                .setPositiveButton(
                    "Retry",
                    (d, w) -> {
                      player.prepare();
                      player.play();
                    })
                .setNegativeButton("Library", (d, w) -> finish())
                .show();
          }

          public void onIsPlayingChanged(boolean playing) {
            if (!playing) view.showController();
          }
        });
    openCurrent();
    handler.post(progress);
  }

  void openCurrent() {
    Catalog.Item i = queue.get(index);
    title.setText(i.label());
    next.setVisibility(index + 1 < queue.size() ? View.VISIBLE : View.GONE);
    player.setMediaItem(MediaItem.fromUri(source.stream(i)));
    long position = pausedPosition > 0 ? pausedPosition : restart ? 0 : state.position(i.id);
    if (!i.kind.equals("live")) player.seekTo(position);
    pausedPosition = 0;
    restart = false;
    player.prepare();
    player.setPlayWhenReady(wasPlaying);
  }

  void advance() {
    if (index + 1 >= queue.size()) return;
    saveProgress(false);
    index++;
    restart = false;
    pausedPosition = 0;
    wasPlaying = true;
    openCurrent();
  }

  void offerNext() {
    if (index + 1 >= queue.size()) return;
    if (!state.root.optBoolean("autoplay", true)) {
      view.showController();
      return;
    }
    countdown = 8;
    nextDialog =
        new AlertDialog.Builder(this)
            .setTitle("Up next: " + queue.get(index + 1).title)
            .setMessage("Next episode starts in 8 seconds.")
            .setPositiveButton(
                "Play now",
                (d, w) -> {
                  handler.removeCallbacks(countdownTick);
                  nextDialog = null;
                  advance();
                })
            .setNegativeButton(
                "Cancel",
                (d, w) -> {
                  handler.removeCallbacks(countdownTick);
                  nextDialog = null;
                  view.showController();
                })
            .setOnCancelListener(
                d -> {
                  handler.removeCallbacks(countdownTick);
                  nextDialog = null;
                })
            .create();
    nextDialog.show();
    handler.post(countdownTick);
  }

  void seek(long by) {
    if (player != null && player.isCurrentMediaItemSeekable())
      player.seekTo(
          Math.max(
              0, Math.min(Math.max(0, player.getDuration()), player.getCurrentPosition() + by)));
    view.showController();
  }

  void speed() {
    new AlertDialog.Builder(this)
        .setTitle("Playback speed")
        .setItems(
            new String[] {"0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×"},
            (d, w) -> {
              if (player != null)
                player.setPlaybackSpeed(new float[] {.5f, .75f, 1, 1.25f, 1.5f, 2}[w]);
            })
        .show();
  }

  void trackDialog() {
    if (player == null) return;
    new AlertDialog.Builder(this)
        .setTitle("Audio and subtitles")
        .setItems(
            new String[] {"Audio track", "Subtitle track", "Subtitles off"},
            (d, w) -> {
              if (w == 2) {
                player.setTrackSelectionParameters(
                    player
                        .getTrackSelectionParameters()
                        .buildUpon()
                        .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
                        .build());
                return;
              }
              int type = w == 0 ? C.TRACK_TYPE_AUDIO : C.TRACK_TYPE_TEXT;
              List<String> labels = new ArrayList<>();
              List<TrackSelectionOverride> choices = new ArrayList<>();
              for (Tracks.Group group : player.getCurrentTracks().getGroups())
                if (group.getType() == type)
                  for (int k = 0; k < group.length; k++)
                    if (group.isTrackSupported(k)) {
                      Format f = group.getTrackFormat(k);
                      labels.add(
                          (f.label != null
                                  ? f.label
                                  : f.language != null
                                      ? f.language
                                      : "Track " + (labels.size() + 1))
                              + (group.isTrackSelected(k) ? " ✓" : ""));
                      choices.add(new TrackSelectionOverride(group.getMediaTrackGroup(), k));
                    }
              if (labels.isEmpty()) {
                Toast.makeText(
                        this, "No alternative tracks supplied by this stream", Toast.LENGTH_LONG)
                    .show();
                return;
              }
              new AlertDialog.Builder(this)
                  .setTitle(w == 0 ? "Audio" : "Subtitles")
                  .setItems(
                      labels.toArray(new String[0]),
                      (dialog, n) ->
                          player.setTrackSelectionParameters(
                              player
                                  .getTrackSelectionParameters()
                                  .buildUpon()
                                  .setTrackTypeDisabled(type, false)
                                  .setOverrideForType(choices.get(n))
                                  .build()))
                  .show();
            })
        .show();
  }

  static String format(long ms) {
    long s = Math.max(0, ms / 1000);
    return s >= 3600
        ? String.format(Locale.ROOT, "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        : String.format(Locale.ROOT, "%d:%02d", s / 60, s % 60);
  }

  String timeLabel() {
    if (player == null) return "";
    long pos = player.getCurrentPosition(), duration = player.getDuration();
    if (duration < 0) return queue.get(index).kind.equals("live") ? "● LIVE" : format(pos);
    int mode = state.root.optInt("clock");
    return mode == 0
        ? "−" + format(duration - pos)
        : mode == 1 ? format(pos) : format(pos) + " / " + format(duration);
  }

  void saveProgress(boolean ended) {
    if (player == null || state == null) return;
    try {
      long duration = player.getDuration();
      long position = player.getCurrentPosition();
      if (ended && duration > 0) position = duration;
      Catalog.Item item = queue.get(index);
      JSONObject old = state.history.optJSONObject(item.id);
      if (old != null
          && old.optBoolean("completed")
          && player.getPlaybackState() == Player.STATE_ENDED) return;
      state.record(item, position, duration);
      JSONObject data = new JSONObject(state.json().toString());
      String name = "state-" + source.scope();
      io.execute(
          () -> {
            try {
              storage.write(name, data);
            } catch (Exception ignored) {
            }
          });
    } catch (Exception ignored) {
    }
  }

  @Override
  public boolean dispatchKeyEvent(KeyEvent event) {
    if (player != null) {
      int k = event.getKeyCode();
      if (event.getAction() == KeyEvent.ACTION_DOWN) {
        if (k == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE || k == KeyEvent.KEYCODE_SPACE) {
          if (player.isPlaying()) player.pause();
          else player.play();
          return true;
        }
        if (k == KeyEvent.KEYCODE_MEDIA_PLAY) {
          player.play();
          return true;
        }
        if (k == KeyEvent.KEYCODE_MEDIA_PAUSE) {
          player.pause();
          return true;
        }
        if (k == KeyEvent.KEYCODE_MEDIA_FAST_FORWARD) {
          seek(10000);
          return true;
        }
        if (k == KeyEvent.KEYCODE_MEDIA_REWIND) {
          seek(-10000);
          return true;
        }
        if (!view.isControllerFullyVisible()
            && (k == KeyEvent.KEYCODE_DPAD_LEFT || k == KeyEvent.KEYCODE_DPAD_RIGHT)) {
          seek(k == KeyEvent.KEYCODE_DPAD_LEFT ? -10000 : 10000);
          return true;
        }
        if (!view.isControllerFullyVisible() && k == KeyEvent.KEYCODE_DPAD_CENTER) {
          player.setPlayWhenReady(!player.getPlayWhenReady());
          view.showController();
          return true;
        }
      }
      if (view.dispatchKeyEvent(event)) return true;
    }
    return super.dispatchKeyEvent(event);
  }

  @Override
  public void onBackPressed() {
    if (view != null && view.isControllerFullyVisible() && player != null && player.isPlaying()) {
      view.hideController();
      return;
    }
    finish();
  }

  @Override
  protected void onStart() {
    super.onStart();
    active = true;
    if (view != null) startPlayer();
  }

  @Override
  protected void onStop() {
    active = false;
    handler.removeCallbacksAndMessages(null);
    if (nextDialog != null) {
      nextDialog.dismiss();
      nextDialog = null;
    }
    if (player != null) {
      saveProgress(false);
      pausedPosition = player.getCurrentPosition();
      wasPlaying = player.getPlayWhenReady();
      if (mediaSession != null) {
        mediaSession.release();
        mediaSession = null;
      }
      view.setPlayer(null);
      player.release();
      player = null;
    }
    super.onStop();
  }

  @Override
  protected void onDestroy() {
    destroyed = true;
    handler.removeCallbacksAndMessages(null);
    io.shutdown();
    super.onDestroy();
  }
}

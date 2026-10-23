package dev.luma.tv;

import static org.junit.Assert.*;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.widget.*;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.*;
import java.util.*;
import org.json.*;
import org.junit.*;
import org.junit.runner.RunWith;

@RunWith(AndroidJUnit4.class)
public class TvExperienceTest {
  final Instrumentation test = InstrumentationRegistry.getInstrumentation();
  MainActivity activity;

  void main(Runnable r) {
    test.runOnMainSync(r);
    test.waitForIdleSync();
  }

  void settle() throws Exception {
    test.waitForIdleSync();
    Thread.sleep(650);
  }

  void shot(String name) throws Exception {
    settle();
    Bitmap b = test.getUiAutomation().takeScreenshot();
    assertNotNull(b);
    File dir = new File(activity.getExternalFilesDir(null), "screenshots");
    dir.mkdirs();
    try (FileOutputStream out = new FileOutputStream(new File(dir, name + ".png"))) {
      b.compress(Bitmap.CompressFormat.PNG, 100, out);
    }
    b.recycle();
  }

  @Before
  public void launch() throws Exception {
    Context c = test.getTargetContext();
    new Storage(c).disconnect();
    activity =
        (MainActivity)
            test.startActivitySync(
                new Intent(c, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    settle();
  }

  @After
  public void close() {
    main(() -> activity.finish());
  }

  @Test
  public void remoteLibraryAndMarketingCaptures() throws Exception {
    main(() -> activity.demo());
    settle();
    assertEquals(24, activity.catalog.items.size());
    assertNotNull(activity.getCurrentFocus());
    test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_DOWN);
    settle();
    assertTrue(activity.getCurrentFocus() instanceof Button);
    assertTrue(((Button) activity.getCurrentFocus()).getText().toString().contains("Live TV"));
    test.sendKeyDownUpSync(KeyEvent.KEYCODE_DPAD_UP);
    settle();
    shot("tv-discover");
    Catalog.Item movie = activity.catalog.items.get(0);
    main(() -> activity.details(movie));
    shot("tv-details");
    main(() -> activity.details(activity.catalog.items.get(12)));
    assertEquals(4, activity.currentEpisodes.size());
    shot("tv-series");
    main(
        () -> {
          activity.favorite(movie);
          activity.favorite(movie);
        });
    assertFalse(activity.state.favorites.contains(movie.id));

    main(
        () -> {
          activity.destination = "Live TV";
          activity.dashboard();
        });
    shot("tv-live");
    main(
        () -> {
          activity.destination = "Discover";
          activity.dashboard();
          activity.manageShelves();
        });
    shot("tv-customize");
    test.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK);
    main(
        () -> {
          try {
            activity.state.root.put("theme", "light");
          } catch (Exception e) {
            throw new RuntimeException(e);
          }
          activity.applyTheme();
          activity.dashboard();
        });
    shot("tv-light");
    assertEquals(0xfff6f8f5, activity.bg);
  }

  @Test
  public void encryptedStateAndResumeRoundTrip() throws Exception {
    Storage storage = new Storage(test.getTargetContext());
    Catalog.Item i = new Catalog.Item();
    i.id = "fixture-movie";
    i.title = "Resume fixture";
    i.kind = "movie";
    Storage.State state = new Storage.State(new JSONObject());
    state.favorites.add(i.id);
    state.record(i, 12000, 30000);
    storage.write("test-state", state.json());
    Storage.State copy = new Storage.State(storage.read("test-state"));
    assertEquals(12000, copy.position(i.id));
    assertEquals(1, copy.history(true).size());
    assertTrue(copy.favorites.contains(i.id));
    state.record(i, 30000, 30000);
    assertTrue(state.completed(i.id));
    assertEquals(0, state.history(true).size());
    File f = new File(test.getTargetContext().getFilesDir(), "test-state");
    String envelope = new String(java.nio.file.Files.readAllBytes(f.toPath()), "UTF-8");
    assertFalse(envelope.contains("Resume fixture"));
    assertFalse(envelope.contains("fixture-movie"));
    f.delete();
  }

  @Test
  public void providerClientAgainstPostmanSimulation() throws Exception {
    Catalog.Source source = new Catalog.Source();
    source.address = "http://127.0.0.1:4900/xtream";
    source.username = "fixture";
    source.password = "fixture";
    Catalog.Provider client = new Catalog.Provider(source);
    Catalog library = client.load();
    assertEquals(3, library.items.size());
    assertEquals(3, library.categories.size());
    Catalog.Item movie = null, series = null;
    for (Catalog.Item i : library.items) {
      if (i.kind.equals("movie")) movie = i;
      if (i.kind.equals("series")) series = i;
    }
    assertNotNull(movie);
    assertNotNull(series);
    assertEquals("An original fixture description.", client.details(movie).summary);
    java.util.List<Catalog.Item> es = client.episodes(series);
    assertEquals(2, es.size());
    assertEquals(1, es.get(0).season);
    assertEquals(2, es.get(1).season);
    source.password = "incorrect";
    try {
      new Catalog.Provider(source).load();
      fail("Expected rejected login");
    } catch (java.io.IOException expected) {
      assertTrue(expected.getMessage().contains("Login rejected"));
    }
  }

  @Test
  public void realMedia3PlaybackResumesAndPersists() throws Exception {
    Catalog.Source src = new Catalog.Source();
    src.type = "playlist";
    src.address = "http://127.0.0.1:4901/test.m3u";
    Catalog.Item movie = new Catalog.Item();
    movie.id = "playback-fixture";
    movie.title = "Generated playback fixture";
    movie.kind = "movie";
    movie.url = "http://127.0.0.1:4901/fixture.mp4";
    Storage.State state = new Storage.State(new JSONObject());
    state.record(movie, 12000, 30000);
    Storage storage = new Storage(test.getTargetContext());
    storage.write("state-" + src.scope(), state.json());
    storage.write(
        "playback",
        new JSONObject()
            .put("source", src.json())
            .put("queue", new JSONArray().put(movie.json()))
            .put("selected", movie.id));
    Instrumentation.ActivityMonitor monitor =
        test.addMonitor(PlaybackActivity.class.getName(), null, false);
    main(() -> activity.startActivity(new Intent(activity, PlaybackActivity.class)));
    PlaybackActivity playback = (PlaybackActivity) monitor.waitForActivityWithTimeout(10000);
    assertNotNull(playback);
    long deadline = android.os.SystemClock.uptimeMillis() + 20000;
    final boolean[] advanced = {false};
    while (android.os.SystemClock.uptimeMillis() < deadline) {
      main(
          () -> {
            advanced[0] =
                playback.player != null
                    && playback.player.getCurrentPosition() > 13500
                    && playback.player.isPlaying();
          });
      if (advanced[0]) break;
      Thread.sleep(300);
    }
    assertTrue("Media3 must advance beyond saved resume position", advanced[0]);
    main(
        () -> {
          playback.view.showController();
        });
    Bitmap screenshot = test.getUiAutomation().takeScreenshot();
    File dir = new File(activity.getExternalFilesDir(null), "screenshots");
    dir.mkdirs();
    try (FileOutputStream out = new FileOutputStream(new File(dir, "tv-player.png"))) {
      screenshot.compress(Bitmap.CompressFormat.PNG, 100, out);
    }
    screenshot.recycle();
    main(playback::finish);
    Thread.sleep(700);
    Storage.State saved = new Storage.State(storage.read("state-" + src.scope()));
    assertTrue(saved.position(movie.id) > 13000);
    test.removeMonitor(monitor);
  }

  @Test
  public void episodeAutoplayCrossesSeasonAndKeepsCompletion() throws Exception {
    Catalog.Source src = new Catalog.Source();
    src.type = "playlist";
    src.address = "http://127.0.0.1:4901/episodes.m3u";
    Catalog.Item first = new Catalog.Item();
    first.id = "autoplay-1";
    first.title = "First fixture";
    first.kind = "series";
    first.series = "fixture-series";
    first.season = 1;
    first.episode = 1;
    first.url = "http://127.0.0.1:4901/fixture.mp4";
    Catalog.Item second = Catalog.Item.from(first.json());
    second.id = "autoplay-2";
    second.title = "Second fixture";
    second.season = 2;
    Storage storage = new Storage(test.getTargetContext());
    storage.write("state-" + src.scope(), new JSONObject());
    storage.write(
        "playback",
        new JSONObject()
            .put("source", src.json())
            .put("queue", new JSONArray().put(first.json()).put(second.json()))
            .put("selected", first.id));
    Instrumentation.ActivityMonitor monitor =
        test.addMonitor(PlaybackActivity.class.getName(), null, false);
    main(() -> activity.startActivity(new Intent(activity, PlaybackActivity.class)));
    PlaybackActivity playback = (PlaybackActivity) monitor.waitForActivityWithTimeout(10000);
    assertNotNull(playback);
    final boolean[] ready = {false};
    long deadline = android.os.SystemClock.uptimeMillis() + 15000;
    while (android.os.SystemClock.uptimeMillis() < deadline) {
      main(
          () ->
              ready[0] =
                  playback.player != null
                      && playback.player.getDuration() > 1000
                      && playback.player.isPlaying());
      if (ready[0]) break;
      Thread.sleep(200);
    }
    assertTrue(ready[0]);
    main(() -> playback.player.seekTo(playback.player.getDuration() - 250));
    final boolean[] moved = {false};
    deadline = android.os.SystemClock.uptimeMillis() + 16000;
    while (android.os.SystemClock.uptimeMillis() < deadline) {
      main(
          () ->
              moved[0] =
                  playback.index == 1
                      && playback.player != null
                      && playback.player.getCurrentPosition() > 500);
      if (moved[0]) break;
      Thread.sleep(250);
    }
    assertTrue("Eight-second autoplay must reach the next season", moved[0]);
    assertTrue(playback.state.completed(first.id));
    main(playback::finish);
    Thread.sleep(700);
    Storage.State saved = new Storage.State(storage.read("state-" + src.scope()));
    assertTrue(saved.completed(first.id));
    test.removeMonitor(monitor);
  }
}

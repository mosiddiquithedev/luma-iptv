package dev.luma.tv;

import static org.junit.Assert.*;

import java.util.*;
import org.json.*;
import org.junit.Test;

public class CatalogTest {
  @Test
  public void playlistPreservesQuotedCommasAndRelativeUrls() throws Exception {
    Catalog c =
        Catalog.parse(
            "\uFEFF#EXTM3U\n"
                + "#EXTINF:-1 group-title=\"News, World\" tvg-logo=\"logo.png\",World, Today\n"
                + "feed/one.ts\n"
                + "#EXTINF:-1,Duplicate\n"
                + "feed/one.ts",
            "https://example.com/list.m3u");
    assertEquals(1, c.items.size());
    assertEquals("World, Today", c.items.get(0).title);
    assertEquals("News, World", c.categories.get("live:News, World"));
    assertEquals("https://example.com/feed/one.ts", c.items.get(0).url);
    assertEquals("https://example.com/logo.png", c.items.get(0).art);
  }

  @Test
  public void groupsSeriesAndSortsAcrossSeasons() throws Exception {
    Catalog c =
        Catalog.parse(
            "#EXTM3U\n"
                + "#EXTINF:-1 group-title=\"Drama\",Orbit S02E01\n"
                + "https://example.com/3.mkv\n"
                + "#EXTINF:-1 group-title=\"Drama\",Orbit 1x02\n"
                + "https://example.com/2.mkv\n"
                + "#EXTINF:-1 group-title=\"Drama\",Orbit S01 E01\n"
                + "https://example.com/1.mkv",
            "https://example.com/list.m3u");
    assertEquals(1, c.items.size());
    assertEquals("series", c.items.get(0).kind);
    List<Catalog.Item> es = c.episodes.get(c.items.get(0).id);
    assertEquals(3, es.size());
    assertEquals(1, es.get(0).episode);
    assertEquals(1, es.get(0).season);
    assertEquals(2, es.get(2).season);
    assertTrue(c.items.get(0).series.isEmpty());
    assertTrue(c.items.get(0).url.isEmpty());
  }

  @Test
  public void stableIdsAndMediaKinds() throws Exception {
    String raw =
        "#EXTM3U\n"
            + "#EXTINF:-1,Film (2024)\n"
            + "https://example.com/movie.mp4\n"
            + "#EXTINF:-1,Channel\n"
            + "https://example.com/live.ts";
    Catalog a = Catalog.parse(raw, "https://example.com/"),
        b = Catalog.parse(raw, "https://example.com/");
    assertEquals(a.items.get(0).id, b.items.get(0).id);
    assertEquals("movie", a.items.get(0).kind);
    assertEquals("live", a.items.get(1).kind);
    assertEquals(2024, a.items.get(0).releaseYear());
    assertEquals(0, a.items.get(1).releaseYear());
  }

  @Test
  public void credentialsAreEncodedAsPathSegments() {
    Catalog.Source s = new Catalog.Source();
    s.address = "https://example.com:8080/base/";
    s.username = "a user";
    s.password = "p/?&#";
    Catalog.Item i = new Catalog.Item();
    i.kind = "series";
    i.series = "series:2";
    i.providerID = "42";
    i.ext = "mkv";
    assertEquals("https://example.com:8080/base/series/a%20user/p%2F%3F%26%23/42.mkv", s.stream(i));
    assertFalse(s.scope().contains(s.password));
  }

  @Test
  public void itemsRoundTripEpisodeMetadata() throws Exception {
    Catalog.Item i = new Catalog.Item();
    i.id = "e1";
    i.kind = "series";
    i.series = "s1";
    i.season = 2;
    i.episode = 10;
    i.summary = "Description";
    Catalog.Item copy = Catalog.Item.from(new JSONObject(i.json().toString()));
    assertEquals(2, copy.season);
    assertEquals(10, copy.episode);
    assertEquals("Description", copy.summary);
    assertEquals("s1", copy.series);
  }

  @Test(expected = Exception.class)
  public void rejectsInvalidPlaylist() throws Exception {
    Catalog.parse("<html>Not found</html>", "https://example.com");
  }

  @Test
  public void rejectsDangerousUrlsButRetainsGroupDirective() throws Exception {
    Catalog c =
        Catalog.parse(
            "#EXTM3U\n"
                + "#EXTINF:-1,Skip\n"
                + "javascript:alert(1)\n"
                + "#EXTINF:-1,Keep\n"
                + "#EXTGRP:Local News\n"
                + "https://example.com/live.ts",
            "https://example.com");
    assertEquals(1, c.items.size());
    assertEquals("Local News", c.categories.get("live:Local News"));
  }

  @Test
  public void releaseMetadataOnlyUsesBracketedTitleYears() {
    Catalog.Item i = new Catalog.Item();
    i.title = "2001 A Space Odyssey";
    assertEquals(0, i.releaseYear());
    i.year = "1968-04-02";
    assertEquals(1968, i.releaseYear());
  }
}

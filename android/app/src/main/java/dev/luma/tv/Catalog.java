package dev.luma.tv;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.regex.*;
import org.json.*;

/** Provider-independent models and parser. No Android dependency, credentials, or demo streams. */
public final class Catalog {
  public static final String LIVE = "live", MOVIE = "movie", SERIES = "series";

  public static String text(JSONObject j, String k) {
    Object v = j.opt(k);
    return v == null || v == JSONObject.NULL ? "" : String.valueOf(v);
  }

  public static String first(JSONObject j, String... keys) {
    for (String k : keys) {
      String s = text(j, k);
      if (!s.isEmpty() && !s.equalsIgnoreCase("null") && !s.equalsIgnoreCase("n/a")) return s;
    }
    return "";
  }

  public static String hash(String s) {
    try {
      byte[] bytes =
          MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));
      StringBuilder b = new StringBuilder();
      for (byte v : bytes) b.append(String.format(Locale.ROOT, "%02x", v));
      return b.toString();
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }

  public static class Item {
    public String id = "",
        providerID = "",
        title = "",
        kind = LIVE,
        category = "",
        art = "",
        url = "",
        ext = "",
        summary = "",
        rating = "",
        year = "",
        series = "";
    public int season, episode;

    public JSONObject json() {
      JSONObject j = new JSONObject();
      try {
        j.put("id", id)
            .put("providerID", providerID)
            .put("title", title)
            .put("kind", kind)
            .put("category", category)
            .put("art", art)
            .put("url", url)
            .put("ext", ext)
            .put("summary", summary)
            .put("rating", rating)
            .put("year", year)
            .put("series", series)
            .put("season", season)
            .put("episode", episode);
      } catch (JSONException e) {
        throw new IllegalStateException(e);
      }
      return j;
    }

    public static Item from(JSONObject j) {
      Item i = new Item();
      i.id = text(j, "id");
      i.providerID = text(j, "providerID");
      i.title = text(j, "title");
      i.kind = text(j, "kind");
      i.category = text(j, "category");
      i.art = text(j, "art");
      i.url = text(j, "url");
      i.ext = text(j, "ext");
      i.summary = text(j, "summary");
      i.rating = text(j, "rating");
      i.year = text(j, "year");
      i.series = text(j, "series");
      i.season = j.optInt("season");
      i.episode = j.optInt("episode");
      return i;
    }

    public String label() {
      return series.isEmpty() ? title : "S" + season + " · E" + episode + "  " + title;
    }

    public int releaseYear() {
      Matcher m = Pattern.compile("(?:18|19|20|21)\\d{2}").matcher(year);
      if (m.find()) return Integer.parseInt(m.group());
      m = Pattern.compile("[\\[(]((?:18|19|20|21)\\d{2})[\\])]").matcher(title);
      return m.find() ? Integer.parseInt(m.group(1)) : 0;
    }
  }

  public static class Source {
    public String type = "xtream", address = "", username = "", password = "", name = "My library";

    public JSONObject json() {
      JSONObject j = new JSONObject();
      try {
        j.put("type", type)
            .put("address", address)
            .put("username", username)
            .put("password", password)
            .put("name", name);
      } catch (JSONException e) {
        throw new IllegalStateException(e);
      }
      return j;
    }

    public static Source from(JSONObject j) {
      Source s = new Source();
      s.type = text(j, "type");
      s.address = text(j, "address");
      s.username = text(j, "username");
      s.password = text(j, "password");
      s.name = text(j, "name");
      return s;
    }

    public String base() {
      return address.contains(":") ? address : "https://" + address;
    }

    public String scope() {
      return hash(type + "|" + address + "|" + username);
    }

    public String stream(Item i) {
      if (!i.url.isEmpty()) return i.url;
      String path = !i.series.isEmpty() ? "series" : i.kind.equals(LIVE) ? "live" : "movie";
      return base().replaceAll("/+$", "")
          + "/"
          + path
          + "/"
          + encode(username)
          + "/"
          + encode(password)
          + "/"
          + encode(i.providerID)
          + "."
          + (i.ext.isEmpty() ? (i.kind.equals(LIVE) ? "ts" : "mp4") : i.ext);
    }
  }

  public final List<Item> items = new ArrayList<>();
  public final LinkedHashMap<String, String> categories = new LinkedHashMap<>();
  public final Map<String, List<Item>> episodes = new HashMap<>();

  public static String encode(String s) {
    try {
      return URLEncoder.encode(s, "UTF-8").replace("+", "%20");
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }

  private static final Pattern EP =
      Pattern.compile(
          "(?i)^(.+?)[ ._-]+(?:s(\\d{1,2})[ ._-]*e(\\d{1,3})|(\\d{1,2})x(\\d{1,3}))(?:\\b|[ ._-])");

  public static Catalog parse(String raw, String base) throws Exception {
    String input = raw.replace("\uFEFF", "").trim();
    if (!input.startsWith("#EXTM3U")) throw new IOException("This file is not an M3U playlist.");
    Catalog c = new Catalog();
    String info = null, group = "";
    Set<String> seen = new HashSet<>(), shows = new HashSet<>();
    for (String rawLine : input.split("\\r?\\n")) {
      String line = rawLine.trim();
      if (line.startsWith("#EXTINF:")) {
        info = line;
        group = "";
        continue;
      }
      if (line.startsWith("#EXTGRP:")) {
        group = line.substring(8);
        continue;
      }
      if (line.isEmpty() || line.startsWith("#") || info == null) continue;
      String meta = info;
      info = null;
      Map<String, String> a = new HashMap<>();
      Matcher attrs = Pattern.compile("([\\w-]+)\\s*=\\s*\"([^\"]*)\"").matcher(meta);
      while (attrs.find()) a.put(attrs.group(1).toLowerCase(Locale.ROOT), attrs.group(2));
      String url;
      try {
        url = new URI(base).resolve(line).toString();
        String scheme = new URI(url).getScheme();
        if (scheme == null
            || !Arrays.asList("http", "https", "rtsp", "rtmp", "udp", "content", "file")
                .contains(scheme.toLowerCase(Locale.ROOT))) continue;
      } catch (Exception e) {
        continue;
      }
      Item i = new Item();
      i.id = "m3u:" + hash(url);
      if (!seen.add(i.id)) continue;
      i.url = url;
      boolean quoted = false;
      int comma = -1;
      for (int k = 0; k < meta.length(); k++) {
        char ch = meta.charAt(k);
        if (ch == '"') quoted = !quoted;
        if (ch == ',' && !quoted) {
          comma = k;
          break;
        }
      }
      i.title =
          comma < 0 ? a.getOrDefault("tvg-name", "Untitled") : meta.substring(comma + 1).trim();
      if (i.title.isEmpty()) i.title = a.getOrDefault("tvg-name", "Untitled");
      Matcher ep = EP.matcher(i.title);
      boolean episode = ep.find();
      String path = new URI(url).getPath();
      boolean vod =
          path != null && path.toLowerCase(Locale.ROOT).matches(".*\\.(mp4|mkv|avi|mov|m4v)$");
      try {
        vod |= Double.parseDouble(meta.substring(8).split("[ ,]", 2)[0]) > 0;
      } catch (Exception ignored) {
      }
      i.kind = episode ? SERIES : vod ? MOVIE : LIVE;
      String category = a.getOrDefault("group-title", group.isEmpty() ? "Uncategorized" : group);
      i.category = i.kind + ":" + category;
      c.categories.put(i.category, category);
      if (a.containsKey("tvg-logo")) {
        try {
          i.art = new URI(base).resolve(a.get("tvg-logo")).toString();
        } catch (Exception ignored) {
        }
      }
      i.summary = a.getOrDefault("description", a.getOrDefault("tvg-description", ""));
      i.year = a.getOrDefault("year", a.getOrDefault("release-date", ""));
      if (episode) {
        String showTitle = ep.group(1).trim();
        String sid = "m3u-show:" + hash(category + ":" + showTitle.toLowerCase(Locale.ROOT));
        i.series = sid;
        i.season = Integer.parseInt(ep.group(2) != null ? ep.group(2) : ep.group(4));
        i.episode = Integer.parseInt(ep.group(3) != null ? ep.group(3) : ep.group(5));
        c.episodes.computeIfAbsent(sid, k -> new ArrayList<>()).add(i);
        if (shows.add(sid)) {
          Item show = Item.from(i.json());
          show.id = sid;
          show.providerID = sid;
          show.title = showTitle;
          show.series = "";
          show.url = "";
          show.season = show.episode = 0;
          c.items.add(show);
        }
      } else c.items.add(i);
    }
    for (List<Item> es : c.episodes.values()) sortEpisodes(es);
    if (c.items.isEmpty()) throw new IOException("The playlist has no supported entries.");
    return c;
  }

  public static void sortEpisodes(List<Item> es) {
    Collections.sort(
        es,
        Comparator.comparingInt((Item i) -> i.season)
            .thenComparingInt(i -> i.episode)
            .thenComparing(i -> i.title));
  }

  public static String download(String address) throws Exception {
    HttpURLConnection connection = (HttpURLConnection) new URL(address).openConnection();
    connection.setConnectTimeout(15000);
    connection.setReadTimeout(45000);
    connection.setRequestProperty("User-Agent", "LumaTV/1.0");
    try {
      int code = connection.getResponseCode();
      if (code < 200 || code >= 300)
        throw new IOException(
            "Provider returned HTTP " + code + ". Retry or update your connection.");
      try (InputStream in = connection.getInputStream();
          ByteArrayOutputStream out = new ByteArrayOutputStream()) {
        byte[] b = new byte[16384];
        int n, total = 0;
        while ((n = in.read(b)) != -1) {
          if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException();
          total += n;
          if (total > 100000000) throw new IOException("Catalog is too large.");
          out.write(b, 0, n);
        }
        return out.toString("UTF-8");
      }
    } finally {
      connection.disconnect();
    }
  }

  public static class Provider {
    final Source source;

    public Provider(Source s) {
      source = s;
    }

    Object api(String action, String key, String value) throws Exception {
      String u =
          source.base().replaceAll("/+$", "")
              + "/player_api.php?username="
              + encode(source.username)
              + "&password="
              + encode(source.password);
      if (action != null) u += "&action=" + encode(action);
      if (key != null) u += "&" + key + "=" + encode(value);
      return new JSONTokener(download(u)).nextValue();
    }

    public Catalog load() throws Exception {
      if (source.type.equals("playlist")) return parse(download(source.base()), source.base());
      Object auth = api(null, null, null);
      JSONObject user =
          auth instanceof JSONObject ? ((JSONObject) auth).optJSONObject("user_info") : null;
      if (user == null || !text(user, "auth").equals("1"))
        throw new IOException("Login rejected. Check your provider credentials.");
      if (!text(user, "status").isEmpty() && !text(user, "status").equalsIgnoreCase("active"))
        throw new IOException("Your provider account is inactive.");
      Catalog c = new Catalog();
      for (String kind : Arrays.asList(LIVE, MOVIE, SERIES)) {
        String prefix = kind.equals(MOVIE) ? "vod" : kind;
        Object cs = api("get_" + prefix + "_categories", null, null);
        Object rows =
            api(kind.equals(SERIES) ? "get_series" : "get_" + prefix + "_streams", null, null);
        if (!(cs instanceof JSONArray) || !(rows instanceof JSONArray))
          throw new IOException("Provider returned an invalid catalog.");
        for (int k = 0; k < ((JSONArray) cs).length(); k++) {
          JSONObject j = ((JSONArray) cs).getJSONObject(k);
          c.categories.put(kind + ":" + text(j, "category_id"), text(j, "category_name"));
        }
        Set<String> seen = new HashSet<>();
        for (int k = 0; k < ((JSONArray) rows).length(); k++) {
          JSONObject j = ((JSONArray) rows).getJSONObject(k);
          Item i = new Item();
          i.providerID = text(j, kind.equals(SERIES) ? "series_id" : "stream_id");
          if (i.providerID.isEmpty()) continue;
          i.id = kind + ":" + i.providerID;
          if (!seen.add(i.id)) continue;
          i.kind = kind;
          i.title = text(j, "name");
          i.category = kind + ":" + text(j, "category_id");
          if (!c.categories.containsKey(i.category)) c.categories.put(i.category, "Uncategorized");
          i.art = first(j, "cover", "stream_icon");
          i.ext = text(j, "container_extension");
          enrich(i, j);
          c.items.add(i);
        }
      }
      return c;
    }

    static void enrich(Item i, JSONObject j) {
      String t = first(j, "plot", "description", "overview");
      if (!t.isEmpty()) i.summary = t;
      t =
          first(
              j,
              "year",
              "releaseDate",
              "release_date",
              "releasedate",
              "first_air_date",
              "air_date");
      if (!t.isEmpty()) i.year = t;
      t = text(j, "rating");
      if (!t.isEmpty()) i.rating = t;
    }

    public Item details(Item i) throws Exception {
      Object raw = api("get_vod_info", "vod_id", i.providerID);
      if (!(raw instanceof JSONObject)) throw new IOException("Movie details unavailable.");
      Item copy = Item.from(i.json());
      JSONObject root = (JSONObject) raw;
      if (root.optJSONObject("movie_data") != null) enrich(copy, root.getJSONObject("movie_data"));
      if (root.optJSONObject("info") != null) enrich(copy, root.getJSONObject("info"));
      return copy;
    }

    public List<Item> episodes(Item show) throws Exception {
      Object raw = api("get_series_info", "series_id", show.providerID);
      if (!(raw instanceof JSONObject)) throw new IOException("Series details unavailable.");
      JSONObject root = (JSONObject) raw;
      JSONObject info = root.optJSONObject("info");
      if (info != null) enrich(show, info);
      JSONObject seasons = root.optJSONObject("episodes");
      List<Item> result = new ArrayList<>();
      if (seasons == null) {
        if (root.optJSONArray("episodes") != null && root.getJSONArray("episodes").length() == 0)
          return result;
        throw new IOException("Provider returned invalid episodes.");
      }
      Iterator<String> keys = seasons.keys();
      while (keys.hasNext()) {
        String season = keys.next();
        JSONArray rows = seasons.optJSONArray(season);
        if (rows == null) continue;
        for (int k = 0; k < rows.length(); k++) {
          JSONObject j = rows.getJSONObject(k);
          Item i = new Item();
          i.providerID = text(j, "id");
          if (i.providerID.isEmpty()) continue;
          i.id = "episode:" + i.providerID;
          i.kind = SERIES;
          i.title = first(j, "title", "name");
          i.category = show.category;
          i.art = show.art;
          i.ext = first(j, "container_extension");
          i.series = show.id;
          i.season = j.optInt("season", Integer.parseInt(season.replaceAll("\\D", "0")));
          i.episode = j.optInt("episode_num", k + 1);
          JSONObject einfo = j.optJSONObject("info");
          if (einfo != null) {
            enrich(i, einfo);
            String art = text(einfo, "movie_image");
            if (!art.isEmpty()) i.art = art;
          }
          result.add(i);
        }
      }
      sortEpisodes(result);
      return result;
    }
  }
}

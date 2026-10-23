package dev.luma.tv;

import android.app.*;
import android.content.*;
import android.content.res.Configuration;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.*;
import android.text.*;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import androidx.recyclerview.widget.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

public class MainActivity extends Activity {
  int bg = 0xff101211,
      surface = 0xff1b201d,
      fg = 0xfff5f7f4,
      muted = 0xff929c94,
      accent = 0xffbddfb7;
  final ExecutorService io = Executors.newSingleThreadExecutor(),
      filter = Executors.newSingleThreadExecutor();
  final Handler main = new Handler(Looper.getMainLooper());
  Storage storage;
  Storage.State state = new Storage.State(new JSONObject());
  Catalog.Source source;
  Catalog catalog = new Catalog();
  LinearLayout root, body, content, sidebar;
  TextView status;
  RecyclerView grid;
  Cards adapter;
  String destination = "Discover", category = "", search = "", categorySearch = "";
  int year = 0, queryGeneration = 0;
  volatile int generation = 0;
  boolean reverse = false, loading = false, demo = false, detail = false;
  volatile boolean destroyed = false;
  Catalog.Item selected;
  ArrayList<Catalog.Item> currentEpisodes = new ArrayList<>();
  int lastFocused = 0;
  String[] destinations = {
    "Discover", "Live TV", "Movies", "Series", "Favorites", "History", "Settings"
  };

  public int dp(float v) {
    return Math.round(v * getResources().getDisplayMetrics().density);
  }

  @Override
  public void onCreate(Bundle b) {
    super.onCreate(b);
    storage = new Storage(this);
    getWindow().getDecorView().setSystemUiVisibility(5894);
    showOpening();
    io.execute(
        () -> {
          try {
            JSONObject j = storage.read("source");
            if (!j.has("address")) {
              runOnUiThread(this::connection);
              return;
            }
            Catalog.Source s = Catalog.Source.from(j);
            Storage.State st = new Storage.State(storage.read("state-" + s.scope()));
            runOnUiThread(
                () -> {
                  if (destroyed) return;
                  source = s;
                  state = st;
                  applyTheme();
                  dashboard();
                  load();
                });
          } catch (Exception e) {
            runOnUiThread(
                () ->
                    recovery(
                        "Saved connection could not be opened. Retry, or remove it and"
                            + " reconnect."));
          }
        });
  }

  void applyTheme() {
    String theme = state.root.optString("theme", "dark");
    boolean light =
        theme.equals("light")
            || theme.equals("system")
                && (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                    != Configuration.UI_MODE_NIGHT_YES;
    if (light) {
      bg = 0xfff6f8f5;
      surface = 0xffffffff;
      fg = 0xff19251d;
      muted = 0xff626e64;
      accent = 0xff2f663c;
    } else {
      bg = 0xff101211;
      surface = 0xff1b201d;
      fg = 0xfff5f7f4;
      muted = 0xff929c94;
      accent = 0xffbddfb7;
    }
  }

  LinearLayout column() {
    LinearLayout l = new LinearLayout(this);
    l.setOrientation(LinearLayout.VERTICAL);
    return l;
  }

  LinearLayout row() {
    LinearLayout l = new LinearLayout(this);
    l.setOrientation(LinearLayout.HORIZONTAL);
    l.setGravity(Gravity.CENTER_VERTICAL);
    return l;
  }

  TextView text(String s, int size, int color) {
    TextView t = new TextView(this);
    t.setText(s);
    t.setTextSize(size);
    t.setTextColor(color);
    t.setFontFeatureSettings("kern");
    t.setPadding(0, dp(4), 0, dp(4));
    return t;
  }

  TextView heading(String s, int size) {
    TextView t = text(s, size, fg);
    t.setTypeface(null, Typeface.BOLD);
    return t;
  }

  GradientDrawable shape(int color, int stroke) {
    GradientDrawable d = new GradientDrawable();
    d.setColor(color);
    d.setCornerRadius(dp(9));
    if (stroke != 0) d.setStroke(dp(2), stroke);
    return d;
  }

  Button button(String title, Runnable action) {
    Button b = new Button(this);
    b.setText(title);
    b.setTextSize(13);
    b.setTextColor(fg);
    b.setAllCaps(false);
    b.setMinHeight(dp(44));
    b.setMinimumWidth(dp(76));
    b.setPadding(dp(14), dp(4), dp(14), dp(4));
    b.setBackground(shape(surface, 0));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-2, dp(44));
    p.setMargins(dp(3), dp(3), dp(3), dp(3));
    b.setLayoutParams(p);
    b.setOnFocusChangeListener(
        (v, f) -> {
          v.setBackground(shape(f ? accent : surface, f ? accent : 0));
          b.setTextColor(f ? bg : fg);
        });
    b.setOnClickListener(v -> action.run());
    return b;
  }

  void mount(LinearLayout layout) {
    layout.setBackgroundColor(bg);
    layout.setPadding(dp(40), dp(28), dp(40), dp(28));
    setContentView(layout);
    root = layout;
  }

  void showOpening() {
    LinearLayout l = column();
    mount(l);
    l.setGravity(Gravity.CENTER);
    l.addView(heading("▶  Luma", 42));
    l.addView(text("Opening your library…", 18, muted));
  }

  void recovery(String message) {
    LinearLayout l = column();
    mount(l);
    l.addView(heading("Your library is safe", 30));
    l.addView(text(message, 18, muted));
    l.addView(button("Retry", () -> recreate()));
    l.addView(
        button(
            "Remove saved connection",
            () -> {
              io.execute(storage::disconnect);
              source = null;
              connection();
            }));
  }

  EditText field(String hint, boolean password) {
    EditText e = new EditText(this);
    e.setSingleLine();
    e.setHint(hint);
    e.setTextColor(fg);
    e.setHintTextColor(muted);
    e.setTextSize(16);
    e.setPadding(dp(16), 0, dp(16), 0);
    e.setBackground(shape(surface, 0));
    e.setInputType(
        password
            ? InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD
            : InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, dp(48));
    p.bottomMargin = dp(10);
    e.setLayoutParams(p);
    e.setOnFocusChangeListener((v, f) -> v.setBackground(shape(surface, f ? accent : 0)));
    return e;
  }

  void connection() {
    generation++;
    loading = false;
    detail = false;
    LinearLayout outer = row();
    mount(outer);
    LinearLayout intro = column();
    intro.setPadding(0, 0, dp(32), 0);
    outer.addView(intro, new LinearLayout.LayoutParams(0, -1, 1));
    intro.addView(heading("▶  Luma", 36));
    intro.addView(text("YOUR LIBRARY. BIGGER.", 12, accent));
    intro.addView(heading("A little closer\nto what you love.", 36));
    intro.addView(
        text("Live TV, movies and series.\nOne calm place for everything you watch.", 18, muted));
    intro.addView(
        text(
            "Made for your remote.\n"
                + "Bring your own provider or M3U playlist.\n"
                + "Luma does not supply any content.",
            14,
            muted));
    ScrollView formScroll = new ScrollView(this);
    formScroll.setFillViewport(true);
    outer.addView(formScroll, new LinearLayout.LayoutParams(0, -1, 1));
    LinearLayout form = column();
    formScroll.addView(form);
    form.addView(heading("Connect your library", 26));
    form.addView(text("Credentials are encrypted on this device.", 14, muted));
    final boolean[] playlist = {source != null && source.type.equals("playlist")};
    LinearLayout tabs = row();
    form.addView(tabs);
    EditText address = field("https://your-provider.example", false),
        username = field("Username", false),
        password = field("Password", true),
        name = field("Library name (optional)", false);
    tabs.addView(
        button(
            "Provider login",
            () -> {
              playlist[0] = false;
              username.setVisibility(View.VISIBLE);
              password.setVisibility(View.VISIBLE);
              address.setHint("Server URL");
            }));
    tabs.addView(
        button(
            "M3U playlist",
            () -> {
              playlist[0] = true;
              username.setVisibility(View.GONE);
              password.setVisibility(View.GONE);
              address.setHint("Playlist URL");
            }));
    form.addView(address);
    form.addView(username);
    form.addView(password);
    form.addView(name);
    if (source != null) {
      address.setText(source.address);
      username.setText(source.username);
      password.setText(source.password);
      name.setText(source.name);
    }
    if (playlist[0]) {
      username.setVisibility(View.GONE);
      password.setVisibility(View.GONE);
    }
    TextView error = text("", 13, 0xffdc9e91);
    form.addView(error);
    form.addView(
        button(
            "Connect library  →",
            () -> {
              String a = address.getText().toString().trim();
              if (a.isEmpty()
                  || (!playlist[0] && (username.length() == 0 || password.length() == 0))) {
                error.setText("Enter the address and your provider credentials.");
                return;
              }
              Catalog.Source s = new Catalog.Source();
              s.type = playlist[0] ? "playlist" : "xtream";
              s.address = a.contains("://") ? a : "https://" + a;
              s.username = username.getText().toString().trim();
              s.password = password.getText().toString();
              s.name = name.length() == 0 ? "My library" : name.getText().toString();
              if (!s.address.startsWith("https://")
                  && !s.address.startsWith("http://")
                  && !s.address.startsWith("content://")) {
                error.setText("Use an HTTP or HTTPS address.");
                return;
              }
              source = s;
              demo = false;
              state = new Storage.State(new JSONObject());
              catalog = new Catalog();
              dashboard();
              load();
            }));
    form.addView(
        button(
            "Choose a local M3U file",
            () -> {
              Intent i =
                  new Intent(Intent.ACTION_OPEN_DOCUMENT)
                      .setType("*/*")
                      .addCategory(Intent.CATEGORY_OPENABLE)
                      .addFlags(
                          Intent.FLAG_GRANT_READ_URI_PERMISSION
                              | Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
              try {
                startActivityForResult(i, 71);
              } catch (ActivityNotFoundException e) {
                error.setText("This TV has no file picker. Use a playlist URL instead.");
              }
            }));
    if (BuildConfig.DEBUG) form.addView(button("Preview with sample library", this::demo));
    if (source != null) form.addView(button("Back to library", this::dashboard));
    tabs.getChildAt(0).requestFocus();
    getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
  }

  @Override
  protected void onActivityResult(int request, int result, Intent data) {
    super.onActivityResult(request, result, data);
    if (request == 71 && result == RESULT_OK && data != null && data.getData() != null) {
      try {
        getContentResolver()
            .takePersistableUriPermission(data.getData(), Intent.FLAG_GRANT_READ_URI_PERMISSION);
      } catch (Exception ignored) {
      }
      source = new Catalog.Source();
      source.type = "playlist";
      source.address = data.getData().toString();
      source.name = "M3U library";
      demo = false;
      dashboard();
      load();
    }
  }

  void demo() {
    demo = true;
    source = new Catalog.Source();
    source.type = "demo";
    source.name = "Sample library";
    catalog = Demo.catalog();
    state = new Storage.State(new JSONObject());
    defaults();
    try {
      for (int n : new int[] {0, 1, 6, 7}) {
        Catalog.Item i = catalog.items.get(n);
        state.record(i, 720000 + n * 40000, 5400000);
      }
      state.favorites.add(catalog.items.get(1).id);
    } catch (Exception ignored) {
    }
    dashboard();
  }

  void defaults() {
    if (state.shelves != null) return;
    state.shelves = new JSONArray();
    for (String[] row :
        new String[][] {
          {"Hollywood Movies", "movie", "hollywood|english"},
          {"Bollywood Movies", "movie", "bollywood|hindi"},
          {"Hollywood TV Series", "series", "hollywood|english|usa|british|uk"},
          {"Bollywood TV Series", "series", "bollywood|hindi|indian web"}
        }) {
      JSONObject s = new JSONObject();
      JSONArray cats = new JSONArray();
      for (Map.Entry<String, String> e : catalog.categories.entrySet())
        if (e.getKey().startsWith(row[1] + ":")
            && e.getValue().toLowerCase(Locale.ROOT).matches(".*(" + row[2] + ").*"))
          cats.put(e.getKey());
      try {
        s.put("id", UUID.randomUUID().toString())
            .put("title", row[0])
            .put("categories", cats)
            .put("items", new JSONArray());
        state.shelves.put(s);
      } catch (Exception ignored) {
      }
    }
  }

  void load() {
    int ticket = ++generation;
    loading = true;
    statusMessage("Loading your library… You can browse saved history meanwhile.");
    Catalog.Source s = source;
    io.execute(
        () -> {
          try {
            Storage.State st = new Storage.State(storage.read("state-" + s.scope()));
            Catalog c;
            if (s.address.startsWith("content://")) {
              try (java.io.InputStream in =
                      getContentResolver().openInputStream(android.net.Uri.parse(s.address));
                  java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream()) {
                byte[] b = new byte[16384];
                int n, total = 0;
                while ((n = in.read(b)) != -1) {
                  total += n;
                  if (total > 100000000) throw new java.io.IOException("Playlist is too large.");
                  out.write(b, 0, n);
                }
                c = Catalog.parse(out.toString("UTF-8"), s.address);
              }
            } else c = new Catalog.Provider(s).load();
            if (destroyed || ticket != generation) return;
            storage.write("source", s.json());
            Catalog loaded = c;
            runOnUiThread(
                () -> {
                  if (destroyed || ticket != generation) return;
                  catalog = loaded;
                  state = st;
                  defaults();
                  loading = false;
                  applyTheme();
                  dashboard();
                  save();
                });
          } catch (Exception e) {
            runOnUiThread(
                () -> {
                  if (destroyed || ticket != generation) return;
                  loading = false;
                  statusMessage(
                      "Could not load the library. Check your connection, then Retry or Update"
                          + " connection.");
                });
          }
        });
  }

  void statusMessage(String s) {
    if (status != null) status.setText(s);
  }

  void save() {
    if (source == null || demo) return;
    try {
      JSONObject j = new JSONObject(state.json().toString());
      String name = "state-" + source.scope();
      io.execute(
          () -> {
            try {
              storage.write(name, j);
            } catch (Exception e) {
              runOnUiThread(
                  () ->
                      statusMessage("Could not save watch state. Check available device storage."));
            }
          });
    } catch (Exception ignored) {
    }
  }

  void dashboard() {
    if (destroyed) return;
    detail = false;
    LinearLayout layout = row();
    mount(layout);
    layout.setPadding(dp(32), dp(24), dp(32), dp(24));
    sidebar = column();
    sidebar.setPadding(0, 0, dp(20), 0);
    layout.addView(sidebar, new LinearLayout.LayoutParams(dp(165), -1));
    sidebar.addView(heading("▶ Luma", 28));
    sidebar.addView(text(demo ? "SAMPLE LIBRARY" : "YOUR PERSONAL PLAYER", 10, accent));
    for (String d : destinations) {
      Button b =
          button(
              (d.equals(destination) ? "●  " : "") + d,
              () -> {
                destination = d;
                category = "";
                search = "";
                year = 0;
                dashboard();
              });
      b.setLayoutParams(new LinearLayout.LayoutParams(-1, dp(43)));
      sidebar.addView(b);
    }
    TextView foot =
        text(
            "ANDROID TV\n"
                + (demo ? "Fictional preview titles" : source == null ? "" : source.name),
            11,
            muted);
    foot.setPadding(0, dp(14), 0, 0);
    sidebar.addView(foot);
    content = column();
    layout.addView(content, new LinearLayout.LayoutParams(0, -1, 1));
    LinearLayout title = row();
    content.addView(title);
    TextView name = heading(destination, 30);
    title.addView(name, new LinearLayout.LayoutParams(0, -2, 1));
    title.addView(
        button(
            "↻ Refresh",
            () -> {
              if (demo) {
                demo();
                return;
              }
              if (!loading) load();
            }));
    title.addView(button("Connection", this::connection));
    status =
        text(
            loading
                ? "Loading your library…"
                : demo
                    ? "Interface preview · fictional sample titles · no channels supplied"
                    : catalog.items.size()
                        + " titles · "
                        + catalog.categories.size()
                        + " categories",
            11,
            muted);
    content.addView(status);
    if (destination.equals("Settings")) {
      settings();
      return;
    }
    LinearLayout tools = row();
    content.addView(tools);
    EditText query = field("Search titles…", false);
    query.setText(search);
    query.setImeOptions(android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH);
    tools.addView(query, new LinearLayout.LayoutParams(0, dp(42), 1));
    query.addTextChangedListener(
        new TextWatcher() {
          Runnable task;

          public void beforeTextChanged(CharSequence s, int a, int c, int f) {}

          public void onTextChanged(CharSequence s, int a, int before, int count) {
            search = s.toString();
            if (task != null) main.removeCallbacks(task);
            task = () -> populate();
            main.postDelayed(task, 220);
          }

          public void afterTextChanged(Editable e) {}
        });
    tools.addView(button("Category", this::categories));
    tools.addView(button("Year", this::years));
    tools.addView(
        button(
            reverse ? "Z–A" : "A–Z",
            () -> {
              reverse = !reverse;
              populate();
            }));
    if (destination.equals("History"))
      tools.addView(
          button(
              "Clear history",
              () ->
                  new AlertDialog.Builder(this)
                      .setTitle("Clear watch history?")
                      .setMessage("This removes all resume positions for this source.")
                      .setNegativeButton("Cancel", null)
                      .setPositiveButton(
                          "Clear",
                          (d, w) -> {
                            state.history = new JSONObject();
                            save();
                            populate();
                          })
                      .show()));
    if (destination.equals("Discover")) {
      LinearLayout welcome = row();
      welcome.setPadding(dp(18), dp(10), dp(14), dp(10));
      welcome.setBackground(shape(surface, 0));
      LinearLayout copy = column();
      copy.addView(text("MAKE YOURSELF AT HOME", 10, accent));
      copy.addView(heading("Your world. Ready to play.", 24));
      copy.addView(text("Pick up where you left off, or find your next favorite.", 12, muted));
      welcome.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));
      welcome.addView(button("Edit Discover", this::manageShelves));
      content.addView(welcome);
    }
    grid = new RecyclerView(this);
    grid.setClipToPadding(false);
    grid.setPadding(dp(5), dp(8), dp(5), dp(10));
    grid.setItemAnimator(null);
    grid.setItemViewCacheSize(10);
    GridLayoutManager manager = new GridLayoutManager(this, 4);
    manager.setSpanSizeLookup(
        new GridLayoutManager.SpanSizeLookup() {
          public int getSpanSize(int position) {
            return adapter != null
                    && position < adapter.rows.size()
                    && adapter.rows.get(position) instanceof String
                ? 4
                : 1;
          }
        });
    grid.setLayoutManager(manager);
    adapter = new Cards();
    grid.setAdapter(adapter);
    content.addView(grid, new LinearLayout.LayoutParams(-1, 0, 1));
    populate();
    query.clearFocus();
    sidebar
        .getChildAt(Math.max(2, 2 + Arrays.asList(destinations).indexOf(destination)))
        .requestFocus();
  }

  String kind() {
    return destination.equals("Live TV")
        ? "live"
        : destination.equals("Movies") ? "movie" : destination.equals("Series") ? "series" : "";
  }

  boolean matches(Catalog.Item i) {
    return (search.isEmpty()
            || i.title.toLowerCase(Locale.ROOT).contains(search.toLowerCase(Locale.ROOT)))
        && (category.isEmpty() || category.equals(i.category))
        && (year == 0 || i.kind.equals("live") || i.releaseYear() == year);
  }

  static boolean has(JSONArray a, String s) {
    if (a != null) for (int k = 0; k < a.length(); k++) if (s.equals(a.optString(k))) return true;
    return false;
  }

  boolean inShelf(JSONObject s, Catalog.Item i) {
    return s.optBoolean("favorites")
        ? state.favorites.contains(i.id)
            && (!s.has("kinds") || has(s.optJSONArray("kinds"), i.kind))
        : has(s.optJSONArray("categories"), i.category) || has(s.optJSONArray("items"), i.id);
  }

  void populate() {
    if (grid == null || adapter == null) return;
    int ticket = ++queryGeneration;
    ArrayList<Catalog.Item> items = new ArrayList<>(catalog.items);
    String dest = destination, k = kind(), term = search.toLowerCase(Locale.ROOT), cat = category;
    int selectedYear = year;
    boolean descending = reverse;
    Storage.State snapshot;
    try {
      snapshot = new Storage.State(new JSONObject(state.json().toString()));
    } catch (Exception e) {
      return;
    }
    java.util.function.Predicate<Catalog.Item> test =
        i ->
            (term.isEmpty() || i.title.toLowerCase(Locale.ROOT).contains(term))
                && (cat.isEmpty() || cat.equals(i.category))
                && (selectedYear == 0 || i.kind.equals("live") || i.releaseYear() == selectedYear);
    filter.execute(
        () -> {
          List<Object> rows = new ArrayList<>();
          List<Catalog.Item> matches = new ArrayList<>();
          for (Catalog.Item i : items)
            if (test.test(i)
                && (k.isEmpty() || i.kind.equals(k))
                && (!dest.equals("Favorites") || snapshot.favorites.contains(i.id))) matches.add(i);
          Collections.sort(
              matches,
              (a, b) ->
                  descending
                      ? b.title.compareToIgnoreCase(a.title)
                      : a.title.compareToIgnoreCase(b.title));
          if (dest.equals("History")) {
            for (Catalog.Item i : snapshot.history(false)) if (test.test(i)) rows.add(i);
          } else if (dest.equals("Discover")) {
            List<Catalog.Item> progress = snapshot.history(true);
            if (!progress.isEmpty()) {
              rows.add("Continue watching");
              for (Catalog.Item i : progress) if (test.test(i)) rows.add(i);
            }
            JSONArray shelves = snapshot.shelves;
            if (shelves != null)
              for (int n = 0; n < shelves.length(); n++) {
                JSONObject s = shelves.optJSONObject(n);
                if (s == null) continue;
                List<Catalog.Item> shelf = new ArrayList<>();
                for (Catalog.Item i : matches)
                  if (s.optBoolean("favorites")
                      ? snapshot.favorites.contains(i.id)
                          && (!s.has("kinds") || has(s.optJSONArray("kinds"), i.kind))
                      : has(s.optJSONArray("categories"), i.category)
                          || has(s.optJSONArray("items"), i.id)) shelf.add(i);
                rows.add(s.optString("title", "Untitled section") + "  ·  " + shelf.size());
                int end = Math.min(shelf.size(), 12);
                rows.addAll(shelf.subList(0, end));
                if (shelf.size() > end) rows.add(new ShelfLink(s));
              }
            if (rows.isEmpty()) {
              rows.add("Your library, your way");
              rows.add(
                  "Use Edit Discover to create rows from categories, individual titles, or"
                      + " favorites.");
            }
          } else rows.addAll(matches);
          if (rows.isEmpty())
            rows.add("No titles to show. Try another filter or connect your library.");
          main.post(
              () -> {
                if (destroyed || detail || ticket != queryGeneration) return;
                adapter.rows = rows;
                adapter.notifyDataSetChanged();
                statusMessage(
                    (loading ? "Loading library… · " : "")
                        + (demo ? "Sample library · fictional titles · " : "")
                        + (dest.equals("Discover")
                            ? "Your curated shelves"
                            : rows.size() + " results")
                        + (category.isEmpty() ? "" : " · " + catalog.categories.get(category))
                        + (year == 0 ? "" : " · " + year));
              });
        });
  }

  static class ShelfLink {
    JSONObject shelf;

    ShelfLink(JSONObject s) {
      shelf = s;
    }
  }

  class Cards extends RecyclerView.Adapter<RecyclerView.ViewHolder> {
    List<Object> rows = new ArrayList<>();

    public int getItemCount() {
      return rows.size();
    }

    public int getItemViewType(int p) {
      return rows.get(p) instanceof String ? 1 : 0;
    }

    public RecyclerView.ViewHolder onCreateViewHolder(ViewGroup parent, int type) {
      if (type == 1) {
        TextView t = heading("", 19);
        t.setPadding(dp(3), dp(14), 0, dp(8));
        t.setLayoutParams(new RecyclerView.LayoutParams(-1, -2));
        return new RecyclerView.ViewHolder(t) {};
      }
      LinearLayout card = column();
      card.setFocusable(true);
      card.setClickable(true);
      card.setPadding(dp(7), dp(7), dp(7), dp(7));
      RecyclerView.LayoutParams p = new RecyclerView.LayoutParams(-1, dp(208));
      p.setMargins(dp(3), dp(4), dp(3), dp(6));
      card.setLayoutParams(p);
      card.setBackground(shape(surface, 0));
      Artwork art = new Artwork(MainActivity.this);
      card.addView(art, new LinearLayout.LayoutParams(-1, dp(146)));
      TextView title = text("", 13, fg);
      title.setMaxLines(1);
      title.setEllipsize(android.text.TextUtils.TruncateAt.END);
      card.addView(title);
      TextView sub = text("", 10, muted);
      sub.setMaxLines(1);
      card.addView(sub);
      card.setOnFocusChangeListener(
          (v, f) -> {
            v.setBackground(shape(surface, f ? accent : 0));
            v.setElevation(f ? dp(4) : 0);
          });
      return new RecyclerView.ViewHolder(card) {};
    }

    public void onBindViewHolder(RecyclerView.ViewHolder h, int p) {
      Object data = rows.get(p);
      if (data instanceof String) {
        ((TextView) h.itemView).setText((String) data);
        return;
      }
      LinearLayout card = (LinearLayout) h.itemView;
      Artwork art = (Artwork) card.getChildAt(0);
      TextView title = (TextView) card.getChildAt(1), sub = (TextView) card.getChildAt(2);
      if (data instanceof ShelfLink) {
        JSONObject shelf = ((ShelfLink) data).shelf;
        Catalog.Item fake = new Catalog.Item();
        fake.id = "all";
        fake.title = "View all →";
        fake.kind = "movie";
        art.bind(fake);
        title.setText("View all titles →");
        sub.setText(shelf.optString("title"));
        card.setOnClickListener(v -> openShelf(shelf));
        return;
      }
      Catalog.Item i = (Catalog.Item) data;
      art.bind(i);
      title.setText(i.title);
      String tag =
          i.kind.equals("live")
              ? "● LIVE"
              : i.releaseYear() == 0
                  ? i.kind.toUpperCase(Locale.ROOT)
                  : String.valueOf(i.releaseYear());
      sub.setText(
          (state.favorites.contains(i.id) ? "♥  " : "")
              + tag
              + (i.series.isEmpty() ? "" : "  S" + i.season + " · E" + i.episode)
              + (state.position(i.id) > 0 ? "  · Resume" : ""));
      card.setContentDescription(i.label() + ", " + tag);
      card.setOnClickListener(
          v -> {
            lastFocused = Math.max(0, h.getBindingAdapterPosition());
            details(i);
          });
      card.setOnLongClickListener(
          v -> {
            favorite(i);
            return true;
          });
    }
  }

  void favorite(Catalog.Item i) {
    if (!state.favorites.add(i.id)) state.favorites.remove(i.id);
    save();
    Toast.makeText(
            this,
            state.favorites.contains(i.id) ? "Added to favorites" : "Removed from favorites",
            Toast.LENGTH_SHORT)
        .show();
    if (adapter != null) adapter.notifyDataSetChanged();
  }

  void categories() {
    List<String> ids = new ArrayList<>(), labels = new ArrayList<>();
    ids.add("");
    labels.add("All categories");
    String k = kind();
    for (Map.Entry<String, String> e : catalog.categories.entrySet())
      if (k.isEmpty() || e.getKey().startsWith(k + ":")) {
        ids.add(e.getKey());
        labels.add(e.getValue());
      }
    LinearLayout l = column();
    EditText q = field("Search categories…", false);
    q.setText(categorySearch);
    l.addView(q);
    ListView list = new ListView(this);
    l.addView(list, new LinearLayout.LayoutParams(-1, dp(260)));
    List<String> visibleIDs = new ArrayList<>(), visibleLabels = new ArrayList<>();
    ArrayAdapter<String> a =
        new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, visibleLabels);
    list.setAdapter(a);
    Runnable refresh =
        () -> {
          visibleIDs.clear();
          visibleLabels.clear();
          for (int n = 0; n < ids.size(); n++)
            if (labels
                .get(n)
                .toLowerCase(Locale.ROOT)
                .contains(q.getText().toString().toLowerCase(Locale.ROOT))) {
              visibleIDs.add(ids.get(n));
              visibleLabels.add(labels.get(n));
            }
          a.notifyDataSetChanged();
        };
    refresh.run();
    q.addTextChangedListener(
        watcher(
            () -> {
              categorySearch = q.getText().toString();
              refresh.run();
            }));
    AlertDialog dialog =
        new AlertDialog.Builder(this)
            .setTitle("Provider categories")
            .setView(l)
            .setNegativeButton("Close", null)
            .create();
    list.setOnItemClickListener(
        (v, c, p, id) -> {
          category = visibleIDs.get(p);
          dialog.dismiss();
          populate();
        });
    dialog.show();
  }

  TextWatcher watcher(Runnable r) {
    return new TextWatcher() {
      public void beforeTextChanged(CharSequence s, int a, int c, int f) {}

      public void onTextChanged(CharSequence s, int a, int b, int c) {
        r.run();
      }

      public void afterTextChanged(Editable e) {}
    };
  }

  void years() {
    TreeSet<Integer> years = new TreeSet<>(Collections.reverseOrder());
    for (Catalog.Item i : catalog.items)
      if (!i.kind.equals("live") && i.releaseYear() > 0) years.add(i.releaseYear());
    List<Integer> values = new ArrayList<>();
    values.add(0);
    values.addAll(years);
    String[] labels = new String[values.size()];
    for (int n = 0; n < values.size(); n++)
      labels[n] = values.get(n) == 0 ? "All years" : values.get(n).toString();
    new AlertDialog.Builder(this)
        .setTitle("Release year")
        .setItems(
            labels,
            (d, w) -> {
              year = values.get(w);
              populate();
            })
        .show();
  }

  void openShelf(JSONObject shelf) {
    detail = true;
    queryGeneration++;
    LinearLayout l = column();
    mount(l);
    l.addView(button("← Discover", this::dashboard));
    l.addView(heading(shelf.optString("title"), 28));
    RecyclerView rv = new RecyclerView(this);
    GridLayoutManager lm = new GridLayoutManager(this, 5);
    rv.setLayoutManager(lm);
    Cards a = new Cards();
    for (Catalog.Item i : catalog.items) if (inShelf(shelf, i) && matches(i)) a.rows.add(i);
    rv.setAdapter(a);
    l.addView(rv, new LinearLayout.LayoutParams(-1, 0, 1));
    rv.requestFocus();
  }

  void details(Catalog.Item i) {
    detail = true;
    queryGeneration++;
    selected = i;
    currentEpisodes.clear();
    renderDetail(i, null);
    if (i.kind.equals("series") && i.series.isEmpty()) {
      List<Catalog.Item> cached = catalog.episodes.get(i.id);
      if (cached != null) {
        currentEpisodes.addAll(cached);
        renderDetail(i, null);
      } else if (!demo) {
        int ticket = ++generation;
        io.execute(
            () -> {
              try {
                List<Catalog.Item> es = new Catalog.Provider(source).episodes(i);
                runOnUiThread(
                    () -> {
                      if (destroyed || ticket != generation || selected != i || !detail) return;
                      catalog.episodes.put(i.id, es);
                      currentEpisodes.addAll(es);
                      renderDetail(i, null);
                    });
              } catch (Exception e) {
                runOnUiThread(
                    () -> {
                      if (selected == i && detail)
                        renderDetail(i, "Episodes could not be loaded. Go back and retry.");
                    });
              }
            });
      }
    } else if (i.kind.equals("movie") && !demo && source.type.equals("xtream")) {
      io.execute(
          () -> {
            try {
              Catalog.Item enriched = new Catalog.Provider(source).details(i);
              runOnUiThread(
                  () -> {
                    if (selected == i && detail) renderDetail(enriched, null);
                  });
            } catch (Exception ignored) {
            }
          });
    }
  }

  void renderDetail(Catalog.Item i, String error) {
    LinearLayout l = column();
    mount(l);
    Button back =
        button(
            "← Back to library",
            () -> {
              dashboard();
              grid.scrollToPosition(lastFocused);
            });
    l.addView(back);
    LinearLayout info = row();
    l.addView(info);
    Artwork art = new Artwork(this);
    art.bind(i);
    info.addView(art, new LinearLayout.LayoutParams(dp(156), dp(208)));
    LinearLayout copy = column();
    copy.setPadding(dp(24), 0, 0, 0);
    info.addView(copy, new LinearLayout.LayoutParams(0, -2, 1));
    copy.addView(
        text(
            i.kind.toUpperCase(Locale.ROOT)
                + (i.releaseYear() > 0 ? "  /  " + i.releaseYear() : "")
                + (i.rating.isEmpty() ? "" : "  /  ★ " + i.rating),
            12,
            accent));
    copy.addView(heading(i.label(), 30));
    TextView desc =
        text(
            i.summary.isEmpty() ? "No description supplied by your provider." : i.summary,
            15,
            muted);
    desc.setMaxLines(4);
    copy.addView(desc);
    copy.addView(
        button(
            "Full description",
            () ->
                new AlertDialog.Builder(this)
                    .setTitle(i.title)
                    .setMessage(i.summary.isEmpty() ? "No description available." : i.summary)
                    .setPositiveButton("Close", null)
                    .show()));
    LinearLayout actions = row();
    copy.addView(actions);
    if (!i.kind.equals("series") || !i.series.isEmpty()) {
      actions.addView(
          button(
              state.position(i.id) > 0 ? "▶ Resume" : "▶ Play",
              () -> play(i, Collections.singletonList(i), false)));
      if (state.position(i.id) > 0)
        actions.addView(button("Start over", () -> play(i, Collections.singletonList(i), true)));
    }
    actions.addView(
        button(
            state.favorites.contains(i.id) ? "♥ Favorited" : "♡ Favorite",
            () -> {
              favorite(i);
              renderDetail(i, null);
            }));
    if (state.history.has(i.id))
      actions.addView(
          button(
              "Remove history",
              () -> {
                state.history.remove(i.id);
                save();
                renderDetail(i, null);
              }));
    if (i.kind.equals("series") && i.series.isEmpty()) {
      if (error != null) {
        l.addView(text(error, 15, 0xffdc9e91));
      } else if (currentEpisodes.isEmpty()) {
        l.addView(
            text(
                catalog.episodes.containsKey(i.id)
                    ? "No episodes supplied by this source."
                    : "Loading episodes…",
                16,
                muted));
      } else {
        TreeSet<Integer> seasons = new TreeSet<>();
        for (Catalog.Item e : currentEpisodes) seasons.add(e.season);
        LinearLayout seasonRow = row();
        l.addView(seasonRow);
        ListView list = new ListView(this);
        l.addView(list, new LinearLayout.LayoutParams(-1, 0, 1));
        List<Catalog.Item> visible = new ArrayList<>();
        ArrayAdapter<String> a =
            new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, new ArrayList<>());
        list.setAdapter(a);
        java.util.function.IntConsumer choose =
            n -> {
              visible.clear();
              a.clear();
              for (Catalog.Item e : currentEpisodes)
                if (e.season == n) {
                  visible.add(e);
                  a.add(
                      (state.completed(e.id) ? "✓ " : state.position(e.id) > 0 ? "↻ " : "")
                          + e.label());
                }
              a.notifyDataSetChanged();
            };
        for (int season : seasons)
          seasonRow.addView(button("Season " + season, () -> choose.accept(season)));
        choose.accept(seasons.first());
        list.setOnItemClickListener((v, c, p, id) -> episodeDialog(visible.get(p)));
      }
    }
    back.requestFocus();
  }

  void episodeDialog(Catalog.Item e) {
    new AlertDialog.Builder(this)
        .setTitle(e.label())
        .setMessage(e.summary.isEmpty() ? "No episode description supplied." : e.summary)
        .setPositiveButton(
            state.position(e.id) > 0 ? "Resume" : "Play", (d, w) -> play(e, currentEpisodes, false))
        .setNeutralButton("Start over", (d, w) -> play(e, currentEpisodes, true))
        .setNegativeButton("Cancel", null)
        .show();
  }

  void play(Catalog.Item i, List<Catalog.Item> queue, boolean restart) {
    if (demo) {
      new AlertDialog.Builder(this)
          .setTitle("Sample library")
          .setMessage("These titles demonstrate the interface. Connect your own provider to watch.")
          .setPositiveButton("Close", null)
          .show();
      return;
    }
    if (i.url.isEmpty() && i.providerID.isEmpty()) {
      Toast.makeText(this, "No playback address available", Toast.LENGTH_LONG).show();
      return;
    }
    try {
      JSONArray arr = new JSONArray();
      for (Catalog.Item e : queue) arr.put(e.json());
      JSONObject session =
          new JSONObject()
              .put("source", source.json())
              .put("queue", arr)
              .put("selected", i.id)
              .put("restart", restart);
      io.execute(
          () -> {
            try {
              storage.write("playback", session);
              runOnUiThread(() -> startActivity(new Intent(this, PlaybackActivity.class)));
            } catch (Exception ex) {
              runOnUiThread(
                  () ->
                      Toast.makeText(this, "Could not prepare playback", Toast.LENGTH_LONG).show());
            }
          });
    } catch (Exception ignored) {
    }
  }

  void settings() {
    ScrollView scroll = new ScrollView(this);
    content.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
    LinearLayout settings = column();
    scroll.addView(settings);
    settings.addView(heading("Make Luma yours", 23));
    settings.addView(text("Appearance, playback and your personal Discover rows.", 15, muted));
    settings.addView(
        button(
            "Appearance: " + state.root.optString("theme", "dark"),
            () ->
                new AlertDialog.Builder(this)
                    .setTitle("Appearance")
                    .setItems(
                        new String[] {"Dark", "Light", "System"},
                        (d, w) -> {
                          try {
                            state.root.put("theme", new String[] {"dark", "light", "system"}[w]);
                          } catch (Exception ignored) {
                          }
                          applyTheme();
                          save();
                          dashboard();
                        })
                    .show()));
    settings.addView(
        button(
            "Autoplay next episode: " + (state.root.optBoolean("autoplay", true) ? "On" : "Off"),
            () -> {
              try {
                state.root.put("autoplay", !state.root.optBoolean("autoplay", true));
              } catch (Exception ignored) {
              }
              save();
              dashboard();
            }));
    settings.addView(button("Customize Discover", this::manageShelves));
    settings.addView(button("Update connection", this::connection));
    settings.addView(
        button(
            "Disconnect",
            () ->
                new AlertDialog.Builder(this)
                    .setTitle("Disconnect this library?")
                    .setMessage(
                        "The saved login is removed. Local favorites and progress are kept for"
                            + " reconnection.")
                    .setNegativeButton("Cancel", null)
                    .setPositiveButton(
                        "Disconnect",
                        (d, w) -> {
                          generation++;
                          io.execute(storage::disconnect);
                          source = null;
                          catalog = new Catalog();
                          state = new Storage.State(new JSONObject());
                          connection();
                        })
                    .show()));
    settings.addView(
        text(
            "Luma for Android TV · 1.0\n"
                + "No content, channels or subscriptions are included.\n"
                + "Use content you are authorized to access.\n"
                + "HTTP providers are supported; use HTTPS where available.",
            13,
            muted));
  }

  void manageShelves() {
    List<String> names = new ArrayList<>();
    names.add("+ New custom section");
    names.add("+ Favorite TV Channels");
    names.add("+ Favorite Movies");
    names.add("+ Favorite Series");
    for (int k = 0; k < state.shelves.length(); k++)
      names.add(state.shelves.optJSONObject(k).optString("title", "Untitled"));
    new AlertDialog.Builder(this)
        .setTitle("Customize Discover")
        .setItems(
            names.toArray(new String[0]),
            (d, w) -> {
              if (w >= 4) {
                shelfActions(w - 4);
                return;
              }
              JSONObject s = new JSONObject();
              try {
                s.put("id", UUID.randomUUID().toString())
                    .put("title", w == 0 ? "New section" : names.get(w).substring(2))
                    .put("categories", new JSONArray())
                    .put("items", new JSONArray());
                if (w > 0)
                  s.put("favorites", true)
                      .put(
                          "kinds",
                          new JSONArray().put(new String[] {"", "live", "movie", "series"}[w]));
                state.shelves.put(s);
                save();
                editShelf(state.shelves.length() - 1);
              } catch (Exception ignored) {
              }
            })
        .setNegativeButton("Close", null)
        .show();
  }

  void shelfActions(int n) {
    new AlertDialog.Builder(this)
        .setTitle(state.shelves.optJSONObject(n).optString("title"))
        .setItems(
            new String[] {"Edit section", "Move up", "Move down", "Remove section"},
            (d, w) -> {
              if (w == 0) {
                editShelf(n);
                return;
              }
              List<JSONObject> values = new ArrayList<>();
              for (int k = 0; k < state.shelves.length(); k++)
                values.add(state.shelves.optJSONObject(k));
              if (w == 3) values.remove(n);
              else {
                int next = w == 1 ? n - 1 : n + 1;
                if (next >= 0 && next < values.size()) Collections.swap(values, n, next);
              }
              state.shelves = new JSONArray(values);
              save();
              dashboard();
              manageShelves();
            })
        .show();
  }

  void editShelf(int n) {
    JSONObject s = state.shelves.optJSONObject(n);
    LinearLayout l = column();
    l.setPadding(dp(12), dp(8), dp(12), dp(8));
    EditText name = field("Section name", false);
    name.setText(s.optString("title"));
    l.addView(name);
    l.addView(button("Select categories", () -> selectShelfValues(s, "categories")));
    l.addView(button("Select individual titles", () -> selectShelfValues(s, "items")));
    l.addView(
        button(
            "Favorites only: " + s.optBoolean("favorites"),
            () -> {
              try {
                s.put("favorites", !s.optBoolean("favorites"));
              } catch (Exception ignored) {
              }
              save();
              Toast.makeText(this, "Favorites filter updated", Toast.LENGTH_SHORT).show();
            }));
    l.addView(
        button(
            "Favorite media types",
            () -> {
              String[] kinds = {"live", "movie", "series"};
              JSONArray kindsArray = s.optJSONArray("kinds");
              boolean[] checked = {
                kindsArray == null || has(kindsArray, "live"),
                kindsArray == null || has(kindsArray, "movie"),
                kindsArray == null || has(kindsArray, "series")
              };
              new AlertDialog.Builder(this)
                  .setTitle("Favorite media types")
                  .setMultiChoiceItems(
                      new String[] {"Live TV", "Movies", "Series"},
                      checked,
                      (d, w, b) -> checked[w] = b)
                  .setPositiveButton(
                      "Save",
                      (d, w) -> {
                        JSONArray values = new JSONArray();
                        for (int k = 0; k < 3; k++) if (checked[k]) values.put(kinds[k]);
                        try {
                          s.put("kinds", values);
                        } catch (Exception ignored) {
                        }
                        save();
                        populate();
                      })
                  .show();
            }));
    new AlertDialog.Builder(this)
        .setTitle("Edit Discover section")
        .setView(l)
        .setPositiveButton(
            "Save",
            (d, w) -> {
              try {
                s.put(
                    "title",
                    name.getText().toString().trim().isEmpty()
                        ? "Untitled section"
                        : name.getText().toString().trim());
              } catch (Exception ignored) {
              }
              save();
              populate();
            })
        .setNegativeButton("Close", null)
        .show();
  }

  void selectShelfValues(JSONObject shelf, String field) {
    LinearLayout l = column();
    l.setPadding(dp(12), 0, dp(12), 0);
    EditText q = field("Search " + field + "…", false);
    l.addView(q);
    LinearLayout modes = row();
    l.addView(modes);
    String[] kind = {"live"};
    boolean[] only = {false};
    ListView list = new ListView(this);
    l.addView(list, new LinearLayout.LayoutParams(-1, dp(250)));
    list.setChoiceMode(ListView.CHOICE_MODE_MULTIPLE);
    Set<String> chosen = new HashSet<>();
    JSONArray old = shelf.optJSONArray(field);
    if (old != null) for (int k = 0; k < old.length(); k++) chosen.add(old.optString(k));
    List<String> ids = new ArrayList<>();
    ArrayAdapter<String> a =
        new ArrayAdapter<>(
            this, android.R.layout.simple_list_item_multiple_choice, new ArrayList<>());
    list.setAdapter(a);
    Runnable update =
        () -> {
          ids.clear();
          a.clear();
          list.clearChoices();
          String term = q.getText().toString().toLowerCase(Locale.ROOT);
          if (field.equals("categories")) {
            for (Map.Entry<String, String> e : catalog.categories.entrySet())
              if (e.getKey().startsWith(kind[0] + ":")
                  && e.getValue().toLowerCase(Locale.ROOT).contains(term)
                  && (!only[0] || chosen.contains(e.getKey()))) {
                ids.add(e.getKey());
                a.add(e.getValue());
              }
          } else {
            int count = 0;
            for (Catalog.Item i : catalog.items)
              if (i.kind.equals(kind[0])
                  && i.title.toLowerCase(Locale.ROOT).contains(term)
                  && (!only[0] || chosen.contains(i.id))) {
                ids.add(i.id);
                a.add(i.title);
                if (++count == 500) break;
              }
          }
          a.notifyDataSetChanged();
          for (int k = 0; k < ids.size(); k++) list.setItemChecked(k, chosen.contains(ids.get(k)));
        };
    for (String k : Arrays.asList("live", "movie", "series"))
      modes.addView(
          button(
              k,
              () -> {
                kind[0] = k;
                update.run();
              }));
    modes.addView(
        button(
            "Selected only",
            () -> {
              only[0] = !only[0];
              update.run();
            }));
    q.addTextChangedListener(watcher(update));
    list.setOnItemClickListener(
        (v, c, p, id) -> {
          if (!chosen.add(ids.get(p))) chosen.remove(ids.get(p));
        });
    update.run();
    new AlertDialog.Builder(this)
        .setTitle("Select " + field + " · search to narrow titles")
        .setView(l)
        .setPositiveButton(
            "Save selection",
            (d, w) -> {
              try {
                shelf.put(field, new JSONArray(chosen));
              } catch (Exception ignored) {
              }
              save();
              populate();
            })
        .setNegativeButton("Cancel", null)
        .show();
  }

  @Override
  protected void onResume() {
    super.onResume();
    if (source != null && !demo) {
      String scope = source.scope();
      io.execute(
          () -> {
            try {
              Storage.State saved = new Storage.State(storage.read("state-" + scope));
              runOnUiThread(
                  () -> {
                    if (source == null || !scope.equals(source.scope()) || destroyed) return;
                    state = saved;
                    if (detail && selected != null) renderDetail(selected, null);
                    else if (adapter != null) populate();
                  });
            } catch (Exception ignored) {
            }
          });
    }
  }

  @Override
  public void onBackPressed() {
    if (detail) {
      dashboard();
      if (grid != null) grid.scrollToPosition(lastFocused);
    } else if (source != null && !destination.equals("Discover")) {
      destination = "Discover";
      category = "";
      search = "";
      year = 0;
      dashboard();
    } else
      new AlertDialog.Builder(this)
          .setTitle("Close Luma?")
          .setNegativeButton("Stay", null)
          .setPositiveButton("Close", (d, w) -> finish())
          .show();
  }

  @Override
  protected void onDestroy() {
    destroyed = true;
    generation++;
    queryGeneration++;
    main.removeCallbacksAndMessages(null);
    io.shutdown();
    filter.shutdownNow();
    super.onDestroy();
  }
}

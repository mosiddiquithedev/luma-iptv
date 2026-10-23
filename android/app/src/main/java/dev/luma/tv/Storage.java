package dev.luma.tv;

import android.content.*;
import android.security.keystore.*;
import android.util.Base64;
import java.io.*;
import java.security.*;
import java.util.*;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import org.json.*;

/** AES-GCM files with a non-exportable Android Keystore key. Backups are disabled. */
public final class Storage {
  final Context context;

  public Storage(Context c) {
    context = c.getApplicationContext();
  }

  private SecretKey key() throws Exception {
    KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
    ks.load(null);
    if (!ks.containsAlias("luma-v1")) {
      KeyGenerator g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
      g.init(
          new KeyGenParameterSpec.Builder(
                  "luma-v1", KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
              .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
              .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
              .build());
      g.generateKey();
    }
    return (SecretKey) ks.getKey("luma-v1", null);
  }

  public synchronized void write(String name, JSONObject value) throws Exception {
    Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
    c.init(Cipher.ENCRYPT_MODE, key());
    JSONObject envelope =
        new JSONObject()
            .put("iv", Base64.encodeToString(c.getIV(), Base64.NO_WRAP))
            .put(
                "data",
                Base64.encodeToString(
                    c.doFinal(value.toString().getBytes("UTF-8")), Base64.NO_WRAP));
    android.util.AtomicFile f = new android.util.AtomicFile(new File(context.getFilesDir(), name));
    FileOutputStream out = f.startWrite();
    try {
      out.write(envelope.toString().getBytes("UTF-8"));
      f.finishWrite(out);
    } catch (Exception e) {
      f.failWrite(out);
      throw e;
    }
  }

  public synchronized JSONObject read(String name) throws Exception {
    File f = new File(context.getFilesDir(), name);
    if (!f.exists()) return new JSONObject();
    ByteArrayOutputStream bytes = new ByteArrayOutputStream();
    try (InputStream in = new FileInputStream(f)) {
      byte[] b = new byte[8192];
      int n;
      while ((n = in.read(b)) != -1) bytes.write(b, 0, n);
    }
    JSONObject env = new JSONObject(bytes.toString("UTF-8"));
    Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
    c.init(
        Cipher.DECRYPT_MODE,
        key(),
        new GCMParameterSpec(128, Base64.decode(env.getString("iv"), Base64.NO_WRAP)));
    return new JSONObject(
        new String(c.doFinal(Base64.decode(env.getString("data"), Base64.NO_WRAP)), "UTF-8"));
  }

  public void disconnect() {
    new File(context.getFilesDir(), "source").delete();
  }

  public static class State {
    public JSONObject root;
    public final Set<String> favorites = new HashSet<>();
    public JSONObject history;
    public JSONArray shelves;

    public State(JSONObject j) {
      root = j;
      JSONArray fs = j.optJSONArray("favorites");
      if (fs != null) for (int k = 0; k < fs.length(); k++) favorites.add(fs.optString(k));
      history = j.optJSONObject("history");
      if (history == null) history = new JSONObject();
      shelves = j.optJSONArray("shelves");
    }

    public boolean completed(String id) {
      return history.optJSONObject(id) != null && history.optJSONObject(id).optBoolean("completed");
    }

    public long position(String id) {
      JSONObject h = history.optJSONObject(id);
      return h == null || h.optBoolean("completed") ? 0 : h.optLong("position");
    }

    public void record(Catalog.Item i, long position, long duration) throws Exception {
      JSONObject h =
          new JSONObject()
              .put("item", i.json())
              .put("position", Math.max(0, position))
              .put("duration", Math.max(0, duration))
              .put("completed", duration > 0 && position >= duration * 0.95)
              .put("updated", System.currentTimeMillis());
      history.put(i.id, h);
    }

    public List<Catalog.Item> history(boolean unfinished) {
      List<JSONObject> hs = new ArrayList<>();
      Iterator<String> keys = history.keys();
      while (keys.hasNext()) {
        JSONObject h = history.optJSONObject(keys.next());
        if (h != null) hs.add(h);
      }
      Collections.sort(hs, (a, b) -> Long.compare(b.optLong("updated"), a.optLong("updated")));
      List<Catalog.Item> result = new ArrayList<>();
      Set<String> seriesSeen = new HashSet<>();
      for (JSONObject h : hs) {
        JSONObject raw = h.optJSONObject("item");
        if (raw == null) continue;
        Catalog.Item i = Catalog.Item.from(raw);
        if (unfinished) {
          if (i.kind.equals(Catalog.LIVE)
              || !seriesSeen.add(i.series.isEmpty() ? i.id : i.series)
              || h.optBoolean("completed")
              || h.optLong("position") < 5000) continue;
        }
        result.add(i);
      }
      return result;
    }

    public JSONObject json() throws Exception {
      root.put("favorites", new JSONArray(favorites)).put("history", history);
      if (shelves != null) root.put("shelves", shelves);
      return root;
    }
  }
}

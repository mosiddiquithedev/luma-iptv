package dev.luma.tv;

import android.content.*;
import android.graphics.*;
import android.graphics.drawable.*;
import android.util.LruCache;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.net.*;
import java.util.concurrent.*;

/** Bounded queue, sampled bitmaps and a 10 MB cache for low-memory TV boxes. */
public final class Artwork extends View {
  static final LruCache<String, Bitmap> cache =
      new LruCache<String, Bitmap>(10 * 1024 * 1024) {
        protected int sizeOf(String k, Bitmap b) {
          return b.getByteCount();
        }
      };
  static final ThreadPoolExecutor workers =
      new ThreadPoolExecutor(
          2,
          2,
          15,
          TimeUnit.SECONDS,
          new ArrayBlockingQueue<>(48),
          new ThreadPoolExecutor.DiscardOldestPolicy());
  Catalog.Item item;
  Bitmap bitmap;
  final Paint paint = new Paint(3);

  public Artwork(Context c) {
    super(c);
    setImportantForAccessibility(IMPORTANT_FOR_ACCESSIBILITY_NO);
  }

  public void bind(Catalog.Item i) {
    item = i;
    bitmap = cache.get(i.art);
    invalidate();
    if (bitmap != null || !(i.art.startsWith("https://") || i.art.startsWith("http://"))) return;
    String address = i.art;
    workers.execute(
        () -> {
          try {
            HttpURLConnection conn = (HttpURLConnection) new URL(address).openConnection();
            conn.setConnectTimeout(7000);
            conn.setReadTimeout(7000);
            byte[] bytes;
            try (InputStream in = conn.getInputStream();
                ByteArrayOutputStream out = new ByteArrayOutputStream()) {
              byte[] buf = new byte[8192];
              int n, total = 0;
              while ((n = in.read(buf)) != -1) {
                total += n;
                if (total > 5000000) return;
                out.write(buf, 0, n);
              }
              bytes = out.toByteArray();
            } finally {
              conn.disconnect();
            }
            BitmapFactory.Options options = new BitmapFactory.Options();
            options.inJustDecodeBounds = true;
            BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
            options.inSampleSize = 1;
            while (options.outWidth / options.inSampleSize > 400
                || options.outHeight / options.inSampleSize > 500) options.inSampleSize *= 2;
            options.inJustDecodeBounds = false;
            options.inPreferredConfig = Bitmap.Config.RGB_565;
            Bitmap b = BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
            if (b != null) {
              cache.put(address, b);
              post(
                  () -> {
                    if (item != null && address.equals(item.art)) {
                      bitmap = b;
                      invalidate();
                    }
                  });
            }
          } catch (Exception ignored) {
          }
        });
  }

  protected void onDraw(Canvas c) {
    super.onDraw(c);
    if (item == null) return;
    float w = getWidth(), h = getHeight();
    int[] colors = {0xff405d50, 0xff685744, 0xff48566a, 0xff5a465b, 0xff53604a};
    int tone = colors[Math.floorMod(item.id.hashCode(), colors.length)];
    paint.setShader(new LinearGradient(0, 0, w, h, tone, 0xff131a16, Shader.TileMode.CLAMP));
    c.drawRect(0, 0, w, h, paint);
    paint.setShader(null);
    if (bitmap != null) {
      float scale = Math.max(w / bitmap.getWidth(), h / bitmap.getHeight());
      float bw = bitmap.getWidth() * scale, bh = bitmap.getHeight() * scale;
      c.drawBitmap(
          bitmap, null, new RectF((w - bw) / 2, (h - bh) / 2, (w + bw) / 2, (h + bh) / 2), paint);
      return;
    }
    paint.setColor(0x22bddfb7);
    c.drawCircle(w * .78f, h * .28f, w * .35f, paint);
    Path mountain = new Path();
    mountain.moveTo(0, h * .8f);
    mountain.lineTo(w * .4f, h * .35f);
    mountain.lineTo(w, h);
    mountain.lineTo(0, h);
    mountain.close();
    c.drawPath(mountain, paint);
    paint.setColor(0xffbddfb7);
    paint.setTypeface(Typeface.create("sans-serif", Typeface.BOLD));
    paint.setTextSize(w * .09f);
    c.drawText(
        item.kind.equals("live")
            ? "● LIVE"
            : "LUMA / " + item.kind.toUpperCase(java.util.Locale.ROOT),
        w * .09f,
        h * .12f,
        paint);
    paint.setColor(0xfff5f7f4);
    paint.setTextSize(w * .14f);
    String[] words = item.title.replaceAll("\\s*\\(.*?\\)", "").split(" ");
    int row = 0;
    String line = "";
    for (String word : words) {
      if (paint.measureText(line + word) > w * .85f && !line.isEmpty()) {
        c.drawText(line, w * .09f, h * .57f + row * w * .16f, paint);
        row++;
        line = "";
        if (row == 3) break;
      }
      line += word + " ";
    }
    if (row < 3) c.drawText(line, w * .09f, h * .57f + row * w * .16f, paint);
  }
}

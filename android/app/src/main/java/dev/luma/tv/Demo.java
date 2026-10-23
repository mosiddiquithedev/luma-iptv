package dev.luma.tv;

import java.util.*;

/**
 * Original fictional titles, only activated by the debug-build preview action. No supplied
 * channels.
 */
final class Demo {
  static Catalog catalog() {
    Catalog c = new Catalog();
    String[][] titles = {
      {
        "The Quiet Earth",
        "Across the Blue",
        "Golden Hour",
        "North of Home",
        "Wild Coast",
        "After the Rain"
      },
      {
        "Paper Lanterns",
        "City of Dreams",
        "The Last Train",
        "Monsoon Letters",
        "A New Morning",
        "The Long Road"
      },
      {
        "Orbit", "The Green Room", "Small Hours", "Hidden Valleys", "Parallel Lives", "Second Light"
      },
      {
        "World Journal",
        "Nature Window",
        "Studio Sessions",
        "Travel Notes",
        "Culture Daily",
        "Open Skies"
      }
    };
    for (int row = 0; row < titles.length; row++)
      for (int n = 0; n < titles[row].length; n++) {
        Catalog.Item i = new Catalog.Item();
        i.id = "demo:" + row + ":" + n;
        i.title = titles[row][n];
        i.kind = row == 3 ? "live" : row == 2 ? "series" : "movie";
        i.category =
            i.kind
                + ":"
                + (row == 0
                    ? "Hollywood"
                    : row == 1 ? "Bollywood" : row == 2 ? "English Series" : "World");
        c.categories.put(
            i.category,
            row == 0
                ? "Hollywood"
                : row == 1 ? "Bollywood" : row == 2 ? "English Series" : "World");
        i.year = "2025";
        i.rating = "8.4";
        i.summary =
            "An original sample title for the Luma interface preview. Connect your own provider or"
                + " playlist to watch your content.";
        c.items.add(i);
        if (row == 2) {
          List<Catalog.Item> es = new ArrayList<>();
          for (int e = 1; e <= 4; e++) {
            Catalog.Item ep = Catalog.Item.from(i.json());
            ep.id = i.id + ":" + e;
            ep.title = "Chapter " + e;
            ep.series = i.id;
            ep.season = 1;
            ep.episode = e;
            es.add(ep);
          }
          c.episodes.put(i.id, es);
        }
      }
    return c;
  }
}

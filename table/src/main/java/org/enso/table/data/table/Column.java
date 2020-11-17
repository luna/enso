package org.enso.table.data.table;

import org.enso.table.data.column.builder.object.InferredBuilder;
import org.enso.table.data.column.storage.Storage;

import java.util.BitSet;
import java.util.List;

/** A representation of a column. Consists of a column name and the underlying storage. */
public class Column {
  private final String name;
  private final Storage storage;

  /**
   * Creates a new column.
   *
   * @param name the column name
   * @param storage the underlying storage
   */
  public Column(String name, Storage storage) {
    this.name = name;
    this.storage = storage;
  }

  /** @return the column name */
  public String getName() {
    return name;
  }

  /** @return the underlying storage */
  public Storage getStorage() {
    return storage;
  }

  public long getSize() {
    return getStorage().size();
  }

  public Column mask(BitSet mask, int cardinality) {
    return new Column(name, storage.mask(mask, cardinality));
  }

  public Column rename(String name) {
    return new Column(name, storage);
  }

  public static Column fromItems(String name, List<Object> items) {
    InferredBuilder builder = new InferredBuilder(items.size());
    for (Object item : items) {
      builder.append(item);
    }
    return new Column(name, builder.seal());
  }
}

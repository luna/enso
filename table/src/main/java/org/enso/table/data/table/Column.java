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

  /** @return the number of items in this column. */
  public long getSize() {
    return getStorage().size();
  }

  /**
   * Return a new column, containing only the items marked true in the mask.
   *
   * @param mask the mask to use
   * @param cardinality the number of true values in mask
   * @return a new column, masked with the given mask
   */
  public Column mask(BitSet mask, int cardinality) {
    return new Column(name, storage.mask(mask, cardinality));
  }

  /**
   * Renames the column.
   *
   * @param name the new name
   * @return a new column with the given name
   */
  public Column rename(String name) {
    return new Column(name, storage);
  }

  /**
   * Creates a new column with given name and elements.
   *
   * @param name the name to use
   * @param items the items contained in the column
   * @return a column with given name and items
   */
  public static Column fromItems(String name, List<Object> items) {
    InferredBuilder builder = new InferredBuilder(items.size());
    for (Object item : items) {
      builder.append(item);
    }
    return new Column(name, builder.seal());
  }
}

package org.enso.table.data.column.storage;

import java.util.BitSet;
import java.util.function.Function;

/** A column containing floating point numbers. */
public class DoubleStorage extends Storage {
  private final long[] data;
  private final BitSet isMissing;
  private final int size;

  /**
   * @param data the underlying data
   * @param size the number of items stored
   * @param isMissing a bit set denoting at index {@code i} whether or not the value at index {@code
   *     i} is missing.
   */
  public DoubleStorage(long[] data, int size, BitSet isMissing) {
    this.data = data;
    this.isMissing = isMissing;
    this.size = size;
  }

  /** @inheritDoc */
  @Override
  public long size() {
    return size;
  }

  /**
   * @param idx an index
   * @return the data item contained at the given index.
   */
  public double getItem(long idx) {
    return Double.longBitsToDouble(data[(int) idx]);
  }

  /** @inheritDoc */
  @Override
  public long getType() {
    return Type.DOUBLE;
  }

  /** @inheritDoc */
  @Override
  public boolean isNa(long idx) {
    return isMissing.get((int) idx);
  }

  @Override
  public boolean isOpVectorized(VectorizedOp op) {
    return false;
  }

  @Override
  public DoubleStorage mask(BitSet mask, int cardinality) {
    BitSet newMissing = new BitSet();
    long[] newData = new long[cardinality];
    int resIx = 0;
    for (int i = 0; i < size; i++) {
      if (mask.get(i)) {
        if (isMissing.get(i)) {
          newMissing.set(resIx++);
        } else {
          newData[resIx++] = data[i];
        }
      }
    }
    return new DoubleStorage(newData, cardinality, newMissing);
  }

  @Override
  public Storage map(Function<Object, Object> function) {
    return null;
  }
}

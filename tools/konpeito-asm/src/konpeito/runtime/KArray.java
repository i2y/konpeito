package konpeito.runtime;

import java.util.*;

/**
 * KArray - Ruby Array implementation for JVM backend.
 *
 * Implements java.util.List<T> via composition (wrapping ArrayList<T>),
 * providing both Java collection interop and Ruby-specific methods.
 *
 * @param <T> Element type
 */
public class KArray<T> implements List<T> {
    private final ArrayList<T> data;

    // ========================================================================
    // Constructors
    // ========================================================================

    public KArray() {
        this.data = new ArrayList<>();
    }

    public KArray(int capacity) {
        this.data = new ArrayList<>(capacity);
    }

    public KArray(Collection<? extends T> c) {
        this.data = new ArrayList<>(c);
    }

    // ========================================================================
    // Ruby-specific methods
    // ========================================================================

    /** Ruby: arr.first */
    public T first() {
        return data.isEmpty() ? null : data.get(0);
    }

    /** Ruby: arr.last */
    public T last() {
        return data.isEmpty() ? null : data.get(data.size() - 1);
    }

    /** Ruby: arr.push(elem) / arr << elem — returns self for chaining */
    public KArray<T> push(T elem) {
        data.add(elem);
        return this;
    }

    /** Ruby: arr.pop */
    public T pop() {
        return data.isEmpty() ? null : data.remove(data.size() - 1);
    }

    /** Ruby: arr.length / arr.size — returns long (Ruby Integer) */
    public long length() {
        return data.size();
    }

    /** Ruby: arr.empty? */
    public boolean isEmpty_() {
        return data.isEmpty();
    }

    /** Ruby: arr.include?(elem) */
    public boolean includes(T elem) {
        return data.contains(elem);
    }

    /** Ruby: arr.flatten (single-level) */
    @SuppressWarnings("unchecked")
    public KArray<Object> flatten() {
        KArray<Object> result = new KArray<>();
        for (T elem : data) {
            if (elem instanceof KArray) {
                result.data.addAll(((KArray<Object>) elem).flatten().data);
            } else {
                result.data.add(elem);
            }
        }
        return result;
    }

    /** Ruby: arr.deconstruct — returns self (for pattern matching) */
    public KArray<T> deconstruct() {
        return this;
    }

    /** Ruby: arr.compact — removes nil (null) elements */
    public KArray<T> compact() {
        KArray<T> result = new KArray<>();
        for (T elem : data) {
            if (elem != null) {
                result.data.add(elem);
            }
        }
        return result;
    }

    /** Ruby: arr.uniq */
    public KArray<T> uniq() {
        KArray<T> result = new KArray<>();
        Set<T> seen = new LinkedHashSet<>();
        for (T elem : data) {
            if (seen.add(elem)) {
                result.data.add(elem);
            }
        }
        return result;
    }

    /** Ruby: arr.reverse */
    public KArray<T> reverse() {
        KArray<T> result = new KArray<>(data);
        Collections.reverse(result.data);
        return result;
    }

    /** Ruby: arr.sort (natural ordering) */
    @SuppressWarnings("unchecked")
    public KArray<T> sort() {
        KArray<T> result = new KArray<>(data);
        result.data.sort((a, b) -> ((Comparable<T>) a).compareTo(b));
        return result;
    }

    /** Ruby: arr.min */
    @SuppressWarnings("unchecked")
    public T min() {
        if (data.isEmpty()) return null;
        T result = data.get(0);
        for (int i = 1; i < data.size(); i++) {
            if (((Comparable<T>) data.get(i)).compareTo(result) < 0) {
                result = data.get(i);
            }
        }
        return result;
    }

    /** Ruby: arr.max */
    @SuppressWarnings("unchecked")
    public T max() {
        if (data.isEmpty()) return null;
        T result = data.get(0);
        for (int i = 1; i < data.size(); i++) {
            if (((Comparable<T>) data.get(i)).compareTo(result) > 0) {
                result = data.get(i);
            }
        }
        return result;
    }

    /** Ruby: arr.count (without block, same as length) */
    public long count() {
        return data.size();
    }

    /** Ruby: arr.shift — remove and return first element */
    public T shift() {
        return data.isEmpty() ? null : data.remove(0);
    }

    /** Ruby: arr.unshift(elem) / arr.prepend(elem) — add to front, return self */
    public KArray<T> unshift(T elem) {
        data.add(0, elem);
        return this;
    }

    /** Ruby: arr.delete_at(index) — remove and return element at index */
    public T deleteAt(int index) {
        int idx = index < 0 ? data.size() + index : index;
        if (idx < 0 || idx >= data.size()) return null;
        return data.remove(idx);
    }

    /** Ruby: arr.delete(value) — remove all occurrences, return last removed or nil */
    public T deleteValue(T value) {
        boolean found = data.remove(value);
        return found ? value : null;
    }

    /** Ruby: arr.sum — sum all elements (for numeric arrays) */
    @SuppressWarnings("unchecked")
    public long sumLong() {
        long total = 0;
        for (T elem : data) {
            if (elem instanceof Long) total += (Long) elem;
            else if (elem instanceof Integer) total += (Integer) elem;
        }
        return total;
    }

    /** Ruby: arr.sum for double arrays */
    public double sumDouble() {
        double total = 0.0;
        for (T elem : data) {
            if (elem instanceof Double) total += (Double) elem;
            else if (elem instanceof Float) total += (Float) elem;
            else if (elem instanceof Long) total += (Long) elem;
        }
        return total;
    }

    /** Ruby: arr.find_index(value) — returns index or -1 */
    public long findIndex(T value) {
        int idx = data.indexOf(value);
        return idx;
    }

    /** Ruby: arr.join(sep) */
    public String join(String separator) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < data.size(); i++) {
            if (i > 0) sb.append(separator);
            sb.append(data.get(i));
        }
        return sb.toString();
    }

    /** Ruby: arr.join (no separator) */
    public String join() {
        return join("");
    }

    // ========================================================================
    // Negative index support (Ruby semantics)
    // ========================================================================

    private int adjustIndex(int index) {
        return index < 0 ? data.size() + index : index;
    }

    // ========================================================================
    // List<T> interface delegation with negative index support
    // ========================================================================

    @Override
    public int size() {
        return data.size();
    }

    @Override
    public boolean isEmpty() {
        return data.isEmpty();
    }

    @Override
    public boolean contains(Object o) {
        return data.contains(o);
    }

    @Override
    public Iterator<T> iterator() {
        return data.iterator();
    }

    @Override
    public Object[] toArray() {
        return data.toArray();
    }

    @Override
    public <U> U[] toArray(U[] a) {
        return data.toArray(a);
    }

    @Override
    public boolean add(T t) {
        return data.add(t);
    }

    @Override
    public boolean remove(Object o) {
        return data.remove(o);
    }

    @Override
    public boolean containsAll(Collection<?> c) {
        return data.containsAll(c);
    }

    @Override
    public boolean addAll(Collection<? extends T> c) {
        return data.addAll(c);
    }

    @Override
    public boolean addAll(int index, Collection<? extends T> c) {
        return data.addAll(adjustIndex(index), c);
    }

    @Override
    public boolean removeAll(Collection<?> c) {
        return data.removeAll(c);
    }

    @Override
    public boolean retainAll(Collection<?> c) {
        return data.retainAll(c);
    }

    @Override
    public void clear() {
        data.clear();
    }

    @Override
    public T get(int index) {
        return data.get(adjustIndex(index));
    }

    @Override
    public T set(int index, T element) {
        return data.set(adjustIndex(index), element);
    }

    @Override
    public void add(int index, T element) {
        data.add(adjustIndex(index), element);
    }

    @Override
    public T remove(int index) {
        return data.remove(adjustIndex(index));
    }

    @Override
    public int indexOf(Object o) {
        return data.indexOf(o);
    }

    @Override
    public int lastIndexOf(Object o) {
        return data.lastIndexOf(o);
    }

    @Override
    public ListIterator<T> listIterator() {
        return data.listIterator();
    }

    @Override
    public ListIterator<T> listIterator(int index) {
        return data.listIterator(adjustIndex(index));
    }

    @Override
    public List<T> subList(int fromIndex, int toIndex) {
        return data.subList(adjustIndex(fromIndex), adjustIndex(toIndex));
    }

    // ========================================================================
    // Ruby-compatible toString: [1, 2, 3]
    // ========================================================================

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < data.size(); i++) {
            if (i > 0) sb.append(", ");
            T elem = data.get(i);
            if (elem instanceof String) {
                sb.append("\"").append(elem).append("\"");
            } else {
                sb.append(elem);
            }
        }
        sb.append("]");
        return sb.toString();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o instanceof KArray) {
            return data.equals(((KArray<?>) o).data);
        }
        if (o instanceof List) {
            return data.equals(o);
        }
        return false;
    }

    @Override
    public int hashCode() {
        return data.hashCode();
    }
}

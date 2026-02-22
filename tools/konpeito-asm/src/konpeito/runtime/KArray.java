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
    private boolean frozen = false;

    /** Ruby: arr.freeze */
    public void freeze() { frozen = true; }

    /** Ruby: arr.frozen? */
    public boolean isFrozen() { return frozen; }

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

    /** Ruby: arr.to_a — returns self (identity for arrays, used by for/each desugaring) */
    public KArray<T> to_a() {
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
        result.data.sort((a, b) -> {
            // Try Java Comparable first
            if (a instanceof Comparable) {
                try {
                    return ((Comparable<T>) a).compareTo(b);
                } catch (ClassCastException e) {
                    // Fall through to op_cmp
                }
            }
            // Try Ruby <=> (op_cmp) via reflection
            try {
                java.lang.reflect.Method cmp = a.getClass().getMethod("op_cmp", Object.class);
                Object res = cmp.invoke(a, b);
                if (res instanceof Long) return ((Long) res).intValue();
                if (res instanceof Integer) return (Integer) res;
                return 0;
            } catch (Exception e) {
                throw new ClassCastException("Cannot compare " + a.getClass().getName());
            }
        });
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

    /** Ruby: arr.sort { |a, b| ... } — sort with comparator block (via Comparator) */
    @SuppressWarnings("unchecked")
    public KArray<T> sortWithComparator(java.util.Comparator<Object> comparator) {
        KArray<T> result = new KArray<>(data);
        result.data.sort((java.util.Comparator<? super T>) (Object) comparator);
        return result;
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

    /** Ruby: arr.concat(other) — append all elements from other array, return self */
    @SuppressWarnings("unchecked")
    public KArray<T> concat(Object other) {
        if (other instanceof KArray) {
            data.addAll(((KArray<T>) other).data);
        }
        return this;
    }

    /** Ruby: arr.delete_at(index) — remove and return element at index */
    public T deleteAt(int index) {
        int idx = index < 0 ? data.size() + index : index;
        if (idx < 0 || idx >= data.size()) return null;
        return data.remove(idx);
    }

    /** Ruby: arr.delete(value) — remove all occurrences, return value or nil */
    public T deleteValue(T value) {
        boolean found = false;
        java.util.Iterator<T> it = data.iterator();
        while (it.hasNext()) {
            if (java.util.Objects.equals(it.next(), value)) {
                it.remove();
                found = true;
            }
        }
        return found ? value : null;
    }

    /** Ruby: arr.delete(value) — alias used by invokedynamic dispatch */
    public Object delete(Object value) {
        boolean found = false;
        java.util.Iterator<T> it = data.iterator();
        while (it.hasNext()) {
            if (java.util.Objects.equals(it.next(), value)) {
                it.remove();
                found = true;
            }
        }
        return found ? value : null;
    }

    /** Ruby: arr.rotate / arr.rotate(n) — returns new rotated array */
    public KArray<T> rotate() {
        return rotate(1);
    }

    /** Ruby: arr.rotate(n) — returns new rotated array by n positions */
    public KArray<T> rotate(int n) {
        int size = data.size();
        if (size == 0) return new KArray<>();
        int shift = ((n % size) + size) % size; // normalize negative
        KArray<T> result = new KArray<>(size);
        for (int i = 0; i < size; i++) {
            result.data.add(data.get((i + shift) % size));
        }
        return result;
    }

    /** Ruby: arr.rotate(n) — overload accepting long for JVM compat */
    public KArray<T> rotate(long n) {
        return rotate((int) n);
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

    /** Ruby: arr.find_index(value) / arr.index(value) — returns index or nil */
    public long findIndex(T value) {
        int idx = data.indexOf(value);
        return idx;
    }

    /** Ruby: arr.index(value) — alias for findIndex, returns Long index or null (nil) */
    public Object index(Object value) {
        int idx = data.indexOf(value);
        return idx >= 0 ? Long.valueOf(idx) : null;
    }

    /** Ruby: arr.first(n) — returns first n elements */
    public KArray<T> first(int n) {
        KArray<T> result = new KArray<>();
        int limit = Math.min(n, data.size());
        for (int i = 0; i < limit; i++) {
            result.data.add(data.get(i));
        }
        return result;
    }

    /** Ruby: arr.last(n) — returns last n elements */
    public KArray<T> last(int n) {
        KArray<T> result = new KArray<>();
        int start = Math.max(0, data.size() - n);
        for (int i = start; i < data.size(); i++) {
            result.data.add(data.get(i));
        }
        return result;
    }

    /** Ruby: arr.take(n) — returns first n elements */
    public KArray<T> take(int n) {
        return first(n);
    }

    /** Ruby: arr.drop(n) — returns elements after first n */
    public KArray<T> drop(int n) {
        KArray<T> result = new KArray<>();
        for (int i = Math.min(n, data.size()); i < data.size(); i++) {
            result.data.add(data.get(i));
        }
        return result;
    }

    /** Multi-assign splat: collect elements from startIndex to size()-endOffset */
    public KArray<T> splatSlice(int startIndex, int endOffset) {
        KArray<T> result = new KArray<>();
        int end = data.size() - endOffset;
        for (int i = startIndex; i < end; i++) {
            result.data.add(data.get(i));
        }
        return result;
    }

    /** Ruby: arr.zip(other) — pairs elements from two arrays */
    @SuppressWarnings("unchecked")
    public KArray<KArray<Object>> zip(KArray<?> other) {
        KArray<KArray<Object>> result = new KArray<>();
        for (int i = 0; i < data.size(); i++) {
            KArray<Object> pair = new KArray<>();
            pair.data.add(data.get(i));
            pair.data.add(i < other.size() ? other.get(i) : null);
            result.data.add(pair);
        }
        return result;
    }

    /** Ruby: arr.flatten(depth) — flattens with depth limit */
    @SuppressWarnings("unchecked")
    public KArray<Object> flatten(int depth) {
        KArray<Object> result = new KArray<>();
        flattenHelper(result, data, depth);
        return result;
    }

    @SuppressWarnings("unchecked")
    private static void flattenHelper(KArray<Object> result, List<?> list, int depth) {
        for (Object elem : list) {
            if (depth > 0 && elem instanceof KArray) {
                flattenHelper(result, ((KArray<Object>) elem).data, depth - 1);
            } else {
                result.data.add(elem);
            }
        }
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
        int idx = adjustIndex(index);
        if (idx < 0 || idx >= data.size()) return null;
        return data.get(idx);
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

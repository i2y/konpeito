package konpeito.runtime;

import java.util.*;

/**
 * KHash - Ruby Hash implementation for JVM backend.
 *
 * Implements java.util.Map<K,V> via composition (wrapping LinkedHashMap<K,V>),
 * providing both Java collection interop and Ruby-specific methods.
 * LinkedHashMap preserves insertion order, matching Ruby Hash semantics.
 *
 * @param <K> Key type
 * @param <V> Value type
 */
public class KHash<K, V> implements Map<K, V> {
    private final LinkedHashMap<K, V> data;

    // ========================================================================
    // Constructors
    // ========================================================================

    public KHash() {
        this.data = new LinkedHashMap<>();
    }

    public KHash(Map<? extends K, ? extends V> m) {
        this.data = new LinkedHashMap<>(m);
    }

    // ========================================================================
    // Ruby-specific methods
    // ========================================================================

    /** Ruby: hash.deconstruct_keys(keys) — returns self (for pattern matching) */
    @SuppressWarnings("unchecked")
    public KHash<K, V> deconstruct_keys(Object keys) {
        // In Ruby, deconstruct_keys returns a hash with only the specified keys.
        // For simplicity, return self — the pattern matcher will check keys individually.
        return this;
    }

    /** Ruby: hash.length / hash.size — returns long (Ruby Integer) */
    public long length() {
        return data.size();
    }

    /** Ruby: hash.has_key?(key) / hash.key?(key) */
    public boolean hasKey(K key) {
        return data.containsKey(key);
    }

    /** Ruby: hash.has_value?(value) / hash.value?(value) */
    public boolean hasValue(V value) {
        return data.containsValue(value);
    }

    /** Ruby: hash.keys — returns KArray */
    public KArray<K> rubyKeys() {
        return new KArray<>(data.keySet());
    }

    /** Ruby: hash.values — returns KArray */
    public KArray<V> rubyValues() {
        return new KArray<>(data.values());
    }

    /** Ruby: hash.empty? */
    public boolean isEmpty_() {
        return data.isEmpty();
    }

    /** Ruby: hash.fetch(key, default) */
    public V fetch(K key, V defaultValue) {
        V value = data.get(key);
        return value != null ? value : defaultValue;
    }

    /** Ruby: hash.merge(other) — returns new hash */
    public KHash<K, V> merge(KHash<K, V> other) {
        KHash<K, V> result = new KHash<>(this.data);
        result.data.putAll(other.data);
        return result;
    }

    /** Ruby: hash.to_a — returns array of [key, value] pairs */
    public KArray<KArray<Object>> toArray_() {
        KArray<KArray<Object>> result = new KArray<>();
        for (Map.Entry<K, V> entry : data.entrySet()) {
            KArray<Object> pair = new KArray<>(2);
            pair.add(entry.getKey());
            pair.add(entry.getValue());
            result.add(pair);
        }
        return result;
    }

    /** Ruby: hash.count (without block) */
    public long count() {
        return data.size();
    }

    /** Ruby: hash.merge!(other) / hash.update(other) — mutating merge */
    @SuppressWarnings("unchecked")
    public KHash<K, V> mergeInPlace(KHash<K, V> other) {
        this.data.putAll(other.data);
        return this;
    }

    /** Ruby: hash.each_key { |k| ... } support — returns keys as KArray */
    public KArray<K> eachKeys() {
        return new KArray<>(data.keySet());
    }

    /** Ruby: hash.each_value { |v| ... } support — returns values as KArray */
    public KArray<V> eachValues() {
        return new KArray<>(data.values());
    }

    /** Sort pairs by scores — used by JVM codegen for sort_by.
     *  pairs and scores are parallel KArrays. Sorts both in-place by scores ascending. */
    @SuppressWarnings("unchecked")
    public static void sortPairsByScores(KArray<Object> pairs, KArray<Object> scores) {
        int n = pairs.size();
        // Selection sort — simple and O(n²) is fine for small hashes
        for (int i = 0; i < n - 1; i++) {
            int minIdx = i;
            for (int j = i + 1; j < n; j++) {
                Comparable<Object> sj = (Comparable<Object>) scores.get(j);
                Comparable<Object> sm = (Comparable<Object>) scores.get(minIdx);
                if (sj.compareTo((Object) sm) < 0) {
                    minIdx = j;
                }
            }
            if (minIdx != i) {
                // Swap pairs
                Object tmp = pairs.get(i);
                pairs.set(i, pairs.get(minIdx));
                pairs.set(minIdx, tmp);
                // Swap scores
                Object stmp = scores.get(i);
                scores.set(i, scores.get(minIdx));
                scores.set(minIdx, stmp);
            }
        }
    }

    // ========================================================================
    // Map<K,V> interface delegation
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
    public boolean containsKey(Object key) {
        return data.containsKey(key);
    }

    @Override
    public boolean containsValue(Object value) {
        return data.containsValue(value);
    }

    @Override
    public V get(Object key) {
        return data.get(key);
    }

    @Override
    public V put(K key, V value) {
        return data.put(key, value);
    }

    @Override
    public V remove(Object key) {
        return data.remove(key);
    }

    @Override
    public void putAll(Map<? extends K, ? extends V> m) {
        data.putAll(m);
    }

    @Override
    public void clear() {
        data.clear();
    }

    @Override
    public Set<K> keySet() {
        return data.keySet();
    }

    @Override
    public Collection<V> values() {
        return data.values();
    }

    @Override
    public Set<Map.Entry<K, V>> entrySet() {
        return data.entrySet();
    }

    // ========================================================================
    // Ruby-compatible toString: {"a" => 1, "b" => 2}
    // ========================================================================

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder("{");
        boolean first = true;
        for (Map.Entry<K, V> entry : data.entrySet()) {
            if (!first) sb.append(", ");
            first = false;
            K key = entry.getKey();
            V value = entry.getValue();
            if (key instanceof String) {
                sb.append("\"").append(key).append("\"");
            } else {
                sb.append(key);
            }
            sb.append(" => ");
            if (value instanceof String) {
                sb.append("\"").append(value).append("\"");
            } else {
                sb.append(value);
            }
        }
        sb.append("}");
        return sb.toString();
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o instanceof KHash) {
            return data.equals(((KHash<?, ?>) o).data);
        }
        if (o instanceof Map) {
            return data.equals(o);
        }
        return false;
    }

    @Override
    public int hashCode() {
        return data.hashCode();
    }
}

package konpeito.runtime;

import java.util.Map;
import java.util.LinkedHashMap;

/**
 * KMatchData - Ruby MatchData implementation for JVM backend.
 *
 * Wraps regex match results with group access and the original input string.
 */
public class KMatchData {
    private final KArray<String> groups;
    private final String inputString;
    private final int matchStart;
    private final int matchEnd;
    private final Map<String, String> namedGroups;

    public KMatchData(KArray<String> groups, String inputString) {
        this.groups = groups;
        this.inputString = inputString;
        this.matchStart = 0;
        this.matchEnd = groups.isEmpty() ? 0 : (groups.get(0) != null ? groups.get(0).length() : 0);
        this.namedGroups = new LinkedHashMap<>();
    }

    public KMatchData(KArray<String> groups, String inputString, int matchStart, int matchEnd) {
        this.groups = groups;
        this.inputString = inputString;
        this.matchStart = matchStart;
        this.matchEnd = matchEnd;
        this.namedGroups = new LinkedHashMap<>();
    }

    public KMatchData(KArray<String> groups, String inputString, int matchStart, int matchEnd, Map<String, String> namedGroups) {
        this.groups = groups;
        this.inputString = inputString;
        this.matchStart = matchStart;
        this.matchEnd = matchEnd;
        this.namedGroups = namedGroups != null ? namedGroups : new LinkedHashMap<>();
    }

    /** MatchData#[](index) — returns the nth match group (0 = full match) */
    public Object get(int index) {
        if (index < 0) index = groups.size() + index;
        if (index < 0 || index >= groups.size()) return null;
        return groups.get(index);
    }

    /** MatchData#[](name) — returns a named capture group */
    public Object getByName(String name) {
        return namedGroups.get(name);
    }

    /** MatchData#to_s — returns the entire matched string (group 0) */
    public String toString() {
        if (groups.isEmpty()) return "";
        return groups.get(0) != null ? groups.get(0) : "";
    }

    /** MatchData#string — returns a copy of the match string (input) */
    public String string() {
        return inputString;
    }

    /** MatchData#captures — returns capture groups (excluding group 0) */
    public KArray<String> captures() {
        KArray<String> result = new KArray<>();
        for (int i = 1; i < groups.size(); i++) {
            result.push(groups.get(i));
        }
        return result;
    }

    /** MatchData#size / MatchData#length — number of elements (including full match) */
    public long length() {
        return groups.size();
    }

    /** MatchData#pre_match — returns the string before the match */
    public String pre_match() {
        if (matchStart <= 0) return "";
        return inputString.substring(0, matchStart);
    }

    /** MatchData#post_match — returns the string after the match */
    public String post_match() {
        if (matchEnd >= inputString.length()) return "";
        return inputString.substring(matchEnd);
    }

    /** MatchData#named_captures — returns a Hash of named captures */
    public KHash<Object, Object> named_captures() {
        KHash<Object, Object> result = new KHash<>();
        for (Map.Entry<String, String> entry : namedGroups.entrySet()) {
            result.put(entry.getKey(), entry.getValue());
        }
        return result;
    }

    /** MatchData#class */
    public String k_class() {
        return "MatchData";
    }
}

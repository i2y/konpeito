package konpeito.runtime;

/**
 * KMatchData - Ruby MatchData implementation for JVM backend.
 *
 * Wraps regex match results with group access and the original input string.
 */
public class KMatchData {
    private final KArray<String> groups;
    private final String inputString;

    public KMatchData(KArray<String> groups, String inputString) {
        this.groups = groups;
        this.inputString = inputString;
    }

    /** MatchData#[](index) — returns the nth match group (0 = full match) */
    public Object get(int index) {
        if (index < 0 || index >= groups.size()) return null;
        return groups.get(index);
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
    // Note: would need start index to implement fully

    /** MatchData#class */
    public String k_class() {
        return "MatchData";
    }
}

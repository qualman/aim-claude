public enum BuddyNamer {
    /// xX_Claude_Xx is buddy 1; later buddies are xX_Claude<n>_Xx, filling the lowest free number.
    public static func nextName(existing: [String]) -> String {
        let taken = Set(existing)
        var n = 1
        while taken.contains(name(for: n)) { n += 1 }
        return name(for: n)
    }

    static func name(for n: Int) -> String {
        n == 1 ? "xX_Claude_Xx" : "xX_Claude\(n)_Xx"
    }
}

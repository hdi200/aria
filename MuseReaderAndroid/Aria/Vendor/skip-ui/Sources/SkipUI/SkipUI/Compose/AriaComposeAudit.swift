// ARIA PATCH: the TEST manifest selects these guards in an ignored package copy;
// ordinary builds contain no callback/hot-path code.
#if SKIP && ARIA_PHONE_AUDIT
public enum AriaComposeAudit {
    public static var record: ((String, Int) -> Void)? = nil
    public static func point(_ name: String, value: Int = 0) {
        guard let callback = record else { return }
        callback(name, value)
    }
}
#endif

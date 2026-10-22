# Aria patches to swift-jni

Vendored from 0.5.1, revision `71385f88cfff14409fe105e27fcad3ebd44348d0`.
The public upstream head matched this revision when checked October 17, 2026.
No Skip version upgrade is included. Root `Aria/Package.swift` selects this directory.

- `Sources/SwiftJNI/JWeakObject.swift` supplies an owning JNI weak reference, identity
  comparison with `IsSameObject`, and scoped promotion with `NewLocalRef` before any
  operation. Promotion handles collection atomically; local references are deleted on
  all paths and the weak reference is deleted on native deinit. State observers can
  notify a Compose-owned support without keeping its composition graph alive.
- `AriaJNILifecycle.swift`, `SwiftJNI.swift`, and the package manifest add opt-in
  counters for global create/delete, JObject init/deinit, weak globals and scoped
  locals. ART table dumps also check the actual thread-local and process-global
  tables. Build with
  environment `ARIA_PERF_DIAGNOSTICS=1`; production builds omit the counters entirely.
  The counter covers this JNI library's calls, not globals created directly by Qt/ART.
- `Tests/SwiftJNITests/AriaWeakObjectTests.swift` checks reference identity, notification
  while the referent is alive, and safe no-op behavior after collection.

All modifications are marked `ARIA PATCH`. Preserve the Apache-2.0 upstream sources and
license when updating; rebase these changes deliberately and rerun the lifetime gates.

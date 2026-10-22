# Aria patches to skip-fuse-ui

Vendored from 1.19.0, revision `36479f246560f72c64af30fc8e8927c84550f70c`.
Public upstream heads for skip-fuse-ui, skip-bridge 0.18.0, and swift-jni 0.5.1 matched
Aria's pins on October 17, 2026; there was no newer head fix to adopt. No upgrade.
Root `Aria/Package.swift` selects this directory; its manifest uses the sibling patched
skip-ui and swift-jni directories. Two upstream local-run experiment documents with
machine-specific paths are omitted; runtime sources and licensing are preserved.

Related upstream report: [skip-fuse-ui issue 124](https://github.com/skiptools/skip-fuse-ui/issues/124)
describes duplicate StateSupport globals and, separately, an idle recomposition loop.
Its reports corroborate the failure class; Aria's idle-versus-playback counters and
soaks are the evidence for this patch. The upstream report does not establish that
every screen has an idle loop or that the pinned version has a lifecycle repair.

## Compose state ownership

`Properties/BridgedStateBox.swift` previously retained a strong Swift projection of
Java StateSupport on each native view projection. That projection owns a JNI global
reference. A state support's Compose observation graph can retain callbacks capturing
native views, so globally rooting the support prevents the obsolete page states from
being collected. Replacing a projection on one view does not release projections held
by the other retained view instances.

`Properties/Box.swift` now holds one `JWeakObject` per remembered slot. Every synced
native view shares that value box. `IsSameObject` reuses the weak reference when syncing
the same support; the generated temporary strong projection is released on return.
Access/update notify the support via a scoped local reference and cached method IDs.
Compose retains the live support; native code observes it without owning its Java
lifecycle. A disposed, collected support safely receives no notification. State values
and animation provenance still live in the shared native value box.

Opt-in wrapper, actual shared value-box, and sync counters use
`ARIA_PERF_DIAGNOSTICS=1`; upload builds omit them. Image-owner events correlate
shared value-box addresses with JNI image handles for a separate local heap capture.
Wrapper counts alone do not establish how many distinct image values remain alive.
No generated bridge output is edited as the lasting fix.

## Cleared support and local references

`JWeakObject` promotes the weak reference with `NewLocalRef` for each access/update,
then calls `DeleteLocalRef` in a `defer`, including throwing paths. Native attached
threads do not rely on an incoming JNI frame for cleanup. `IsSameObject` does not
allocate a local reference.

When promotion returns nil, the Java owner has gone away. Reads still return the
shared native box's value; writes store that value before attempting notification.
The next `Java_initStateSupport` binds a new Java owner to that same native box.
Diagnostics log `ARIA_STATE_SUPPORT_CLEARED` and count cleared accesses/updates.
The diagnostics-only lifecycle probe forces collection, changes 7 to 42, reattaches,
and asserts 42; it then performs 100,000 accesses inside one native attachment and
compares both scoped-local counters and ART's actual reference tables.

## Local TEST-only focused UI audit

`ARIA_PHONE_AUDIT=1` adds buffered native span callbacks around outermost
`Java_viewOrEmpty` conversion, deferred GeometryReader content construction,
and ForEach item construction/conversion. Nested conversions count nodes without
reading clocks. Type metadata is converted to names after the timed run; no view,
closure, image or bitmap is retained by the recorder. The application enables these
hooks on a balanced subset of existing TEST actions to check observer overhead.
The ordinary package build excludes the helper and calls the original code paths.
No framework version or rendering behavior changes. The local audit protocol, measurements and recordings are not part of the
production source package.

## Updating

All changes are marked `ARIA PATCH`. Rebase against an explicitly approved release,
keep the same Compose ownership contract, and rerun JNI identity/collection tests,
playback/editing soaks, state updates, selection and cursor checks before shipping.

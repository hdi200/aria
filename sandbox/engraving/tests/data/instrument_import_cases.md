# Synthetic instrument import cases

- `grouped_excerpt.mscz`: five source parts and one legacy inline grouped excerpt containing all five. Individual part views must not reuse that group.
- `choir_to_flute.mscz`: a normal choir instrument with a flute change in bar two. Both sounds must survive import, part creation, save, and reopen.
- `custom_choir_id.mscz`: the same score with a custom/unrecognized choir ID and an explicit GM choir program (52). Diagnostic only: the current MuseScore setup resolver falls back to piano. Do not change sound selection until the reported real score establishes the desired behavior.

All are small generated examples without private user content.

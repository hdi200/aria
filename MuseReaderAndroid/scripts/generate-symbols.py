#!/usr/bin/env python3
"""Android icons for the SF Symbols the shared iOS views name.

Apple's license limits SF Symbols to Apple platforms, so each name the app uses gets a
Google Material icon (Apache 2.0) instead, from the copy bundled with Android Studio.
They are written as symbol sets into the Android app's assets, at the path of the app
module's asset catalog (aria/skip/Resources/Module.xcassets), where Skip looks up
Image(systemName:) before its own built-in icons. They stay out of the Swift package's
Resources because Xcode's asset compiler (the Skip project's iOS build) only accepts SF
Symbols templates.

    scripts/generate-symbols.py [path/to/android.jar]
"""
import json
import os
import re
import sys
import zipfile

ANDROID_JAR = "/Applications/Android Studio.app/Contents/plugins/android/lib/android.jar"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Aria", "Android", "app", "symbol-assets",
                       "aria", "skip", "Resources", "Module.xcassets")

# SF Symbol name -> Material icon name. ".fill" names use the filled style; the rest
# the outlined style, like SF Symbols' outline/fill pairs.
SYMBOLS = {
    # Returned from code (instrument families, sort orders, annotation tools, ...).
    "accordion": "piano",
    "circle": "radio_button_unchecked",
    "clock": "schedule",
    "drum": "adjust",
    "eye": "visibility",
    "guitars": "music_note",
    "highlighter": "border_color",
    "largecircle.fill.circle": "radio_button_checked",
    "lasso": "highlight_alt",
    "scroll": "view_stream",
    "arrow.counterclockwise": "replay",
    "arrow.down": "arrow_downward",
    "arrow.down.circle": "arrow_circle_down",
    "arrow.left": "arrow_back",
    "arrow.right": "arrow_forward",
    "arrow.up": "arrow_upward",
    "arrow.up.arrow.down": "swap_vert",
    "arrow.up.left.and.arrow.down.right": "open_in_full",
    "arrow.up.right.square": "open_in_new",
    "arrow.uturn.backward": "undo",
    "arrow.uturn.forward": "redo",
    "arrowtriangle.down.fill": "arrow_drop_down",
    "arrowtriangle.up.fill": "arrow_drop_up",
    "book.pages": "menu_book",
    "checkmark": "check",
    "checkmark.circle": "check_circle",
    "checkmark.circle.fill": "check_circle",
    "checkmark.square.fill": "check_box",
    "square": "check_box_outline_blank",
    "infinity.circle.fill": "all_inclusive",
    "chevron.down": "expand_more",
    "chevron.down.2": "keyboard_double_arrow_down",
    "chevron.left": "chevron_left",
    "chevron.right": "chevron_right",
    "chevron.up": "expand_less",
    "chevron.up.2": "keyboard_double_arrow_up",
    "chevron.up.chevron.down": "unfold_more",
    "circle.grid.3x3.fill": "apps",
    "circle.grid.cross": "control_camera",
    "clock.arrow.circlepath": "history",
    "cursorarrow": "near_me",
    "doc": "insert_drive_file",
    "doc.badge.gearshape": "file_present",
    "doc.badge.plus": "note_add",
    "doc.on.clipboard": "content_paste",
    "doc.on.doc": "content_copy",
    "doc.richtext": "article",
    "doc.text": "description",
    "doc.text.magnifyingglass": "find_in_page",
    "ellipsis": "more_horiz",
    "eraser": "auto_fix_normal",
    "exclamationmark.triangle": "warning",
    "exclamationmark.triangle.fill": "warning",
    "eye.slash": "visibility_off",
    "film": "movie",
    "forward.end": "skip_next",
    "gearshape": "settings",
    "hand.tap": "touch_app",
    "hands.clap": "celebration",
    "info.circle": "info",
    "info.circle.fill": "info",
    "laptopcomputer.and.iphone": "devices",
    "line.3.horizontal": "menu",
    "link": "link",
    "list.bullet": "format_list_bulleted",
    "list.bullet.indent": "format_indent_increase",
    "location": "near_me",
    "location.fill": "near_me",
    "lock.fill": "lock",
    "lock.rectangle.stack": "lock",
    "magnifyingglass": "search",
    "minus": "remove",
    "minus.circle": "remove_circle_outline",
    "minus.magnifyingglass": "zoom_out",
    "music.note": "music_note",
    "music.note.house": "library_music",
    "music.note.list": "queue_music",
    "music.quarternote.3": "music_note",
    "pause": "pause",
    "pause.fill": "pause",
    "pause.rectangle.fill": "pause_presentation",
    "pencil": "edit",
    "pencil.tip": "draw",
    "pencil.tip.crop.circle": "draw",
    "pencil.tip.crop.circle.badge.plus": "edit_note",
    "person.2": "people",
    "person.3.fill": "groups",
    "person.wave.2": "record_voice_over",
    "photo.badge.plus": "add_photo_alternate",
    "photo.on.rectangle": "photo_library",
    "pianokeys": "piano",
    "play.circle": "play_circle",
    "play.circle.fill": "play_circle",
    "play.fill": "play_arrow",
    "play.rectangle": "slideshow",
    "plus": "add",
    "plus.circle": "add_circle_outline",
    "plus.circle.fill": "add_circle",
    "plus.magnifyingglass": "zoom_in",
    "rectangle.grid.1x2": "view_agenda",
    "rectangle.portrait.on.rectangle.portrait": "filter_none",
    "repeat": "repeat",
    "repeat.circle.fill": "repeat_on",
    "scissors": "content_cut",
    "scope": "gps_fixed",
    "slider.horizontal.3": "tune",
    "slider.vertical.3": "equalizer",
    "sparkles": "auto_awesome",
    "sparkles.rectangle.stack": "auto_awesome_motion",
    "square.and.arrow.down": "file_download",
    "square.and.arrow.up": "ios_share",
    "square.and.pencil": "edit_note",
    "square.grid.2x2": "grid_view",
    "square.grid.2x2.fill": "grid_view",
    "square.grid.3x3": "apps",
    "star": "star_outline",
    "stop.fill": "stop",
    "text.alignleft": "format_align_left",
    "text.badge.minus": "format_clear",
    "text.badge.plus": "post_add",
    "textformat": "text_fields",
    "textformat.abc": "abc",
    "trash": "delete",
    "waveform": "graphic_eq",
    "xmark": "close",
    "xmark.circle.fill": "cancel",
}


# Symbols Material has no icon for, drawn for Aria (24 x 24, filled paths; inner outlines
# are wound the other way so they cut holes).
CUSTOM = {
    # A metronome like SF Symbols' "metronome": a tapered case with a bar across its
    # foot, and a pendulum from the foot that pokes out through the right wall, with its
    # weight inside the case.
    "metronome": [
        "M9.6 2.5H14.4L19.6 21.5H4.4Z M10.9 4.1L6.5 19.9H17.5L13.1 4.1Z",
        "M7.45 16.5H16.55L16.97 18H7.03Z",
        "M11.35 16.23L12.65 16.77L16.95 6.47L15.65 5.93Z",
        "M12.69 11.86a1.25 1.25 0 1 0 2.5 0a1.25 1.25 0 1 0 -2.5 0Z",
    ],
}


# The iOS app's own images the shared views name with Image("..."), linked from its asset
# catalog so they stay the same.
IOS_ASSETS = os.path.join(os.path.dirname(__file__), "..", "..", "MuseReaderiOS", "MuseReaderiOS", "Assets.xcassets")
IMAGESETS = ["AriaLogoMark", "ScoreReaderStackedChord"]


def link_imagesets():
    for name in IMAGESETS:
        link = os.path.join(OUT_DIR, f"{name}.imageset")
        target = os.path.relpath(os.path.join(IOS_ASSETS, f"{name}.imageset"), OUT_DIR)
        if os.path.islink(link):
            os.remove(link)
        os.symlink(target, link)


def write_symbol(symbol, paths):
    folder = os.path.join(OUT_DIR, f"{symbol}.symbolset")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, f"{symbol}.svg"), "w") as f:
        f.write(svg(paths))
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1},
                   "symbols": [{"filename": f"{symbol}.svg", "idiom": "universal"}]}, f, indent=2)


def vector_xml(jar, material, filled):
    styles = [("materialicons", "baseline")] if filled else [("materialiconsoutlined", "outline"), ("materialicons", "baseline")]
    for folder, prefix in styles:
        path = f"images/material/icons/{folder}/{material}/{prefix}_{material}_24.xml"
        try:
            return jar.read(path).decode("utf-8")
        except KeyError:
            continue
    return None


def svg(paths):
    # Skip reads the paths of the Regular-M weight inside the "Symbols" group, the layout
    # of an SF Symbols template, and fits them to the symbol's bounds.
    body = "\n".join(f'      <path d="{d}"/>' for d in paths)
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g id="Symbols">
    <g id="Regular-M">
{body}
    </g>
  </g>
</svg>
'''


def main():
    jar_path = sys.argv[1] if len(sys.argv) > 1 else ANDROID_JAR
    jar = zipfile.ZipFile(jar_path)
    os.makedirs(OUT_DIR, exist_ok=True)
    missing = []
    for symbol, material in sorted(SYMBOLS.items()):
        xml = vector_xml(jar, material, symbol.endswith(".fill"))
        if xml is None:
            missing.append(f"{symbol} -> {material}")
            continue
        write_symbol(symbol, re.findall(r'android:pathData="([^"]+)"', xml))
    for symbol, paths in sorted(CUSTOM.items()):
        write_symbol(symbol, paths)
    link_imagesets()
    print(f"Wrote {len(SYMBOLS) + len(CUSTOM) - len(missing)} symbols to {os.path.normpath(OUT_DIR)}")
    if missing:
        print("Not found in the Material set:\n  " + "\n  ".join(missing))
        sys.exit(1)


if __name__ == "__main__":
    main()

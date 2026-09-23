"""Focused checks for MIDI shapes seen in the MuseScore playback corpus."""

import tempfile
import unittest
from pathlib import Path

from playback_midi import compare, summarize


def midi_file(track: bytes) -> bytes:
    return (b"MThd" + (6).to_bytes(4, "big") + b"\x00\x00\x00\x01\x01\xe0"
            + b"MTrk" + len(track).to_bytes(4, "big") + track)


class MidiComparisonTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)

    def parse(self, name: str, track: bytes) -> dict:
        path = Path(self.work.name) / name
        path.write_bytes(midi_file(track))
        return summarize(path)

    def test_five_byte_negative_preroll_delta(self):
        # MuseScore's guitar-bend fixtures encode -120 as an unsigned tick.
        score = self.parse("preroll.mid", b"\x8f\xff\xff\xff\x08\x90\x3c\x64"
                           b"\x00\x90\x3c\x00\x00\xff\x2f\x00")
        self.assertEqual(score["long_vlq_count"], 1)
        self.assertEqual(len(score["notes"]), 1)
        self.assertEqual(compare(score, score)["status"], "match")
        self.assertEqual(compare(score, score)["warnings"][0]["kind"], "nonstandard-vlq")

    def test_small_tempo_difference_is_not_hidden_by_note_tolerance(self):
        ref = self.parse("ref.mid", b"\x00\xff\x51\x03\x07\xa1\x20"
                         b"\x00\x90\x3c\x64\x83\x60\x90\x3c\x00\x00\xff\x2f\x00")
        cand = self.parse("cand.mid", b"\x00\xff\x51\x03\x07\xa1\x21"
                          b"\x00\x90\x3c\x64\x83\x60\x90\x3c\x00\x00\xff\x2f\x00")
        result = compare(ref, cand)
        self.assertEqual(result["status"], "different")
        self.assertEqual([issue["kind"] for issue in result["issues"]], ["tempo"])
        self.assertEqual(result["issues"][0]["max_note_duration_delta_us"], 1)

    def test_pitch_bend_without_range_setup_remains_visible(self):
        prefix = b"\x00\x90\x3c\x64\x00\xe0\x00\x50\x83\x60\x90\x3c\x00\x00\xff\x2f\x00"
        setup = (b"\x00\xb0\x64\x00\x00\xb0\x65\x00\x00\xb0\x06\x0c"
                 b"\x00\xb0\x64\x7f\x00\xb0\x65\x7f")
        ref = self.parse("rpn.mid", setup + prefix)
        cand = self.parse("no-rpn.mid", prefix)
        result = compare(ref, cand)
        self.assertEqual(result["status"], "different")
        self.assertEqual([issue["kind"] for issue in result["issues"]], ["rpn-bend-risk"])


if __name__ == "__main__":
    unittest.main()

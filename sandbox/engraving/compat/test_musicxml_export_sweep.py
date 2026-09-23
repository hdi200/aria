"""Unit checks for semantic MusicXML comparison without launching MuseScore."""

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from musicxml_export_sweep import compare_semantics, make_records, mscore_stage, semantic_events


def score_xml(divisions, note_duration, pitch="C", lyric="hello"):
    return f"""<?xml version="1.0" encoding="utf-8"?>
<score-partwise version="4.0">
  <part-list><score-part id="P1"><part-name>Voice</part-name></score-part></part-list>
  <part id="P1"><measure number="1">
    <attributes><divisions>{divisions}</divisions></attributes>
    <direction><direction-type><dynamics><f /></dynamics></direction-type><sound tempo="120"/></direction>
    <harmony><root><root-step>C</root-step></root><kind>major</kind></harmony>
    <note><pitch><step>{pitch}</step><octave>4</octave></pitch>
      <duration>{note_duration}</duration><voice>1</voice><tie type="start" />
      <lyric number="1"><syllabic>single</syllabic><text>{lyric}</text></lyric></note>
    <backup><duration>{note_duration}</duration></backup>
    <note><rest/><duration>{note_duration}</duration><voice>2</voice></note>
  </measure></part>
</score-partwise>"""


class SemanticMusicXmlTests(unittest.TestCase):
    def test_equivalent_divisions_and_voice_cursor(self):
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.musicxml"
            second = Path(directory) / "second.musicxml"
            first.write_text(score_xml(480, 480))
            second.write_text(score_xml(10080, 10080))
            a = semantic_events(first)
            b = semantic_events(second)
            self.assertEqual(compare_semantics(a, b), {})
            self.assertEqual(len(a["notes"]), 2)
            self.assertEqual(len(a["lyrics"]), 1)
            self.assertEqual(len(a["chords"]), 1)
            self.assertEqual(len(a["dynamics"]), 1)

    def test_pitch_and_lyric_loss_are_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.musicxml"
            second = Path(directory) / "second.musicxml"
            first.write_text(score_xml(480, 480))
            second.write_text(score_xml(480, 480, pitch="D", lyric="goodbye"))
            differences = compare_semantics(semantic_events(first), semantic_events(second))
            self.assertEqual(set(differences), {"notes", "lyrics"})

    def test_missing_part_name_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.musicxml"
            second = Path(directory) / "second.musicxml"
            first.write_text(score_xml(480, 480))
            second.write_text(score_xml(480, 480).replace("<part-name>Voice</part-name>",
                                                       "<part-name></part-name>"))
            differences = compare_semantics(semantic_events(first), semantic_events(second))
            self.assertEqual(set(differences), {"parts"})

    def test_batch_conversion_keeps_failures_per_score(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            records = make_records([root / "first.mscx", root / "second.mscx"], root)

            def fake_convert(_mscore, pairs, _work, parallel, force, label):
                self.assertEqual((parallel, force, label), (2, False, "normalize"))
                self.assertEqual(len(pairs), 2)
                first_output = pairs[0][1]
                import zipfile
                with zipfile.ZipFile(first_output, "w") as archive:
                    archive.writestr("score.mscx", "<museScore/>")
                return {first_output}

            with patch("musicxml_export_sweep.mscore_convert_all", side_effect=fake_convert):
                mscore_stage(records, "source", "start", "unused", root, 2, False, "normalize")
            self.assertEqual(records[0]["status"], "pending")
            self.assertEqual(records[1]["status"], "failed")
            self.assertEqual(records[1]["stage"], "normalize")
            self.assertEqual(records[1]["origin"], "reference")


if __name__ == "__main__":
    unittest.main()

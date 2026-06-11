/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 *
 * MuseScore Studio
 * Music Composition & Notation
 *
 * Copyright (C) 2021 MuseScore Limited
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
#include <gtest/gtest.h>

#include <QByteArray>
#include <QDir>

#include <sstream>
#include <string>
#include <vector>

#include "io/buffer.h"

#include "engraving/dom/chord.h"
#include "engraving/dom/harmony.h"
#include "engraving/dom/masterscore.h"
#include "engraving/dom/measure.h"
#include "engraving/dom/note.h"
#include "engraving/dom/rest.h"
#include "engraving/dom/segment.h"
#include "engraving/infrastructure/mscreader.h"
#include "engraving/infrastructure/mscwriter.h"

#include "utils/scorerw.h"

using namespace muse;
using namespace muse::io;
using namespace mu::engraving;

namespace {
std::vector<std::string> scoreMusicSignature(Score* score)
{
    std::vector<std::string> signature;
    if (!score) {
        return signature;
    }

    int measureIndex = 0;
    for (Measure* measure = score->firstMeasure(); measure; measure = measure->nextMeasure(), ++measureIndex) {
        for (Segment* segment = measure->first(); segment; segment = segment->next()) {
            if (!segment->isChordRestType()) {
                continue;
            }

            for (track_idx_t track = 0; track < score->ntracks(); ++track) {
                EngravingItem* item = segment->element(track);
                if (!item || !item->isChordRest()) {
                    continue;
                }

                ChordRest* chordRest = toChordRest(item);
                std::ostringstream out;
                out << measureIndex
                    << "|tick=" << segment->tick().toString().toStdString()
                    << "|track=" << track
                    << "|dur=" << chordRest->actualTicks().toString().toStdString()
                    << "|dots=" << chordRest->actualDots();

                if (item->isChord()) {
                    Chord* chord = toChord(item);
                    out << "|chord";
                    for (const Note* note : chord->notes()) {
                        out << "|note=" << note->pitch()
                            << "," << note->tpc()
                            << ",tieFor=" << (note->tieFor() ? 1 : 0)
                            << ",tieBack=" << (note->tieBack() ? 1 : 0);
                    }
                } else if (item->isRest()) {
                    Rest* rest = toRest(item);
                    out << "|rest"
                        << "|measureRest=" << (rest->isMeasureRest() ? 1 : 0);
                }

                signature.push_back(out.str());
            }

            for (EngravingItem* annotation : segment->annotations()) {
                if (!annotation || !annotation->isHarmony()) {
                    continue;
                }

                Harmony* harmony = toHarmony(annotation);
                std::ostringstream out;
                out << measureIndex
                    << "|tick=" << segment->tick().toString().toStdString()
                    << "|track=" << harmony->track()
                    << "|harmony"
                    << "|root=" << harmony->rootTpc()
                    << "|bass=" << harmony->bassTpc()
                    << "|name=" << harmony->harmonyName().toStdString();
                signature.push_back(out.str());
            }
        }
    }

    return signature;
}
}

class Engraving_MsczFileTests : public ::testing::Test
{
public:
};

TEST_F(Engraving_MsczFileTests, MsczFile_WriteRead)
{
    //! CASE Writing and reading multiple datas

    //! GIVEN Some datas

    const ByteArray originScoreData("score");
    const ByteArray originImageData("image");
    const ByteArray originThumbnailData("thumbnail");

    //! DO Write datas
    ByteArray msczData;
    {
        Buffer buf(&msczData);
        MscWriter::Params params;
        params.device = &buf;
        params.filePath = "simple1.mscz";
        params.mode = MscIoMode::Zip;

        MscWriter writer(params);
        writer.open();

        writer.writeScoreFile(originScoreData);
        writer.writeThumbnailFile(originThumbnailData);
        writer.addImageFile(u"image1.png", originImageData);
    }

    //! CHECK Read and compare with origin
    {
        Buffer buf(&msczData);
        MscReader::Params params;
        params.device = &buf;
        params.filePath = "simple1.mscz";
        params.mode = MscIoMode::Zip;

        MscReader reader(params);
        reader.open();

        ByteArray scoreData = reader.readScoreFile();
        EXPECT_EQ(scoreData, originScoreData);

        ByteArray thumbnailData = reader.readThumbnailFile();
        EXPECT_EQ(thumbnailData, originThumbnailData);

        std::vector<String> images = reader.imageFileNames();
        ByteArray imageData = reader.readImageFile(u"image1.png");
        EXPECT_EQ(images.size(), 1);
        EXPECT_EQ(images.at(0), u"image1.png");
        EXPECT_EQ(imageData, originImageData);
    }
}

TEST_F(Engraving_MsczFileTests, MsczFile_WriteReadMuseScore47CompatibilityHeader)
{
    //! CASE Writing score data through MscWriter keeps the iOS compatibility
    //! target at MuseScore 4.7.2 instead of downgrading 4.60+ XML to 4.10.

    const ByteArray originScoreData("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                                    "<museScore version=\"5.00\">\n"
                                    "  <programVersion>5.0.0</programVersion>\n"
                                    "  <programRevision>development</programRevision>\n"
                                    "  <Score>\n"
                                    "    <Staff id=\"1\">\n"
                                    "      <Measure>\n"
                                    "        <Harmony>\n"
                                    "          <harmonyInfo>\n"
                                    "            <name>6</name>\n"
                                    "            <root>11</root>\n"
                                    "          </harmonyInfo>\n"
                                    "        </Harmony>\n"
                                    "      </Measure>\n"
                                    "    </Staff>\n"
                                    "  </Score>\n"
                                    "</museScore>\n");

    ByteArray msczData;
    {
        Buffer buf(&msczData);
        MscWriter::Params params;
        params.device = &buf;
        params.filePath = "compat.mscz";
        params.mode = MscIoMode::Zip;

        MscWriter writer(params);
        writer.open();
        writer.writeScoreFile(originScoreData);
    }

    Buffer buf(&msczData);
    MscReader::Params params;
    params.device = &buf;
    params.filePath = "compat.mscz";
    params.mode = MscIoMode::Zip;

    MscReader reader(params);
    reader.open();

    ByteArray scoreData = reader.readScoreFile();
    std::string saved(scoreData.constChar(), scoreData.size());

    EXPECT_NE(saved.find("<museScore version=\"4.70\">"), std::string::npos);
    EXPECT_NE(saved.find("<programVersion>4.7.2</programVersion>"), std::string::npos);
    EXPECT_NE(saved.find("<programRevision>69af3e1</programRevision>"), std::string::npos);
    EXPECT_NE(saved.find("<harmonyInfo>"), std::string::npos);
    EXPECT_EQ(saved.find("<museScore version=\"4.10\">"), std::string::npos);
}

TEST_F(Engraving_MsczFileTests, MsczFile_WriteReadMuseScore47CompatibilityStyle)
{
    //! CASE Standalone score_style.mss data is kept aligned with the MuseScore
    //! 4.7.2 compatibility target and filters newer style keys.

    const ByteArray originStyleData("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                                    "<museScore version=\"5.00\">\n"
                                    "  <Style>\n"
                                    "    <spatium>1.76389</spatium>\n"
                                    "    <instrumentNamesFormatLong>nameInTransposition</instrumentNamesFormatLong>\n"
                                    "    <groupBracketFontFace>Edwin</groupBracketFontFace>\n"
                                    "  </Style>\n"
                                    "</museScore>\n");

    ByteArray msczData;
    {
        Buffer buf(&msczData);
        MscWriter::Params params;
        params.device = &buf;
        params.filePath = "style-compat.mscz";
        params.mode = MscIoMode::Zip;

        MscWriter writer(params);
        writer.open();
        writer.writeStyleFile(originStyleData);
    }

    Buffer buf(&msczData);
    MscReader::Params params;
    params.device = &buf;
    params.filePath = "style-compat.mscz";
    params.mode = MscIoMode::Zip;

    MscReader reader(params);
    reader.open();

    ByteArray styleData = reader.readStyleFile();
    std::string saved(styleData.constChar(), styleData.size());

    EXPECT_NE(saved.find("<museScore version=\"4.70\">"), std::string::npos);
    EXPECT_NE(saved.find("<spatium>1.76389</spatium>"), std::string::npos);
    EXPECT_EQ(saved.find("<museScore version=\"5.00\">"), std::string::npos);
    EXPECT_EQ(saved.find("instrumentNamesFormatLong"), std::string::npos);
    EXPECT_EQ(saved.find("groupBracketFontFace"), std::string::npos);
}

TEST_F(Engraving_MsczFileTests, MsczFile_ExportKeepsLegacyScoreMusicIntact)
{
    //! CASE Exporting an older MuseScore score may normalize XML/package
    //! shape, but it must not add, remove, or rewrite musical content.

    MasterScore* original = ScoreRW::readScore(u"../../../src/engraving/tests/all_elements_data/goldberg.mscx");
    ASSERT_TRUE(original);
    const std::vector<std::string> originalSignature = scoreMusicSignature(original);

    const String writeFile = String::fromQString(QDir::tempPath() + "/goldberg-export-roundtrip-test.mscz");
    ASSERT_TRUE(ScoreRW::saveScore(original, writeFile));
    delete original;

    MasterScore* roundTripped = ScoreRW::readScore(writeFile, true);
    ASSERT_TRUE(roundTripped);
    const std::vector<std::string> roundTrippedSignature = scoreMusicSignature(roundTripped);

    EXPECT_EQ(roundTrippedSignature, originalSignature);
    delete roundTripped;
}

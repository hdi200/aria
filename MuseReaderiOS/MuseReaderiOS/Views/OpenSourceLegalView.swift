//
//  OpenSourceLegalView.swift
//  MuseReaderiOS
//
//  Created by Codex on 5/31/26.
//

import SwiftUI

struct OpenSourceLegalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LegalSection(title: "Aria") {
                        Text("Aria includes MuseScore Studio-derived notation, engraving, MusicXML, playback, and render-core code. MuseScore Studio is licensed under the GNU General Public License version 3.")
                        Text("The source code for the corresponding release is available with the public source release for this app.")
                        Text("This program is provided without warranty, to the extent permitted by law.")
                    }

                    LegalSection(title: "Core Licenses") {
                        LegalNoticeRow(name: "MuseScore Studio", detail: "GPLv3")
                        LegalNoticeRow(name: "FluidSynth", detail: "LGPL 2.1")
                        LegalNoticeRow(name: "FreeType", detail: "FreeType License or GPL-compatible option")
                        LegalNoticeRow(name: "Opus", detail: "BSD-style license")
                        LegalNoticeRow(name: "BravuraText", detail: "SIL Open Font License 1.1")
                        LegalNoticeRow(name: "MuseScore General SoundFonts", detail: "MIT according to embedded SoundFont metadata")
                    }

                    LegalSection(title: "Included Files") {
                        Text("Full license texts and third-party notices are bundled in the app resources under Legal and included in the source release.")
                    }
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.primary)
                .padding(.horizontal, 22)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Open Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct LegalSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LegalNoticeRow: View {
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }
}


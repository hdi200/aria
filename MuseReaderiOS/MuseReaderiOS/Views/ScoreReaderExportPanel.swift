//
//  ScoreReaderExportPanel.swift
//  MuseReaderiOS
//

import SwiftUI
import UIKit

enum ScoreReaderExportFormat: String, CaseIterable, Identifiable {
    case museScore
    case pdf
    case musicXML
    case midi
    case audio
    case images

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .museScore:
            return ".mscz"
        case .pdf:
            return "PDF"
        case .musicXML:
            return "MusicXML"
        case .midi:
            return "MIDI"
        case .audio:
            return "Audio"
        case .images:
            return "Images"
        }
    }

    var subtitle: String {
        switch self {
        case .museScore:
            return "Native MuseScore file"
        case .pdf:
            return "Best for sharing & printing"
        case .musicXML:
            return ".musicxml or .xml"
        case .midi:
            return ".mid for playback / DAW"
        case .audio:
            return ".wav"
        case .images:
            return "PNG pages"
        }
    }

    var systemImage: String {
        switch self {
        case .museScore:
            return "doc.badge.gearshape"
        case .pdf:
            return "doc.richtext"
        case .musicXML:
            return "doc.text"
        case .midi:
            return "music.note"
        case .audio:
            return "waveform"
        case .images:
            return "photo.on.rectangle"
        }
    }

    var tint: Color {
        switch self {
        case .museScore:
            return Color.gray
        case .pdf:
            return Color.red
        case .musicXML:
            return Color.gray
        case .midi:
            return Color.purple
        case .audio:
            return Color.green
        case .images:
            return Color.blue
        }
    }

    var isAvailable: Bool {
        switch self {
        case .museScore, .pdf, .musicXML, .midi, .audio, .images:
            return true
        }
    }
}

struct ScoreReaderExportDraft {
    var includesFullScore = true
    var includesParts = false
    var format: ScoreReaderExportFormat = .pdf
    var selectedPartIDs: Set<String> = []
    var fileName = ""
    var exportPartsInConcertPitch = false

    var hasExportContent: Bool {
        includesFullScore || includesParts
    }
}

struct ScoreReaderSharedExportItems: Identifiable {
    let urls: [URL]

    var id: String {
        urls.map(\.absoluteString).joined(separator: "|")
    }
}

enum ScoreReaderExportError: LocalizedError {
    case unsupportedFormat(String)
    case noContentSelected
    case noPages
    case noAudio
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "\(format) export is not available in the current render bridge."
        case .noContentSelected:
            return "Choose at least one export target."
        case .noPages:
            return "There are no rendered pages to export."
        case .noAudio:
            return "There is no playback audio to export."
        case .imageEncodingFailed:
            return "Aria could not encode one of the score pages."
        }
    }
}

enum ScoreReaderExportTarget {
    case fullScore(pageCount: Int)
    case part(ScorePart, pageCount: Int)

    var pageCount: Int {
        switch self {
        case .fullScore(let pageCount), .part(_, let pageCount):
            return pageCount
        }
    }
}

struct ScoreReaderExportPanel: View {
    let scoreTitle: String
    let parts: [ScorePart]
    @Binding var draft: ScoreReaderExportDraft
    let isPreparingExport: Bool
    let cancelAction: () -> Void
    let exportAction: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: isPhone ? 10 : 18) {
                VStack(alignment: .leading, spacing: isPhone ? 2 : 4) {
                    Text("Export Score")
                        .font(.system(size: isPhone ? 18 : 20, weight: .semibold))
                    if !isPhone {
                        Text("Choose content and format")
                            .font(.subheadline)
                            .foregroundStyle(Color.black.opacity(0.52))
                    }
                }

                VStack(alignment: .leading, spacing: isPhone ? 5 : 8) {
                    sectionTitle("What to export")
                    VStack(spacing: 0) {
                        exportContentRow(
                            title: "Full Score",
                            isSelected: draft.includesFullScore,
                            isRequiredSelection: !draft.includesParts
                        ) {
                            if draft.includesFullScore && !draft.includesParts {
                                return
                            }
                            draft.includesFullScore.toggle()
                        }
                        Divider().padding(.leading, 40)
                        exportContentRow(
                            title: "Parts",
                            isSelected: draft.includesParts,
                            isRequiredSelection: !draft.includesFullScore
                        ) {
                            if draft.includesParts && !draft.includesFullScore {
                                return
                            }
                            draft.includesParts.toggle()
                        }
                        if draft.includesParts, !parts.isEmpty {
                            Divider().padding(.leading, 40)
                            partSelector
                        }
                    }
                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(panelBorder)
                }

                VStack(alignment: .leading, spacing: isPhone ? 5 : 8) {
                    sectionTitle("Format")
                    VStack(spacing: 0) {
                        ForEach(Array(ScoreReaderExportFormat.allCases.enumerated()), id: \.element.id) { index, format in
                            if index > 0 {
                                Divider().padding(.leading, 54)
                            }
                            formatRow(format)
                        }
                    }
                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(panelBorder)
                }

                if showsExportPartsInConcertRow {
                    exportPartsInConcertRow
                }

                filenameRow

                HStack(spacing: isPhone ? 8 : 10) {
                    Button(action: cancelAction) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ScoreReaderExportFooterButtonStyle(isPrimary: false, isCompact: isPhone))

                    Button(action: exportAction) {
                        if isPreparingExport {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Export")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(ScoreReaderExportFooterButtonStyle(isPrimary: true, isCompact: isPhone))
                    .disabled(isPreparingExport || !draft.format.isAvailable || !draft.hasExportContent)
                }
            }
            .padding(isPhone ? 14 : 22)
        }
        .font(.system(size: isPhone ? 13 : 14, weight: .medium))
        .foregroundStyle(Color.black.opacity(0.86))
        .frame(width: panelWidth)
        .frame(maxHeight: panelMaxHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.62), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 28, y: 16)
        .onAppear {
            if draft.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.fileName = scoreTitle
            }
            if draft.selectedPartIDs.isEmpty {
                draft.selectedPartIDs = Set(parts.map(\.id))
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: isPhone ? 12 : 15, weight: .semibold))
            .foregroundStyle(Color.black.opacity(isPhone ? 0.58 : 0.86))
    }

    private var panelWidth: CGFloat {
        let phoneWidth: CGFloat = UIScreen.main.bounds.width > UIScreen.main.bounds.height ? 360 : 332
        return min(isPhone ? phoneWidth : 380, max(UIScreen.main.bounds.width - 24, 300))
    }

    private var panelMaxHeight: CGFloat {
        isPhone ? min(UIScreen.main.bounds.height - 72, 720) : min(UIScreen.main.bounds.height - 80, 940)
    }

    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private func exportContentRow(
        title: String,
        isSelected: Bool,
        isRequiredSelection: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.blue : Color.black.opacity(0.34))
                    .font(.system(size: isPhone ? 17 : 20, weight: .semibold))
                Text(title)
                Spacer()
                if isRequiredSelection && !isPhone {
                    Text("Required")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.38))
                }
            }
            .frame(height: isPhone ? 36 : 44)
            .padding(.horizontal, isPhone ? 11 : 14)
        }
        .buttonStyle(.plain)
    }

    private var partSelector: some View {
        VStack(alignment: .leading, spacing: isPhone ? 6 : 9) {
            Text("Select Parts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.64))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(parts) { part in
                        Button {
                            togglePart(part.id)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: draft.selectedPartIDs.contains(part.id) ? "checkmark.square.fill" : "square")
                                Text(part.name)
                                    .lineLimit(1)
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.blue)
                            .padding(.horizontal, 7)
                            .frame(height: 25)
                            .background(Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, isPhone ? 11 : 14)
        .padding(.vertical, isPhone ? 8 : 12)
    }

    private func formatRow(_ format: ScoreReaderExportFormat) -> some View {
        Button {
            guard format.isAvailable else {
                return
            }
            draft.format = format
        } label: {
            HStack(spacing: isPhone ? 9 : 12) {
                Image(systemName: format.systemImage)
                    .font(.system(size: isPhone ? 16 : 20, weight: .semibold))
                    .foregroundStyle(format.tint)
                    .frame(width: isPhone ? 26 : 32, height: isPhone ? 26 : 32)
                    .background(format.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: isPhone ? 6 : 7, style: .continuous))

                VStack(alignment: .leading, spacing: isPhone ? 1 : 3) {
                    HStack(spacing: 6) {
                        Text(format.title)
                        if !format.isAvailable {
                            Text("Soon")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.black.opacity(0.42))
                        }
                    }
                    if !isPhone {
                        Text(format.subtitle)
                            .font(.caption)
                            .foregroundStyle(Color.black.opacity(0.50))
                    }
                }

                Spacer()

                Image(systemName: draft.format == format ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(draft.format == format ? Color.blue : Color.black.opacity(0.32))
                    .font(.system(size: isPhone ? 17 : 20, weight: .semibold))
            }
            .padding(.horizontal, isPhone ? 11 : 14)
            .frame(height: isPhone ? 42 : 62)
            .opacity(format.isAvailable ? 1 : 0.44)
        }
        .buttonStyle(.plain)
        .disabled(!format.isAvailable)
    }

    private var filenameRow: some View {
        HStack {
            Text("Filename")
            Spacer()
            TextField(scoreTitle, text: $draft.fileName)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .frame(maxWidth: isPhone ? 160 : 190)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.black.opacity(0.32))
        }
        .padding(.horizontal, isPhone ? 12 : 16)
        .frame(height: isPhone ? 42 : 54)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(panelBorder)
    }

    private var showsExportPartsInConcertRow: Bool {
        draft.format == .pdf && !parts.isEmpty
    }

    private var exportPartsInConcertRow: some View {
        Button {
            draft.exportPartsInConcertPitch.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: draft.exportPartsInConcertPitch ? "checkmark.square.fill" : "square")
                    .foregroundStyle(draft.exportPartsInConcertPitch ? Color.blue : Color.black.opacity(0.34))
                    .font(.system(size: isPhone ? 17 : 20, weight: .semibold))
                Text("Export parts in concert")
                Spacer()
            }
            .padding(.horizontal, isPhone ? 12 : 16)
            .frame(height: isPhone ? 42 : 54)
            .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(panelBorder)
        }
        .buttonStyle(.plain)
        .disabled(!draft.includesParts)
        .opacity(draft.includesParts ? 1 : 0.46)
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(Color.black.opacity(0.08), lineWidth: 1)
    }

    private func togglePart(_ id: String) {
        if draft.selectedPartIDs.contains(id) {
            if draft.selectedPartIDs.count > 1 {
                draft.selectedPartIDs.remove(id)
            }
        } else {
            draft.selectedPartIDs.insert(id)
        }
    }
}

private struct ScoreReaderExportFooterButtonStyle: ButtonStyle {
    let isPrimary: Bool
    var isCompact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: isCompact ? 14 : 15, weight: .semibold))
            .foregroundStyle(isPrimary ? Color.white : Color.black.opacity(0.86))
            .frame(height: isCompact ? 42 : 52)
            .background(
                isPrimary
                    ? Color.blue.opacity(configuration.isPressed ? 0.82 : 1)
                    : Color.white.opacity(configuration.isPressed ? 0.64 : 0.86),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.black.opacity(isPrimary ? 0 : 0.08), lineWidth: 1)
            }
    }
}

struct ScoreReaderShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

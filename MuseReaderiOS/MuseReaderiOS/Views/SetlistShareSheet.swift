//
//  SetlistShareSheet.swift
//  MuseReaderiOS
//
//

import SwiftUI

struct SetlistShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MuseReaderAppModel

    let setlist: LibrarySetlistFolder

    @State private var format: ScoreReaderExportFormat = .pdf
    @State private var combinesPDFPages = false
    @State private var preparedShareItems: ScoreReaderSharedExportItems?
    @State private var preparedScoreCount = 0
    @State private var prepareTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var skippedScores: [SetlistShareFailure] = []

    private var scores: [ReaderRecentDocument] {
        model.orderedScores(in: setlist)
    }

    private var isPreparing: Bool {
        prepareTask != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if scores.isEmpty {
                    emptyState
                } else {
                    shareOptions
                }
            }
            .navigationTitle("Share \(setlist.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        cancelPreparation()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        prepareShareItems()
                    }
                    .fontWeight(.semibold)
                    .disabled(scores.isEmpty || isPreparing)
                }
            }
            .overlay {
                if isPreparing {
                    preparingOverlay
                }
            }
        }
        .frame(minWidth: 320, idealWidth: 520, minHeight: 420, idealHeight: 640)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isPreparing)
        .alert("Could Not Share Setlist", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Aria could not prepare this setlist for sharing.")
        }
        // Staying put when scores were skipped lets the sheet report what did
        // not make it into the share.
        .sheet(item: $preparedShareItems, onDismiss: {
            if skippedScores.isEmpty {
                dismiss()
            }
        }) { shareItems in
            ScoreReaderShareSheetView(activityItems: shareItems.urls)
        }
    }

    private var shareOptions: some View {
        List {
            Section {
                ForEach(ScoreReaderExportFormat.setlistShareFormats) { option in
                    Button {
                        format = option
                    } label: {
                        formatRow(option)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Format")
            } footer: {
                Text(formatFooter)
            }

            if format == .pdf {
                Section {
                    Toggle("Combine into one PDF", isOn: $combinesPDFPages)
                        .tint(LibraryPalette.accent)
                }
            }

            if !skippedScores.isEmpty {
                Section {
                    ForEach(skippedScores) { failure in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(failure.scoreTitle)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(LibraryPalette.ink)
                            Text(failure.message)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(LibraryPalette.mutedInk)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Skipped")
                } footer: {
                    Text("These scores were left out of the share.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .disabled(isPreparing)
    }

    private func formatRow(_ option: ScoreReaderExportFormat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: option.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(option.tint)
                .frame(width: 30, height: 30)
                .background(option.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(option.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LibraryPalette.ink)
                Text(option.subtitle)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(LibraryPalette.mutedInk)
            }

            Spacer(minLength: 0)

            Image(systemName: format == option ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(format == option ? LibraryPalette.accent : LibraryPalette.subtle)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(option.title)
        .accessibilityValue(format == option ? "Selected" : "Not selected")
    }

    private var formatFooter: String {
        let scoreCount = scores.count
        if format == .pdf, combinesPDFPages {
            return "All \(scoreCount) \(scoreCount == 1 ? "score" : "scores") are merged into a single PDF in setlist order."
        }

        return "Each score is shared as its own \(format.title) file using the score title as its filename."
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(LibraryPalette.subtle)
            Text("Add scores to this setlist before sharing it.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LibraryPalette.mutedInk)
                .multilineTextAlignment(.center)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LibraryPalette.mainBackground)
    }

    private var preparingOverlay: some View {
        ZStack {
            Color.black.opacity(0.06)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                ProgressView()
                Text(preparingLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LibraryPalette.mutedInk)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var preparingLabel: String {
        let scoreCount = scores.count
        guard scoreCount > 1 else {
            return "Preparing score…"
        }
        return "Preparing \(min(preparedScoreCount + 1, scoreCount)) of \(scoreCount)…"
    }

    private var errorIsPresented: Binding<Bool> {
        Binding {
            errorMessage != nil
        } set: { isPresented in
            if !isPresented {
                errorMessage = nil
            }
        }
    }

    private func prepareShareItems() {
        guard prepareTask == nil else {
            return
        }

        let sharedScores = scores
        let setlistName = setlist.name
        let selectedFormat = format
        let combinesPDFs = combinesPDFPages
        preparedScoreCount = 0
        skippedScores = []
        errorMessage = nil

        prepareTask = Task { @MainActor in
            do {
                let preparation = try await SetlistShareExporter.prepareShareItems(
                    setlistName: setlistName,
                    scores: sharedScores,
                    format: selectedFormat,
                    combinesPDFPages: combinesPDFs,
                    model: model,
                    progress: { completedScoreCount in
                        preparedScoreCount = completedScoreCount
                    }
                )
                prepareTask = nil
                skippedScores = preparation.failures
                preparedShareItems = ScoreReaderSharedExportItems(urls: preparation.urls)
            } catch is CancellationError {
                prepareTask = nil
            } catch {
                prepareTask = nil
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func cancelPreparation() {
        prepareTask?.cancel()
        prepareTask = nil
    }
}

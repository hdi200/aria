//
//  LibraryAccessViews.swift
//  MuseReaderiOS
//

import SwiftUI

struct LibraryPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var model: MuseReaderAppModel
    @ObservedObject var accessController: LibraryAccessController

    let context: LibraryPaywallContext

    @State private var resultMessage: String?
    @State private var didUnlock = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 11) {
                    AriaLogoMark(size: 42, cornerRadius: 12)

                    Text("Aria")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(LibraryPalette.ink)

                    Text("PRO")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(LibraryPalette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(LibraryPalette.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer(minLength: 0)

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(LibraryPalette.mutedInk)
                            .frame(width: 34, height: 34)
                            .background(LibraryPalette.background, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.bottom, 30)

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [LibraryPalette.accentSoft, .white],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 96, height: 96)
                            .overlay {
                                Circle()
                                    .stroke(LibraryPalette.accent.opacity(0.13), lineWidth: 1)
                            }

                        Image(systemName: "infinity")
                            .font(.system(size: 39, weight: .semibold))
                            .foregroundStyle(LibraryPalette.accent)
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        if context != .settings {
                            Text(context.title.uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(LibraryPalette.accent)
                        }

                        Text("Unlock Aria Pro")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(LibraryPalette.ink)
                            .multilineTextAlignment(.center)

                        Text("One purchase. No subscription.")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(LibraryPalette.ink)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        PaywallBenefitRow(systemImage: "music.note.list", title: "Unlimited score library")
                        PaywallBenefitRow(systemImage: "sparkles", title: "Every feature Aria offers today")
                        PaywallBenefitRow(systemImage: "laptopcomputer.and.iphone", title: "Works across your iPhone, iPad, and Mac")
                        PaywallBenefitRow(systemImage: "person.2", title: "Included with Family Sharing")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(LibraryPalette.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                    }
                    .shadow(color: LibraryPalette.ink.opacity(0.04), radius: 14, y: 6)

                    if let resultMessage {
                        Text(resultMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(LibraryPalette.mutedInk)
                            .multilineTextAlignment(.center)
                            .accessibilityLabel(resultMessage)
                    }

                    VStack(spacing: 13) {
                        Button {
                            Task { await purchase() }
                        } label: {
                            HStack(spacing: 9) {
                                if accessController.isPerformingPurchase {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(primaryButtonTitle)
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .foregroundStyle(.white)
                            .background(LibraryPalette.accent, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .shadow(color: LibraryPalette.accent.opacity(0.20), radius: 10, y: 5)
                        }
                        .buttonStyle(.plain)
                        .disabled(accessController.isPerformingPurchase)

                        Button("Restore Purchases") {
                            Task { await restore() }
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LibraryPalette.accent)
                        .disabled(accessController.isPerformingPurchase)
                    }
                }
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 34 : 22)
            .padding(.top, 18)
            .padding(.bottom, 32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(LibraryPalette.mainBackground)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onChangeCompatible(of: accessController.status) { status in
            guard status.hasUnlimitedScores else {
                return
            }
            completeUnlock()
        }
        .onDisappear {
            if !didUnlock {
                model.cancelPendingLibraryAction()
            }
        }
    }

    private var primaryButtonTitle: String {
        if accessController.isPerformingPurchase {
            return "Contacting App Store…"
        }
        if let displayPrice = accessController.displayPrice {
            return "Unlock Forever — \(displayPrice)"
        }
        return accessController.isLoadingProduct ? "Loading Price…" : "Unlock Forever"
    }

    private func purchase() async {
        await handle(accessController.purchaseUnlimitedScores())
    }

    private func restore() async {
        await handle(accessController.restorePurchases())
    }

    private func handle(_ result: LibraryPurchaseResult) async {
        switch result {
        case .purchased, .restored:
            completeUnlock()
        case .pending:
            resultMessage = "The purchase is awaiting approval. Aria Pro will unlock automatically when it completes."
        case .cancelled:
            resultMessage = nil
        case .failed(let message):
            resultMessage = message
        }
    }

    private func completeUnlock() {
        guard !didUnlock else {
            return
        }
        didUnlock = true
        dismiss()
        model.resumePendingLibraryActionAfterUnlock()
    }
}

private struct PaywallBenefitRow: View {
    let systemImage: String
    let title: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LibraryPalette.accent)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LibraryPalette.ink)
        }
    }
}

struct ScoreImportReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: MuseReaderAppModel

    let review: ScoreImportReview

    @State private var selectedIDs: Set<UUID>
    @State private var capacityMessage: String?

    init(model: MuseReaderAppModel, review: ScoreImportReview) {
        self.model = model
        self.review = review
        _selectedIDs = State(initialValue: Self.defaultSelection(for: review))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(review.candidates) { candidate in
                        Button {
                            toggle(candidate)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(selectedIDs.contains(candidate.id) ? LibraryPalette.accent : LibraryPalette.subtle)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.url.lastPathComponent)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(LibraryPalette.ink)
                                        .lineLimit(1)
                                    Text(candidate.disposition.isReplacement ? "Replace existing · no slot used" : "Add as a new score")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(candidate.disposition.isReplacement ? LibraryPalette.accent : LibraryPalette.mutedInk)
                                }

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Selected Scores")
                } footer: {
                    VStack(alignment: .leading, spacing: 5) {
                        if review.hasDuplicateDestinations {
                            Text("Files with the same destination name conflict. Choose one from each matching group.")
                        }
                        if let capacityMessage {
                            Text(capacityMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button(primaryActionTitle) {
                        let candidates = selectedCandidates
                        dismiss()
                        model.confirmImportReview(candidates)
                    }
                    .disabled(selectedCandidates.isEmpty)

                    if review.exceedsFreeCapacity {
                        Button("Unlock & Import All") {
                            let candidates = candidatesForUnlimitedImport
                            model.unlockAndImport(candidates)
                        }
                        .foregroundStyle(LibraryPalette.accent)
                        .disabled(hasUnresolvedDuplicateConflict)
                    }
                }
            }
            .navigationTitle(reviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var selectedCandidates: [ScoreImportCandidate] {
        review.candidates.filter { selectedIDs.contains($0.id) }
    }

    private var selectedNewCount: Int {
        selectedCandidates.filter(\.disposition.usesNewSlot).count
    }

    private var reviewTitle: String {
        if review.replacementCount > 0, review.exceedsFreeCapacity {
            return "Review Replacements & New Scores"
        }
        if review.replacementCount > 0 {
            return review.replacementCount == 1 ? "Replace Existing Score?" : "Replace Existing Scores?"
        }
        return "Choose Scores to Import"
    }

    private var primaryActionTitle: String {
        guard !selectedCandidates.isEmpty else {
            return "Choose Scores"
        }
        if selectedNewCount == 0, !selectedCandidates.isEmpty {
            return selectedCandidates.count == 1 ? "Replace Score" : "Replace Selected"
        }
        return "Import Selected (\(selectedCandidates.count))"
    }

    private var candidatesForUnlimitedImport: [ScoreImportCandidate] {
        var chosen: [ScoreImportCandidate] = []
        for group in orderedGroups {
            if group.count == 1, let candidate = group.first {
                chosen.append(candidate)
            } else if let selected = group.first(where: { selectedIDs.contains($0.id) }) {
                chosen.append(selected)
            } else if let first = group.first {
                chosen.append(first)
            }
        }
        return chosen
    }

    private var hasUnresolvedDuplicateConflict: Bool {
        orderedGroups.contains { group in
            group.count > 1 && !group.contains(where: { selectedIDs.contains($0.id) })
        }
    }

    private var orderedGroups: [[ScoreImportCandidate]] {
        var keys: [String] = []
        var groups: [String: [ScoreImportCandidate]] = [:]
        for candidate in review.candidates {
            if groups[candidate.destinationKey] == nil {
                keys.append(candidate.destinationKey)
            }
            groups[candidate.destinationKey, default: []].append(candidate)
        }
        return keys.compactMap { groups[$0] }
    }

    private func toggle(_ candidate: ScoreImportCandidate) {
        capacityMessage = nil
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
            return
        }

        for conflict in review.candidates where conflict.destinationKey == candidate.destinationKey {
            selectedIDs.remove(conflict.id)
        }

        if candidate.disposition.usesNewSlot,
           !review.hasUnlimitedScores,
           selectedNewCount >= review.availableNewSlots
        {
            capacityMessage = review.availableNewSlots == 0
                ? "No free slots remain. Replace matching scores or unlock unlimited scores."
                : "Your free library has room for \(review.availableNewSlots) more score\(review.availableNewSlots == 1 ? "" : "s")."
            return
        }
        selectedIDs.insert(candidate.id)
    }

    private static func defaultSelection(for review: ScoreImportReview) -> Set<UUID> {
        var selected: Set<UUID> = []
        var usedDestinationKeys: Set<String> = []
        var selectedNewCount = 0
        let newLimit = review.hasUnlimitedScores ? Int.max : review.availableNewSlots

        for candidate in review.candidates {
            guard usedDestinationKeys.insert(candidate.destinationKey).inserted else {
                continue
            }
            if candidate.disposition.isReplacement || selectedNewCount < newLimit {
                selected.insert(candidate.id)
                if candidate.disposition.usesNewSlot {
                    selectedNewCount += 1
                }
            }
        }
        return selected
    }
}

struct EarlySupporterAccessView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(LibraryPalette.accentSoft)
                    .frame(width: 84, height: 84)
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(LibraryPalette.accent)
            }

            VStack(spacing: 9) {
                Text("Aria Pro Is Yours")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(LibraryPalette.ink)
                    .multilineTextAlignment(.center)
                Text("Thanks for being with Aria early. You have Aria Pro—no purchase needed.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LibraryPalette.mutedInk)
                    .multilineTextAlignment(.center)
            }

            Button("Continue") {
                dismiss()
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(LibraryPalette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .buttonStyle(.plain)
        }
        .padding(30)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LibraryPalette.mainBackground)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct FreeScoreAllowancePill: View {
    let used: Int
    let limit: Int

    var body: some View {
        HStack(spacing: 7) {
            Text("Free · \(min(used, limit)) of \(limit)")
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 3) {
                ForEach(0..<limit, id: \.self) { index in
                    Circle()
                        .fill(index < used ? LibraryPalette.accent : LibraryPalette.cardBorder)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .foregroundStyle(LibraryPalette.mutedInk)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(LibraryPalette.accentSoft, in: Capsule())
        .accessibilityLabel("Free library, \(min(used, limit)) of \(limit) scores used")
    }
}

struct FreeLibraryFullNotice: View {
    let unlockAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(LibraryPalette.accent)
            Text("Your free library is full. Replace a score or unlock Aria Pro.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LibraryPalette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Unlock", action: unlockAction)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(LibraryPalette.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(LibraryPalette.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct LibraryAccessSettingsCard: View {
    let status: LibraryAccessStatus
    let displayPrice: String?
    let unlockAction: () -> Void

    var body: some View {
        Button(action: buttonAction) {
            HStack(spacing: 14) {
                Image(systemName: status.hasUnlimitedScores ? "infinity.circle.fill" : "music.note.list")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(LibraryPalette.accent)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Aria Pro")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LibraryPalette.ink)
                    Text(statusDescription)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(LibraryPalette.mutedInk)
                }

                Spacer(minLength: 0)

                if !status.hasUnlimitedScores {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LibraryPalette.subtle)
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 72, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(LibraryPalette.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(status.hasUnlimitedScores)
    }

    private var statusDescription: String {
        switch status {
        case .checking:
            return "Checking App Store access…"
        case .free:
            if let displayPrice {
                return "2 scores free · Aria Pro for \(displayPrice)"
            }
            return "2 scores free · One-time Aria Pro unlock available"
        case .unlimited(let reason):
            return "Aria Pro · \(reason.settingsTitle)"
        }
    }

    private func buttonAction() {
        guard !status.hasUnlimitedScores else {
            return
        }
        unlockAction()
    }
}

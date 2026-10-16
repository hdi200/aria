import StoreKit
import SwiftUI

/// One informational card in the first-run reader tour. Each step only points a
/// feature out — nothing here asks the reader to perform the action first.
struct ScoreReaderFeatureTourStep: Identifiable {
    let id: Int
    let systemImage: String
    let title: String
    let message: String
}

/// Remembers whether the reader tour has been shown, and to whom. The tour announces
/// what this update added, so it is for people who already had the app — someone
/// installing for the first time has nothing to be told is new.
///
/// Versioned so a later release can introduce a new tour by bumping `currentVersion`.
struct ScoreReaderFeatureTourStore {
    // Still version 1: count-in is announced in the update notice instead, so people
    // who already saw this tour are not shown it again.
    static let currentVersion = 1

    // Version 6.0, which introduced the mixer and play-from-here tour, began its
    // release on September 15, 2026 at 2:00 PM Eastern. AppTransaction supplies
    // Apple's signed date for when this customer first acquired the app. That
    // remains available across an update, unlike a UserDefaults marker introduced
    // by the update itself.
    static let featureReleaseDate = Date(timeIntervalSince1970: 1_789_495_200)

    private let defaultsKey = "ScoreReaderFeatureTour.seenVersion"
    private var audienceKey: String {
        "ScoreReaderFeatureTour.v\(Self.currentVersion).isExistingInstall"
    }
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    static func isExistingInstall(originalPurchaseDate: Date) -> Bool {
        originalPurchaseDate < featureReleaseDate
    }

    /// A missing or unverified App Store transaction is left unresolved so a later
    /// score open can retry. Never guess that a customer is new and permanently hide
    /// the update tour merely because the device is temporarily offline.
    func shouldPresentTour() async -> Bool {
        guard userDefaults.integer(forKey: defaultsKey) < Self.currentVersion else {
            return false
        }

        if userDefaults.object(forKey: audienceKey) != nil {
            return userDefaults.bool(forKey: audienceKey)
        }

        guard let originalPurchaseDate = await verifiedOriginalPurchaseDate() else {
            return false
        }

        // Another scene may have completed or dismissed the tour while StoreKit
        // was resolving. Re-read both persisted values before committing our answer.
        guard userDefaults.integer(forKey: defaultsKey) < Self.currentVersion else {
            return false
        }
        if userDefaults.object(forKey: audienceKey) != nil {
            return userDefaults.bool(forKey: audienceKey)
        }

        let isExistingInstall = Self.isExistingInstall(originalPurchaseDate: originalPurchaseDate)
        userDefaults.set(isExistingInstall, forKey: audienceKey)
        return isExistingInstall
    }

    func markTourSeen() {
        userDefaults.set(Self.currentVersion, forKey: defaultsKey)
    }

    private func verifiedOriginalPurchaseDate() async -> Date? {
        do {
            guard case .verified(let transaction) = try await AppTransaction.shared else {
                return nil
            }
            return transaction.originalPurchaseDate
        } catch {
            return nil
        }
    }
}

struct ScoreReaderFeatureTour: View {
    let steps: [ScoreReaderFeatureTourStep]
    let dismiss: () -> Void

    @State var stepIndex = 0

    static let defaultSteps: [ScoreReaderFeatureTourStep] = [
        ScoreReaderFeatureTourStep(
            id: 0,
            systemImage: "slider.vertical.3",
            title: "Mix each instrument",
            message: "Use the mixer to adjust volume and pan, or mute and solo any part. "
                + "Your mix is saved with this score."
        ),
        ScoreReaderFeatureTourStep(
            id: 1,
            systemImage: "play.circle.fill",
            title: "Play or loop any passage",
            message: "In View mode, touch and hold a measure, then choose Play from here. "
                + "Drag across measures to loop a section instead."
        )
    ]

    private var step: ScoreReaderFeatureTourStep? {
        steps.indices.contains(stepIndex) ? steps[stepIndex] : nil
    }

    private var isLastStep: Bool {
        stepIndex >= steps.count - 1
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { advance() }

            if let step {
                card(for: step)
                    .padding(.horizontal, 28)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .id(step.id)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: stepIndex)
        .accessibilityAddTraits(.isModal)
    }

    private func card(for step: ScoreReaderFeatureTourStep) -> some View {
        VStack(spacing: 16) {
            Image(systemName: step.systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 68, height: 68)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(step.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                Text(step.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if steps.count > 1 {
                HStack(spacing: 6) {
                    ForEach(steps.indices, id: \.self) { index in
                        Circle()
                            .fill(index == stepIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }

            Button(action: advance) {
                Text(isLastStep ? "Got it" : "Next")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(step.title). \(step.message)")
    }

    private func advance() {
        guard !isLastStep else {
            dismiss()
            return
        }
        stepIndex += 1
    }
}

import SwiftUI

struct ScoreLegacyRepairPrompt: Identifiable {
    let id = UUID()
    let issues: [ScoreLegacyRepairIssue]
}

struct ScoreLegacyRepairSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndexes: Set<Int>
    @State private var isFixing = false
    @State private var errorMessage: String?

    let issues: [ScoreLegacyRepairIssue]
    let fixSelected: @MainActor ([Int]) async throws -> Void

    init(issues: [ScoreLegacyRepairIssue], fixSelected: @escaping @MainActor ([Int]) async throws -> Void) {
        self.issues = issues
        self.fixSelected = fixSelected
        _selectedIndexes = State(initialValue: Set(issues.map(\.index)))
    }

    /// Most of these come from earlier versions of Aria; an extra starting clef can also come
    /// from desktop's clef palette, so the headline only blames Aria when every issue is Aria's.
    private var headline: String {
        let found = "Aria found \(issues.count) issue\(issues.count == 1 ? "" : "s") in this score"
        let allFromEarlierAria = issues.allSatisfy { $0.kind != "strayClef" }
        let cause = allFromEarlierAria ? ", left by an earlier version of Aria," : ""
        return "\(found)\(cause) that it can fix. Review each one below. Nothing changes unless you fix it."
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.top, 12)

                List(issues) { issue in
                    Button {
                        if selectedIndexes.contains(issue.index) {
                            selectedIndexes.remove(issue.index)
                        } else {
                            selectedIndexes.insert(issue.index)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedIndexes.contains(issue.index) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selectedIndexes.contains(issue.index) ? Color.accentColor : Color.secondary)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.title).font(.body.weight(.semibold))
                                Text(issue.message).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(issue.title)
                    .accessibilityValue(selectedIndexes.contains(issue.index) ? "Selected" : "Not selected")
                    .disabled(isFixing)
                }

                VStack(spacing: 12) {
                    Text("Aria saves an untouched copy in Files → Aria Backups before changing the score.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button {
                        isFixing = true
                        errorMessage = nil
                        Task { @MainActor in
                            do {
                                try await fixSelected(selectedIndexes.sorted())
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                isFixing = false
                            }
                        }
                    } label: {
                        if isFixing {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(selectedIndexes.count == issues.count ? "Back Up & Fix All" : "Back Up & Fix Selected")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedIndexes.isEmpty || isFixing)
                    .accessibilityIdentifier("legacyRepairFixSelected")
                }
                .padding()
            }
            .navigationTitle("Review Score Fixes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }.disabled(isFixing)
                }
            }
        }
        .frame(maxWidth: 560)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isFixing)
    }
}

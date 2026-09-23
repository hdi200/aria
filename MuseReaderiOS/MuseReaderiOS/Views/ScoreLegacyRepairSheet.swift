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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Aria found \(issues.count) older score issue\(issues.count == 1 ? "" : "s") that can be fixed from matching markings in the full score or linked parts. Review each one below.")
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

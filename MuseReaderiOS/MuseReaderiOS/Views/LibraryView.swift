//
//  LibraryView.swift
//  MuseReaderiOS
//
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: MuseReaderAppModel
    @ObservedObject private var accessController: LibraryAccessController

    @State private var searchText = ""
    @State private var selectedCategory: LibraryCategory = .allScores
    @State private var readerPresentation: LibraryReaderPresentation?
    @State private var pendingCreatedReaderPresentation: LibraryReaderPresentation?
    @State private var scorePendingDeletion: ReaderRecentDocument?
    @State private var scoreInfoEditorSession: ScoreSession?
    @State private var editableScoreInfo = ScoreEditableMetadata()
    @State private var isSavingScoreInfo = false
    @State private var scoreInfoSaveErrorMessage: String?
    @State private var isNewSetlistPresented = false
    @State private var newSetlistName = ""
    @State private var folderPendingRename: LibrarySetlistFolder?
    @State private var folderPendingScoreAdd: FolderScoreAddRequest?
    @State private var isSetlistReorderPresented = false
    @State private var isEditingActiveSetlist = false
    @State private var renameSetlistName = ""
    @State private var scorePendingFolderSelection: ReaderRecentDocument?
    @State private var isOpenSourceLegalPresented = false
    @AppStorage("LibraryScoreSortOrder") private var scoreSortOrder = LibraryScoreSortOrder.recentlyOpened
    @AppStorage("LibraryDashboardScoreLayout") private var dashboardScoreLayout = LibraryScoreLayout.medium
    @AppStorage("LibraryPhoneScoreLayout") private var phoneScoreLayout = LibraryScoreLayout.list
    @AppStorage("SetlistScoreSortOrder") private var setlistScoreSortOrder = LibraryScoreSortOrder.setlistOrder
    @AppStorage("SetlistDashboardScoreLayout") private var setlistDashboardScoreLayout = LibraryScoreLayout.medium
    @AppStorage("SetlistPhoneScoreLayout") private var setlistPhoneScoreLayout = LibraryScoreLayout.list

    private let sidebarWidth: CGFloat = 286

    init(model: MuseReaderAppModel) {
        self.model = model
        _accessController = ObservedObject(wrappedValue: model.libraryAccessController)
    }

    private var activeSetlistFolder: LibrarySetlistFolder? {
        guard case .setlist(let folderID) = selectedCategory else {
            return nil
        }
        return model.setlistFolders.first { $0.id == folderID }
    }

    private var displayedScores: [ReaderRecentDocument] {
        let baseScores: [ReaderRecentDocument]
        let activeSortOrder: LibraryScoreSortOrder
        switch selectedCategory {
        case .allScores:
            baseScores = model.recents
            activeSortOrder = scoreSortOrder
        case .setlists, .settings:
            baseScores = []
            activeSortOrder = scoreSortOrder
        case .setlist(let folderID):
            if let folder = model.setlistFolders.first(where: { $0.id == folderID }) {
                baseScores = model.orderedScores(in: folder)
            } else {
                baseScores = []
            }
            activeSortOrder = setlistScoreSortOrder
        }

        let filteredScores = LibraryScoreDisplayPolicy.filtered(baseScores, query: searchText)
        return activeSortOrder.sorted(filteredScores)
    }

    private var displayedCategoryTitle: String {
        if case .setlist(let folderID) = selectedCategory,
           let folder = model.setlistFolders.first(where: { $0.id == folderID })
        {
            return folder.name
        }
        return selectedCategory.title
    }

    private var isPhoneInterface: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var isShowingSetlist: Bool {
        if case .setlist = selectedCategory {
            return true
        }
        return false
    }

    private var activeSetlistOrderedScores: [ReaderRecentDocument] {
        activeSetlistFolder.map(model.orderedScores(in:)) ?? []
    }

    var body: some View {
        GeometryReader { geometry in
            if isPhoneInterface {
                PhoneLibraryView(
                    scores: displayedScores,
                    activeSetlistOrderedScores: activeSetlistOrderedScores,
                    selectedCategory: $selectedCategory,
                    title: displayedCategoryTitle,
                    searchText: $searchText,
                    sortOrder: isShowingSetlist ? $setlistScoreSortOrder : $scoreSortOrder,
                    scoreLayout: isShowingSetlist ? $setlistPhoneScoreLayout : $phoneScoreLayout,
                    folders: model.setlistFolders,
                    createAction: model.startCreateScore,
                    importAction: model.startImport,
                    openAction: openScore,
                    editInfoAction: presentScoreInfoEditor,
                    deleteAction: { scorePendingDeletion = $0 },
                    activeFolder: activeSetlistFolder,
                    addToFolderAction: { scorePendingFolderSelection = $0 },
                    removeFromFolderAction: { score, folder in
                        model.removeScore(score, from: folder)
                    },
                    showAddScoresAction: { folder in
                        folderPendingScoreAdd = FolderScoreAddRequest(id: folder.id)
                    },
                    isEditingSetlist: $isEditingActiveSetlist,
                    reorderScoresAction: reorderScores,
                    createFolderAction: {
                        newSetlistName = ""
                        isNewSetlistPresented = true
                    },
                    renameFolderAction: { folder in
                        folderPendingRename = folder
                        renameSetlistName = folder.name
                    },
                    reorderSetlistsAction: presentSetlistReorder,
                    openSourceAction: {
                        isOpenSourceLegalPresented = true
                    },
                    accessStatus: accessController.status,
                    accessDisplayPrice: accessController.displayPrice,
                    managedScoreCount: model.managedScoreCount,
                    freeScoreLimit: model.freeScoreLimit,
                    unlockAction: model.presentUnlimitedScoresFromSettings
                )
                .background(LibraryPalette.mainBackground.ignoresSafeArea())
                .overlay {
                    if model.isLoading {
                        Color.black.opacity(0.05)
                            .ignoresSafeArea()

                        ProgressView(model.importProgress?.message ?? "Importing score…")
                            .padding(.horizontal, 22)
                            .padding(.vertical, 16)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            } else {
                HStack(spacing: 0) {
                    LibrarySidebar(
                    selectedCategory: $selectedCategory,
                    folders: model.setlistFolders,
                    importAction: model.startImport,
                    isLoading: model.isLoading,
                    loadingMessage: model.importProgress?.message ?? "Importing score…",
                    createFolderAction: {
                        newSetlistName = ""
                        isNewSetlistPresented = true
                    },
                    renameFolderAction: { folder in
                        folderPendingRename = folder
                        renameSetlistName = folder.name
                    },
                    reorderSetlistsAction: presentSetlistReorder,
                    settingsAction: {
                        selectedCategory = .settings
                    },
                    dropScoreAction: { scoreKey, folder in
                        model.addScoreKey(scoreKey, to: folder)
                    }
                )
                .frame(width: min(sidebarWidth, geometry.size.width * 0.34))

                    Rectangle()
                        .fill(LibraryPalette.divider)
                        .frame(width: 1)

                    LibraryDashboardView(
                    scores: displayedScores,
                    activeSetlistOrderedScores: activeSetlistOrderedScores,
                    selectedCategory: selectedCategory,
                    title: displayedCategoryTitle,
                    searchText: $searchText,
                    sortOrder: isShowingSetlist ? $setlistScoreSortOrder : $scoreSortOrder,
                    scoreLayout: isShowingSetlist ? $setlistDashboardScoreLayout : $dashboardScoreLayout,
                    createAction: model.startCreateScore,
                    importAction: model.startImport,
                    openAction: openScore,
                    editInfoAction: presentScoreInfoEditor,
                    deleteAction: { scorePendingDeletion = $0 },
                    activeSetlist: activeSetlistFolder,
                    showAddScoresAction: { folder in
                        folderPendingScoreAdd = FolderScoreAddRequest(id: folder.id)
                    },
                    isEditingSetlist: $isEditingActiveSetlist,
                    reorderScoresAction: reorderScores,
                    removeFromSetlistAction: { score, setlist in
                        model.removeScore(score, from: setlist)
                    },
                    openSourceAction: {
                        isOpenSourceLegalPresented = true
                    },
                    accessStatus: accessController.status,
                    accessDisplayPrice: accessController.displayPrice,
                    managedScoreCount: model.managedScoreCount,
                    freeScoreLimit: model.freeScoreLimit,
                    unlockAction: model.presentUnlimitedScoresFromSettings
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LibraryPalette.mainBackground)
                }
                .background(LibraryPalette.mainBackground.ignoresSafeArea())
            }
        }
        .fileImporter(
            isPresented: $model.isImportingPresented,
            allowedContentTypes: model.supportedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: model.handleImportSelection
        )
        .task {
            await model.refreshVisibleLibrary()
            model.presentEarlySupporterMessageIfNeeded()
        }
        .onChangeCompatible(of: accessController.status) { _ in
            model.presentEarlySupporterMessageIfNeeded()
        }
        .onChangeCompatible(of: selectedCategory) { _ in
            isEditingActiveSetlist = false
        }
        .onChangeCompatible(of: scenePhase) { phase in
            guard phase == .active else {
                return
            }
            Task {
                await accessController.refreshEntitlements()
                await model.refreshVisibleLibrary()
            }
        }
        .onChangeCompatible(of: model.pendingImportedSession?.id) { _ in
            guard let session = model.pendingImportedSession else {
                return
            }

            readerPresentation = LibraryReaderPresentation(session: session, startPageIndex: 0)
            model.consumePendingImportedSession()
        }
        .alert(item: visibleErrorAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .alert("Delete Score?", isPresented: deleteConfirmationIsPresented) {
            Button("Cancel", role: .cancel) {
                scorePendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                if let scorePendingDeletion {
                    model.deleteScore(scorePendingDeletion)
                }
                scorePendingDeletion = nil
            }
        } message: {
            Text("This removes the score from your library.")
        }
        .alert("Could Not Save Score Info", isPresented: scoreInfoSaveErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(scoreInfoSaveErrorMessage ?? "Aria could not save these score details.")
        }
        .alert("New Setlist", isPresented: $isNewSetlistPresented) {
            TextField("Setlist name", text: $newSetlistName)
            Button("Cancel", role: .cancel) {
                newSetlistName = ""
            }
            Button("Create") {
                model.createSetlistFolder(named: newSetlistName)
                newSetlistName = ""
            }
        } message: {
            Text("Create a setlist for organizing scores in performance order.")
        }
        .alert("Rename Setlist", isPresented: renameConfirmationIsPresented) {
            TextField("Setlist name", text: $renameSetlistName)
            Button("Cancel", role: .cancel) {
                folderPendingRename = nil
                renameSetlistName = ""
            }
            Button("Rename") {
                if let folderPendingRename {
                    model.renameSetlistFolder(folderPendingRename, to: renameSetlistName)
                    if selectedCategory == .setlist(folderPendingRename.id) {
                        selectedCategory = .setlist(folderPendingRename.id)
                    }
                }
                folderPendingRename = nil
                renameSetlistName = ""
            }
        }
        .fullScreenCover(isPresented: $model.isCreateScorePresented) {
            CreateNewScoreView { draft in
                guard let session = await model.createScore(from: draft) else {
                    await MainActor.run {
                        model.isCreateScorePresented = false
                    }
                    return false
                }

                await MainActor.run {
                    pendingCreatedReaderPresentation = LibraryReaderPresentation(
                        session: session,
                        startPageIndex: 0,
                        initialToolCategory: .notes,
                        initialInteractionMode: .edit
                    )
                    model.isCreateScorePresented = false
                }
                return false
            }
            .onDisappear {
                model.createScoreFlowDidDismiss()
                guard let pendingPresentation = pendingCreatedReaderPresentation else {
                    return
                }

                pendingCreatedReaderPresentation = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(200))
                    readerPresentation = pendingPresentation
                }
            }
        }
        .fullScreenCover(item: $readerPresentation) { presentation in
            Group {
                if let setlistSequence = presentation.setlistSequence {
                    SetlistScoreReaderHost(
                        model: model,
                        initialSession: presentation.session,
                        sequence: setlistSequence
                    )
                } else {
                    ScoreReaderView(
                        session: presentation.session,
                        initialPageIndex: presentation.startPageIndex,
                        initialToolCategory: presentation.initialToolCategory,
                        initialInteractionMode: presentation.initialInteractionMode
                    )
                }
            }
                .onDisappear {
                    guard presentation.setlistSequence == nil else {
                        return
                    }
                    Task {
                        await model.refreshLibraryPreviewAfterClosing(presentation.session)
                    }
                }
        }
        .sheet(isPresented: $isOpenSourceLegalPresented) {
            OpenSourceLegalView()
        }
        .sheet(item: $scorePendingFolderSelection) { score in
            ScoreSetlistPickerSheet(
                scoreTitle: score.primaryTitle,
                setlists: foldersAvailableForAdding(score),
                hasAnySetlists: !model.setlistFolders.isEmpty,
                addAction: { setlist in
                    model.addScore(score, to: setlist)
                }
            )
        }
        .sheet(item: $model.libraryAccessSheet) { sheet in
            switch sheet {
            case .paywall(let context):
                LibraryPaywallView(
                    model: model,
                    accessController: accessController,
                    context: context
                )
            case .importReview(let review):
                ScoreImportReviewSheet(model: model, review: review)
            case .earlySupporter:
                EarlySupporterAccessView()
            }
        }
        .sheet(item: $folderPendingScoreAdd) { request in
            if let folder = model.setlistFolders.first(where: { $0.id == request.id }) {
                FolderScorePickerSheet(
                    folderName: folder.name,
                    scores: scoresAvailableForAdding(to: folder),
                    addAction: { score in
                        model.addScore(score, to: folder)
                    }
                )
            } else {
                Text("This setlist is no longer available.")
                    .padding()
            }
        }
        .sheet(isPresented: $isSetlistReorderPresented) {
            ReorderSetlistsSheet(setlists: model.setlistFolders) { orderedIDs in
                model.reorderSetlists(using: orderedIDs)
            }
        }
        .fullScreenCover(item: $scoreInfoEditorSession) { session in
            LibraryScoreInfoEditorSheet(
                metadata: $editableScoreInfo,
                isSaving: isSavingScoreInfo,
                cancelAction: {
                    guard !isSavingScoreInfo else {
                        return
                    }
                    scoreInfoEditorSession = nil
                },
                saveAction: {
                    saveEditedScoreInfo(for: session)
                }
            )
        }
        // Re-assert a visible status bar so the top safe-area inset is restored
        // after the reader cover (which hides it) is dismissed.
        .statusBarHidden(false)
    }

    private var visibleErrorAlert: Binding<ReaderAlert?> {
        Binding {
            model.isCreateScorePresented || readerPresentation != nil || model.libraryAccessSheet != nil
                ? nil
                : model.errorAlert
        } set: { alert in
            model.errorAlert = alert
        }
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding {
            scorePendingDeletion != nil && model.errorAlert == nil && !model.isCreateScorePresented && readerPresentation == nil
        } set: { isPresented in
            if !isPresented {
                scorePendingDeletion = nil
            }
        }
    }

    private var renameConfirmationIsPresented: Binding<Bool> {
        Binding {
            folderPendingRename != nil
        } set: { isPresented in
            if !isPresented {
                folderPendingRename = nil
                renameSetlistName = ""
            }
        }
    }

    private var scoreInfoSaveErrorIsPresented: Binding<Bool> {
        Binding {
            scoreInfoSaveErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                scoreInfoSaveErrorMessage = nil
            }
        }
    }

    private func foldersAvailableForAdding(_ score: ReaderRecentDocument) -> [LibrarySetlistFolder] {
        model.setlistFolders.filter { !folder($0, contains: score) }
    }

    private func scoresAvailableForAdding(to folder: LibrarySetlistFolder) -> [ReaderRecentDocument] {
        model.recents
            .filter { !self.folder(folder, contains: $0) }
            .sorted { $0.lastOpened > $1.lastOpened }
    }

    private func folder(_ folder: LibrarySetlistFolder, contains score: ReaderRecentDocument) -> Bool {
        var keys = [score.setlistKey, score.fileReference]
        if let libraryRelativePath = score.libraryRelativePath {
            keys.append(libraryRelativePath)
        }
        return !Set(folder.scoreKeys).isDisjoint(with: keys)
    }

    private func openScore(_ recent: ReaderRecentDocument) {
        // Capture the exact visible performance order before opening updates
        // the score's recent timestamp and potentially changes Recent sorting.
        let setlist = activeSetlistFolder
        let visibleScoreSnapshot = displayedScores
        let selectedSnapshotIndex = visibleScoreSnapshot.firstIndex(where: { $0.id == recent.id })

        Task {
            guard let session = await model.readerSession(for: recent) else {
                return
            }

            let sequence: SetlistReaderSequence?
            if let setlist,
               let selectedIndex = selectedSnapshotIndex
            {
                sequence = SetlistReaderSequence(
                    setlistID: setlist.id,
                    scores: visibleScoreSnapshot,
                    selectedIndex: selectedIndex
                )
            } else {
                sequence = nil
            }

            readerPresentation = LibraryReaderPresentation(
                session: session,
                startPageIndex: 0,
                setlistSequence: sequence
            )
        }
    }

    private func presentSetlistReorder() {
        guard model.setlistFolders.count > 1 else {
            return
        }
        isSetlistReorderPresented = true
    }

    private func reorderScores(
        in setlist: LibrarySetlistFolder,
        using orderedScoreIDs: [ReaderRecentDocument.ID]
    ) {
        model.reorderScores(in: setlist, using: orderedScoreIDs)
        setlistScoreSortOrder = .setlistOrder
    }

    private func presentScoreInfoEditor(for recent: ReaderRecentDocument) {
        Task {
            guard let session = await model.readerSession(for: recent) else {
                return
            }

            editableScoreInfo = ScoreEditableMetadata(document: session.document)
            scoreInfoSaveErrorMessage = nil
            scoreInfoEditorSession = session
        }
    }

    private func saveEditedScoreInfo(for session: ScoreSession) {
        guard !isSavingScoreInfo else {
            return
        }

        isSavingScoreInfo = true
        scoreInfoSaveErrorMessage = nil
        let metadata = editableScoreInfo

        Task {
            do {
                try await model.saveMetadata(metadata, for: session)
                await MainActor.run {
                    isSavingScoreInfo = false
                    scoreInfoEditorSession = nil
                }
            } catch {
                await MainActor.run {
                    scoreInfoSaveErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isSavingScoreInfo = false
                }
            }
        }
    }
}

private enum LibraryCategory: Equatable {
    case allScores
    case setlists
    case setlist(UUID)
    case settings

    var title: String {
        switch self {
        case .allScores:
            return "All Scores"
        case .setlists:
            return "Setlists"
        case .setlist(_):
            return "Setlist"
        case .settings:
            return "Settings"
        }
    }
}

enum LibraryScoreSortOrder: String, CaseIterable, Identifiable {
    case setlistOrder
    case recentlyOpened
    case titleAscending
    case titleDescending

    var id: Self { self }

    var title: String {
        switch self {
        case .setlistOrder:
            return "Custom Order"
        case .recentlyOpened:
            return "Recently Opened"
        case .titleAscending:
            return "Title A–Z"
        case .titleDescending:
            return "Title Z–A"
        }
    }

    var compactTitle: String {
        switch self {
        case .setlistOrder:
            return "Custom"
        case .recentlyOpened:
            return "Recent"
        case .titleAscending:
            return "A–Z"
        case .titleDescending:
            return "Z–A"
        }
    }

    var systemImage: String {
        switch self {
        case .setlistOrder:
            return "line.3.horizontal"
        case .recentlyOpened:
            return "clock"
        case .titleAscending, .titleDescending:
            return "textformat.abc"
        }
    }

    func sorted(_ scores: [ReaderRecentDocument]) -> [ReaderRecentDocument] {
        guard self != .setlistOrder else {
            return scores
        }

        return scores.sorted { lhs, rhs in
            switch self {
            case .setlistOrder:
                return false
            case .recentlyOpened:
                if lhs.lastOpened != rhs.lastOpened {
                    return lhs.lastOpened > rhs.lastOpened
                }
                let comparison = compareTitles(lhs, rhs)
                return comparison == .orderedSame ? lhs.fileReference < rhs.fileReference : comparison == .orderedAscending
            case .titleAscending:
                let comparison = compareTitles(lhs, rhs)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.lastOpened == rhs.lastOpened ? lhs.fileReference < rhs.fileReference : lhs.lastOpened > rhs.lastOpened
            case .titleDescending:
                let comparison = compareTitles(lhs, rhs)
                if comparison != .orderedSame {
                    return comparison == .orderedDescending
                }
                return lhs.lastOpened == rhs.lastOpened ? lhs.fileReference < rhs.fileReference : lhs.lastOpened > rhs.lastOpened
            }
        }
    }

    private func compareTitles(_ lhs: ReaderRecentDocument, _ rhs: ReaderRecentDocument) -> ComparisonResult {
        lhs.primaryTitle.localizedStandardCompare(rhs.primaryTitle)
    }
}

struct LibraryScoreDisplayPolicy {
    static func filtered(_ scores: [ReaderRecentDocument], query rawQuery: String) -> [ReaderRecentDocument] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return scores
        }
        return scores.filter { score in
            [score.primaryTitle, score.secondaryLine ?? "", score.displayName]
                .map { $0.lowercased() }
                .contains { $0.contains(query) }
        }
    }
}

private enum LibraryScoreLayout: String, CaseIterable, Identifiable {
    case list
    case small
    case medium
    case large
    case extraLarge

    var id: Self { self }

    var title: String {
        switch self {
        case .list: return "List"
        case .small: return "Small Icons"
        case .medium: return "Medium Icons"
        case .large: return "Large Icons"
        case .extraLarge: return "Extra Large Icons"
        }
    }

    var compactTitle: String {
        switch self {
        case .list: return "List"
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .extraLarge: return "XL"
        }
    }

    var systemImage: String {
        switch self {
        case .list:
            return "list.bullet"
        case .small:
            return "square.grid.3x3"
        case .medium:
            return "square.grid.2x2"
        case .large, .extraLarge:
            return "rectangle.grid.1x2"
        }
    }

    var dashboardColumns: [GridItem] {
        let sizing: (minimum: CGFloat, maximum: CGFloat, spacing: CGFloat)
        switch self {
        case .list:
            return []
        case .small:
            sizing = (118, 145, 16)
        case .medium:
            sizing = (170, 195, 24)
        case .large:
            sizing = (220, 255, 28)
        case .extraLarge:
            sizing = (290, 330, 32)
        }
        return [GridItem(.adaptive(minimum: sizing.minimum, maximum: sizing.maximum), spacing: sizing.spacing)]
    }

    var phoneColumns: [GridItem] {
        let sizing: (minimum: CGFloat, maximum: CGFloat, spacing: CGFloat)
        switch self {
        case .list:
            return []
        case .small:
            sizing = (96, 125, 10)
        case .medium:
            sizing = (140, 175, 12)
        case .large:
            sizing = (185, 235, 14)
        case .extraLarge:
            sizing = (260, 340, 16)
        }
        return [GridItem(.adaptive(minimum: sizing.minimum, maximum: sizing.maximum), spacing: sizing.spacing)]
    }

    var phoneGridAlignment: HorizontalAlignment {
        switch self {
        case .large, .extraLarge:
            return .center
        case .list, .small, .medium:
            return .leading
        }
    }

    var gridSpacing: CGFloat {
        switch self {
        case .list: return 0
        case .small: return 18
        case .medium: return 24
        case .large: return 28
        case .extraLarge: return 32
        }
    }
}

private struct FolderScoreAddRequest: Identifiable {
    let id: UUID
}

private struct ReorderSetlistsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var setlists: [LibrarySetlistFolder]

    let saveAction: ([UUID]) -> Void

    init(setlists: [LibrarySetlistFolder], saveAction: @escaping ([UUID]) -> Void) {
        _setlists = State(initialValue: setlists)
        self.saveAction = saveAction
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(setlists) { setlist in
                    Label(setlist.name, systemImage: "music.note.list")
                        .font(.system(size: 16, weight: .medium))
                        .accessibilityLabel("Setlist, \(setlist.name)")
                }
                .onMove { source, destination in
                    setlists.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Setlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAction(setlists.map(\.id))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .frame(minWidth: 320, idealWidth: 520, minHeight: 420, idealHeight: 640)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

enum LibraryPalette {
    static let accent = Color(red: 0.00, green: 0.48, blue: 1.00)
    static let accentSoft = Color(red: 0.89, green: 0.95, blue: 1.00)
    static let background = Color.white
    static let mainBackground = Color(red: 0.985, green: 0.986, blue: 0.993)
    static let divider = Color(red: 0.91, green: 0.91, blue: 0.94)
    static let ink = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let mutedInk = Color(red: 0.40, green: 0.40, blue: 0.44)
    static let subtle = Color(red: 0.70, green: 0.70, blue: 0.75)
    static let cardBorder = Color(red: 0.90, green: 0.91, blue: 0.94)
    static let skeleton = Color(red: 0.95, green: 0.95, blue: 0.97)
    static let cardPalettes: [(fill: Color, icon: Color)] = [
        (Color(red: 0.87, green: 0.90, blue: 1.00), Color(red: 0.49, green: 0.50, blue: 0.92)),
        (Color(red: 0.86, green: 0.90, blue: 0.99), Color(red: 0.45, green: 0.53, blue: 0.93)),
        (Color(red: 0.86, green: 0.97, blue: 0.90), Color(red: 0.45, green: 0.71, blue: 0.63)),
        (Color(red: 1.00, green: 0.95, blue: 0.75), Color(red: 0.84, green: 0.63, blue: 0.33)),
        (Color(red: 1.00, green: 0.89, blue: 0.92), Color(red: 0.84, green: 0.49, blue: 0.58)),
        (Color(red: 0.83, green: 0.96, blue: 1.00), Color(red: 0.46, green: 0.67, blue: 0.77))
    ]
}

private struct LibrarySidebar: View {
    @Binding var selectedCategory: LibraryCategory
    let folders: [LibrarySetlistFolder]
    let importAction: () -> Void
    let isLoading: Bool
    let loadingMessage: String
    let createFolderAction: () -> Void
    let renameFolderAction: (LibrarySetlistFolder) -> Void
    let reorderSetlistsAction: () -> Void
    let settingsAction: () -> Void
    let dropScoreAction: (String, LibrarySetlistFolder) -> Void

    var body: some View {
        ZStack {
            LibraryPalette.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                LibraryBrandHeader()
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        SidebarSectionTitle("LIBRARY")

                        SidebarNavButton(
                            title: "All Scores",
                            systemImage: "square.grid.2x2",
                            isSelected: selectedCategory == .allScores
                        ) {
                            selectedCategory = .allScores
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SidebarSectionTitle("SETLISTS")
                            Spacer()
                            HStack(spacing: 12) {
                                Button(action: reorderSetlistsAction) {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(LibraryPalette.subtle)
                                }
                                .buttonStyle(.plain)
                                .disabled(folders.count < 2)
                                .accessibilityLabel("Reorder Setlists")

                                Button(action: createFolderAction) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(LibraryPalette.subtle)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("New Setlist")
                            }
                        }

                        ForEach(folders) { folder in
                            SidebarSetlistButton(
                                folder: folder,
                                isSelected: selectedCategory == .setlist(folder.id),
                                selectAction: {
                                    selectedCategory = .setlist(folder.id)
                                },
                                renameAction: {
                                    renameFolderAction(folder)
                                },
                                dropScoreAction: { scoreKey in
                                    dropScoreAction(scoreKey, folder)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(LibraryPalette.divider)
                        .frame(height: 1)

                    Button(action: settingsAction) {
                        HStack(spacing: 12) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20, weight: .regular))
                            Text("Settings")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .foregroundStyle(LibraryPalette.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 22)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isLoading {
                Color.black.opacity(0.05)
                    .ignoresSafeArea()

                ProgressView(loadingMessage)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

private struct LibraryBrandHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            AriaLogoMark(size: 36, cornerRadius: 11)

            Text("Aria")
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(LibraryPalette.ink)
        }
    }
}

struct AriaLogoMark: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Image("AriaLogoMark")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct SidebarSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(LibraryPalette.subtle)
    }
}

private struct SidebarNavButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                Text(title)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(isSelected ? LibraryPalette.accent : LibraryPalette.mutedInk)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? LibraryPalette.accentSoft : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarSetlistButton: View {
    let folder: LibrarySetlistFolder
    let isSelected: Bool
    let selectAction: () -> Void
    let renameAction: () -> Void
    let dropScoreAction: (String) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        Button(action: selectAction) {
            HStack(spacing: 12) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 18, weight: .medium))
                Text(folder.name)
                    .font(.system(size: 17, weight: .medium))
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(isSelected ? LibraryPalette.accent : LibraryPalette.mutedInk)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected || isDropTargeted ? LibraryPalette.accentSoft : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: renameAction) {
                Label("Rename Setlist", systemImage: "pencil")
            }
        }
        .onDrop(of: [UTType.plainText], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else {
                return false
            }
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let key: String?
                if let data = item as? Data {
                    key = String(data: data, encoding: .utf8)
                } else {
                    key = item as? String
                }
                if let key = key?.trimmedToNil {
                    Task { @MainActor in
                        dropScoreAction(key)
                    }
                }
            }
            return true
        }
    }
}

// Shared by PhoneLibraryView and PhoneBottomTabBar
enum PhoneTab: Int, CaseIterable {
    case all, setlists, settings

    var title: String {
        switch self {
        case .all: return "All Scores"
        case .setlists: return "Setlists"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .setlists: return "music.note.list"
        case .settings: return "gearshape"
        }
    }
}

private struct PhoneLibraryView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let scores: [ReaderRecentDocument]
    let activeSetlistOrderedScores: [ReaderRecentDocument]
    @Binding var selectedCategory: LibraryCategory
    let title: String
    @Binding var searchText: String
    @Binding var sortOrder: LibraryScoreSortOrder
    @Binding var scoreLayout: LibraryScoreLayout
    let folders: [LibrarySetlistFolder]
    let createAction: () -> Void
    let importAction: () -> Void
    let openAction: (ReaderRecentDocument) -> Void
    let editInfoAction: (ReaderRecentDocument) -> Void
    let deleteAction: (ReaderRecentDocument) -> Void
    let activeFolder: LibrarySetlistFolder?
    let addToFolderAction: (ReaderRecentDocument) -> Void
    let removeFromFolderAction: (ReaderRecentDocument, LibrarySetlistFolder) -> Void
    let showAddScoresAction: (LibrarySetlistFolder) -> Void
    @Binding var isEditingSetlist: Bool
    let reorderScoresAction: (LibrarySetlistFolder, [ReaderRecentDocument.ID]) -> Void
    let createFolderAction: () -> Void
    let renameFolderAction: (LibrarySetlistFolder) -> Void
    let reorderSetlistsAction: () -> Void
    let openSourceAction: () -> Void
    let accessStatus: LibraryAccessStatus
    let accessDisplayPrice: String?
    let managedScoreCount: Int
    let freeScoreLimit: Int
    let unlockAction: () -> Void

    private var activeTab: PhoneTab {
        switch selectedCategory {
        case .allScores:          return .all
        case .setlists, .setlist: return .setlists
        case .settings:           return .settings
        }
    }

    private var showsScoreList: Bool {
        switch selectedCategory {
        case .allScores, .setlist: return true
        case .setlists, .settings: return false
        }
    }

    private var setlistEditorHeight: CGFloat {
        verticalSizeClass == .compact ? 240 : 480
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // ── Compact header row ──────────────────────────────────
                HStack(alignment: .center, spacing: 0) {
                    AriaLogoMark(size: 28, cornerRadius: 8)

                    Text("Aria")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(LibraryPalette.ink)
                        .padding(.leading, 8)

                    Spacer(minLength: 0)

                    // Small icon buttons
                    HStack(spacing: 6) {
                        Button(action: importAction) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(LibraryPalette.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Import Score")

                        Button(action: createAction) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(LibraryPalette.accent)
                                .frame(width: 36, height: 36)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New Score")
                    }
                }

                if activeTab != .settings {
                    PhoneSearchField(text: $searchText)
                        .disabled(isEditingSetlist)
                }

                if selectedCategory == .allScores,
                   accessStatus == .free,
                   managedScoreCount >= freeScoreLimit
                {
                    FreeLibraryFullNotice(unlockAction: unlockAction)
                }

                // ── Content area ────────────────────────────────────────
                if selectedCategory == .setlists {
                    PhoneSetlistContent(
                        folders: folders,
                        selectedCategory: $selectedCategory,
                        createFolderAction: createFolderAction,
                        renameFolderAction: renameFolderAction,
                        reorderSetlistsAction: reorderSetlistsAction
                    )
                } else if activeTab == .settings {
                    PhoneSettingsContent(
                        accessStatus: accessStatus,
                        accessDisplayPrice: accessDisplayPrice,
                        unlockAction: unlockAction,
                        openSourceAction: openSourceAction
                    )
                } else if showsScoreList {
                    if let activeFolder {
                        HStack(alignment: .center, spacing: 12) {
                            Button {
                                selectedCategory = .setlists
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(LibraryPalette.accent)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Back to Setlists")

                            Text(title)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(LibraryPalette.ink)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Button {
                                showAddScoresAction(activeFolder)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus")
                                    Text("Add")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(LibraryPalette.accent)
                                .padding(.horizontal, 11)
                                .frame(height: 32)
                                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditingSetlist)
                            .accessibilityLabel("Add Scores to Setlist")

                            Button {
                                if !isEditingSetlist {
                                    sortOrder = .setlistOrder
                                }
                                isEditingSetlist.toggle()
                            } label: {
                                Text(isEditingSetlist ? "Done" : "Edit")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(LibraryPalette.accent)
                                    .padding(.horizontal, 11)
                                    .frame(height: 32)
                                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .disabled(activeSetlistOrderedScores.isEmpty)
                            .accessibilityLabel(isEditingSetlist ? "Done Editing Setlist" : "Edit Setlist")
                        }
                    }
                    if !isEditingSetlist {
                        LibraryScoreDisplayBar(
                            scoreCount: scores.count,
                            sortOrder: $sortOrder,
                            scoreLayout: $scoreLayout,
                            isCompact: true,
                            freeScoreUsage: selectedCategory == .allScores && accessStatus == .free
                                ? managedScoreCount
                                : nil,
                            freeScoreLimit: freeScoreLimit,
                            includesSetlistOrder: activeFolder != nil
                        )
                    }

                    if isEditingSetlist, let activeFolder {
                        SetlistScoreEditingList(
                            scores: activeSetlistOrderedScores,
                            removeAction: { score in
                                removeFromFolderAction(score, activeFolder)
                            },
                            reorderAction: { orderedIDs in
                                reorderScoresAction(activeFolder, orderedIDs)
                            }
                        )
                        .frame(
                            height: min(
                                max(90, CGFloat(activeSetlistOrderedScores.count) * 62 + 18),
                                setlistEditorHeight
                            )
                        )
                    } else if scores.isEmpty, activeFolder != nil {
                        VStack(spacing: 10) {
                            Image(systemName: "text.badge.plus")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(LibraryPalette.subtle)
                            Text("No scores in this setlist")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(LibraryPalette.mutedInk)
                            Text("Tap Add to choose scores from your library.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(LibraryPalette.subtle)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    } else if scoreLayout == .list {
                        PhoneScoreList(
                            scores: scores,
                            openAction: openAction,
                            editInfoAction: editInfoAction,
                            deleteAction: deleteAction,
                            activeFolder: activeFolder,
                            addToFolderAction: addToFolderAction,
                            removeFromFolderAction: removeFromFolderAction
                        )
                    } else {
                        PhoneScoreGrid(
                            scores: scores,
                            scoreLayout: scoreLayout,
                            openAction: openAction,
                            editInfoAction: editInfoAction,
                            deleteAction: deleteAction,
                            activeFolder: activeFolder,
                            addToFolderAction: addToFolderAction,
                            removeFromFolderAction: removeFromFolderAction
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 92)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            PhoneBottomTabBar(activeTab: activeTab) { tapped in
                switch tapped {
                case .all:
                    selectedCategory = .allScores
                case .setlists:
                    selectedCategory = .setlists
                case .settings:
                    selectedCategory = .settings
                }
            }
        }
    }
}

// PhoneLibraryActionButtons removed — buttons now inline in PhoneLibraryView header

private struct PhoneSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LibraryPalette.subtle)

            TextField("Search library...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LibraryPalette.ink)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(LibraryPalette.subtle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.955, green: 0.960, blue: 0.972))
        )
    }
}

private struct PhoneBottomTabBar: View {
    let activeTab: PhoneTab
    let onSelect: (PhoneTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PhoneTab.allCases, id: \.rawValue) { tab in
                let isActive = tab == activeTab
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 19, weight: isActive ? .semibold : .medium))
                        Text(tab.title)
                            .font(.system(size: 11, weight: isActive ? .semibold : .medium))
                    }
                    .foregroundStyle(isActive ? LibraryPalette.accent : LibraryPalette.mutedInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isActive)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LibraryPalette.divider)
                .frame(height: 1)
        }
    }
}

// PhoneSetlistContent — shown when Setlists tab is active
private struct PhoneSetlistContent: View {
    let folders: [LibrarySetlistFolder]
    @Binding var selectedCategory: LibraryCategory
    let createFolderAction: () -> Void
    let renameFolderAction: (LibrarySetlistFolder) -> Void
    let reorderSetlistsAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header row with New Folder button
            HStack {
                Text("Setlists")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LibraryPalette.subtle)
                    .tracking(0.5)
                Spacer()
                HStack(spacing: 14) {
                    Button(action: reorderSetlistsAction) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text("Reorder")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LibraryPalette.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(folders.count < 2)

                    Button(action: createFolderAction) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("New Setlist")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LibraryPalette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            if folders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(LibraryPalette.subtle)
                    Text("No setlists yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LibraryPalette.subtle)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                        Button {
                            selectedCategory = .setlist(folder.id)
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundStyle(LibraryPalette.accent)
                                    .frame(width: 22)
                                Text(folder.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(LibraryPalette.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(LibraryPalette.subtle)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { renameFolderAction(folder) } label: {
                                Label("Rename Setlist", systemImage: "pencil")
                            }
                        }

                        if index < folders.count - 1 {
                            Rectangle()
                                .fill(LibraryPalette.divider)
                                .frame(height: 1)
                                .padding(.leading, 51)
                        }
                    }
                }
                .background(Color.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                }
            }
        }
    }
}

private struct PhoneScoreList: View {
    let scores: [ReaderRecentDocument]
    let openAction: (ReaderRecentDocument) -> Void
    let editInfoAction: (ReaderRecentDocument) -> Void
    let deleteAction: (ReaderRecentDocument) -> Void
    let activeFolder: LibrarySetlistFolder?
    let addToFolderAction: (ReaderRecentDocument) -> Void
    let removeFromFolderAction: (ReaderRecentDocument, LibrarySetlistFolder) -> Void

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(scores.enumerated()), id: \.element.id) { index, score in
                PhoneScoreListRow(
                    score: score,
                    openAction: { openAction(score) },
                    editInfoAction: { editInfoAction(score) },
                    deleteAction: { deleteAction(score) },
                    activeFolder: activeFolder,
                    addToFolderAction: { addToFolderAction(score) },
                    removeFromFolderAction: { folder in
                        removeFromFolderAction(score, folder)
                    }
                )

                if index < scores.count - 1 {
                    Rectangle()
                        .fill(LibraryPalette.divider)
                        .frame(height: 1)
                        .padding(.leading, 18)
                }
            }
        }
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LibraryPalette.cardBorder, lineWidth: 1)
        }
    }
}

private struct PhoneScoreGrid: View {
    let scores: [ReaderRecentDocument]
    let scoreLayout: LibraryScoreLayout
    let openAction: (ReaderRecentDocument) -> Void
    let editInfoAction: (ReaderRecentDocument) -> Void
    let deleteAction: (ReaderRecentDocument) -> Void
    let activeFolder: LibrarySetlistFolder?
    let addToFolderAction: (ReaderRecentDocument) -> Void
    let removeFromFolderAction: (ReaderRecentDocument, LibrarySetlistFolder) -> Void

    var body: some View {
        LazyVGrid(
            columns: scoreLayout.phoneColumns,
            alignment: scoreLayout.phoneGridAlignment,
            spacing: scoreLayout.gridSpacing
        ) {
            ForEach(Array(scores.enumerated()), id: \.element.id) { index, score in
                LibraryScoreCard(
                    score: score,
                    paletteIndex: index,
                    openAction: { openAction(score) },
                    editInfoAction: { editInfoAction(score) },
                    deleteAction: { deleteAction(score) },
                    addToFolderAction: { addToFolderAction(score) },
                    removeFromFolderAction: activeFolder.map { folder in
                        { removeFromFolderAction(score, folder) }
                    }
                )
            }
        }
    }
}

private struct PhoneScoreListRow: View {
    let score: ReaderRecentDocument
    let openAction: () -> Void
    let editInfoAction: () -> Void
    let deleteAction: () -> Void
    let activeFolder: LibrarySetlistFolder?
    let addToFolderAction: () -> Void
    let removeFromFolderAction: (LibrarySetlistFolder) -> Void

    var body: some View {
        Button(action: openAction) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(score.primaryTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LibraryPalette.ink)
                        .lineLimit(1)

                    Text(score.secondaryLine ?? "Unknown Composer")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(LibraryPalette.mutedInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(score.format.rawValue.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LibraryPalette.subtle)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(LibraryPalette.skeleton, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LibraryPalette.subtle)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: editInfoAction) {
                Label("Edit Info", systemImage: "square.and.pencil")
            }
            Button(action: addToFolderAction) {
                Label("Add to Setlist", systemImage: "text.badge.plus")
            }
            if let activeFolder {
                Button {
                    removeFromFolderAction(activeFolder)
                } label: {
                    Label("Remove from Setlist", systemImage: "text.badge.minus")
                }
            }
            Button(role: .destructive, action: deleteAction) {
                Label("Delete Score", systemImage: "trash")
            }
        }
    }
}

private struct FolderScorePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let folderName: String
    let scores: [ReaderRecentDocument]
    let addAction: (ReaderRecentDocument) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if scores.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(LibraryPalette.subtle)
                        Text("All scores are already in this setlist.")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(LibraryPalette.mutedInk)
                            .multilineTextAlignment(.center)
                    }
                    .padding(26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LibraryPalette.mainBackground)
                } else {
                    List(scores) { score in
                        Button {
                            addAction(score)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(score.primaryTitle)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(LibraryPalette.ink)
                                        .lineLimit(1)

                                    Text(score.secondaryLine ?? "Unknown Composer")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundStyle(LibraryPalette.mutedInk)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "plus.circle")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(LibraryPalette.accent)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Add to \(folderName)")
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

private struct ScoreSetlistPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let scoreTitle: String
    let setlists: [LibrarySetlistFolder]
    let hasAnySetlists: Bool
    let addAction: (LibrarySetlistFolder) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if setlists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(LibraryPalette.subtle)
                        Text(
                            hasAnySetlists
                                ? "This score is already in every setlist."
                                : "Create a setlist before adding this score."
                        )
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(LibraryPalette.mutedInk)
                            .multilineTextAlignment(.center)
                    }
                    .padding(26)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LibraryPalette.mainBackground)
                } else {
                    List(setlists) { setlist in
                        Button {
                            addAction(setlist)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(LibraryPalette.accent)
                                    .frame(width: 24)

                                Text(setlist.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(LibraryPalette.ink)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Image(systemName: "plus.circle")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(LibraryPalette.accent)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Add \(scoreTitle) to Setlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct PhoneSettingsContent: View {
    let accessStatus: LibraryAccessStatus
    let accessDisplayPrice: String?
    let unlockAction: () -> Void
    let openSourceAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(LibraryPalette.ink)

            if accessStatus.showsMonetizationUI {
                LibraryAccessSettingsCard(
                    status: accessStatus,
                    displayPrice: accessDisplayPrice,
                    unlockAction: unlockAction
                )
            }

            Button(action: openSourceAction) {
                HStack(spacing: 14) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 28)

                    Text("Open Source Licenses")
                        .font(.system(size: 17, weight: .medium))

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LibraryPalette.subtle)
                }
                .foregroundStyle(LibraryPalette.mutedInk)
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct LibraryDashboardView: View {
    let scores: [ReaderRecentDocument]
    let activeSetlistOrderedScores: [ReaderRecentDocument]
    let selectedCategory: LibraryCategory
    let title: String
    @Binding var searchText: String
    @Binding var sortOrder: LibraryScoreSortOrder
    @Binding var scoreLayout: LibraryScoreLayout
    let createAction: () -> Void
    let importAction: () -> Void
    let openAction: (ReaderRecentDocument) -> Void
    let editInfoAction: (ReaderRecentDocument) -> Void
    let deleteAction: (ReaderRecentDocument) -> Void
    let activeSetlist: LibrarySetlistFolder?
    let showAddScoresAction: (LibrarySetlistFolder) -> Void
    @Binding var isEditingSetlist: Bool
    let reorderScoresAction: (LibrarySetlistFolder, [ReaderRecentDocument.ID]) -> Void
    let removeFromSetlistAction: (ReaderRecentDocument, LibrarySetlistFolder) -> Void
    let openSourceAction: () -> Void
    let accessStatus: LibraryAccessStatus
    let accessDisplayPrice: String?
    let managedScoreCount: Int
    let freeScoreLimit: Int
    let unlockAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LibraryDashboardHeader(
                title: title,
                searchText: $searchText,
                createAction: createAction,
                importAction: importAction,
                activeSetlist: activeSetlist,
                showAddScoresAction: showAddScoresAction,
                canEditSetlist: !activeSetlistOrderedScores.isEmpty,
                isEditingSetlist: $isEditingSetlist
            )

            if selectedCategory != .settings, !isEditingSetlist {
                LibraryScoreDisplayBar(
                    scoreCount: scores.count,
                    sortOrder: $sortOrder,
                    scoreLayout: $scoreLayout,
                    isCompact: false,
                    freeScoreUsage: selectedCategory == .allScores && accessStatus == .free
                        ? managedScoreCount
                        : nil,
                    freeScoreLimit: freeScoreLimit,
                    includesSetlistOrder: activeSetlist != nil
                )
            }

            if selectedCategory == .allScores,
               accessStatus == .free,
               managedScoreCount >= freeScoreLimit
            {
                FreeLibraryFullNotice(unlockAction: unlockAction)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 10)
                    .background(LibraryPalette.background)
            }

            if isEditingSetlist, let activeSetlist {
                SetlistScoreEditingList(
                    scores: activeSetlistOrderedScores,
                    removeAction: { score in
                        removeFromSetlistAction(score, activeSetlist)
                    },
                    reorderAction: { orderedIDs in
                        reorderScoresAction(activeSetlist, orderedIDs)
                    }
                )
            } else {
                ScrollView {
                if selectedCategory == .settings {
                    LibrarySettingsContent(
                        accessStatus: accessStatus,
                        accessDisplayPrice: accessDisplayPrice,
                        unlockAction: unlockAction,
                        openSourceAction: openSourceAction
                    )
                        .padding(34)
                } else if scores.isEmpty {
                    LibraryEmptyState(createAction: createAction, importAction: importAction, selectedCategory: selectedCategory)
                        .padding(36)
                } else if scoreLayout == .list {
                    LibraryScoreList(
                        scores: scores,
                        openAction: openAction,
                        editInfoAction: editInfoAction,
                        deleteAction: deleteAction,
                        removeFromSetlistAction: activeSetlist.map { setlist in
                            { score in removeFromSetlistAction(score, setlist) }
                        }
                    )
                    .padding(34)
                } else {
                    LazyVGrid(columns: scoreLayout.dashboardColumns, alignment: .leading, spacing: scoreLayout.gridSpacing) {
                        ForEach(Array(scores.enumerated()), id: \.element.id) { index, score in
                            LibraryScoreCard(
                                score: score,
                                paletteIndex: index,
                                openAction: { openAction(score) },
                                editInfoAction: { editInfoAction(score) },
                                deleteAction: { deleteAction(score) },
                                removeFromFolderAction: activeSetlist.map { setlist in
                                    { removeFromSetlistAction(score, setlist) }
                                }
                            )
                        }
                    }
                    .padding(34)
                }
            }
            }
        }
        .background(LibraryPalette.mainBackground)
        .onChangeCompatible(of: isEditingSetlist) { isEditing in
            if isEditing {
                sortOrder = .setlistOrder
            }
        }
    }
}

private struct LibraryScoreDisplayBar: View {
    let scoreCount: Int
    @Binding var sortOrder: LibraryScoreSortOrder
    @Binding var scoreLayout: LibraryScoreLayout
    let isCompact: Bool
    var freeScoreUsage: Int? = nil
    var freeScoreLimit: Int = LibraryAccessPolicy.freeScoreLimit
    var includesSetlistOrder = false

    private var scoreCountLabel: String {
        "\(scoreCount) \(scoreCount == 1 ? "score" : "scores")"
    }

    private var freeUsageLabel: String? {
        guard let freeScoreUsage else {
            return nil
        }
        return "Free plan · \(min(freeScoreUsage, freeScoreLimit))/\(freeScoreLimit) slots used"
    }

    var body: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            if let freeUsageLabel {
                VStack(alignment: .leading, spacing: isCompact ? 2 : 1) {
                    Text(scoreCountLabel)
                        .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                        .foregroundStyle(LibraryPalette.mutedInk)

                    Text(freeUsageLabel)
                        .font(.system(size: isCompact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(LibraryPalette.accent.opacity(0.82))
                }
                .lineLimit(1)
            } else {
                Text(scoreCountLabel)
                    .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                    .foregroundStyle(LibraryPalette.mutedInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Picker("Sort Order", selection: $sortOrder) {
                    ForEach(LibraryScoreSortOrder.allCases.filter { includesSetlistOrder || $0 != .setlistOrder }) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
            } label: {
                LibraryDisplayMenuLabel(
                    systemImage: "arrow.up.arrow.down",
                    title: isCompact ? sortOrder.compactTitle : sortOrder.title,
                    accessibilityLabel: "Sort: \(sortOrder.title)",
                    isCompact: isCompact
                )
            }

            Menu {
                Picker("View", selection: $scoreLayout) {
                    ForEach(LibraryScoreLayout.allCases) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
            } label: {
                LibraryDisplayMenuLabel(
                    systemImage: scoreLayout.systemImage,
                    title: isCompact ? scoreLayout.compactTitle : scoreLayout.title,
                    accessibilityLabel: "View: \(scoreLayout.title)",
                    isCompact: isCompact
                )
            }
        }
        .padding(.horizontal, isCompact ? 2 : 34)
        .frame(height: isCompact ? 42 : 52)
        .background(isCompact ? Color.clear : LibraryPalette.background)
        .overlay(alignment: .bottom) {
            if !isCompact {
                Rectangle()
                    .fill(LibraryPalette.divider)
                    .frame(height: 1)
            }
        }
    }
}

private struct LibraryDisplayMenuLabel: View {
    let systemImage: String
    let title: String
    let accessibilityLabel: String
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))

            Text(title)
                .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(LibraryPalette.subtle)
        }
        .foregroundStyle(LibraryPalette.mutedInk)
        .padding(.horizontal, isCompact ? 9 : 12)
        .frame(height: isCompact ? 32 : 34)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LibraryPalette.cardBorder, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SetlistScoreEditingList: View {
    let scores: [ReaderRecentDocument]
    let removeAction: (ReaderRecentDocument) -> Void
    let reorderAction: ([ReaderRecentDocument.ID]) -> Void

    var body: some View {
        List {
            ForEach(scores) { score in
                VStack(alignment: .leading, spacing: 3) {
                    Text(score.primaryTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(LibraryPalette.ink)
                        .lineLimit(1)

                    if let secondaryLine = score.secondaryLine?.trimmedToNil {
                        Text(secondaryLine)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(LibraryPalette.mutedInk)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .onDelete { offsets in
                for offset in offsets.sorted(by: >) {
                    guard scores.indices.contains(offset) else { continue }
                    removeAction(scores[offset])
                }
            }
            .onMove { source, destination in
                var reorderedScores = scores
                reorderedScores.move(fromOffsets: source, toOffset: destination)
                reorderAction(reorderedScores.map(\.id))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LibraryPalette.mainBackground)
        .environment(\.editMode, .constant(.active))
        .accessibilityLabel("Edit Setlist Scores")
    }
}

private struct LibraryScoreList: View {
    let scores: [ReaderRecentDocument]
    let openAction: (ReaderRecentDocument) -> Void
    let editInfoAction: (ReaderRecentDocument) -> Void
    let deleteAction: (ReaderRecentDocument) -> Void
    let removeFromSetlistAction: ((ReaderRecentDocument) -> Void)?

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(scores.enumerated()), id: \.element.id) { index, score in
                LibraryScoreListRow(
                    score: score,
                    openAction: { openAction(score) },
                    editInfoAction: { editInfoAction(score) },
                    deleteAction: { deleteAction(score) },
                    removeFromSetlistAction: removeFromSetlistAction.map { action in
                        { action(score) }
                    }
                )

                if index < scores.count - 1 {
                    Rectangle()
                        .fill(LibraryPalette.divider)
                        .frame(height: 1)
                        .padding(.leading, 18)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LibraryPalette.cardBorder, lineWidth: 1)
        }
    }
}

private struct LibraryScoreListRow: View {
    let score: ReaderRecentDocument
    let openAction: () -> Void
    let editInfoAction: () -> Void
    let deleteAction: () -> Void
    let removeFromSetlistAction: (() -> Void)?

    var body: some View {
        Button(action: openAction) {
            HStack(spacing: 14) {
                Text(score.primaryTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LibraryPalette.ink)
                    .lineLimit(1)

                if let secondaryLine = score.secondaryLine?.trimmedToNil {
                    Text(secondaryLine)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(LibraryPalette.mutedInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(score.format.rawValue.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LibraryPalette.subtle)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LibraryPalette.subtle)
            }
            .padding(.horizontal, 18)
            .frame(height: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: editInfoAction) {
                Label("Edit Info", systemImage: "square.and.pencil")
            }
            if let removeFromSetlistAction {
                Button(action: removeFromSetlistAction) {
                    Label("Remove from Setlist", systemImage: "text.badge.minus")
                }
            }
            Button(role: .destructive, action: deleteAction) {
                Label("Delete Score", systemImage: "trash")
            }
        }
        .onDrag {
            NSItemProvider(object: score.setlistKey as NSString)
        }
    }
}

private struct LibrarySettingsContent: View {
    let accessStatus: LibraryAccessStatus
    let accessDisplayPrice: String?
    let unlockAction: () -> Void
    let openSourceAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if accessStatus.showsMonetizationUI {
                LibraryAccessSettingsCard(
                    status: accessStatus,
                    displayPrice: accessDisplayPrice,
                    unlockAction: unlockAction
                )
                .frame(width: 420)
            }

            Button(action: openSourceAction) {
                HStack(spacing: 14) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(LibraryPalette.accent)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open Source Licenses")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(LibraryPalette.ink)
                        Text("View GPLv3 and bundled third-party notices.")
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(LibraryPalette.mutedInk)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LibraryPalette.subtle)
                }
                .padding(.horizontal, 18)
                .frame(width: 420, height: 72, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LibraryDashboardHeader: View {
    let title: String
    @Binding var searchText: String
    let createAction: () -> Void
    let importAction: () -> Void
    let activeSetlist: LibrarySetlistFolder?
    let showAddScoresAction: (LibrarySetlistFolder) -> Void
    let canEditSetlist: Bool
    @Binding var isEditingSetlist: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(LibraryPalette.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)

            HStack(spacing: 16) {
                SearchField(text: $searchText)
                    .frame(width: activeSetlist == nil ? 320 : 260)
                    .disabled(isEditingSetlist)

                if let activeSetlist {
                    Button {
                        showAddScoresAction(activeSetlist)
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LibraryPalette.accent)
                            .frame(width: 76, height: 48)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(isEditingSetlist)
                    .accessibilityLabel("Add Scores to Setlist")

                    Button {
                        isEditingSetlist.toggle()
                    } label: {
                        Text(isEditingSetlist ? "Done" : "Edit")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LibraryPalette.accent)
                            .frame(width: 68, height: 48)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEditSetlist)
                    .accessibilityLabel(isEditingSetlist ? "Done Editing Setlist" : "Edit Setlist")

                    Menu {
                        Button(action: importAction) {
                            Label("Import Score", systemImage: "doc.badge.plus")
                        }
                        Button(action: createAction) {
                            Label("New Score", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(LibraryPalette.accent)
                            .frame(width: 48, height: 48)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                            }
                    }
                    .accessibilityLabel("More Library Actions")
                } else {
                    Button(action: importAction) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .foregroundStyle(.white)
                            .frame(width: 74, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(LibraryPalette.accent)
                            )
                            .shadow(color: LibraryPalette.accent.opacity(0.22), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)

                    Button(action: createAction) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .foregroundStyle(LibraryPalette.accent)
                            .frame(width: 70, height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(LibraryPalette.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(LibraryPalette.divider)
                .frame(height: 1)
        }
    }
}

private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LibraryPalette.subtle)

            TextField("Search library...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LibraryPalette.ink)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(LibraryPalette.subtle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LibraryPalette.cardBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
    }
}

private struct LibraryScoreCard: View {
    let score: ReaderRecentDocument
    let paletteIndex: Int
    let openAction: () -> Void
    let editInfoAction: () -> Void
    let deleteAction: () -> Void
    let addToFolderAction: (() -> Void)?
    let removeFromFolderAction: (() -> Void)?

    @State private var isInfoPresented = false

    init(
        score: ReaderRecentDocument,
        paletteIndex: Int,
        openAction: @escaping () -> Void,
        editInfoAction: @escaping () -> Void,
        deleteAction: @escaping () -> Void,
        addToFolderAction: (() -> Void)? = nil,
        removeFromFolderAction: (() -> Void)? = nil
    ) {
        self.score = score
        self.paletteIndex = paletteIndex
        self.openAction = openAction
        self.editInfoAction = editInfoAction
        self.deleteAction = deleteAction
        self.addToFolderAction = addToFolderAction
        self.removeFromFolderAction = removeFromFolderAction
    }

    private var palette: (fill: Color, icon: Color) {
        LibraryPalette.cardPalettes[paletteIndex % LibraryPalette.cardPalettes.count]
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: openAction) {
                VStack(alignment: .leading, spacing: 12) {
                    ScoreCardThumbnail(
                        palette: palette,
                        formatLabel: score.format.rawValue.uppercased(),
                        previewImage: score.previewImageData.flatMap(UIImage.init(data:))
                    )
                    .aspectRatio(0.74, contentMode: .fit)

                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(score.primaryTitle)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(LibraryPalette.ink)
                                .lineLimit(1)

                            Text(score.secondaryLine ?? "Unknown Composer")
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundStyle(LibraryPalette.mutedInk)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(action: editInfoAction) {
                    Label("Edit Info", systemImage: "square.and.pencil")
                }
                if let addToFolderAction {
                    Button(action: addToFolderAction) {
                        Label("Add to Setlist", systemImage: "text.badge.plus")
                    }
                }
                if let removeFromFolderAction {
                    Button(action: removeFromFolderAction) {
                        Label("Remove from Setlist", systemImage: "text.badge.minus")
                    }
                }
                Button(role: .destructive, action: deleteAction) {
                    Label("Delete Score", systemImage: "trash")
                }
            }
            .onDrag {
                NSItemProvider(object: score.setlistKey as NSString)
            }

            Button {
                isInfoPresented = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LibraryPalette.mutedInk)
                    .frame(width: 32, height: 32)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 10)
            .popover(isPresented: $isInfoPresented, arrowEdge: .top) {
                ScoreCardInfoPopover(score: score)
            }
        }
    }
}

private struct ScoreCardThumbnail: View {
    let palette: (fill: Color, icon: Color)
    let formatLabel: String
    let previewImage: UIImage?

    var body: some View {
        Group {
            if let previewImage {
                ZStack(alignment: .bottomTrailing) {
                    Color.white

                    Image(uiImage: previewImage)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, 6)
                        .padding(.top, 6)
                        .padding(.bottom, 18)

                    if !formatLabel.isEmpty {
                        Text(formatLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 0.84, green: 0.84, blue: 0.87))
                            .padding(.trailing, 14)
                            .padding(.bottom, 12)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 0, style: .continuous)
                            .fill(palette.fill)

                        Image(systemName: "music.note")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(palette.icon)
                    }
                    .frame(height: 64)

                    ZStack(alignment: .topLeading) {
                        Color.white

                        ScoreCardPlaceholder()
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 14)

                        VStack {
                            Spacer(minLength: 0)

                            HStack {
                                Spacer()
                                if !formatLabel.isEmpty {
                                    Text(formatLabel)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color(red: 0.84, green: 0.84, blue: 0.87))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(LibraryPalette.cardBorder, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 3)
    }
}

private struct ScoreCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(LibraryPalette.skeleton)
                .frame(width: 92, height: 8)

            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(LibraryPalette.skeleton)
                .frame(width: 70, height: 8)

            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(LibraryPalette.skeleton.opacity(0.9))
                .frame(width: 108, height: 8)

            Spacer(minLength: 0)
        }
    }
}

private struct ScoreCardInfoPopover: View {
    let score: ReaderRecentDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(score.primaryTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(LibraryPalette.ink)

                if let secondaryLine = score.secondaryLine?.trimmedToNil {
                    Text(secondaryLine)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(LibraryPalette.mutedInk)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ScoreInfoRow(label: "Composer", value: score.composer ?? "Unknown")

                if let subtitle = score.subtitle?.trimmedToNil {
                    ScoreInfoRow(label: "Subtitle", value: subtitle)
                }

                ScoreInfoRow(label: "Format", value: score.format.displayName)
                ScoreInfoRow(label: "Imported", value: score.importedAt.formatted(date: .abbreviated, time: .omitted))
                ScoreInfoRow(label: "Storage", value: score.isStoredInLibrary ? "Aria Library" : "External File")

                if let version = score.museScoreVersion?.trimmedToNil {
                    ScoreInfoRow(label: "MuseScore", value: version)
                }
            }

            Text(score.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LibraryPalette.subtle)
                .lineLimit(2)
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .background(LibraryPalette.background)
    }
}

private struct ScoreInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LibraryPalette.subtle)
                .frame(width: 84, alignment: .leading)

            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LibraryPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LibraryScoreInfoEditorSheet: View {
    @Binding var metadata: ScoreEditableMetadata
    let isSaving: Bool
    let cancelAction: () -> Void
    let saveAction: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Title Page") {
                    TextField("Title", text: $metadata.title)
                    TextField("Subtitle", text: $metadata.subtitle)
                }

                Section("Credits") {
                    TextField("Composer", text: $metadata.composer)
                    TextField("Arranger", text: $metadata.arranger)
                    TextField("Lyricist", text: $metadata.lyricist)
                }

                Section {
                    Text("Changes save back to this score in your Aria library.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Score Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancelAction)
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save", action: saveAction)
                        .disabled(isSaving)
                }
            }
        }
    }
}

private struct LibraryEmptyState: View {
    let createAction: () -> Void
    let importAction: () -> Void
    let selectedCategory: LibraryCategory

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: isSetlist ? "music.note.list" : "music.note.house")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(LibraryPalette.accent)

            Text(isSetlist ? "No scores in this setlist" : "No scores in your library yet")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(LibraryPalette.ink)

            Text(
                isSetlist
                    ? "Use Add Scores above to choose scores from your library."
                    : "Create a new score or import a MuseScore file. It will appear here, ready to open in the reader."
            )
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LibraryPalette.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            if !isSetlist {
                HStack(spacing: 14) {
                Button(action: createAction) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                        Text("New Score")
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LibraryPalette.accent)
                    )
                }
                .buttonStyle(.plain)

                Button(action: importAction) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.badge.plus")
                        Text("Import")
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LibraryPalette.accent)
                    .padding(.horizontal, 24)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(LibraryPalette.cardBorder, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private var isSetlist: Bool {
        if case .setlist = selectedCategory {
            return true
        }
        return false
    }
}

private struct SetlistReaderSequence {
    let setlistID: UUID
    let scores: [ReaderRecentDocument]
    let selectedIndex: Int
}

struct SetlistReaderNavigationPlan {
    static func targetIndex(
        from currentIndex: Int,
        direction: ScoreReaderSequenceDirection,
        scoreCount: Int
    ) -> Int? {
        guard scoreCount > 0, currentIndex >= 0, currentIndex < scoreCount else {
            return nil
        }

        let candidate: Int
        switch direction {
        case .previous:
            candidate = currentIndex - 1
        case .next:
            candidate = currentIndex + 1
        }
        return candidate >= 0 && candidate < scoreCount ? candidate : nil
    }

    static func initialPageIndex(
        for direction: ScoreReaderSequenceDirection,
        targetPageCount: Int
    ) -> Int {
        switch direction {
        case .previous:
            return max(targetPageCount - 1, 0)
        case .next:
            return 0
        }
    }

    static func nextPreloadIndex(from currentIndex: Int, scoreCount: Int) -> Int? {
        targetIndex(from: currentIndex, direction: .next, scoreCount: scoreCount)
    }
}

private struct SetlistScoreReaderHost: View {
    private struct FailedTransition {
        let direction: ScoreReaderSequenceDirection
        let readingStyle: ScoreReaderReadingStyle
    }

    private struct PreloadedScore {
        let index: Int
        let scoreID: ReaderRecentDocument.ID
        let session: ScoreSession
    }

    @ObservedObject var model: MuseReaderAppModel

    let sequence: SetlistReaderSequence

    @State private var currentSession: ScoreSession
    @State private var currentIndex: Int
    @State private var initialPageIndex = 0
    @State private var readingStyleOverride: ScoreReaderReadingStyle?
    @State private var transitionErrorMessage: String?
    @State private var failedTransition: FailedTransition?
    @State private var retryLoadingTitle: String?
    @State private var preloadedNextScore: PreloadedScore?
    @State private var preloadTask: Task<Void, Never>?
    @State private var preloadingTargetIndex: Int?
    @State private var preloadGeneration = 0
    @State private var sessionsAwaitingPreviewRefresh: [ScoreSession] = []

    init(model: MuseReaderAppModel, initialSession: ScoreSession, sequence: SetlistReaderSequence) {
        self.model = model
        self.sequence = sequence
        _currentSession = State(initialValue: initialSession)
        _currentIndex = State(
            initialValue: min(max(sequence.selectedIndex, 0), max(sequence.scores.count - 1, 0))
        )
    }

    var body: some View {
        ZStack {
            ScoreReaderView(
                session: currentSession,
                initialPageIndex: initialPageIndex,
                resumesRememberedPage: false,
                initialReadingStyle: readingStyleOverride,
                setlistNavigation: navigation,
                readerReadyAction: readerDidBecomeReady
            )
            .id(currentSession.id)

            if let retryLoadingTitle {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Opening \(retryLoadingTitle)…")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .alert("Couldn’t Open Score", isPresented: transitionErrorIsPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Try Again") {
                retryFailedTransition()
            }
        } message: {
            Text(transitionErrorMessage ?? "Aria could not open the selected score.")
        }
        .onDisappear {
            cancelNextScorePreload()
            let departedSessions = sessionsAwaitingPreviewRefresh
            let finalSession = currentSession
            sessionsAwaitingPreviewRefresh.removeAll()
            Task {
                for session in departedSessions {
                    await model.refreshLibraryPreviewAfterSetlistTransition(session)
                }
                await model.refreshLibraryPreviewAfterClosing(finalSession)
            }
        }
    }

    private var navigation: ScoreReaderSetlistNavigation {
        let previousTitle = score(at: currentIndex - 1)?.primaryTitle
        let nextTitle = score(at: currentIndex + 1)?.primaryTitle
        let nextPosition = min(currentIndex + 2, sequence.scores.count)
        return ScoreReaderSetlistNavigation(
            previousScoreTitle: previousTitle,
            nextScoreTitle: nextTitle,
            positionLabel: "Score \(nextPosition) of \(sequence.scores.count)",
            transition: { direction, readingStyle in
                await transition(direction: direction, readingStyle: readingStyle)
            }
        )
    }

    private var transitionErrorIsPresented: Binding<Bool> {
        Binding {
            transitionErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                transitionErrorMessage = nil
            }
        }
    }

    private func score(at index: Int) -> ReaderRecentDocument? {
        guard sequence.scores.indices.contains(index) else {
            return nil
        }
        return sequence.scores[index]
    }

    @MainActor
    private func transition(
        direction: ScoreReaderSequenceDirection,
        readingStyle: ScoreReaderReadingStyle
    ) async -> Bool {
        guard let targetIndex = SetlistReaderNavigationPlan.targetIndex(
            from: currentIndex,
            direction: direction,
            scoreCount: sequence.scores.count
        ) else {
            return false
        }

        let targetScore = sequence.scores[targetIndex]
        let outgoingSession = currentSession
        do {
            let targetSession: ScoreSession
            if direction == .next {
                if preloadingTargetIndex == targetIndex {
                    await preloadTask?.value
                }

                if let preloadedNextScore,
                   preloadedNextScore.index == targetIndex,
                   preloadedNextScore.scoreID == targetScore.id
                {
                    targetSession = preloadedNextScore.session
                    model.activatePreloadedReaderSession(targetSession, for: targetScore)
                } else {
                    targetSession = try await model.loadReaderSession(for: targetScore)
                }
            } else {
                cancelNextScorePreload()
                targetSession = try await model.loadReaderSession(for: targetScore)
            }

            cancelNextScorePreload()
            readingStyleOverride = readingStyle
            initialPageIndex = SetlistReaderNavigationPlan.initialPageIndex(
                for: direction,
                targetPageCount: targetSession.pageCount
            )
            sessionsAwaitingPreviewRefresh.append(outgoingSession)
            currentIndex = targetIndex
            currentSession = targetSession
            transitionErrorMessage = nil
            failedTransition = nil
            return true
        } catch is CancellationError {
            return false
        } catch {
            failedTransition = FailedTransition(direction: direction, readingStyle: readingStyle)
            transitionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func readerDidBecomeReady() {
        preloadNextScoreIfNeeded()
        refreshDepartedSessionPreviews()
    }

    private func refreshDepartedSessionPreviews() {
        guard !sessionsAwaitingPreviewRefresh.isEmpty else {
            return
        }

        let sessions = sessionsAwaitingPreviewRefresh
        sessionsAwaitingPreviewRefresh.removeAll()
        Task { @MainActor in
            // Let the forward preload claim the render-core lane first. Neither
            // task blocks the newly displayed score.
            try? await Task.sleep(for: .milliseconds(200))
            for session in sessions {
                await model.refreshLibraryPreviewAfterSetlistTransition(session)
            }
        }
    }

    private func preloadNextScoreIfNeeded() {
        guard let targetIndex = SetlistReaderNavigationPlan.nextPreloadIndex(
                  from: currentIndex,
                  scoreCount: sequence.scores.count
              ),
              preloadedNextScore?.index != targetIndex,
              preloadingTargetIndex != targetIndex
        else {
            return
        }

        cancelNextScorePreload()
        let targetScore = sequence.scores[targetIndex]
        preloadGeneration += 1
        let generation = preloadGeneration
        preloadingTargetIndex = targetIndex
        preloadTask = Task { @MainActor in
            do {
                let session = try await model.preloadReaderSession(for: targetScore)
                guard !Task.isCancelled,
                      generation == preloadGeneration,
                      currentIndex + 1 == targetIndex,
                      let session
                else {
                    if generation == preloadGeneration {
                        preloadTask = nil
                        preloadingTargetIndex = nil
                    }
                    return
                }

                preloadedNextScore = PreloadedScore(
                    index: targetIndex,
                    scoreID: targetScore.id,
                    session: session
                )
                preloadTask = nil
                preloadingTargetIndex = nil
                print("Aria setlist preload ready: score=\(targetScore.primaryTitle)")
            } catch is CancellationError {
                if generation == preloadGeneration {
                    preloadTask = nil
                    preloadingTargetIndex = nil
                }
            } catch {
                if generation == preloadGeneration {
                    preloadTask = nil
                    preloadingTargetIndex = nil
                }
                print("Aria setlist preload skipped: score=\(targetScore.primaryTitle) error=\(error.localizedDescription)")
            }
        }
    }

    private func cancelNextScorePreload() {
        preloadGeneration += 1
        preloadTask?.cancel()
        preloadTask = nil
        preloadingTargetIndex = nil
        preloadedNextScore = nil
    }

    private func retryFailedTransition() {
        guard let failedTransition,
              let targetIndex = SetlistReaderNavigationPlan.targetIndex(
                  from: currentIndex,
                  direction: failedTransition.direction,
                  scoreCount: sequence.scores.count
              )
        else {
            return
        }

        transitionErrorMessage = nil
        retryLoadingTitle = sequence.scores[targetIndex].primaryTitle
        Task { @MainActor in
            _ = await transition(
                direction: failedTransition.direction,
                readingStyle: failedTransition.readingStyle
            )
            retryLoadingTitle = nil
        }
    }
}

private struct LibraryReaderPresentation: Identifiable {
    let id = UUID()
    let session: ScoreSession
    let startPageIndex: Int
    var initialToolCategory: ScoreReaderToolCategory = .select
    var initialInteractionMode: ScoreReaderInteractionMode = .view
    var setlistSequence: SetlistReaderSequence? = nil
}

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

    @State private var searchText = ""
    @State private var selectedCategory: LibraryCategory = .allScores
    @State private var readerPresentation: LibraryReaderPresentation?
    @State private var scorePendingDeletion: ReaderRecentDocument?
    @State private var isNewSetlistPresented = false
    @State private var newSetlistName = ""
    @State private var folderPendingRename: LibrarySetlistFolder?
    @State private var renameSetlistName = ""
    @State private var isOpenSourceLegalPresented = false

    private let sidebarWidth: CGFloat = 286

    private var displayedScores: [ReaderRecentDocument] {
        let baseScores: [ReaderRecentDocument]
        switch selectedCategory {
        case .allScores:
            baseScores = model.recents.sorted { $0.lastOpened > $1.lastOpened }
        case .setlists, .settings:
            baseScores = []
        case .setlist(let folderID):
            if let folder = model.setlistFolders.first(where: { $0.id == folderID }) {
                let scoreKeys = Set(folder.scoreKeys)
                baseScores = model.recents
                    .filter { scoreKeys.contains($0.setlistKey) || scoreKeys.contains($0.fileReference) }
                    .sorted { $0.lastOpened > $1.lastOpened }
            } else {
                baseScores = []
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return baseScores
        }

        return baseScores.filter { score in
            [
                score.primaryTitle,
                score.secondaryLine ?? "",
                score.displayName
            ]
            .map { $0.lowercased() }
            .contains { $0.contains(query) }
        }
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

    var body: some View {
        GeometryReader { geometry in
            if isPhoneInterface {
                PhoneLibraryView(
                    scores: displayedScores,
                    selectedCategory: $selectedCategory,
                    title: displayedCategoryTitle,
                    searchText: $searchText,
                    folders: model.setlistFolders,
                    createAction: model.startCreateScore,
                    importAction: model.startImport,
                    openAction: openScore,
                    deleteAction: { scorePendingDeletion = $0 },
                    createFolderAction: {
                        newSetlistName = ""
                        isNewSetlistPresented = true
                    },
                    renameFolderAction: { folder in
                        folderPendingRename = folder
                        renameSetlistName = folder.name
                    },
                    openSourceAction: {
                        isOpenSourceLegalPresented = true
                    }
                )
                .background(LibraryPalette.mainBackground.ignoresSafeArea())
                .overlay {
                    if model.isLoading {
                        Color.black.opacity(0.05)
                            .ignoresSafeArea()

                        ProgressView("Importing score…")
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
                    createFolderAction: {
                        newSetlistName = ""
                        isNewSetlistPresented = true
                    },
                    renameFolderAction: { folder in
                        folderPendingRename = folder
                        renameSetlistName = folder.name
                    },
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
                    selectedCategory: selectedCategory,
                    title: displayedCategoryTitle,
                    searchText: $searchText,
                    createAction: model.startCreateScore,
                    importAction: model.startImport,
                    openAction: openScore,
                    deleteAction: { scorePendingDeletion = $0 },
                    openSourceAction: {
                        isOpenSourceLegalPresented = true
                    }
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
            allowsMultipleSelection: false,
            onCompletion: model.handleImportSelection
        )
        .task {
            await model.refreshVisibleLibrary()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }
            Task {
                await model.refreshVisibleLibrary()
            }
        }
        .onChange(of: model.pendingImportedSession?.id) { _, _ in
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
        .alert("New Folder", isPresented: $isNewSetlistPresented) {
            TextField("Folder name", text: $newSetlistName)
            Button("Cancel", role: .cancel) {
                newSetlistName = ""
            }
            Button("Create") {
                model.createSetlistFolder(named: newSetlistName)
                newSetlistName = ""
            }
        } message: {
            Text("Create a folder for organizing scores.")
        }
        .alert("Rename Folder", isPresented: renameConfirmationIsPresented) {
            TextField("Folder name", text: $renameSetlistName)
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
                    readerPresentation = LibraryReaderPresentation(session: session, startPageIndex: 0)
                }
                return true
            }
        }
        .fullScreenCover(item: $readerPresentation) { presentation in
            ScoreReaderView(session: presentation.session, initialPageIndex: presentation.startPageIndex)
                .onDisappear {
                    Task {
                        await model.refreshLibraryPreviewAfterClosing(presentation.session)
                    }
                }
        }
        .sheet(isPresented: $isOpenSourceLegalPresented) {
            OpenSourceLegalView()
        }
        // Re-assert a visible status bar so the top safe-area inset is restored
        // after the reader cover (which hides it) is dismissed.
        .statusBarHidden(false)
    }

    private var visibleErrorAlert: Binding<ReaderAlert?> {
        Binding {
            model.isCreateScorePresented || readerPresentation != nil ? nil : model.errorAlert
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

    private func openScore(_ recent: ReaderRecentDocument) {
        Task {
            guard let session = await model.readerSession(for: recent) else {
                return
            }

            readerPresentation = LibraryReaderPresentation(session: session, startPageIndex: 0)
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
            return "Folders"
        case .setlist(_):
            return "Folder"
        case .settings:
            return "Settings"
        }
    }
}

private enum LibraryPalette {
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
    let createFolderAction: () -> Void
    let renameFolderAction: (LibrarySetlistFolder) -> Void
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
                            SidebarSectionTitle("FOLDERS")
                            Spacer()
                            Button(action: createFolderAction) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(LibraryPalette.subtle)
                            }
                            .buttonStyle(.plain)
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

                ProgressView("Importing score…")
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

private struct AriaLogoMark: View {
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
                Image(systemName: "folder")
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
                Label("Rename Folder", systemImage: "pencil")
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
        case .setlists: return "Folders"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .setlists: return "folder"
        case .settings: return "gearshape"
        }
    }
}

private struct PhoneLibraryView: View {
    let scores: [ReaderRecentDocument]
    @Binding var selectedCategory: LibraryCategory
    let title: String
    @Binding var searchText: String
    let folders: [LibrarySetlistFolder]
    let createAction: () -> Void
    let importAction: () -> Void
    let openAction: (ReaderRecentDocument) -> Void
    let deleteAction: (ReaderRecentDocument) -> Void
    let createFolderAction: () -> Void
    let renameFolderAction: (LibrarySetlistFolder) -> Void
    let openSourceAction: () -> Void

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
                }

                // ── Content area ────────────────────────────────────────
                if selectedCategory == .setlists {
                    PhoneSetlistContent(
                        folders: folders,
                        selectedCategory: $selectedCategory,
                        createFolderAction: createFolderAction,
                        renameFolderAction: renameFolderAction
                    )
                } else if activeTab == .settings {
                    PhoneSettingsContent(openSourceAction: openSourceAction)
                } else if showsScoreList {
                    if case .setlist = selectedCategory {
                        Text(title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(LibraryPalette.ink)
                            .lineLimit(1)
                    }
                    PhoneScoreList(
                        scores: scores,
                        openAction: openAction,
                        deleteAction: deleteAction
                    )
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

    var body: some View {
        VStack(spacing: 0) {
            // Header row with New Folder button
            HStack {
                Text("Folders")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LibraryPalette.subtle)
                    .tracking(0.5)
                Spacer()
                Button(action: createFolderAction) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New Folder")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LibraryPalette.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            if folders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(LibraryPalette.subtle)
                    Text("No folders yet")
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
                                Image(systemName: "folder")
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
                                Label("Rename Folder", systemImage: "pencil")
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
    let deleteAction: (ReaderRecentDocument) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(scores.enumerated()), id: \.element.id) { index, score in
                PhoneScoreListRow(
                    score: score,
                    openAction: { openAction(score) },
                    deleteAction: { deleteAction(score) }
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

private struct PhoneScoreListRow: View {
    let score: ReaderRecentDocument
    let openAction: () -> Void
    let deleteAction: () -> Void

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
            Button(role: .destructive, action: deleteAction) {
                Label("Delete Score", systemImage: "trash")
            }
        }
    }
}

private struct PhoneSettingsContent: View {
    let openSourceAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(LibraryPalette.ink)

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
    let selectedCategory: LibraryCategory
    let title: String
    @Binding var searchText: String
    let createAction: () -> Void
    let importAction: () -> Void
    let openAction: (ReaderRecentDocument) -> Void
    let deleteAction: (ReaderRecentDocument) -> Void
    let openSourceAction: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 170, maximum: 195), spacing: 24)
    ]

    var body: some View {
        VStack(spacing: 0) {
            LibraryDashboardHeader(
                title: title,
                searchText: $searchText,
                createAction: createAction,
                importAction: importAction
            )

            ScrollView {
                if selectedCategory == .settings {
                    LibrarySettingsContent(openSourceAction: openSourceAction)
                        .padding(34)
                } else if scores.isEmpty {
                    LibraryEmptyState(createAction: createAction, importAction: importAction, selectedCategory: selectedCategory)
                        .padding(36)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                        ForEach(Array(scores.enumerated()), id: \.element.id) { index, score in
                            LibraryScoreCard(
                                score: score,
                                paletteIndex: index,
                                openAction: { openAction(score) },
                                deleteAction: { deleteAction(score) }
                            )
                        }
                    }
                    .padding(34)
                }
            }
        }
        .background(LibraryPalette.mainBackground)
    }
}

private struct LibrarySettingsContent: View {
    let openSourceAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(LibraryPalette.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)

            HStack(spacing: 16) {
                SearchField(text: $searchText)
                    .frame(width: 320)

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
    let deleteAction: () -> Void

    @State private var isInfoPresented = false

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
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.55)
                    .onEnded { _ in
                        deleteAction()
                    }
            )
            .contextMenu {
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

private struct LibraryEmptyState: View {
    let createAction: () -> Void
    let importAction: () -> Void
    let selectedCategory: LibraryCategory

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note.house")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(LibraryPalette.accent)

            Text("No scores in your library yet")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(LibraryPalette.ink)

            Text("Create a new score or import a MuseScore file. It will appear here with the new library styling, ready to open in the reader.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LibraryPalette.mutedInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

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
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

private struct LibraryReaderPresentation: Identifiable {
    let id = UUID()
    let session: ScoreSession
    let startPageIndex: Int
}

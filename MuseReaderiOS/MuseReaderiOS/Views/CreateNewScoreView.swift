//
//  CreateNewScoreView.swift
//  MuseReaderiOS
//
//  Created by Codex on 5/7/26.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CreateNewScoreView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft = NewScoreDraft()
    @State private var isCreating = false

    let createAction: (NewScoreDraft) async -> Bool

    private var isPhoneInterface: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    var body: some View {
        GeometryReader { geometry in
            let isPhone = isPhoneInterface
            ZStack(alignment: .bottom) {
                Color(red: 0.985, green: 0.986, blue: 0.993)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    CreateScoreTopBar(isPhone: isPhone, cancelAction: { dismiss() })

                    ScrollView {
                        VStack(alignment: .leading, spacing: isPhone ? 14 : 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Create New Score")
                                    .font(.system(size: isPhone ? 32 : 30, weight: .bold))
                                    .foregroundStyle(CreateScorePalette.ink)

                                Text("Start from a blank score or choose a template.")
                                    .font(.system(size: isPhone ? 15 : 16, weight: .medium))
                                    .foregroundStyle(CreateScorePalette.mutedInk)
                            }
                            .padding(.top, isPhone ? 18 : 24)

                            content(width: geometry.size.width, isPhone: isPhone)
                                .padding(.bottom, isPhone ? 112 : 92)
                        }
                        .padding(.horizontal, isPhone ? 16 : 28)
                    }
                }

                CreateScoreBottomBar(
                    isCreating: isCreating,
                    canCreate: !draft.selectedInstruments.isEmpty,
                    isPhone: isPhone,
                    cancelAction: { dismiss() },
                    createAction: createScore
                )
            }
        }
    }

    @ViewBuilder
    private func content(width: CGFloat, isPhone: Bool) -> some View {
        let isWide = !isPhone && width >= 980

        if isWide {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 12) {
                    CreateScoreDetailsSection(draft: $draft, isPhone: isPhone)
                    CreateScoreInstrumentationSection(instruments: $draft.selectedInstruments, isPhone: isPhone)
                }
                .frame(width: min(380, width * 0.33))

                VStack(spacing: 12) {
                    CreateScoreTemplateSection(draft: $draft, isPhone: isPhone)
                    CreateScoreMusicSettingsSection(draft: $draft, isPhone: isPhone)
                    CreateScoreOptionsSection(draft: $draft, isPhone: isPhone)
                }
            }
        } else {
            VStack(spacing: 12) {
                CreateScoreDetailsSection(draft: $draft, isPhone: isPhone)
                CreateScoreTemplateSection(draft: $draft, isPhone: isPhone)
                CreateScoreInstrumentationSection(instruments: $draft.selectedInstruments, isPhone: isPhone)
                CreateScoreMusicSettingsSection(draft: $draft, isPhone: isPhone)
                CreateScoreOptionsSection(draft: $draft, isPhone: isPhone)
            }
        }
    }

    private func createScore() {
        guard !isCreating, !draft.selectedInstruments.isEmpty else {
            return
        }

        isCreating = true
        Task {
            let created = await createAction(draft)
            await MainActor.run {
                isCreating = false
                if created {
                    dismiss()
                }
            }
        }
    }
}

private enum CreateScorePalette {
    static let accent = Color.blue
    static let accentSoft = Color.blue.opacity(0.10)
    static let ink = Color(red: 0.12, green: 0.12, blue: 0.14)
    static let mutedInk = Color(red: 0.42, green: 0.42, blue: 0.46)
    static let subtle = Color(red: 0.67, green: 0.67, blue: 0.72)
    static let cardBorder = Color(red: 0.88, green: 0.89, blue: 0.92)
    static let divider = Color(red: 0.90, green: 0.91, blue: 0.94)
}

private struct CreateScoreTopBar: View {
    var isPhone = false
    let cancelAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: cancelAction) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                    if !isPhone {
                        Text("My Scores")
                    }
                }
                .font(.system(size: isPhone ? 20 : 17, weight: .medium))
                .foregroundStyle(CreateScorePalette.ink)
                .frame(width: isPhone ? 38 : nil, height: isPhone ? 38 : nil)
            }
            .buttonStyle(.plain)

            if isPhone {
                Text("My Scores")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CreateScorePalette.ink)
            }

            Spacer()
        }
        .frame(height: isPhone ? 58 : 54)
        .padding(.horizontal, isPhone ? 14 : 28)
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CreateScorePalette.divider)
                .frame(height: 1)
        }
    }
}

private struct CreateScoreSection<Content: View>: View {
    let number: Int
    let title: String
    var isPhone = false
    var collapsible = false
    @State private var isExpanded: Bool
    @ViewBuilder let content: Content

    init(number: Int,
         title: String,
         isPhone: Bool = false,
         collapsible: Bool = false,
         startsCollapsed: Bool = false,
         @ViewBuilder content: () -> Content)
    {
        self.number = number
        self.title = title
        self.isPhone = isPhone
        self.collapsible = collapsible
        self._isExpanded = State(initialValue: !(collapsible && startsCollapsed))
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isPhone ? 13 : 16) {
            header

            if isExpanded {
                content
            }
        }
        .padding(isPhone ? 13 : 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: isPhone ? 12 : 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: isPhone ? 12 : 14, style: .continuous)
                .stroke(CreateScorePalette.cardBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var header: some View {
        if collapsible {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                headerLabel
            }
            .buttonStyle(.plain)
        } else {
            headerLabel
        }
    }

    private var headerLabel: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: isPhone ? 14 : 16, weight: .semibold))
                .foregroundStyle(CreateScorePalette.accent)
                .frame(width: isPhone ? 24 : 26, height: isPhone ? 24 : 26)
                .overlay {
                    Circle()
                        .stroke(CreateScorePalette.accent, lineWidth: 1.5)
                }

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CreateScorePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if collapsible {
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CreateScorePalette.mutedInk)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .contentShape(Rectangle())
    }
}

private struct CreateScoreDetailsSection: View {
    @Binding var draft: NewScoreDraft
    var isPhone = false

    var body: some View {
        CreateScoreSection(number: 1, title: "Score Details", isPhone: isPhone) {
            VStack(spacing: 12) {
                CreateScoreTextField(label: "Title", placeholder: "New Score", text: $draft.title)
                CreateScoreTextField(label: "Subtitle", placeholder: "Subtitle", text: $draft.subtitle, optional: true)
                CreateScoreTextField(label: "Composer", placeholder: "Your Name", text: $draft.composer)
            }
        }
    }
}

private struct CreateScoreTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var optional = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                if optional {
                    Text("(Optional)")
                        .foregroundStyle(CreateScorePalette.subtle)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(CreateScorePalette.ink)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .regular))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CreateScorePalette.cardBorder, lineWidth: 1)
                }
        }
    }
}

private struct CreateScoreTemplateSection: View {
    @Binding var draft: NewScoreDraft
    var isPhone = false
    @State private var isTemplateBrowserPresented = false

    private var columns: [GridItem] {
        if isPhone {
            return [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ]
        }
        return [GridItem(.adaptive(minimum: 108, maximum: 128), spacing: 10)]
    }

    var body: some View {
        CreateScoreSection(number: 2, title: "Template", isPhone: isPhone) {
            LazyVGrid(columns: columns, spacing: isPhone ? 8 : 10) {
                ForEach(NewScoreTemplate.allCases) { template in
                    CreateScoreTemplateCard(
                        template: template,
                        isSelected: draft.template == template && template != .custom,
                        isPhone: isPhone
                    ) {
                        if template == .custom {
                            isTemplateBrowserPresented = true
                        } else {
                            applyTemplate(template)
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isTemplateBrowserPresented) {
            TemplateBrowserSheet(selectedTemplate: draft.templateChoice) { choice in
                draft.template = .custom
                draft.templateChoice = choice
                draft.title = "New \(choice.title) Score"
                draft.selectedInstruments = choice.instruments
                isTemplateBrowserPresented = false
            }
            .presentationBackground(.clear)
        }
    }

    private func applyTemplate(_ template: NewScoreTemplate) {
        draft.template = template
        draft.templateChoice = template.choice
        draft.title = template.defaultTitle
        draft.selectedInstruments = template == .blankScore ? [] : template.choice.instruments
    }
}

private struct CreateScoreTemplateCard: View {
    let template: NewScoreTemplate
    let isSelected: Bool
    var isPhone = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: isPhone ? 7 : 10) {
                ZStack(alignment: .topTrailing) {
                    CreateScoreTemplateIcon(template: template, isPhone: isPhone)
                        .frame(height: isPhone ? 46 : 72)
                        .frame(maxWidth: .infinity)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: isPhone ? 10 : 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: isPhone ? 20 : 24, height: isPhone ? 20 : 24)
                            .background(CreateScorePalette.accent, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }

                Text(template.title)
                    .font(.system(size: isPhone ? 12 : 14, weight: .medium))
                    .foregroundStyle(isSelected ? CreateScorePalette.accent : CreateScorePalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(isPhone ? 7 : 10)
            .frame(height: isPhone ? 104 : 152)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? CreateScorePalette.accent : CreateScorePalette.cardBorder, lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CreateScoreTemplateIcon: View {
    let template: NewScoreTemplate
    var isPhone = false

    private var glyphSize: CGFloat { isPhone ? 24 : 32 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isPhone ? 10 : 12, style: .continuous)
                .fill(isCustom ? CreateScorePalette.divider.opacity(0.5) : CreateScorePalette.accentSoft)

            if isCustom {
                RoundedRectangle(cornerRadius: isPhone ? 10 : 12, style: .continuous)
                    .stroke(CreateScorePalette.subtle, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
            }

            glyph
                .foregroundStyle(isCustom ? CreateScorePalette.mutedInk : CreateScorePalette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isCustom: Bool { template == .custom }

    @ViewBuilder
    private var glyph: some View {
        switch template {
        case .blank:
            // The "Treble Clef" template — show an actual clef glyph.
            Text(ScorePartClef.treble.symbol)
                .font(.system(size: glyphSize * 1.45, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        case .piano:
            Image(systemName: "pianokeys")
                .font(.system(size: glyphSize, weight: .regular))
        case .leadSheet:
            Image(systemName: "music.note.list")
                .font(.system(size: glyphSize, weight: .regular))
        case .stringQuartet:
            Image(systemName: "music.quarternote.3")
                .font(.system(size: glyphSize, weight: .regular))
        case .choir:
            Image(systemName: "person.3.fill")
                .font(.system(size: glyphSize * 0.82, weight: .regular))
        case .blankScore:
            Image(systemName: "doc")
                .font(.system(size: glyphSize, weight: .regular))
        case .custom:
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: glyphSize * 0.9, weight: .regular))
        }
    }
}

private struct TemplateBrowserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: NewScoreTemplateCategory
    @State private var focusedTemplate: NewScoreTemplateChoice

    let selectAction: (NewScoreTemplateChoice) -> Void

    init(selectedTemplate: NewScoreTemplateChoice, selectAction: @escaping (NewScoreTemplateChoice) -> Void) {
        let categories = NewScoreTemplateChoice.allTemplates
        let category = categories.first { category in
            category.templates.contains { $0.id == selectedTemplate.id }
        } ?? categories[0]
        _selectedCategory = State(initialValue: category)
        _focusedTemplate = State(initialValue: category.templates.first { $0.id == selectedTemplate.id } ?? category.templates[0])
        self.selectAction = selectAction
    }

    var body: some View {
        GeometryReader { geometry in
            let isPhone = UIDevice.current.userInterfaceIdiom == .phone
            let modalWidth = min(max(geometry.size.width - 64, 720), 940)
            let modalHeight = min(max(geometry.size.height - 170, 560), 760)

            ZStack {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()

                if isPhone {
                    VStack(spacing: 0) {
                        header
                        phoneTemplateBrowser
                    }
                    .frame(width: max(geometry.size.width - 24, 0), height: max(geometry.size.height - 74, 0))
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 28, x: 0, y: 14)
                } else {
                    VStack(spacing: 0) {
                        header

                        HStack(spacing: 0) {
                            categoryList
                                .frame(width: 220)
                            Divider()
                            templateList
                                .frame(maxWidth: .infinity)
                            Divider()
                            instrumentPanel
                                .frame(width: 292)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(width: modalWidth, height: modalHeight)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 28, x: 0, y: 14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
    }

    private var isPhoneInterface: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CreateScorePalette.accent)
                .frame(minWidth: isPhoneInterface ? 62 : 110, alignment: .leading)

            Spacer()

            Text("Choose Template")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CreateScorePalette.ink)

            Spacer()

            Button("Use Template") {
                selectAction(focusedTemplate)
            }
            .font(.system(size: isPhoneInterface ? 14 : 15, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, isPhoneInterface ? 10 : 14)
            .frame(minWidth: isPhoneInterface ? 78 : 110, minHeight: 34)
            .background(CreateScorePalette.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .padding(.horizontal, isPhoneInterface ? 14 : 22)
        .padding(.vertical, 16)
    }

    private var categoryList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(NewScoreTemplateChoice.allTemplates) { category in
                    Button {
                        selectedCategory = category
                        focusedTemplate = category.templates[0]
                    } label: {
                        HStack {
                            Text(category.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.84)
                            Spacer()
                        }
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(CreateScorePalette.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(category.id == selectedCategory.id ? Color.blue.opacity(0.16) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(red: 0.82, green: 0.86, blue: 0.91))
    }

    private var templateList: some View {
        List(selectedCategory.templates) { template in
            Button {
                focusedTemplate = template
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CreateScorePalette.ink)
                        Text(template.categoryTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CreateScorePalette.mutedInk)
                    }
                    Spacer()
                    if template.id == focusedTemplate.id {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(CreateScorePalette.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(template.id == focusedTemplate.id ? CreateScorePalette.accentSoft : Color.clear)
        }
        .listStyle(.plain)
    }

    private var instrumentPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(focusedTemplate.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(CreateScorePalette.ink)

            Text(focusedTemplate.categoryTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CreateScorePalette.mutedInk)

            Text("Instrumentation")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CreateScorePalette.ink)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(focusedTemplate.instruments) { instrument in
                        HStack(spacing: 10) {
                            CreateScoreClef(clef: instrument.clef, size: 20)
                                .frame(width: 24, height: 30)
                            Text(instrument.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(CreateScorePalette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            Spacer()
                        }
                        .frame(height: 38)
                        if instrument.id != focusedTemplate.instruments.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(CreateScorePalette.cardBorder, lineWidth: 1)
            }

            Spacer()
        }
        .padding(18)
        .background(Color(.systemGroupedBackground))
    }

    private var phoneTemplateBrowser: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NewScoreTemplateChoice.allTemplates) { category in
                        Button {
                            selectedCategory = category
                            focusedTemplate = category.templates.first ?? focusedTemplate
                        } label: {
                            Text(category.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(category.id == selectedCategory.id ? CreateScorePalette.accent : CreateScorePalette.mutedInk)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(category.id == selectedCategory.id ? CreateScorePalette.accentSoft : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            List(selectedCategory.templates) { template in
                Button {
                    focusedTemplate = template
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CreateScorePalette.ink)
                        Text(template.instruments.map(\.name).joined(separator: ", "))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CreateScorePalette.mutedInk)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(template.id == focusedTemplate.id ? CreateScorePalette.accentSoft : Color.clear)
            }
            .listStyle(.plain)
        }
    }
}

private struct CreateScoreStaffLines: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { _ in
                Rectangle()
                    .fill(Color.black.opacity(0.42))
                    .frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CreateScoreInstrumentationSection: View {
    @Binding var instruments: [NewScoreInstrument]
    var isPhone = false
    @State private var isInstrumentPickerPresented = false

    var body: some View {
        CreateScoreSection(number: 3, title: "Instrumentation", isPhone: isPhone) {
            VStack(spacing: 0) {
                if instruments.isEmpty {
                    Text("Choose at least one instrument.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CreateScorePalette.mutedInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 42)
                        .padding(.horizontal, 12)
                } else {
                    ForEach(instruments) { instrument in
                        CreateScoreInstrumentRow(instrument: instrument)
                        if instrument.id != instruments.last?.id {
                            Rectangle()
                                .fill(CreateScorePalette.divider)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(CreateScorePalette.cardBorder, lineWidth: 1)
            }

            Button(action: { isInstrumentPickerPresented = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Instrument")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(CreateScorePalette.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(CreateScorePalette.cardBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(isPresented: $isInstrumentPickerPresented) {
            AddInstrumentSheet(selectedInstruments: $instruments)
                .presentationBackground(.clear)
        }
    }
}

private struct CreateScoreInstrumentRow: View {
    let instrument: NewScoreInstrument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.grid.3x3.fill")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(CreateScorePalette.subtle)

            CreateScoreClef(clef: instrument.clef, size: 24)
                .frame(width: 30, height: 34)

            Text(instrument.name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CreateScorePalette.ink)

            Spacer()

            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CreateScorePalette.mutedInk)
        }
        .frame(height: 42)
        .padding(.horizontal, 12)
    }
}

struct AddInstrumentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedInstruments: [NewScoreInstrument]
    @Binding var currentInstruments: [NewScoreInstrument]
    let showsCurrentInstruments: Bool
    var commitAction: ([NewScoreInstrument]) -> Void
    var addCurrentInstrumentAction: (NewScoreInstrument) -> Void
    var removeCurrentInstrumentAction: (Int, NewScoreInstrument) -> Void
    var moveCurrentInstrumentAction: (Int, Int) -> Void
    @State private var selectedGenre: NewScoreInstrumentGenre = .common
    @State private var selectedCategory: NewScoreInstrumentCategory = .all
    @State private var searchText = ""
    @State private var focusedInstrument: NewScoreInstrument = NewScoreInstrumentCatalog.importantInstruments.first!
    @State private var removalCandidate: NewScoreInstrument?
    @State private var draggedInstrumentID: String?
    @State private var draggedInstrumentOriginalIndex: Int?

    init(selectedInstruments: Binding<[NewScoreInstrument]>,
         currentInstruments: Binding<[NewScoreInstrument]> = .constant([]),
         showsCurrentInstruments: Bool = false,
         commitAction: @escaping ([NewScoreInstrument]) -> Void = { _ in },
         addCurrentInstrumentAction: @escaping (NewScoreInstrument) -> Void = { _ in },
         removeCurrentInstrumentAction: @escaping (Int, NewScoreInstrument) -> Void = { _, _ in },
         moveCurrentInstrumentAction: @escaping (Int, Int) -> Void = { _, _ in })
    {
        _selectedInstruments = selectedInstruments
        _currentInstruments = currentInstruments
        self.showsCurrentInstruments = showsCurrentInstruments
        self.commitAction = commitAction
        self.addCurrentInstrumentAction = addCurrentInstrumentAction
        self.removeCurrentInstrumentAction = removeCurrentInstrumentAction
        self.moveCurrentInstrumentAction = moveCurrentInstrumentAction
    }

    private var visibleInstruments: [NewScoreInstrument] {
        let category = visibleCategories.contains(selectedCategory) ? selectedCategory : .all
        return NewScoreInstrumentCatalog.instruments(for: selectedGenre, category: category, matching: searchText)
    }

    private var visibleCategories: [NewScoreInstrumentCategory] {
        let matchingInstruments = NewScoreInstrumentCatalog.instruments(for: selectedGenre, category: .all, matching: searchText)
        let categories = Set(matchingInstruments.map(\.category))
        return NewScoreInstrumentCategory.allCases.filter { category in
            category == .all || categories.contains(category)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let isPhone = UIDevice.current.userInterfaceIdiom == .phone
            let modalWidth = min(max(geometry.size.width - 64, 680), 940)
            let modalHeight = min(max(geometry.size.height - 170, 560), 760)
            let layout = AddInstrumentSheetLayout(width: modalWidth)

            ZStack {
                if !isPhone {
                    Color.black.opacity(0.24)
                        .ignoresSafeArea()
                }

                if isPhone {
                    VStack(spacing: 0) {
                        header
                        phoneInstrumentPicker
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                } else {
                    VStack(spacing: 0) {
                        header

                        searchField
                            .padding(.horizontal, layout.outerPadding)
                            .padding(.bottom, 12)

                        HStack(spacing: 0) {
                            genreList
                                .frame(width: layout.genreWidth)
                            Divider()
                            categoryList
                                .frame(width: layout.categoryWidth)
                            Divider()
                            instrumentList
                                .frame(width: layout.instrumentWidth)
                            Divider()
                            selectedPanel
                                .frame(width: layout.selectedWidth)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(width: modalWidth, height: modalHeight)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 28, x: 0, y: 14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.clear)
        .confirmationDialog(
            "Remove Instrument?",
            isPresented: Binding(
                get: { removalCandidate != nil },
                set: { if !$0 { removalCandidate = nil } }
            ),
            titleVisibility: .visible,
            presenting: removalCandidate
        ) { instrument in
            Button("Remove \(instrument.name)", role: .destructive) {
                removeConfirmed(instrument)
            }
            Button("Cancel", role: .cancel) {
                removalCandidate = nil
            }
        } message: { instrument in
            Text("This removes \(instrument.name) and its music from the score.")
        }
    }

    private var isPhoneInterface: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var header: some View {
        HStack {
            Button(showsCurrentInstruments ? "Close" : "Cancel") { dismiss() }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CreateScorePalette.accent)
                .frame(minWidth: isPhoneInterface ? 58 : 104, alignment: .leading)

            Spacer()

            Text(showsCurrentInstruments ? "Add/Remove Instruments" : "Add Instruments")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CreateScorePalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Button(showsCurrentInstruments ? "Done" : "Add \(selectedInstruments.count) Instrument\(selectedInstruments.count == 1 ? "" : "s")") {
                commitAction(selectedInstruments)
                dismiss()
            }
            .font(.system(size: isPhoneInterface ? 13 : 15, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, isPhoneInterface ? 8 : 14)
            .frame(minWidth: isPhoneInterface ? 76 : 104, minHeight: 34)
            .background(CreateScorePalette.accent, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(!showsCurrentInstruments && selectedInstruments.isEmpty ? 0.45 : 1)
            .disabled(!showsCurrentInstruments && selectedInstruments.isEmpty)
        }
        .padding(.horizontal, isPhoneInterface ? 14 : 22)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CreateScorePalette.subtle)
            TextField("Search instruments", text: $searchText)
                .textFieldStyle(.plain)
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var phoneInstrumentPicker: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(CreateScorePalette.subtle)
                    .font(.system(size: 16, weight: .medium))
                TextField("Search instruments…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .regular))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(CreateScorePalette.subtle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            // Genre pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NewScoreInstrumentGenre.allCases) { genre in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedGenre = genre
                                selectedCategory = .all
                            }
                        } label: {
                            Text(genre.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(genre == selectedGenre ? .white : CreateScorePalette.ink)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(
                                    genre == selectedGenre
                                        ? CreateScorePalette.accent
                                        : Color(.secondarySystemFill),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.bottom, 8)

            // Category pills (hidden when searching)
            if searchText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(visibleCategories) { category in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedCategory = category
                                }
                            } label: {
                                Text(category.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(
                                        category == selectedCategory
                                            ? CreateScorePalette.accent
                                            : CreateScorePalette.mutedInk
                                    )
                                    .padding(.horizontal, 11)
                                    .frame(height: 30)
                                    .background(
                                        category == selectedCategory
                                            ? CreateScorePalette.accentSoft
                                            : Color.clear,
                                        in: Capsule()
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                category == selectedCategory
                                                    ? CreateScorePalette.accent.opacity(0.35)
                                                    : Color(.separator),
                                                lineWidth: 0.75
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .padding(.bottom, 6)
            }

            Divider()

            // Instrument list
            List(visibleInstruments) { instrument in
                Button {
                    if showsCurrentInstruments {
                        let inst = instrumentInstance(from: instrument)
                        currentInstruments.append(inst)
                        addCurrentInstrumentAction(inst)
                    } else {
                        toggleInstrument(instrument)
                    }
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(instrument.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(CreateScorePalette.ink)
                            Text(instrument.detailText)
                                .font(.system(size: 13))
                                .foregroundStyle(CreateScorePalette.mutedInk)
                        }
                        Spacer()
                        Image(
                            systemName: isSelected(instrument)
                                ? "checkmark.circle.fill"
                                : "plus.circle"
                        )
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            isSelected(instrument)
                                ? CreateScorePalette.accent
                                : CreateScorePalette.subtle
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    isSelected(instrument) ? CreateScorePalette.accentSoft : Color.clear
                )
            }
            .listStyle(.plain)

            // Selected instruments tray — new-score context
            if !showsCurrentInstruments {
                Divider()
                VStack(spacing: 0) {
                    HStack {
                        Text(
                            selectedInstruments.isEmpty
                                ? "Selected Instruments"
                                : "Selected (\(selectedInstruments.count))"
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CreateScorePalette.mutedInk)

                        Spacer()

                        if !selectedInstruments.isEmpty {
                            Button {
                                selectedInstruments.removeAll()
                            } label: {
                                Text("Clear All")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.red.opacity(0.78))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .background(Color(.secondarySystemBackground))

                    if selectedInstruments.isEmpty {
                        HStack {
                            Image(systemName: "hand.tap")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(CreateScorePalette.subtle)
                            Text("Tap an instrument above to add it")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(CreateScorePalette.subtle)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(.secondarySystemBackground))
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(selectedInstruments.enumerated()), id: \.element.id) { index, instrument in
                                    HStack(spacing: 12) {
                                        Image(systemName: "line.3.horizontal")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(CreateScorePalette.subtle)
                                            .frame(width: 20, alignment: .center)

                                        CreateScoreClef(clef: instrument.clef, size: 20)
                                            .frame(width: 24, height: 28)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(instrument.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(CreateScorePalette.ink)
                                            Text(instrument.detailText)
                                                .font(.system(size: 12))
                                                .foregroundStyle(CreateScorePalette.mutedInk)
                                        }

                                        Spacer()

                                        Button {
                                            removeInstrument(instrument)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 20, weight: .medium))
                                                .foregroundStyle(Color(.tertiaryLabel))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 52)
                                    .background(Color(.secondarySystemBackground))
                                    .contentShape(Rectangle())
                                    .onDrag {
                                        draggedInstrumentID = instrument.id
                                        draggedInstrumentOriginalIndex = index
                                        return NSItemProvider(object: instrument.id as NSString)
                                    }
                                    .onDrop(
                                        of: [UTType.plainText],
                                        delegate: InstrumentReorderDropDelegate(
                                            instrument: instrument,
                                            instruments: $selectedInstruments,
                                            draggedInstrumentID: $draggedInstrumentID,
                                            draggedOriginalIndex: $draggedInstrumentOriginalIndex,
                                            didDrop: nil
                                        )
                                    )

                                    if instrument.id != selectedInstruments.last?.id {
                                        Divider()
                                            .padding(.leading, 72)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: min(CGFloat(selectedInstruments.count) * 53, 160))
                        .background(Color(.secondarySystemBackground))
                    }
                }
                .background(Color(.secondarySystemBackground))
            }

            // "In Score" section — shows current instruments when in reader context
            if showsCurrentInstruments && !currentInstruments.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    HStack {
                        Text("In Score (\(currentInstruments.count))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CreateScorePalette.mutedInk)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(currentInstruments.enumerated()), id: \.element.id) { index, instrument in
                                HStack(spacing: 6) {
                                    Text(instrument.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(CreateScorePalette.ink)
                                        .lineLimit(1)
                                    Button {
                                        if currentInstruments.count > 1 {
                                            removalCandidate = instrument
                                        }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(
                                                currentInstruments.count > 1
                                                    ? CreateScorePalette.mutedInk
                                                    : CreateScorePalette.subtle
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(currentInstruments.count <= 1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
                .background(Color(.secondarySystemBackground))
            }
        }
    }

    private var genreList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(NewScoreInstrumentGenre.allCases) { genre in
                    Button {
                        selectedGenre = genre
                        selectedCategory = .all
                    } label: {
                        HStack {
                            Text(genre.rawValue)
                                .lineLimit(1)
                                .minimumScaleFactor(0.84)
                            Spacer()
                        }
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(CreateScorePalette.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(genre == selectedGenre ? Color.blue.opacity(0.16) : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(red: 0.82, green: 0.86, blue: 0.91))
    }

    private var categoryList: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(visibleCategories) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 0) {
                            Text(category.rawValue)
                            Spacer()
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(category == selectedCategory ? CreateScorePalette.accent : CreateScorePalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(category == selectedCategory ? CreateScorePalette.accentSoft : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
    }

    private var instrumentList: some View {
        List(visibleInstruments) { instrument in
            Button {
                focusedInstrument = instrument
                toggleInstrument(instrument)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(instrument.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CreateScorePalette.ink)
                        Text(instrument.detailText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CreateScorePalette.mutedInk)
                    }
                    Spacer()
                    Image(systemName: isSelected(instrument) ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSelected(instrument) ? CreateScorePalette.accent : CreateScorePalette.subtle)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(isSelected(instrument) ? CreateScorePalette.accentSoft : Color.clear)
        }
        .listStyle(.plain)
    }

    private var selectedPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(showsCurrentInstruments ? "In Score (\(currentInstruments.count))" : "Selected (\(selectedInstruments.count))")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CreateScorePalette.ink)

            if showsCurrentInstruments {
                currentInstrumentList
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(selectedInstruments.enumerated()), id: \.element.id) { index, instrument in
                        selectedInstrumentRow(instrument)
                            .onDrag {
                                draggedInstrumentID = instrument.id
                                draggedInstrumentOriginalIndex = index
                                return NSItemProvider(object: instrument.id as NSString)
                            }
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: InstrumentReorderDropDelegate(
                                    instrument: instrument,
                                    instruments: $selectedInstruments,
                                    draggedInstrumentID: $draggedInstrumentID,
                                    draggedOriginalIndex: $draggedInstrumentOriginalIndex,
                                    didDrop: nil
                                )
                            )
                        if instrument.id != selectedInstruments.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(CreateScorePalette.cardBorder, lineWidth: 1)
                }
            }

            Spacer(minLength: 12)

            instrumentDetailCard(focusedInstrument)
        }
        .padding(16)
        .background(Color(.systemGroupedBackground))
    }

    private var currentInstrumentList: some View {
        ScrollView {
            VStack(spacing: 0) {
            ForEach(Array(currentInstruments.enumerated()), id: \.element.id) { index, instrument in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CreateScorePalette.subtle)
                    Text(instrument.name)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button {
                        removalCandidate = instrument
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentInstruments.count <= 1)
                    .opacity(currentInstruments.count <= 1 ? 0.35 : 1)
                }
                .frame(height: 42)
                .padding(.horizontal, 10)
                .background(Color.white)
                .onDrag {
                    draggedInstrumentID = instrument.id
                    draggedInstrumentOriginalIndex = index
                    return NSItemProvider(object: instrument.id as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: InstrumentReorderDropDelegate(
                        instrument: instrument,
                        instruments: $currentInstruments,
                        draggedInstrumentID: $draggedInstrumentID,
                        draggedOriginalIndex: $draggedInstrumentOriginalIndex,
                        didDrop: moveCurrentInstrumentAction
                    )
                )

                if instrument.id != currentInstruments.last?.id {
                    Divider()
                }
            }
            }
        }
        .frame(minHeight: 160, maxHeight: 260)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CreateScorePalette.cardBorder, lineWidth: 1)
        }
    }

    private func selectedInstrumentRow(_ instrument: NewScoreInstrument) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CreateScorePalette.subtle)
            Text(instrument.name)
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Button {
                removeInstrument(instrument)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CreateScorePalette.subtle)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 42)
    }

    private func instrumentDetailCard(_ instrument: NewScoreInstrument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(instrument.name)
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Image(systemName: "star")
                    .foregroundStyle(CreateScorePalette.subtle)
            }
            detailRow("Category", instrument.category.rawValue)
            detailRow("Staff", instrument.clef.instrumentLabel)
            detailRow("Transposition", instrument.transposition)
            detailRow("Playback", instrument.playbackName)

            VStack(alignment: .leading, spacing: 8) {
                Text(instrument.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CreateScorePalette.ink)
                CreateScoreStaffLines()
                    .overlay(alignment: .leading) {
                        Text(instrument.clef.symbol)
                            .font(.system(size: 30))
                            .offset(x: 6)
                    }
            }
            .padding(10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CreateScorePalette.cardBorder, lineWidth: 1)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CreateScorePalette.cardBorder, lineWidth: 1)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(CreateScorePalette.ink)
            Spacer()
            Text(value)
                .foregroundStyle(CreateScorePalette.mutedInk)
        }
        .font(.system(size: 14, weight: .medium))
    }

    private func isSelected(_ instrument: NewScoreInstrument) -> Bool {
        if showsCurrentInstruments {
            return false
        }
        return selectedInstruments.contains { $0.instrumentID == instrument.instrumentID && $0.name == instrument.name }
    }

    private func toggleInstrument(_ instrument: NewScoreInstrument) {
        if showsCurrentInstruments {
            let instrumentToAdd = instrumentInstance(from: instrument)
            currentInstruments.append(instrumentToAdd)
            focusedInstrument = instrumentToAdd
            addCurrentInstrumentAction(instrumentToAdd)
            return
        }

        if let index = selectedInstruments.firstIndex(where: { $0.instrumentID == instrument.instrumentID && $0.name == instrument.name }) {
            selectedInstruments.remove(at: index)
        } else {
            selectedInstruments.append(instrumentInstance(from: instrument))
        }
    }

    private func instrumentInstance(from instrument: NewScoreInstrument) -> NewScoreInstrument {
        NewScoreInstrument(
            instanceID: "\(instrument.instrumentID)-\(UUID().uuidString)",
            instrumentID: instrument.instrumentID,
            name: instrument.name,
            category: instrument.category,
            clef: instrument.clef,
            transposition: instrument.transposition,
            playbackName: instrument.playbackName,
            genres: instrument.genres
        )
    }

    private func removeInstrument(_ instrument: NewScoreInstrument) {
        selectedInstruments.removeAll { $0.id == instrument.id }
    }

    private func removeConfirmed(_ instrument: NewScoreInstrument) {
        guard let index = currentInstruments.firstIndex(where: { $0.id == instrument.id }) else {
            removalCandidate = nil
            return
        }
        currentInstruments.remove(at: index)
        removeCurrentInstrumentAction(index, instrument)
        removalCandidate = nil
    }
}

private struct InstrumentReorderDropDelegate: DropDelegate {
    let instrument: NewScoreInstrument
    @Binding var instruments: [NewScoreInstrument]
    @Binding var draggedInstrumentID: String?
    @Binding var draggedOriginalIndex: Int?
    let didDrop: ((Int, Int) -> Void)?

    func dropEntered(info: DropInfo) {
        guard
            let draggedInstrumentID,
            draggedInstrumentID != instrument.id,
            let sourceIndex = instruments.firstIndex(where: { $0.id == draggedInstrumentID }),
            let destinationIndex = instruments.firstIndex(where: { $0.id == instrument.id })
        else {
            return
        }

        let proposedDestination = destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex
        withAnimation(.snappy(duration: 0.16)) {
            instruments.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: proposedDestination)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        if
            let draggedInstrumentID,
            let originalIndex = draggedOriginalIndex,
            let finalIndex = instruments.firstIndex(where: { $0.id == draggedInstrumentID })
        {
            let destination = finalIndex > originalIndex ? finalIndex + 1 : finalIndex
            didDrop?(originalIndex, destination)
        }
        draggedInstrumentID = nil
        draggedOriginalIndex = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct AddInstrumentSheetLayout {
    let outerPadding: CGFloat
    let genreWidth: CGFloat
    let categoryWidth: CGFloat
    let selectedWidth: CGFloat
    let instrumentWidth: CGFloat

    init(width: CGFloat) {
        let compact = width < 720
        outerPadding = width >= 820 ? 22 : 16
        genreWidth = width >= 820 ? 152 : (compact ? 128 : 140)
        categoryWidth = width >= 820 ? 172 : (compact ? 146 : 158)
        selectedWidth = width >= 820 ? 250 : (compact ? 196 : 220)
        let dividers: CGFloat = 3
        let availableListWidth = width - genreWidth - categoryWidth - selectedWidth - dividers
        instrumentWidth = max(compact ? 180 : 250, availableListWidth)
    }
}

private struct CreateScoreClef: View {
    let clef: ScorePartClef
    let size: CGFloat

    var body: some View {
        Text(clef.symbol)
            .font(.system(size: size, weight: .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: size * 1.35, height: size * 1.45)
    }
}

private struct CreateScoreMusicSettingsSection: View {
    @Binding var draft: NewScoreDraft
    var isPhone = false
    @State private var isKeySignaturePresented = false
    @State private var isTimeSignaturePresented = false

    private var columns: [GridItem] {
        if isPhone {
            return [GridItem(.flexible(), spacing: 10)]
        }
        return [GridItem(.adaptive(minimum: 150), spacing: 14)]
    }

    var body: some View {
        CreateScoreSection(number: 4, title: "Music Settings", isPhone: isPhone, collapsible: isPhone, startsCollapsed: isPhone) {
            LazyVGrid(columns: columns, spacing: isPhone ? 10 : 14) {
                CreateScorePickerField(title: "Key Signature") {
                    Button(action: { isKeySignaturePresented = true }) {
                        HStack {
                            Text(draft.keySignature.rawValue)
                                .foregroundStyle(CreateScorePalette.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CreateScorePalette.mutedInk)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                CreateScorePickerField(title: "Time Signature") {
                    Button(action: { isTimeSignaturePresented = true }) {
                        HStack {
                            Text(draft.timeSignature.rawValue)
                                .foregroundStyle(CreateScorePalette.ink)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CreateScorePalette.mutedInk)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                CreateScorePickerField(title: "Tempo") {
                    Stepper(value: $draft.tempo, in: 30...240, step: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "music.note")
                            Text("\(draft.tempo)")
                        }
                    }
                }

                CreateScorePickerField(title: "Measures") {
                    Stepper(value: $draft.measureCount, in: 1...256, step: 1) {
                        Text("\(draft.measureCount)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .sheet(isPresented: $isKeySignaturePresented) {
            ScoreReaderKeySignatureSheet(
                currentKeyValue: draft.keySignature.keyValue,
                isBusy: false,
                commitAction: { value, _ in
                    draft.keySignature = NewScoreKeySignature.from(value)
                }
            )
        }
        .sheet(isPresented: $isTimeSignaturePresented) {
            ScoreReaderTimeSignatureSheet(
                isBusy: false,
                commitAction: { value, _ in
                    draft.timeSignature = NewScoreTimeSignature.from(value)
                }
            )
        }
    }
}

private struct CreateScorePickerField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CreateScorePalette.ink)

            content
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 40)
                .frame(maxWidth: .infinity)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(CreateScorePalette.cardBorder, lineWidth: 1)
                }
        }
    }
}

private struct CreateScoreOptionsSection: View {
    @Binding var draft: NewScoreDraft
    var isPhone = false
    @State private var isPickupMeasurePresented = false
    @State private var pickupSheetOpenedFromDisabled = false
    @State private var pickupSelectionCommitted = false

    private var pickupEnabled: Binding<Bool> {
        Binding(
            get: { draft.hasPickupMeasure },
            set: { newValue in
                let wasEnabled = draft.hasPickupMeasure
                draft.hasPickupMeasure = newValue
                if newValue {
                    pickupSheetOpenedFromDisabled = !wasEnabled
                    pickupSelectionCommitted = false
                    isPickupMeasurePresented = true
                }
            }
        )
    }

    private var pickupContext: ScorePickupEditorContext {
        ScorePickupEditorContext(
            isExistingPickup: draft.hasPickupMeasure && !pickupSheetOpenedFromDisabled,
            createsNewMeasure: false,
            nominalNumerator: draft.timeSignature.numerator,
            nominalDenominator: draft.timeSignature.denominator,
            currentNumerator: draft.pickupNumerator,
            currentDenominator: draft.pickupDenominator
        )
    }

    var body: some View {
        CreateScoreSection(number: 5, title: "Options", isPhone: isPhone, collapsible: isPhone, startsCollapsed: isPhone) {
            VStack(spacing: 12) {
                Toggle(isOn: pickupEnabled) {
                    CreateScoreOptionLabel(title: "Pickup Measure", detail: "Start with an incomplete measure.", isPhone: isPhone)
                }
                if draft.hasPickupMeasure {
                    CreateScorePickupMeasureSummary(
                        numerator: draft.pickupNumerator,
                        denominator: draft.pickupDenominator,
                        editAction: {
                            pickupSheetOpenedFromDisabled = false
                            pickupSelectionCommitted = false
                            isPickupMeasurePresented = true
                        }
                    )
                }
            }
            .toggleStyle(.switch)
        }
        .sheet(isPresented: $isPickupMeasurePresented) {
            ScoreReaderPickupEditorSheet(
                context: pickupContext,
                isBusy: false,
                applyAction: { numerator, denominator in
                    draft.pickupNumerator = numerator
                    draft.pickupDenominator = denominator
                    draft.hasPickupMeasure = true
                    pickupSelectionCommitted = true
                },
                removeAction: {
                    draft.hasPickupMeasure = false
                    pickupSelectionCommitted = true
                },
                cancelAction: {
                    if pickupSheetOpenedFromDisabled && !pickupSelectionCommitted {
                        draft.hasPickupMeasure = false
                    }
                }
            )
            .onDisappear {
                if pickupSheetOpenedFromDisabled && !pickupSelectionCommitted {
                    draft.hasPickupMeasure = false
                }
                pickupSheetOpenedFromDisabled = false
            }
        }
    }
}

private struct CreateScorePickupMeasureSummary: View {
    let numerator: Int
    let denominator: Int
    let editAction: () -> Void

    var body: some View {
        Button(action: editAction) {
            HStack(spacing: 12) {
                Text("Pickup Measure")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CreateScorePalette.ink)
                Spacer()
                Text("\(numerator)/\(denominator)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CreateScorePalette.accent)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CreateScorePalette.mutedInk)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(CreateScorePalette.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CreateScoreOptionLabel: View {
    let title: String
    let detail: String
    var isPhone = false

    var body: some View {
        Group {
            if isPhone {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CreateScorePalette.ink)
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(CreateScorePalette.mutedInk)
                        .lineLimit(2)
                }
            } else {
                HStack(spacing: 18) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CreateScorePalette.ink)
                .frame(width: 150, alignment: .leading)

            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CreateScorePalette.mutedInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

private struct CreateScoreBottomBar: View {
    let isCreating: Bool
    let canCreate: Bool
    var isPhone = false
    let cancelAction: () -> Void
    let createAction: () -> Void

    var body: some View {
        HStack(spacing: isPhone ? 10 : 14) {
            if !isPhone {
                Spacer()
            }

            Button(action: cancelAction) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CreateScorePalette.ink)
                    .frame(width: isPhone ? nil : 160, height: 44)
                    .frame(maxWidth: isPhone ? .infinity : nil)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(CreateScorePalette.cardBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(isCreating)

            Button(action: createAction) {
                HStack(spacing: 8) {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isCreating ? "Creating..." : "Create Score")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: isPhone ? nil : 220, height: 44)
                .frame(maxWidth: isPhone ? .infinity : nil)
                .background(canCreate ? CreateScorePalette.accent : CreateScorePalette.subtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isCreating || !canCreate)
        }
        .padding(.horizontal, isPhone ? 16 : 28)
        .padding(.top, 12)
        .padding(.bottom, isPhone ? 24 : 20)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CreateScorePalette.divider)
                .frame(height: 1)
        }
    }
}

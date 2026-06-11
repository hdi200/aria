//
//  DocumentRowView.swift
//  MuseReaderiOS
//
//  Created by Codex on 4/13/26.
//

import SwiftUI
import UIKit

struct DocumentRowView: View {
    let recent: ReaderRecentDocument
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            preview

            VStack(alignment: .leading, spacing: 6) {
                Text(recent.primaryTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.13, blue: 0.09))
                    .lineLimit(2)

                if let secondaryLine = recent.secondaryLine {
                    Text(secondaryLine)
                        .font(.subheadline)
                        .foregroundStyle(Color(red: 0.40, green: 0.31, blue: 0.22))
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Label(recent.format.rawValue.uppercased(), systemImage: "music.note.list")
                    Text(relativeDateText)
                    if let museScoreVersion = recent.museScoreVersion?.trimmedToNil {
                        Text("MuseScore \(museScoreVersion)")
                    }
                }
                .font(.caption)
                .foregroundStyle(Color(red: 0.46, green: 0.39, blue: 0.31))
            }

            Spacer(minLength: 12)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color(red: 0.76, green: 0.28, blue: 0.19))
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color(red: 0.98, green: 0.94, blue: 0.88) : Color.white.opacity(0.8))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isSelected
                    ? Color(red: 0.80, green: 0.47, blue: 0.32).opacity(0.5)
                    : Color.black.opacity(0.06),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.04), radius: 14, y: 8)
    }

    private var relativeDateText: String {
        recent.lastOpened.formatted(.relative(presentation: .named))
    }

    @ViewBuilder
    private var preview: some View {
        if let data = recent.previewImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
        }
        else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.91, green: 0.89, blue: 0.84),
                            Color(red: 0.84, green: 0.81, blue: 0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 96)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                }
                .overlay {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "music.note")
                            .font(.title3.weight(.semibold))
                        Text(recent.format == .mscz ? "MSCZ" : "MSCX")
                            .multilineTextAlignment(.center)
                            .font(.caption.weight(.bold))
                            .tracking(0.6)
                    }
                    .foregroundStyle(Color(red: 0.41, green: 0.31, blue: 0.23))
                }
        }
    }
}

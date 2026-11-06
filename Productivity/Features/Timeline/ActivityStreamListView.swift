import SwiftUI

struct ActivityStreamListView: View {
    let segments: [ActivitySegment]
    let onDelete: (ActivitySegment) async -> Void

    @State private var segmentPendingDeletion: ActivitySegment?
    @State private var isShowingAllStreams = false

    private let previewLimit = 10

    private var hiddenStreamCount: Int {
        max(0, segments.count - previewLimit)
    }

    private var sortedSegments: [ActivitySegment] {
        segments.sorted(by: isMoreRecent)
    }

    var body: some View {
        let visibleSegments = isShowingAllStreams && hiddenStreamCount > 0 ? sortedSegments : recentPreviewSegments

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Captured Streams", systemImage: "rectangle.stack")
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.textPrimary)

                Spacer()

                if hiddenStreamCount > 0 {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            isShowingAllStreams.toggle()
                        }
                    } label: {
                        Label(
                            isShowingAllStreams ? "Show Top 10" : "View All",
                            systemImage: isShowingAllStreams ? "chevron.up" : "list.bullet"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(isShowingAllStreams ? "Collapse captured streams" : hiddenStreamHelpText)
                }
            }

            if segments.isEmpty {
                EmptyActivityStreamRow()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(visibleSegments.enumerated()), id: \.element.id) { index, segment in
                        ActivityStreamRowView(streamNumber: index + 1, segment: segment) {
                            segmentPendingDeletion = segment
                        }
                    }
                }
            }

            if hiddenStreamCount > 0 && !isShowingAllStreams {
                Text(hiddenStreamCount == 1 ? "1 older stream hidden" : "\(hiddenStreamCount) older streams hidden")
                    .productivityFont(.captionMedium)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
        }
        .alert("Delete captured stream?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                guard let segment = segmentPendingDeletion else { return }
                Task {
                    await onDelete(segment)
                    await MainActor.run {
                        segmentPendingDeletion = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                segmentPendingDeletion = nil
            }
        } message: {
            Text("This permanently deletes the captured stream from the local database and removes it from the activity timeline.")
        }
        .onChange(of: hiddenStreamCount) { _, newValue in
            if newValue == 0 {
                isShowingAllStreams = false
            }
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { segmentPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    segmentPendingDeletion = nil
                }
            }
        )
    }

    private var recentPreviewSegments: [ActivitySegment] {
        guard segments.count > previewLimit else {
            return sortedSegments
        }

        var recentSegments: [ActivitySegment] = []
        recentSegments.reserveCapacity(previewLimit)

        for segment in segments {
            let insertionIndex = recentSegments.firstIndex { isMoreRecent(segment, than: $0) } ?? recentSegments.endIndex
            if insertionIndex < previewLimit {
                recentSegments.insert(segment, at: insertionIndex)
                if recentSegments.count > previewLimit {
                    recentSegments.removeLast()
                }
            } else if recentSegments.count < previewLimit {
                recentSegments.append(segment)
            }
        }

        return recentSegments
    }

    private var hiddenStreamHelpText: String {
        hiddenStreamCount == 1 ? "Show 1 more captured stream" : "Show \(hiddenStreamCount) more captured streams"
    }

    private func isMoreRecent(_ lhs: ActivitySegment, than rhs: ActivitySegment) -> Bool {
        if lhs.endDate == rhs.endDate {
            if lhs.startDate == rhs.startDate {
                return lhs.id.uuidString < rhs.id.uuidString
            }

            return lhs.startDate > rhs.startDate
        }

        return lhs.endDate > rhs.endDate
    }
}

private struct EmptyActivityStreamRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("No captured streams yet")
                .productivityFont(.bodyStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)
            Text("Tracked activity and manual events will appear here once they are saved locally.")
                .productivityFont(.caption)
                .foregroundStyle(ProductivityTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct ActivityStreamRowView: View {
    let streamNumber: Int
    let segment: ActivitySegment
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(label.tint.opacity(0.18))
                .overlay {
                    Image(systemName: iconName)
                        .foregroundStyle(label.tint)
                }
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Stream \(streamNumber)")
                        .productivityFont(.bodyStrong)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                    Text(displayName)
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                        .lineLimit(1)
                }

                Text(segment.displayContext)
                    .productivityFont(.caption)
                    .foregroundStyle(segment.userDescription == nil ? ProductivityTheme.textSecondary.opacity(0.62) : ProductivityTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(label.title)
                .productivityFont(.captionMedium)
                .foregroundStyle(label.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(label.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .lineLimit(1)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete captured stream")

            Text(DurationFormatting.abbreviated(segment.duration))
                .productivityFont(.captionMonospaced)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .frame(width: 54, alignment: .trailing)
        }
        .padding(12)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
    }

    private var label: ActivityLabel {
        segment.label
    }

    private var iconName: String {
        if segment.bundleIdentifier == "productivity.lifecycle.sleep" {
            return "moon.zzz"
        }

        return label.systemImage
    }

    private var displayName: String {
        segment.isLifecycleContext ? segment.title : segment.appName
    }
}

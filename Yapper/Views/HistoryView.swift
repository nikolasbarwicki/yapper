import SwiftUI

// MARK: - History View

/// Displays transcript history with search, card layout, and actions.
struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText: String = ""
    @State private var showClearConfirmation: Bool = false

    /// Whether this view is displayed in a standalone window (vs embedded in settings)
    let isStandalone: Bool

    init(isStandalone: Bool = false) {
        self.isStandalone = isStandalone
    }

    /// Reference to the history manager (observable)
    private var historyManager: TranscriptHistoryManager {
        TranscriptHistoryManager.shared
    }

    /// Filtered records based on search
    private var filteredRecords: [TranscriptRecord] {
        if searchText.isEmpty {
            return historyManager.allRecords
        }
        return historyManager.search(query: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Retention picker (only in standalone mode)
            if isStandalone {
                retentionHeader
                Divider()
            }

            // Search bar and actions header
            headerView

            Divider()

            // Content
            if historyManager.recordCount == 0 {
                emptyStateView
            } else if filteredRecords.isEmpty {
                noResultsView
            } else {
                transcriptListView
            }
        }
        .alert("Clear All History", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                historyManager.clearAllHistory()
            }
        } message: {
            Text("This will permanently delete all \(historyManager.recordCount) transcript(s). This action cannot be undone.")
        }
    }

    // MARK: - Retention Header

    private var retentionHeader: some View {
        HStack {
            Text("Keep transcripts for")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("", selection: Bindable(appState).historyRetentionDays) {
                Text("30 days").tag(30)
                Text("60 days").tag(60)
                Text("90 days").tag(90)
                Text("180 days").tag(180)
                Text("1 year").tag(365)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .onChange(of: appState.historyRetentionDays) { _, newValue in
                appState.setHistoryRetentionDays(newValue)
                TranscriptHistoryManager.shared.cleanupOldRecords(retentionDays: newValue)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header View

    private var headerView: some View {
        VStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcripts...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
            )

            // Stats and clear button
            HStack {
                // Stats
                if historyManager.recordCount > 0 {
                    Text("\(historyManager.recordCount) transcript(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Text(historyManager.formattedTotalDuration + " total")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Time saved indicator
                    if historyManager.timeSaved > 0 {
                        Text("•")
                            .foregroundStyle(.tertiary)

                        Label(historyManager.formattedTimeSaved, systemImage: "clock.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                // Clear all button
                if historyManager.recordCount > 0 {
                    Button("Clear All") {
                        showClearConfirmation = true
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("No Transcripts Yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Your transcription history will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 4) {
                Text("No Results")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("No transcripts match \"\(searchText)\"")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Transcript List

    private var transcriptListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredRecords) { record in
                    TranscriptCardView(record: record)
                }
            }
            .padding()
        }
    }
}

// MARK: - Transcript Card View

/// A card displaying a single transcript with metadata and actions.
struct TranscriptCardView: View {
    let record: TranscriptRecord
    @State private var isExpanded: Bool = false
    @State private var showCopiedFeedback: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    /// Maximum characters to show in collapsed preview
    private static let previewCharacterLimit = 100

    /// Preview text (first ~100 characters)
    private var previewText: String {
        if record.text.count <= Self.previewCharacterLimit {
            return record.text
        }
        let index = record.text.index(record.text.startIndex, offsetBy: Self.previewCharacterLimit)
        return String(record.text[..<index]) + "..."
    }

    /// Whether the text is long enough to need expand/collapse
    private var isExpandable: Bool {
        record.text.count > Self.previewCharacterLimit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Date/time and metadata
            HStack(alignment: .top) {
                // Date and time
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.shortDate)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text(record.timeOnly)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Source type badge
                if record.sourceType == .file {
                    Label(record.sourceFileName ?? "File", systemImage: "doc.fill")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                        .lineLimit(1)
                } else {
                    Label("Live", systemImage: "mic.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                Spacer()

                // Metadata badges
                HStack(spacing: 8) {
                    // Duration
                    Label(record.formattedDuration, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // Character count
                    Label("\(record.characterCount)", systemImage: "character.cursor.ibeam")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Transcript text
            Text(isExpanded ? record.text : previewText)
                .font(.body)
                .lineLimit(isExpanded ? nil : 3)
                .textSelection(.enabled)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }

            // Actions
            HStack(spacing: 16) {
                // Expand/collapse
                if isExpandable {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Label(isExpanded ? "Show Less" : "Show More", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }

                Spacer()

                // Copy button
                Button {
                    copyToClipboard()
                } label: {
                    Label(showCopiedFeedback ? "Copied!" : "Copy", systemImage: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showCopiedFeedback ? .green : .blue)

                // Delete button
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .alert("Delete Transcript", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRecord()
            }
        } message: {
            Text("Are you sure you want to delete this transcript? This action cannot be undone.")
        }
    }

    // MARK: - Actions

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.text, forType: .string)

        // Show feedback
        withAnimation {
            showCopiedFeedback = true
        }

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedFeedback = false
            }
        }
    }

    private func deleteRecord() {
        withAnimation {
            TranscriptHistoryManager.shared.deleteRecord(id: record.id)
        }
    }
}

// MARK: - Preview

#Preview {
    HistoryView()
        .environment(AppState())
        .frame(width: 400, height: 500)
}

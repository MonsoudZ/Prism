import SwiftUI

struct NotesPane: View {
    @StateObject private var vm: NotesViewModel
    @State private var showingNewNoteSheet = false
    @State private var showingDeleteAlert = false
    @State private var noteToDelete: Note?
    
    init(vm: NotesViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }
    
    var body: some View {
        HSplitView {
            // Notes list
            notesList
                .frame(minWidth: 200, idealWidth: 250)
            
            // Note editor
            if let selectedNote = vm.selectedNote {
                NoteEditor(
                    note: selectedNote,
                    onUpdate: { updatedNote in
                        Task {
                            await vm.updateNote(updatedNote)
                        }
                    },
                    onDelete: {
                        noteToDelete = selectedNote
                        showingDeleteAlert = true
                    }
                )
                .frame(minWidth: 300)
            } else {
                emptySelectionView
            }
        }
        .sheet(isPresented: $showingNewNoteSheet) {
            NewNoteSheet { title, content in
                Task {
                    await vm.createNote(title: title, content: content)
                }
            }
        }
        .alert("Delete Note", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                noteToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let note = noteToDelete {
                    Task {
                        await vm.deleteNote(id: note.id)
                    }
                }
                noteToDelete = nil
            }
        } message: {
            Text("Are you sure you want to delete '\(noteToDelete?.title ?? "this note")'?")
        }
        .task {
            await vm.loadAll()
        }
    }
    
    // MARK: - Notes List
    
    private var notesList: some View {
        VStack(spacing: 0) {
            // Header
            notesListHeader
            
            Divider()
            
            // Filter/Sort bar
            filterSortBar
            
            Divider()
            
            // List content
            if vm.isLoading {
                loadingView
            } else if vm.filteredNotes.isEmpty {
                emptyNotesView
            } else {
                notesListContent
            }
        }
    }
    
    private var notesListHeader: some View {
        HStack {
            Text("Notes")
                .font(.headline)
            
            Spacer()
            
            Button {
                showingNewNoteSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help("New Note")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var filterSortBar: some View {
        HStack(spacing: 8) {
            // Filter
            Menu {
                Picker("Filter", selection: $vm.selectedFilter) {
                    ForEach(NotesFilterOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundColor(.secondary)
            }
            .frame(width: 30)
            
            // Sort
            Menu {
                Picker("Sort", selection: $vm.selectedSort) {
                    ForEach(NotesSortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .foregroundColor(.secondary)
            }
            .frame(width: 30)
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search notes...", text: $vm.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var notesListContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.filteredNotes) { note in
                    NoteRow(
                        note: note,
                        isSelected: vm.selectedNote?.id == note.id,
                        onSelect: {
                            vm.selectedNote = note
                        },
                        onTogglePin: {
                            Task {
                                await vm.togglePin(noteId: note.id)
                            }
                        }
                    )
                    .contextMenu {
                        noteContextMenu(note)
                    }
                    
                    if note.id != vm.filteredNotes.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading notes...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyNotesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(vm.searchQuery.isEmpty ? "No Notes" : "No Results")
                .font(.headline)
            
            Text(vm.searchQuery.isEmpty ?
                 "Create a note to get started" :
                 "No notes match '\(vm.searchQuery)'")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if vm.searchQuery.isEmpty {
                Button {
                    showingNewNoteSheet = true
                } label: {
                    Label("New Note", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptySelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("Select a Note")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose a note from the list to view and edit")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private func noteContextMenu(_ note: Note) -> some View {
        Button {
            Task {
                await vm.togglePin(noteId: note.id)
            }
        } label: {
            Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
        }
        
        Divider()
        
        Button(role: .destructive) {
            noteToDelete = note
            showingDeleteAlert = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Note Row

struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            
            Text(note.preview)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                if let documentId = note.documentId {
                    Label("Linked", systemImage: "link")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                if !note.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(note.tags.prefix(2), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                
                Spacer()
                
                Text(note.dateModified, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Note Editor

struct NoteEditor: View {
    @State private var editedNote: Note
    let onUpdate: (Note) -> Void
    let onDelete: () -> Void
    
    @State private var newTag = ""
    @FocusState private var titleFocused: Bool
    
    init(note: Note, onUpdate: @escaping (Note) -> Void, onDelete: @escaping () -> Void) {
        _editedNote = State(initialValue: note)
        self.onUpdate = onUpdate
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            editorHeader
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    TextField("Note Title", text: $editedNote.title)
                        .font(.title2)
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                    
                    // Tags
                    tagsSection
                    
                    // Content
                    TextEditor(text: $editedNote.content)
                        .font(.body)
                        .frame(minHeight: 200)
                }
                .padding()
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .onChange(of: editedNote.title) { _, _ in saveChanges() }
        .onChange(of: editedNote.content) { _, _ in saveChanges() }
        .onChange(of: editedNote.tags) { _, _ in saveChanges() }
        .onAppear {
            titleFocused = editedNote.title.isEmpty
        }
    }
    
    private var editorHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(editedNote.title.isEmpty ? "Untitled" : editedNote.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Text("Modified \(editedNote.dateModified, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                editedNote.isPinned.toggle()
                onUpdate(editedNote)
            } label: {
                Image(systemName: editedNote.isPinned ? "pin.fill" : "pin")
            }
            .help(editedNote.isPinned ? "Unpin" : "Pin")
            
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .help("Delete Note")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.caption)
                .foregroundColor(.secondary)
            
            FlowLayout(spacing: 6) {
                ForEach(editedNote.tags, id: \.self) { tag in
                    TagChip(
                        tag: tag,
                        onRemove: {
                            editedNote.tags.removeAll { $0 == tag }
                        }
                    )
                }
                
                // Add tag field
                HStack(spacing: 4) {
                    TextField("Add tag", text: $newTag)
                        .textFieldStyle(.plain)
                        .frame(width: 80)
                        .onSubmit {
                            addTag()
                        }
                    
                    if !newTag.isEmpty {
                        Button {
                            addTag()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
        }
    }
    
    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !editedNote.tags.contains(trimmed) else { return }
        editedNote.tags.append(trimmed)
        newTag = ""
    }
    
    private func saveChanges() {
        // Debounce saves
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            onUpdate(editedNote)
        }
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text("#\(tag)")
                .font(.caption)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.2))
        .cornerRadius(12)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                      y: bounds.minY + result.frames[index].minY),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

// MARK: - New Note Sheet

struct NewNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    let onCreate: (String, String) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("New Note")
                .font(.headline)
            
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
            
            TextEditor(text: $content)
                .font(.body)
                .frame(height: 200)
                .border(Color.secondary.opacity(0.2))
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Create") {
                    onCreate(title.isEmpty ? "Untitled Note" : title, content)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 350)
    }
}

// MARK: - Preview

#Preview {
    NotesPane(
        vm: NotesViewModel(
            repo: MockNotesRepository(
                notes: [
                    Note(title: "Sample Note 1", content: "This is a sample note with some content.", isPinned: true),
                    Note(title: "Sample Note 2", content: "Another note here.", tags: ["swift", "ios"])
                ]
            )
        )
    )
    .frame(width: 800, height: 600)
}

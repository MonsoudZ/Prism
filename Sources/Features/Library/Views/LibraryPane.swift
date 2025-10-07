import SwiftUI
import UniformTypeIdentifiers

struct LibraryPane: View {
    @StateObject private var vm: LibraryViewModel
    @State private var showingImportPicker = false
    @State private var showingDeleteAlert = false
    
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
    ]
    
    init(vm: LibraryViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar
            
            Divider()
            
            // Main content
            if vm.isLoading {
                loadingView
            } else if vm.filteredItems.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .searchable(text: $vm.searchQuery, prompt: "Search library")
        .sheet(isPresented: $showingImportPicker) {
            DocumentPicker { urls in
                Task {
                    for url in urls {
                        await vm.importDocument(from: url)
                    }
                }
            }
        }
        .alert("Delete Documents", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    await vm.deleteSelected()
                }
            }
        } message: {
            Text("Are you sure you want to delete \(vm.selectedItems.count) document(s)?")
        }
        .task {
            await vm.load()
        }
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack {
            // View style toggle
            Picker("View Style", selection: $vm.viewStyle) {
                ForEach(LibraryViewStyle.allCases, id: \.self) { style in
                    Image(systemName: style == .grid ? "square.grid.2x2" : "list.bullet")
                        .tag(style)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            
            Spacer()
            
            // Filter menu
            Menu {
                Picker("Filter", selection: $vm.selectedFilter) {
                    ForEach(LibraryFilterOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Label(vm.selectedFilter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
            }
            
            // Sort menu
            Menu {
                Picker("Sort", selection: $vm.selectedSort) {
                    ForEach(LibrarySortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Label(vm.selectedSort.rawValue, systemImage: "arrow.up.arrow.down")
            }
            
            Spacer()
            
            // Actions
            if vm.isInSelectionMode {
                Button("Deselect All") {
                    vm.deselectAll()
                }
                
                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button {
                    showingImportPicker = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Content Views
    
    private var contentView: some View {
        ScrollView {
            Group {
                if vm.viewStyle == .grid {
                    gridView
                } else {
                    listView
                }
            }
            .padding()
        }
    }
    
    private var gridView: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(vm.filteredItems) { item in
                LibraryItemCard(
                    item: item,
                    isSelected: vm.selectedItems.contains(item.id),
                    onTap: {
                        handleItemTap(item)
                    },
                    onTogglePin: {
                        Task {
                            await vm.togglePin(itemId: item.id)
                        }
                    }
                )
                .contextMenu {
                    itemContextMenu(item)
                }
            }
        }
    }
    
    private var listView: some View {
        LazyVStack(spacing: 0) {
            ForEach(vm.filteredItems) { item in
                LibraryItemRow(
                    item: item,
                    isSelected: vm.selectedItems.contains(item.id),
                    onTap: {
                        handleItemTap(item)
                    },
                    onTogglePin: {
                        Task {
                            await vm.togglePin(itemId: item.id)
                        }
                    }
                )
                .contextMenu {
                    itemContextMenu(item)
                }
                
                if item.id != vm.filteredItems.last?.id {
                    Divider()
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading library...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text(vm.searchQuery.isEmpty ? "No Documents" : "No Results")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(vm.searchQuery.isEmpty ?
                 "Import PDFs to get started" :
                 "No documents match '\(vm.searchQuery)'")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if vm.searchQuery.isEmpty {
                Button {
                    showingImportPicker = true
                } label: {
                    Label("Import Documents", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
    private func handleItemTap(_ item: LibraryItem) {
        if vm.isInSelectionMode {
            vm.toggleSelection(itemId: item.id)
        } else {
            // TODO: Open document in reader
            NotificationCenter.default.post(
                name: .openPDF,
                object: item
            )
        }
    }
    
    @ViewBuilder
    private func itemContextMenu(_ item: LibraryItem) -> some View {
        Button {
            Task {
                await vm.togglePin(itemId: item.id)
            }
        } label: {
            Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
        }
        
        Divider()
        
        Button {
            vm.toggleSelection(itemId: item.id)
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
        
        Divider()
        
        Button(role: .destructive) {
            Task {
                await vm.delete(itemId: item.id)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Library Item Card (Grid)

struct LibraryItemCard: View {
    let item: LibraryItem
    let isSelected: Bool
    let onTap: () -> Void
    let onTogglePin: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            thumbnailView
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Text("\(item.pageCount) pages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .padding(6)
            }
        }
        .overlay(alignment: .topLeading) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .padding(6)
            }
        }
        .onTapGesture(perform: onTap)
    }
    
    private var thumbnailView: some View {
        ZStack {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .aspectRatio(3/4, contentMode: .fit)
            
            Image(systemName: "doc.text.fill")
                .font(.largeTitle)
                .foregroundColor(.secondary)
        }
        .cornerRadius(6)
        .padding(8)
    }
}

// MARK: - Library Item Row (List)

struct LibraryItemRow: View {
    let item: LibraryItem
    let isSelected: Bool
    let onTap: () -> Void
    let onTogglePin: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 40, height: 54)
                    .cornerRadius(4)
                
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.secondary)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.body)
                    .fontWeight(.medium)
                
                HStack(spacing: 4) {
                    Text("\(item.pageCount) pages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let lastOpened = item.lastOpened {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(lastOpened, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Pin indicator
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            
            // Selection indicator
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Document Picker

struct DocumentPicker: NSViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    
    func makeNSViewController(context: Context) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        return panel
    }
    
    func updateNSViewController(_ nsViewController: NSOpenPanel, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator {
        let onPick: ([URL]) -> Void
        
        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }
    }
}

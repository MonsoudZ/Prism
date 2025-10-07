import Foundation
import PDFKit
import Combine

// MARK: - PDF View Model

@MainActor
final class PDFViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var loadingState: PDFLoadingState = .idle
    @Published private(set) var currentDocument: PDFDocument?
    @Published private(set) var documentInfo: PDFDocumentInfo?
    @Published private(set) var currentPageInfo: PDFPageInfo?
    @Published var viewState: PDFViewState = .initial
    @Published private(set) var thumbnails: [PDFThumbnail] = []
    @Published private(set) var annotations: [AnnotationOverlay] = []
    @Published private(set) var error: Error?
    
    // MARK: - Dependencies
    
    private let pdfService: PDFServiceProtocol
    private let persistenceService: PersistenceServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Private State
    
    private var documentId: UUID?
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init(pdfService: PDFServiceProtocol, persistenceService: PersistenceServiceProtocol) {
        self.pdfService = pdfService
        self.persistenceService = persistenceService
        setupObservers()
    }
    
    private func setupObservers() {
        // Auto-save view state changes
        $viewState
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] state in
                self?.saveViewState(state)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Document Loading
    
    func loadDocument(documentId: UUID, url: URL) async {
        self.documentId = documentId
        loadingState = .loading(progress: 0.0)
        
        do {
            // Load PDF document
            let document = try await pdfService.loadDocument(from: url)
            
            loadingState = .loading(progress: 0.3)
            
            // Extract document info
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
            let info = pdfService.extractInfo(from: document, fileSize: fileSize)
            
            loadingState = .loading(progress: 0.5)
            
            // Load persisted annotations
            let persistedAnnotations = try await persistenceService.loadAnnotations(for: documentId)
            let annotationOverlays = persistedAnnotations.map { AnnotationOverlay(from: $0) }
            
            loadingState = .loading(progress: 0.7)
            
            // Load saved view state
            if let savedDocument = try? await persistenceService.loadDocument(id: documentId) {
                viewState.currentPage = savedDocument.currentPage
            }
            
            loadingState = .loading(progress: 0.9)
            
            // Update state
            self.currentDocument = document
            self.documentInfo = info
            self.annotations = annotationOverlays
            
            // Update current page info
            if let page = document.page(at: viewState.currentPage) {
                self.currentPageInfo = pdfService.extractPageInfo(from: page, pageNumber: viewState.currentPage)
            }
            
            loadingState = .loaded(document)
            
            // Generate thumbnails in background
            Task {
                await generateThumbnails()
            }
            
        } catch {
            self.error = error
            loadingState = .failed(error.localizedDescription)
        }
    }
    
    // MARK: - Navigation
    
    func goToPage(_ pageNumber: Int) {
        guard let document = currentDocument,
              pageNumber >= 0,
              pageNumber < document.pageCount else {
            return
        }
        
        viewState.currentPage = pageNumber
        
        if let page = document.page(at: pageNumber) {
            currentPageInfo = pdfService.extractPageInfo(from: page, pageNumber: pageNumber)
        }
    }
    
    func nextPage() {
        guard let document = currentDocument,
              viewState.currentPage < document.pageCount - 1 else {
            return
        }
        goToPage(viewState.currentPage + 1)
    }
    
    func previousPage() {
        guard viewState.currentPage > 0 else {
            return
        }
        goToPage(viewState.currentPage - 1)
    }
    
    // MARK: - Search
    
    func search(query: String) {
        guard let document = currentDocument else { return }
        
        viewState.isSearching = true
        viewState.searchQuery = query
        
        // Cancel previous search
        searchTask?.cancel()
        
        searchTask = Task {
            do {
                let results = try await pdfService.search(in: document, query: query)
                
                if !Task.isCancelled {
                    viewState.searchResults = results
                    viewState.selectedSearchResultIndex = results.isEmpty ? nil : 0
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error
                }
            }
        }
    }
    
    func clearSearch() {
        searchTask?.cancel()
        viewState.isSearching = false
        viewState.searchQuery = ""
        viewState.searchResults = []
        viewState.selectedSearchResultIndex = nil
    }
    
    func selectSearchResult(at index: Int) {
        guard index >= 0 && index < viewState.searchResults.count else { return }
        
        viewState.selectedSearchResultIndex = index
        let result = viewState.searchResults[index]
        goToPage(result.pageNumber)
    }
    
    func nextSearchResult() {
        guard let currentIndex = viewState.selectedSearchResultIndex,
              currentIndex < viewState.searchResults.count - 1 else {
            return
        }
        selectSearchResult(at: currentIndex + 1)
    }
    
    func previousSearchResult() {
        guard let currentIndex = viewState.selectedSearchResultIndex,
              currentIndex > 0 else {
            return
        }
        selectSearchResult(at: currentIndex - 1)
    }
    
    // MARK: - Annotations
    
    func addAnnotation(_ annotation: Annotation) async {
        do {
            try await persistenceService.saveAnnotation(annotation)
            
            // Add overlay
            let overlay = AnnotationOverlay(from: annotation)
            annotations.append(overlay)
            
            // Post notification
            NotificationCenter.default.post(
                name: .prismAnnotationAdded,
                object: nil,
                userInfo: ["annotation": annotation]
            )
        } catch {
            self.error = error
        }
    }
    
    func updateAnnotation(_ annotation: Annotation) async {
        do {
            try await persistenceService.updateAnnotation(annotation)
            
            // Update overlay
            if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
                annotations[index] = AnnotationOverlay(from: annotation)
            }
            
            // Post notification
            NotificationCenter.default.post(
                name: .prismAnnotationUpdated,
                object: nil,
                userInfo: ["annotation": annotation]
            )
        } catch {
            self.error = error
        }
    }
    
    func deleteAnnotation(_ annotationId: UUID) async {
        do {
            try await persistenceService.deleteAnnotation(id: annotationId)
            
            // Remove overlay
            annotations.removeAll { $0.id == annotationId }
            
            // Post notification
            NotificationCenter.default.post(
                name: .prismAnnotationDeleted,
                object: nil,
                userInfo: ["annotationId": annotationId]
            )
        } catch {
            self.error = error
        }
    }
    
    func loadAnnotationsForPage(_ pageNumber: Int) -> [AnnotationOverlay] {
        annotations.filter { annotation in
            // This assumes annotations are already filtered by document
            // We'd need to add page filtering based on the annotation data
            true // TODO: Filter by page when we have that info
        }
    }
    
    // MARK: - Thumbnails
    
    private func generateThumbnails() async {
        guard let document = currentDocument else { return }
        
        let thumbnailSize = CGSize(width: 120, height: 180)
        var generatedThumbnails: [PDFThumbnail] = []
        
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            do {
                let thumbnail = try await pdfService.generateThumbnail(
                    for: page,
                    pageNumber: pageIndex,
                    size: thumbnailSize
                )
                generatedThumbnails.append(thumbnail)
            } catch {
                // Continue generating other thumbnails
                print("Failed to generate thumbnail for page \(pageIndex): \(error)")
            }
        }
        
        self.thumbnails = generatedThumbnails
    }
    
    // MARK: - Export
    
    func exportDocument(options: PDFExportOptions) async -> URL? {
        guard let document = currentDocument else { return nil }
        
        do {
            return try await pdfService.export(document: document, options: options)
        } catch {
            self.error = error
            return nil
        }
    }
    
    // MARK: - State Persistence
    
    private func saveViewState(_ state: PDFViewState) {
        guard let documentId = documentId else { return }
        
        Task {
            do {
                var document = try await persistenceService.loadDocument(id: documentId)
                document.currentPage = state.currentPage
                document.lastOpened = Date()
                
                // Calculate reading progress
                if let docInfo = documentInfo {
                    document.readingProgress = Double(state.currentPage) / Double(docInfo.pageCount)
                }
                
                try await persistenceService.updateDocument(document)
            } catch {
                // Silent fail for auto-save
                print("Failed to save view state: \(error)")
            }
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        searchTask?.cancel()
        cancellables.removeAll()
        currentDocument = nil
        documentInfo = nil
        thumbnails = []
        annotations = []
        viewState = .initial
        loadingState = .idle
    }
}

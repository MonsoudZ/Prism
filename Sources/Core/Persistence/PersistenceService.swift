import Foundation

// MARK: - Persistence Errors

enum PersistenceError: LocalizedError {
    case fileNotFound
    case invalidData
    case encodingFailed
    case decodingFailed
    case saveFailed(String)
    case deleteFailed(String)
    case storageAccessDenied
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The requested file could not be found"
        case .invalidData:
            return "The data is invalid or corrupted"
        case .encodingFailed:
            return "Failed to encode data"
        case .decodingFailed:
            return "Failed to decode data"
        case .saveFailed(let reason):
            return "Failed to save: \(reason)"
        case .deleteFailed(let reason):
            return "Failed to delete: \(reason)"
        case .storageAccessDenied:
            return "Storage access denied"
        }
    }
}

// MARK: - Persistence Protocol

protocol PersistenceServiceProtocol {
    // Documents
    func saveDocument(_ document: Document) async throws
    func loadDocument(id: UUID) async throws -> Document
    func loadAllDocuments() async throws -> [Document]
    func deleteDocument(id: UUID) async throws
    func updateDocument(_ document: Document) async throws
    
    // Annotations
    func saveAnnotation(_ annotation: Annotation) async throws
    func loadAnnotations(for documentId: UUID) async throws -> [Annotation]
    func deleteAnnotation(id: UUID) async throws
    func updateAnnotation(_ annotation: Annotation) async throws
    
    // Notes
    func saveNote(_ note: Note) async throws
    func loadNote(id: UUID) async throws -> Note
    func loadAllNotes() async throws -> [Note]
    func loadNotes(for documentId: UUID) async throws -> [Note]
    func deleteNote(id: UUID) async throws
    func updateNote(_ note: Note) async throws
    
    // Collections
    func saveCollection(_ collection: DocumentCollection) async throws
    func loadAllCollections() async throws -> [DocumentCollection]
    func deleteCollection(id: UUID) async throws
    func updateCollection(_ collection: DocumentCollection) async throws
    
    // Reading Sessions
    func saveSession(_ session: ReadingSession) async throws
    func loadSessions(for documentId: UUID) async throws -> [ReadingSession]
    
    // PDF Files
    func savePDFFile(from url: URL) async throws -> String
    func loadPDFFile(at path: String) throws -> URL
    func deletePDFFile(at path: String) throws
}

// MARK: - File-Based Persistence Implementation

final class FileBasedPersistenceService: PersistenceServiceProtocol {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // Storage directories
    private let documentsDirectory: URL
    private let annotationsDirectory: URL
    private let notesDirectory: URL
    private let collectionsDirectory: URL
    private let sessionsDirectory: URL
    private let pdfsDirectory: URL
    
    init() throws {
        // Get app's documents directory
        guard let baseDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw PersistenceError.storageAccessDenied
        }
        
        // Set up subdirectories
        documentsDirectory = baseDirectory.appendingPathComponent("Documents")
        annotationsDirectory = baseDirectory.appendingPathComponent("Annotations")
        notesDirectory = baseDirectory.appendingPathComponent("Notes")
        collectionsDirectory = baseDirectory.appendingPathComponent("Collections")
        sessionsDirectory = baseDirectory.appendingPathComponent("Sessions")
        pdfsDirectory = baseDirectory.appendingPathComponent("PDFs")
        
        // Create directories if needed
        try createDirectories()
        
        // Configure encoder/decoder
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }
    
    private func createDirectories() throws {
        let directories = [
            documentsDirectory,
            annotationsDirectory,
            notesDirectory,
            collectionsDirectory,
            sessionsDirectory,
            pdfsDirectory
        ]
        
        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }
    }
    
    // MARK: - Generic Save/Load Helpers
    
    private func save<T: Encodable>(_ item: T, to directory: URL, filename: String) async throws {
        let fileURL = directory.appendingPathComponent(filename)
        let data = try encoder.encode(item)
        
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
    }
    
    private func load<T: Decodable>(_ type: T.Type, from directory: URL, filename: String) async throws -> T {
        let fileURL = directory.appendingPathComponent(filename)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw PersistenceError.fileNotFound
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PersistenceError.decodingFailed
        }
    }
    
    private func loadAll<T: Decodable>(_ type: T.Type, from directory: URL) async throws -> [T] {
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var items: [T] = []
        
        for fileURL in contents where fileURL.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: fileURL)
                let item = try decoder.decode(T.self, from: data)
                items.append(item)
            } catch {
                // Skip corrupted files but continue loading others
                print("Failed to load \(fileURL.lastPathComponent): \(error)")
            }
        }
        
        return items
    }
    
    private func delete(from directory: URL, filename: String) async throws {
        let fileURL = directory.appendingPathComponent(filename)
        
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw PersistenceError.deleteFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Documents
    
    func saveDocument(_ document: Document) async throws {
        try await save(document, to: documentsDirectory, filename: "\(document.id).json")
    }
    
    func loadDocument(id: UUID) async throws -> Document {
        try await load(Document.self, from: documentsDirectory, filename: "\(id).json")
    }
    
    func loadAllDocuments() async throws -> [Document] {
        try await loadAll(Document.self, from: documentsDirectory)
    }
    
    func deleteDocument(id: UUID) async throws {
        try await delete(from: documentsDirectory, filename: "\(id).json")
    }
    
    func updateDocument(_ document: Document) async throws {
        try await saveDocument(document)
    }
    
    // MARK: - Annotations
    
    func saveAnnotation(_ annotation: Annotation) async throws {
        try await save(annotation, to: annotationsDirectory, filename: "\(annotation.id).json")
    }
    
    func loadAnnotations(for documentId: UUID) async throws -> [Annotation] {
        let allAnnotations = try await loadAll(Annotation.self, from: annotationsDirectory)
        return allAnnotations.filter { $0.documentId == documentId }
    }
    
    func deleteAnnotation(id: UUID) async throws {
        try await delete(from: annotationsDirectory, filename: "\(id).json")
    }
    
    func updateAnnotation(_ annotation: Annotation) async throws {
        try await saveAnnotation(annotation)
    }
    
    // MARK: - Notes
    
    func saveNote(_ note: Note) async throws {
        try await save(note, to: notesDirectory, filename: "\(note.id).json")
    }
    
    func loadNote(id: UUID) async throws -> Note {
        try await load(Note.self, from: notesDirectory, filename: "\(id).json")
    }
    
    func loadAllNotes() async throws -> [Note] {
        try await loadAll(Note.self, from: notesDirectory)
    }
    
    func loadNotes(for documentId: UUID) async throws -> [Note] {
        let allNotes = try await loadAll(Note.self, from: notesDirectory)
        return allNotes.filter { $0.documentId == documentId }
    }
    
    func deleteNote(id: UUID) async throws {
        try await delete(from: notesDirectory, filename: "\(id).json")
    }
    
    func updateNote(_ note: Note) async throws {
        try await saveNote(note)
    }
    
    // MARK: - Collections
    
    func saveCollection(_ collection: DocumentCollection) async throws {
        try await save(collection, to: collectionsDirectory, filename: "\(collection.id).json")
    }
    
    func loadAllCollections() async throws -> [DocumentCollection] {
        try await loadAll(DocumentCollection.self, from: collectionsDirectory)
    }
    
    func deleteCollection(id: UUID) async throws {
        try await delete(from: collectionsDirectory, filename: "\(id).json")
    }
    
    func updateCollection(_ collection: DocumentCollection) async throws {
        try await saveCollection(collection)
    }
    
    // MARK: - Reading Sessions
    
    func saveSession(_ session: ReadingSession) async throws {
        try await save(session, to: sessionsDirectory, filename: "\(session.id).json")
    }
    
    func loadSessions(for documentId: UUID) async throws -> [ReadingSession] {
        let allSessions = try await loadAll(ReadingSession.self, from: sessionsDirectory)
        return allSessions.filter { $0.documentId == documentId }
    }
    
    // MARK: - PDF Files
    
    func savePDFFile(from url: URL) async throws -> String {
        let filename = "\(UUID().uuidString).pdf"
        let destinationURL = pdfsDirectory.appendingPathComponent(filename)
        
        do {
            try fileManager.copyItem(at: url, to: destinationURL)
            return filename
        } catch {
            throw PersistenceError.saveFailed(error.localizedDescription)
        }
    }
    
    func loadPDFFile(at path: String) throws -> URL {
        let fileURL = pdfsDirectory.appendingPathComponent(path)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw PersistenceError.fileNotFound
        }
        
        return fileURL
    }
    
    func deletePDFFile(at path: String) throws {
        let fileURL = pdfsDirectory.appendingPathComponent(path)
        
        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw PersistenceError.deleteFailed(error.localizedDescription)
        }
    }
}

import Foundation

// MARK: - Document Models

struct Document: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var filePath: String
    var fileSize: Int64
    var pageCount: Int
    var dateAdded: Date
    var dateModified: Date
    var lastOpened: Date?
    var currentPage: Int
    var tags: [String]
    var isFavorite: Bool
    var readingProgress: Double // 0.0 to 1.0
    
    init(
        id: UUID = UUID(),
        title: String,
        filePath: String,
        fileSize: Int64,
        pageCount: Int,
        dateAdded: Date = Date(),
        dateModified: Date = Date(),
        lastOpened: Date? = nil,
        currentPage: Int = 0,
        tags: [String] = [],
        isFavorite: Bool = false,
        readingProgress: Double = 0.0
    ) {
        self.id = id
        self.title = title
        self.filePath = filePath
        self.fileSize = fileSize
        self.pageCount = pageCount
        self.dateAdded = dateAdded
        self.dateModified = dateModified
        self.lastOpened = lastOpened
        self.currentPage = currentPage
        self.tags = tags
        self.isFavorite = isFavorite
        self.readingProgress = readingProgress
    }
    
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - Annotation Models

enum AnnotationType: String, Codable {
    case highlight
    case underline
    case strikethrough
    case note
    case drawing
}

struct Annotation: Identifiable, Codable, Equatable {
    let id: UUID
    var documentId: UUID
    var pageNumber: Int
    var type: AnnotationType
    var color: AnnotationColor
    var rect: CGRect
    var text: String? // Selected text for highlights, note content for notes
    var bezierPath: String? // Serialized UIBezierPath for drawings
    var dateCreated: Date
    var dateModified: Date
    
    init(
        id: UUID = UUID(),
        documentId: UUID,
        pageNumber: Int,
        type: AnnotationType,
        color: AnnotationColor = .yellow,
        rect: CGRect,
        text: String? = nil,
        bezierPath: String? = nil,
        dateCreated: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.documentId = documentId
        self.pageNumber = pageNumber
        self.type = type
        self.color = color
        self.rect = rect
        self.text = text
        self.bezierPath = bezierPath
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }
}

struct AnnotationColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    
    static let yellow = AnnotationColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 0.4)
    static let green = AnnotationColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.4)
    static let blue = AnnotationColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.4)
    static let pink = AnnotationColor(red: 1.0, green: 0.0, blue: 0.5, alpha: 0.4)
    static let orange = AnnotationColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.4)
}

// MARK: - Note Models

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var documentId: UUID?
    var title: String
    var content: String
    var dateCreated: Date
    var dateModified: Date
    var tags: [String]
    var linkedAnnotationIds: [UUID]
    var isPinned: Bool
    
    init(
        id: UUID = UUID(),
        documentId: UUID? = nil,
        title: String,
        content: String = "",
        dateCreated: Date = Date(),
        dateModified: Date = Date(),
        tags: [String] = [],
        linkedAnnotationIds: [UUID] = [],
        isPinned: Bool = false
    ) {
        self.id = id
        self.documentId = documentId
        self.title = title
        self.content = content
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.tags = tags
        self.linkedAnnotationIds = linkedAnnotationIds
        self.isPinned = isPinned
    }
    
    var preview: String {
        let maxLength = 100
        if content.count <= maxLength {
            return content
        }
        return String(content.prefix(maxLength)) + "..."
    }
}

// MARK: - Reading Session Models

struct ReadingSession: Identifiable, Codable, Equatable {
    let id: UUID
    var documentId: UUID
    var startTime: Date
    var endTime: Date?
    var pagesRead: Int
    var startPage: Int
    var endPage: Int
    
    init(
        id: UUID = UUID(),
        documentId: UUID,
        startTime: Date = Date(),
        endTime: Date? = nil,
        pagesRead: Int = 0,
        startPage: Int = 0,
        endPage: Int = 0
    ) {
        self.id = id
        self.documentId = documentId
        self.startTime = startTime
        self.endTime = endTime
        self.pagesRead = pagesRead
        self.startPage = startPage
        self.endPage = endPage
    }
    
    var duration: TimeInterval {
        guard let endTime = endTime else {
            return Date().timeIntervalSince(startTime)
        }
        return endTime.timeIntervalSince(startTime)
    }
}

// MARK: - Collection Models

struct DocumentCollection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var documentIds: [UUID]
    var dateCreated: Date
    var dateModified: Date
    var icon: String?
    var color: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        documentIds: [UUID] = [],
        dateCreated: Date = Date(),
        dateModified: Date = Date(),
        icon: String? = nil,
        color: String? = nil
    ) {
        self.id = id
        self.name = name
        self.documentIds = documentIds
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.icon = icon
        self.color = color
    }
}

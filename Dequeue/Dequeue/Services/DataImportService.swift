//
//  DataImportService.swift
//  Dequeue
//
//  Service for importing tasks from external sources including CSV, JSON,
//  and structured text. Supports mapping external fields to Dequeue's model.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Import Format

/// Supported import formats.
enum ImportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv = "CSV"
    case json = "JSON"
    case plainText = "Plain Text"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        case .plainText: return "txt"
        }
    }

    var utType: UTType {
        switch self {
        case .csv: return .commaSeparatedText
        case .json: return .json
        case .plainText: return .plainText
        }
    }

    var description: String {
        switch self {
        case .csv: return "CSV with headers: title, description, priority, due_date, tags, status"
        case .json: return "JSON array of task objects"
        case .plainText: return "One task per line (- prefix optional)"
        }
    }
}

// MARK: - Import Result

/// Result of an import operation.
struct ImportResult: Sendable {
    let format: ImportFormat
    let totalParsed: Int
    let imported: Int
    let skipped: Int
    let errors: [String]

    var isSuccess: Bool { errors.isEmpty || imported > 0 }

    var summary: String {
        if errors.isEmpty {
            return "Imported \(imported) task\(imported == 1 ? "" : "s")"
        }
        return "Imported \(imported), skipped \(skipped), \(errors.count) error\(errors.count == 1 ? "" : "s")"
    }
}

// MARK: - Parsed Task

/// Intermediate representation of a parsed task before import.
struct ParsedTask: Sendable {
    var title: String
    var description: String?
    var priority: Int?
    var dueDate: Date?
    var startDate: Date?
    var tags: [String]
    var status: String?
}

// MARK: - CSV Parser

/// Parses CSV data into ParsedTask objects.
enum CSVParser {
    static func parse(_ content: String) throws -> [ParsedTask] {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard let headerLine = lines.first else {
            throw ImportError.emptyFile
        }

        let headers = parseCSVRow(headerLine).map {
            $0.lowercased().trimmingCharacters(in: .whitespaces)
        }
        guard headers.contains("title") || headers.contains("name") || headers.contains("task") else {
            throw ImportError.missingTitleColumn
        }

        let titleIdx = headers.firstIndex(of: "title")
            ?? headers.firstIndex(of: "name")
            ?? headers.firstIndex(of: "task")
        let descIdx = headers.firstIndex(of: "description")
            ?? headers.firstIndex(of: "notes")
            ?? headers.firstIndex(of: "details")
        let priorityIdx = headers.firstIndex(of: "priority")
        let dueDateIdx = headers.firstIndex(of: "due_date")
            ?? headers.firstIndex(of: "due")
            ?? headers.firstIndex(of: "deadline")
        let tagsIdx = headers.firstIndex(of: "tags")
            ?? headers.firstIndex(of: "labels")
        let statusIdx = headers.firstIndex(of: "status")
            ?? headers.firstIndex(of: "state")

        var tasks: [ParsedTask] = []

        for line in lines.dropFirst() {
            let columns = parseCSVRow(line)
            guard let tIdx = titleIdx, tIdx < columns.count else { continue }
            let title = columns[tIdx].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }

            var task = ParsedTask(
                title: title,
                tags: []
            )

            if let idx = descIdx, idx < columns.count {
                let desc = columns[idx].trimmingCharacters(in: .whitespaces)
                if !desc.isEmpty { task.description = desc }
            }

            if let idx = priorityIdx, idx < columns.count {
                task.priority = parsePriority(columns[idx])
            }

            if let idx = dueDateIdx, idx < columns.count {
                task.dueDate = parseDate(columns[idx])
            }

            if let idx = tagsIdx, idx < columns.count {
                let tagStr = columns[idx].trimmingCharacters(in: .whitespaces)
                if !tagStr.isEmpty {
                    task.tags = tagStr.components(separatedBy: ";")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
            }

            if let idx = statusIdx, idx < columns.count {
                task.status = columns[idx].trimmingCharacters(in: .whitespaces)
            }

            tasks.append(task)
        }

        return tasks
    }

    /// Parses a CSV row respecting quoted fields.
    static func parseCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in row {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)

        return fields
    }
}

// MARK: - JSON Parser

/// Parses JSON data into ParsedTask objects.
enum JSONTaskParser {
    static func parse(_ content: String) throws -> [ParsedTask] {
        guard let data = content.data(using: .utf8) else {
            throw ImportError.invalidEncoding
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data)

        // Handle array of objects
        guard let array = jsonObject as? [[String: Any]] else {
            // Try single object
            if let single = jsonObject as? [String: Any] {
                return [try parseObject(single)]
            }
            throw ImportError.invalidJSONStructure
        }

        return try array.compactMap { try parseObject($0) }
    }

    private static func parseObject(_ obj: [String: Any]) throws -> ParsedTask {
        let title = (obj["title"] as? String)
            ?? (obj["name"] as? String)
            ?? (obj["task"] as? String)
            ?? (obj["content"] as? String)

        guard let titleStr = title, !titleStr.isEmpty else {
            throw ImportError.missingTitle
        }

        var task = ParsedTask(title: titleStr, tags: [])

        task.description = (obj["description"] as? String)
            ?? (obj["notes"] as? String)

        if let prio = obj["priority"] as? Int {
            task.priority = min(max(prio, 0), 3)
        } else if let prioStr = obj["priority"] as? String {
            task.priority = parsePriority(prioStr)
        }

        if let dateStr = obj["due_date"] as? String {
            task.dueDate = parseDate(dateStr)
        } else if let dateStr = obj["due"] as? String {
            task.dueDate = parseDate(dateStr)
        } else if let dateStr = obj["deadline"] as? String {
            task.dueDate = parseDate(dateStr)
        }

        if let tags = obj["tags"] as? [String] {
            task.tags = tags
        } else if let tags = obj["labels"] as? [String] {
            task.tags = tags
        } else if let tagStr = obj["tags"] as? String {
            task.tags = tagStr.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        task.status = (obj["status"] as? String) ?? (obj["state"] as? String)

        return task
    }
}

// MARK: - Plain Text Parser

/// Parses plain text (one task per line) into ParsedTask objects.
enum PlainTextParser {
    static func parse(_ content: String) -> [ParsedTask] {
        content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                // Strip common list prefixes
                var title = line
                let prefixes = ["- ", "* ", "• ", "□ ", "☐ ", "[ ] ", "[x] ", "[X] "]
                for prefix in prefixes where title.hasPrefix(prefix) {
                    title = String(title.dropFirst(prefix.count))
                    break
                }
                // Strip number prefix (1. 2. 3.)
                if let dotIndex = title.firstIndex(of: "."),
                   title[title.startIndex..<dotIndex].allSatisfy(\.isNumber) {
                    title = String(title[title.index(after: dotIndex)...])
                        .trimmingCharacters(in: .whitespaces)
                }

                let isCompleted = line.hasPrefix("[x] ") || line.hasPrefix("[X] ")

                return ParsedTask(
                    title: title,
                    tags: [],
                    status: isCompleted ? "completed" : nil
                )
            }
            .filter { !$0.title.isEmpty }
    }
}

// MARK: - Import Error

enum ImportError: LocalizedError, Sendable {
    case emptyFile
    case missingTitleColumn
    case invalidEncoding
    case invalidJSONStructure
    case missingTitle
    case noTasksParsed
    case fileReadFailed

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "File is empty"
        case .missingTitleColumn: return "CSV must have a 'title', 'name', or 'task' column"
        case .invalidEncoding: return "File encoding not supported (use UTF-8)"
        case .invalidJSONStructure: return "JSON must be an array of objects or a single object"
        case .missingTitle: return "Task object is missing a title field"
        case .noTasksParsed: return "No tasks found in file"
        case .fileReadFailed: return "Could not read the file"
        }
    }
}

// MARK: - Helpers

/// Parse a priority string to an integer (0-3).
func parsePriority(_ string: String) -> Int? {
    let trimmed = string.lowercased().trimmingCharacters(in: .whitespaces)
    switch trimmed {
    case "none", "0", "": return nil
    case "low", "1", "p3": return 1
    case "medium", "med", "2", "p2": return 2
    case "high", "3", "p1", "urgent": return 3
    default:
        if let num = Int(trimmed) { return min(max(num, 0), 3) }
        return nil
    }
}

/// Parse a date string in common formats.
func parseDate(_ string: String) -> Date? {
    let trimmed = string.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }

    // ISO 8601
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: trimmed) { return date }

    // Common formats
    let formats = [
        "yyyy-MM-dd",
        "MM/dd/yyyy",
        "dd/MM/yyyy",
        "yyyy-MM-dd HH:mm",
        "MM/dd/yyyy HH:mm",
        "MMM d, yyyy",
        "MMMM d, yyyy",
        "d MMM yyyy"
    ]

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")

    for format in formats {
        formatter.dateFormat = format
        if let date = formatter.date(from: trimmed) { return date }
    }

    return nil
}

// MARK: - Import Service

@MainActor
final class DataImportService {
    private let modelContext: ModelContext
    private let eventService: EventService
    private let syncManager: SyncManager?

    init(modelContext: ModelContext, userId: String, deviceId: String, syncManager: SyncManager? = nil) {
        self.modelContext = modelContext
        self.eventService = EventService(modelContext: modelContext, userId: userId, deviceId: deviceId)
        self.syncManager = syncManager
    }

    /// Import tasks from file content into a target stack.
    func importTasks(
        content: String,
        format: ImportFormat,
        targetStack: Stack,
        skipCompleted: Bool = false
    ) async throws -> ImportResult {
        // Parse
        let parsed: [ParsedTask]
        switch format {
        case .csv:
            parsed = try CSVParser.parse(content)
        case .json:
            parsed = try JSONTaskParser.parse(content)
        case .plainText:
            parsed = PlainTextParser.parse(content)
        }

        guard !parsed.isEmpty else {
            throw ImportError.noTasksParsed
        }

        // Import
        var imported = 0
        var skipped = 0
        var errors: [String] = []

        let existingOrder = targetStack.pendingTasks.count

        for (index, parsedTask) in parsed.enumerated() {
            // Skip completed tasks if requested
            if skipCompleted,
               let status = parsedTask.status?.lowercased(),
               status == "completed" || status == "done" || status == "closed" {
                skipped += 1
                continue
            }

            do {
                let status: TaskStatus = {
                    guard let statusStr = parsedTask.status?.lowercased() else { return .pending }
                    switch statusStr {
                    case "completed", "done", "finished": return .completed
                    case "blocked", "waiting": return .blocked
                    case "closed", "cancelled", "canceled": return .closed
                    default: return .pending
                    }
                }()

                let task = QueueTask(
                    title: parsedTask.title,
                    taskDescription: parsedTask.description,
                    dueTime: parsedTask.dueDate,
                    tags: parsedTask.tags,
                    status: status,
                    priority: parsedTask.priority,
                    sortOrder: existingOrder + index,
                    stack: targetStack
                )

                modelContext.insert(task)
                targetStack.tasks.append(task)
                try await eventService.recordTaskCreated(task)
                imported += 1
            } catch {
                errors.append("Row \(index + 1) (\(parsedTask.title)): \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        if imported > 0 {
            syncManager?.triggerImmediatePush()
        }

        return ImportResult(
            format: format,
            totalParsed: parsed.count,
            imported: imported,
            skipped: skipped,
            errors: errors
        )
    }
}

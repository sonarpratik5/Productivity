import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ActivityCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

enum ActivityCSVExporter {
    private static let exportLocale = Locale(identifier: "en_US_POSIX")

    static func document(for segments: [ActivitySegment]) -> ActivityCSVDocument {
        ActivityCSVDocument(text: csv(from: segments))
    }

    private static func csv(from segments: [ActivitySegment]) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "id,app_name,bundle_identifier,title,user_description,start_date,end_date,duration_seconds,label,category,productivity_score"
        let rows = segments.map { segment in
            [
                segment.id.uuidString,
                segment.appName,
                segment.bundleIdentifier,
                segment.title,
                segment.userDescription ?? "",
                formatter.string(from: segment.startDate),
                formatter.string(from: segment.endDate),
                String(Int(segment.duration)),
                segment.label.title,
                segment.category.title,
                String(format: "%.2f", locale: exportLocale, segment.productivityScore)
            ]
            .map(escape)
            .joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    nonisolated private static func escape(_ value: String) -> String {
        let escapedValue = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escapedValue)\""
    }
}

import Foundation

public enum ViewedThreadStore {
    public static func viewedAtByThreadID(
        file: URL?,
        fileManager: FileManager = .default
    ) -> [String: Date] {
        guard let file,
              let data = fileManager.contents(atPath: file.path),
              let values = try? JSONDecoder().decode([String: Date].self, from: data) else {
            return [:]
        }
        return values
    }

    public static func markViewed(
        threadID: String,
        at date: Date = Date(),
        file: URL,
        fileManager: FileManager = .default
    ) throws {
        var values = viewedAtByThreadID(file: file, fileManager: fileManager)
        values[threadID] = date
        if values.count > 100 {
            values = Dictionary(
                uniqueKeysWithValues: values
                    .sorted { $0.value > $1.value }
                    .prefix(100)
                    .map { ($0.key, $0.value) }
            )
        }
        try fileManager.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(values)
        try data.write(to: file, options: .atomic)
    }
}

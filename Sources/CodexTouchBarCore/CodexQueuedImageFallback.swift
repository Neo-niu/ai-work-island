import Foundation

public enum CodexQueuedImageFallback {
    public static func message(text: String, imageURLs: [URL]) -> String {
        guard !imageURLs.isEmpty else { return text }
        let paths = imageURLs.map { "- \($0.path)" }.joined(separator: "\n")
        let instruction = """
        请把以下本地图片作为本条用户消息的图片附件读取并分析：
        \(paths)
        """
        return text.isEmpty ? instruction : "\(text)\n\n\(instruction)"
    }

    public static func stage(
        _ imageURLs: [URL],
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard !imageURLs.isEmpty else { return [] }
        let root = try stagingRoot(fileManager: fileManager)
        try removeExpiredImages(in: root, fileManager: fileManager)
        let batch = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: batch, withIntermediateDirectories: true)
        return try imageURLs.enumerated().map { index, source in
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
            let destination = batch.appendingPathComponent("image-\(index + 1).\(ext)")
            try fileManager.copyItem(at: source, to: destination)
            return destination
        }
    }

    private static func stagingRoot(fileManager: FileManager) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support
            .appendingPathComponent("AI工作岛", isDirectory: true)
            .appendingPathComponent("QueuedImages", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func removeExpiredImages(in root: URL, fileManager: FileManager) throws {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for url in try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values?.contentModificationDate, modified < cutoff {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}

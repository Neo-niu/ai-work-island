import Foundation

public enum ViewedThreadPresentationFilter {
    public static func filtering(
        _ groups: [ProjectGroup],
        viewedAtByThreadID: [String: Date]
    ) -> [ProjectGroup] {
        groups.compactMap { group in
            let threads = group.threads.filter { thread in
                guard !thread.isActive,
                      thread.isUnread,
                      let viewedAt = viewedAtByThreadID[thread.id] else { return true }
                return thread.updatedAt > viewedAt
            }
            guard !threads.isEmpty else { return nil }
            return ProjectGroup(
                id: group.id,
                name: group.name,
                threads: threads,
                isUnnamed: group.isUnnamed,
                hasUnread: threads.contains(where: \.isUnread),
                isSelected: group.isSelected
            )
        }
    }
}

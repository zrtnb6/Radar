import Foundation
import SwiftData

/// 首次安装时预置的默认项目：Radar 监控自己的 GitHub 仓库。
///
/// 设计要点：
/// - 只写本地 SwiftData，不发起网络请求，离线安装也能立刻在列表里看到「Radar」；
/// - `id` 用负数占位（GitHub 仓库 id 恒为正整数），首次联网刷新按 owner/name 拉取快照后，
///   由 `SyncService.update` 补齐头像、Star、Release 等真实数据，占位 id 仅作为本地关联键；
/// - 首次刷新会被当作基线，不对历史 Release 推送通知（见 `SyncService.refresh`）；
/// - 用 UserDefaults 标记保证只注入一次：升级用户不会被塞入新项目，
///   手动清空列表后重启也不会重新冒出来。
enum DefaultRepository {
    static let owner = "zrtnb6"
    static let name = "Radar"
    static let fullName = "\(owner)/\(name)"
    static let url = "https://github.com/\(fullName)"

    /// 负数占位 id，绝不会与 GitHub 的真实仓库 id 冲突。
    static let seedID: Int64 = -1
    static let seedFlagKey = "hasSeededDefaultRepository"

    /// 必要时写入默认项目。
    /// - Returns: 是否真的插入了（供调用方决定是否默认选中）。
    @discardableResult
    static func seedIfNeeded(context: ModelContext) -> Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seedFlagKey) else { return false }

        let existingCount = (try? context.fetchCount(FetchDescriptor<Repository>())) ?? 0
        guard existingCount == 0 else {
            // 已有数据的升级用户：不注入，但仍记下标记，避免日后清空列表又被重新塞回来。
            defaults.set(true, forKey: seedFlagKey)
            return false
        }

        let repository = Repository(
            id: seedID,
            owner: owner,
            name: name,
            fullName: fullName,
            url: url,
            repositoryDescription: "Radar · 原生 macOS GitHub Release 监控客户端",
            language: "Swift",
            topics: ["macos", "swiftui", "swiftdata", "github-releases"]
        )
        context.insert(repository)
        do {
            try context.save()
        } catch {
            context.delete(repository)
            return false
        }
        defaults.set(true, forKey: seedFlagKey)
        return true
    }
}

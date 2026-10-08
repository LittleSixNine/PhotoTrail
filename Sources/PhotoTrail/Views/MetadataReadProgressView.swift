import SwiftUI

/// Observe read counters without rebuilding the workspace.
struct MetadataReadProgressView: View {
    let progress: MetadataLoadingQueue.ReadProgress
    let pause: () -> Void
    let resume: () -> Void
    var body: some View {
        if progress.total > 0 {
            HStack(spacing: 12) {
                ProgressView(value: Double(progress.editableRead + progress.displayRead),
                             total: Double(progress.total * 2)).frame(width: 160)
                Text(L10n.text("元数据：已读取 %1$@/%2$@，失败 %3$@",
                               progress.completed - progress.failures, progress.total, progress.failures))
                if progress.completed < progress.total {
                    if !progress.isPaused { ImportRemainingTimeView(seconds: progress.overallRemainingSeconds) }
                    Button(L10n.text(progress.isPaused ? "继续读取" : "暂停读取"),
                           action: progress.isPaused ? resume : pause)
                }
                Spacer()
            }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 6)
        }
    }
}

struct MetadataPreparationView: View {
    let importedPhotoCount: Int
    let progress: MetadataLoadingQueue.ReadProgress
    let pause: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Text(L10n.text("正在导入照片")).font(.title2)
            Text(L10n.text("第 2 / 2 步：准备元数据")).foregroundStyle(.secondary)
            ProgressView(value: Double(progress.editableRead + progress.displayRead),
                         total: Double(progress.total * 2)).frame(width: 360)
            VStack(spacing: 8) {
                Text(L10n.text("可编辑字段：%1$@/%2$@", progress.editableRead, progress.total))
                Text(L10n.text("完整字段：%1$@/%2$@", progress.displayRead, progress.total))
                Text(L10n.text("元数据：已读取 %1$@/%2$@，失败 %3$@",
                               progress.completed - progress.failures, progress.total, progress.failures))
            }.monospacedDigit()
            ImportRemainingTimeView(seconds: progress.overallRemainingSeconds)
            if importedPhotoCount > 300 {
                Text(L10n.text("您导入的照片较多，处理需要一些时间，请耐心等待。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(L10n.text("可以切换到其他应用，读取会继续。")).foregroundStyle(.secondary)
            Button(L10n.text("暂停读取"), action: pause)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("metadataPreparationView")
    }
}

struct RemainingTimeView: View {
    let seconds: Double?
    var body: some View {
        if let seconds {
            Text(L10n.text("当前阶段预计剩余约 %1$@ 秒", max(10, Int((seconds / 10).rounded(.up)) * 10)))
                .foregroundStyle(.secondary).monospacedDigit()
        } else {
            Text(L10n.text("正在估算当前阶段剩余时间…")).foregroundStyle(.secondary)
        }
    }
}

struct ImportPreparationView: View {
    let progress: ImportProgress
    let metadataProgress: MetadataLoadingQueue.ReadProgress
    private var title: String {
        switch progress.phase {
        case .scanning: L10n.text("正在扫描文件…")
        case .images: L10n.text("正在导入基础信息…")
        case .tracks: L10n.text("正在导入轨迹…")
        }
    }
    var body: some View {
        VStack(spacing: 18) {
            if progress.preparesPhotoMetadata {
                Text(L10n.text("正在导入照片")).font(.title2)
                Text(L10n.text("第 1 / 2 步：导入文件")).foregroundStyle(.secondary)
                Text(title)
            } else {
                Text(title).font(.title2)
            }
            if progress.phase == .scanning {
                ProgressView()
            } else {
                ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                    .frame(width: 360)
                Text(L10n.text("已处理 %1$@/%2$@", progress.completed, progress.total)).monospacedDigit()

            }
            ImportRemainingTimeView(seconds: progress.overallRemainingSeconds(
                metadataSeconds: metadataProgress.estimatedSeconds(forPhotos: progress.photoCount)))
            if progress.photoCount > 300 {
                Text(L10n.text("您导入的照片较多，处理需要一些时间，请耐心等待。"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(L10n.text("可以切换到其他应用，读取会继续。")).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("importPreparationView")
    }
}

struct RenameExecutionProgressView: View {
    @Bindable var workspace: RenameWorkspace
    private var title: String {
        if workspace.restoring { return L10n.text("正在恢复原文件名…") }
        if workspace.stopping { return L10n.text("正在停止…") }
        switch workspace.progress.phase {
        case .checking: return L10n.text("正在检查文件…")
        case .staging: return L10n.text("正在准备修改名称…")
        case .renaming: return L10n.text("正在修改文件名…")
        case .verifying: return L10n.text("正在核对结果…")
        case .restoring: return L10n.text("正在恢复原文件名…")
        }
    }
    var body: some View {
        VStack(spacing: 18) {
            Text(L10n.text("正在重命名照片")).font(.title2)
            Text(L10n.text("检查文件 → 修改名称 → 核对结果")).foregroundStyle(.secondary)
            Text(title)
            ProgressView(value: workspace.progress.fraction).frame(width: 360)
            Text(L10n.text("当前阶段已处理 %1$@/%2$@ 个文件", workspace.progress.completed, workspace.progress.total))
                .monospacedDigit()
            Text(L10n.text("包含关联文件；完成前请勿关闭程序。"))
                .foregroundStyle(.secondary)
            Button(L10n.text("停止并恢复")) { workspace.cancel() }
                .disabled(workspace.stopping || workspace.restoring)
                .accessibilityIdentifier("renameStopAndRestore")
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("renameExecutionProgressView")
    }
}

struct ImportRemainingTimeView: View {
    let seconds: Double?
    var body: some View {
        if let seconds {
            Text(L10n.text("全部导入预计剩余约 %1$@ 秒", max(10, Int((seconds / 10).rounded(.up)) * 10)))
                .foregroundStyle(.secondary).monospacedDigit()
        } else {
            Text(L10n.text("正在估算全部导入剩余时间…")).foregroundStyle(.secondary)
        }
    }
}

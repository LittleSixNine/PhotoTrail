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
                    if !progress.isPaused { RemainingTimeView(seconds: progress.remainingSeconds) }
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
    let progress: MetadataLoadingQueue.ReadProgress
    let pause: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Text(L10n.text("正在准备照片元数据…")).font(.title2)
            ProgressView(value: Double(progress.editableRead + progress.displayRead),
                         total: Double(progress.total * 2)).frame(width: 360)
            VStack(spacing: 8) {
                Text(L10n.text("可编辑字段：%1$@/%2$@", progress.editableRead, progress.total))
                Text(L10n.text("完整字段：%1$@/%2$@", progress.displayRead, progress.total))
                Text(L10n.text("元数据：已读取 %1$@/%2$@，失败 %3$@",
                               progress.completed - progress.failures, progress.total, progress.failures))
            }.monospacedDigit()
            RemainingTimeView(seconds: progress.remainingSeconds)
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
    private var title: String {
        switch progress.phase {
        case .scanning: L10n.text("正在扫描文件…")
        case .images: L10n.text("正在导入基础信息…")
        case .tracks: L10n.text("正在导入轨迹…")
        }
    }
    var body: some View {
        VStack(spacing: 18) {
            Text(title).font(.title2)
            if progress.phase == .scanning {
                ProgressView()
            } else {
                ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                    .frame(width: 360)
                Text(L10n.text("已处理 %1$@/%2$@", progress.completed, progress.total)).monospacedDigit()
                if progress.completed < progress.total { RemainingTimeView(seconds: progress.remainingSeconds) }
            }
            Text(L10n.text("可以切换到其他应用，读取会继续。")).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("importPreparationView")
    }
}

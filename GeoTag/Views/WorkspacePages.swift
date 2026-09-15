import Coords
import ImageData
import SwiftUI
import UDF

extension ImageData {
    var hasPendingChanges: Bool { updatable && metadata != original }
}

enum PhotoListFilter: String, CaseIterable {
    case all = "全部", unlocated = "无定位", located = "有定位", pending = "待保存"

    func includes(_ image: ImageData) -> Bool {
        switch self {
        case .all: true
        case .unlocated: image.metadata.location == nil
        case .located: image.metadata.location != nil
        case .pending: image.hasPendingChanges
        }
    }
}

struct PhotoSaveStatus: View {
    let image: ImageData
    var body: some View {
        Image(systemName: image.hasPendingChanges ? "square.and.arrow.down" : "checkmark.circle.fill")
            .font(.system(size: 18))
            .foregroundStyle(image.hasPendingChanges ? Color.orange : Color.green)
            .help(image.hasPendingChanges ? "有修改，待保存" : "无待保存修改")
            .accessibilityLabel(image.hasPendingChanges ? "待保存" : "无待保存修改")
    }
}

struct PhotoThumbnail: View {
    let image: ImageData
    @State private var thumbnail: Image?
    @Environment(\.displayScale) private var scale

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            if let thumbnail {
                thumbnail.resizable().scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: image.id) {
            let loaded: Image
            if let cached = image.thumbnail {
                loaded = cached
            } else {
                loaded = await image.makeThumbnail(scale: scale)
            }
            guard !Task.isCancelled else { return }
            thumbnail = loaded
        }
    }
}

struct WorkspaceSaveButton: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store
    var body: some View {
        Button {
            store.send(.saveRequest, undoable: false) { SaveHelper.save(store) }
            store.discardAllUndo()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.and.arrow.down")
                Text(store.saveInProgress ? "保存中…" : "保存所有修改")
            }.fixedSize()
        }
        .buttonStyle(WorkspaceToolbarButtonStyle(prominent: true))
        .disabled(store.saveInProgress || !store.unsavedChanges)
        .help("保存全部待保存修改")
    }
}

struct PhotoActionSidebar: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store
    @Environment(LocationWorkspace.self) private var workspace
    @AppStorage(SettingsView.extendedTimeKey) private var extendedTime = 120.0
    @State private var timePresented = false

    private var editable: Bool {
        !store.selection.isEmpty && !store.saveInProgress && store.selection.allSatisfy { store[$0].updatable }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("照片操作").font(.title3.bold())
            Text("已选择 \(store.selection.count) 张照片").font(.subheadline).foregroundStyle(.secondary)
            Menu {
                if workspace.favorites.isEmpty { Text("暂无收藏，请在详情页添加") }
                ForEach(workspace.favorites) { favorite in
                    Button(favorite.name) {
                        store.send(.confirmedWGS84Location(Coords(latitude: favorite.coordinate.latitude,
                                                                 longitude: favorite.coordinate.longitude)),
                                   description: "应用收藏地点")
                    }
                }
            } label: { actionLabel("应用收藏", "star") }
            .disabled(!editable)
            Button {
                LocationHelper.locationFromTrack(store, extendedTime: extendedTime)
            } label: { actionLabel("从轨迹匹配", "point.3.connected.trianglepath.dotted") }
            .disabled(!editable || store.gpxTracks.isEmpty)
            Button { timePresented = true } label: { actionLabel("调整拍摄时间", "clock") }
                .disabled(!editable)
            Button { store.send(.deleteRequest, description: "清除定位") } label: {
                actionLabel("清除定位", "mappin.slash")
            }.disabled(!editable || store.selection.allSatisfy { store[$0].metadata.location == nil })
            Divider().padding(.vertical, 6)
            WorkspaceSaveButton()
            Button { store.undo() } label: { actionLabel("撤销", "arrow.uturn.backward") }
                .disabled(!store.canUndo || store.saveInProgress || store.textfieldActive)
            if store.saveInProgress { ProgressView().controlSize(.small) }
            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered).controlSize(.large).padding(20)
        .frame(width: 240).frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $timePresented) {
            VStack(alignment: .leading, spacing: 16) {
                Text("调整拍摄时间").font(.title2)
                Text("多选时，将相同的时间差应用到全部选中照片。").font(.callout)
                DateTimeSectionView(image: store[store.mostSelected])
                HStack { Spacer(); Button("完成") { timePresented = false } }
            }.padding(24).frame(width: 460)
                .onDisappear { store.send(.textfieldFocusChanged(false), undoable: false) }
        }
    }

    private func actionLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
    }
}

struct PhotoDetailPage: View {
    @Environment(Store<GeoTagState, GeoTagEvent>.self) private var store

    @AppStorage("GeoTagCNDetailWidthRatio") private var leftRatio = 0.26
    @AppStorage("GeoTagCNFilmstripHeightRatio") private var stripRatio = 0.13
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        GeometryReader { geometry in
                            ImageView().frame(width: geometry.size.width, height: geometry.size.height)
                        }.aspectRatio(1.5, contentMode: .fit)
                        if let id = store.mostSelected {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store[id].name).font(.headline).lineLimit(1).truncationMode(.middle)
                                Text(store[id].metadata.timestamp).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.bottom, 12)
                        }
                        Divider()
                        LocationPanel()
                    }.frame(width: max(260, min(geometry.size.width * leftRatio, geometry.size.width - 420)))
                        .background(Color(nsColor: .windowBackgroundColor))
                    Divider().frame(width: 6).contentShape(Rectangle())
                        .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                        .gesture(DragGesture().onChanged { value in
                            if dragStart == nil { dragStart = leftRatio }
                            leftRatio = min(0.5, max(0.18, (dragStart ?? leftRatio)
                                + value.translation.width / geometry.size.width))
                        }.onEnded { _ in dragStart = nil })
                    MapWithSearchView().frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }.frame(width: geometry.size.width,
                        height: max(340, geometry.size.height - max(100, geometry.size.height * stripRatio) - 6))
                Divider().frame(height: 6).contentShape(Rectangle())
                    .onHover { if $0 { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture().onChanged { value in
                        if dragStart == nil { dragStart = stripRatio }
                        stripRatio = min(0.3, max(0.10, (dragStart ?? stripRatio)
                            - value.translation.height / geometry.size.height))
                    }.onEnded { _ in dragStart = nil })
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 12) {
                                ForEach(store.imageData) { image in
                                    Button {
                                        store.send(.selectionChanged([image.id]), undoable: false)
                                    } label: {
                                        VStack(spacing: 5) {
                                            PhotoThumbnail(image: image)
                                                .frame(width: max(90, (geometry.size.height - 48) * 1.5),
                                                       height: max(60, geometry.size.height - 48))
                                                .overlay(RoundedRectangle(cornerRadius: 5)
                                                    .stroke(store.selection.contains(image.id)
                                                            ? Color.accentColor : .clear,
                                                            lineWidth: 3))
                                            Text(image.name).font(.caption).lineLimit(1)
                                                .truncationMode(.middle)
                                                .frame(width: max(90, (geometry.size.height - 48) * 1.5))
                                        }
                                    }.buttonStyle(.plain).id(image.id)
                                }
                            }.padding(14)
                        }.frame(height: geometry.size.height).background(Color(nsColor: .windowBackgroundColor))
                            .onAppear { if let id = store.mostSelected { proxy.scrollTo(id, anchor: .center) } }
                            .onChange(of: store.mostSelected) {
                                if let id = store.mostSelected { proxy.scrollTo(id, anchor: .center) }
                            }
                    }
                }.frame(height: max(100, geometry.size.height * stripRatio))
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

struct WorkspacePageSwitch: View {
    @Binding var selection: Bool
    var firstTitle = "列表页面"
    var secondTitle = "详情页面"
    var firstIcon = "list.bullet"
    var secondIcon = "photo"
    var optionWidth: CGFloat = 124
    var usesGlass = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if usesGlass {
            track.glassEffect(.clear.interactive(), in: Capsule())
        } else {
            track.background(.quaternary.opacity(0.5), in: Capsule())
        }
    }

    private var track: some View {
        HStack(spacing: 0) {
            option(firstTitle, icon: firstIcon, value: false)
            option(secondTitle, icon: secondIcon, value: true)
        }
        .background(alignment: .leading) {
            Capsule().fill(Color.blue).frame(width: optionWidth, height: 30)
                .offset(x: selection ? optionWidth : 0)
        }
        .padding(3)
        .fixedSize()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selection)
    }

    private func option(_ title: String, icon: String, value: Bool) -> some View {
        Button { selection = value } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(selection == value ? Color.white : Color.primary)
            .frame(width: optionWidth, height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

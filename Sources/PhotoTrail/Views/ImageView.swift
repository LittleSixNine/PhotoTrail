import SwiftUI
import UDF

struct ImageView: View {
    @Environment(Store<PhotoTrailState, PhotoTrailEvent>.self) var store
    @Environment(\.displayScale) var displayScale
    @State private var thumbnail: Image?
    @State private var thumbnailKey: PreviewKey?

    private struct PreviewKey: Hashable {
        let id: Int
        let path: String
        let scale: CGFloat
    }
    private var previewKey: PreviewKey? {
        store.mostSelected.map { PreviewKey(id: $0, path: store[$0].fullPath, scale: displayScale) }
    }

    var body: some View {
        Group {
            if let key = previewKey, thumbnailKey == key, let thumbnail {
                PhotoSelectionPreview(image: thumbnail, selectionCount: store.selection.count)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 96))
                    .opacity(0.18)
                    .padding()
            }
        }
        .task(id: previewKey) {
            guard let key = previewKey else { thumbnail = nil; thumbnailKey = nil; return }
            let loaded = await PhotoThumbnailCache.preview.image(
                for: store[key.id], scale: displayScale, maxDimension: 1024)
            guard !Task.isCancelled, previewKey == key else { return }
            thumbnail = loaded
            thumbnailKey = key
        }
    }
}

struct PhotoSelectionPreview: View {
    let image: Image
    let selectionCount: Int
    @Environment(\.colorSchemeContrast) private var contrast

    struct Backplate {
        let degrees: Double
        let offsetX: CGFloat
        let offsetY: CGFloat
    }

    // Fixed, same-size shapes: selecting more photos never loads more previews.
    private static let layers: [Backplate] = [
        .init(degrees: -2.3, offsetX: -2, offsetY: 2),
        .init(degrees: 1.8, offsetX: 2, offsetY: -2),
        .init(degrees: -1.2, offsetX: 1, offsetY: 3),
        .init(degrees: 0.8, offsetX: -3, offsetY: -2),
        .init(degrees: -0.5, offsetX: 3, offsetY: 1),
        .init(degrees: 2.6, offsetX: -1, offsetY: 2),
        .init(degrees: -1.7, offsetX: 2, offsetY: -3)
    ]

    static func backplates(for count: Int) -> ArraySlice<Backplate> {
        let layerCount = count < 2 ? 0 : count == 2 ? 1 : count < 10 ? 2 : 7
        return layers.prefix(layerCount)
    }

    var body: some View {
        GeometryReader { geometry in
            image.resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .background {
                    let plates = Self.backplates(for: selectionCount)
                    ZStack {
                        ForEach(plates.indices, id: \.self) { index in
                            let plate = plates[index]
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(.secondary.opacity(contrast == .increased ? 1 : 0.65),
                                                      lineWidth: contrast == .increased ? 1 : 0.75)
                                }
                                .rotationEffect(.degrees(plate.degrees))
                                .offset(x: plate.offsetX, y: plate.offsetY)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .overlay(alignment: .bottomTrailing) {
                    if selectionCount > 0 {
                        Text(L10n.text("已选 %1$@ 张", selectionCount))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                            .padding(7)
                            .accessibilityLabel(L10n.text("已选择 %1$@ 张照片", selectionCount))
                    }
                }
                // Reserve the same margin in every preset, including portrait photos and wide sidebars.
                .padding(max(16, max(geometry.size.width, geometry.size.height) * 0.04))
                .frame(width: geometry.size.width, height: geometry.size.height)
                .transaction { $0.animation = nil }
        }
    }
}

#Preview(traits: .store) {
    ImageView()
        .frame(width: 400, height: 300)
}

#Preview("image", traits: .select(11)    ) {
    ImageView()
        .frame(width: 400, height: 300)
}

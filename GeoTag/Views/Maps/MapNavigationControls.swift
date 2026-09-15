import SwiftUI

struct MapNavigationControls: View {
    let heading: Double
    let locating: Bool
    let locate: () -> Void
    let navigate: (String) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button(action: locate) {
                Group {
                    if locating { ProgressView().controlSize(.small) }
                    else { Image(systemName: "location.fill") }
                }.frame(width: 40, height: 40)
            }.disabled(locating)
                .glassEffect(.clear.interactive(), in: Circle())
                .help("回到本机位置")
                .accessibilityLabel("本机定位")
            HStack(alignment: .bottom, spacing: 10) {
                Button { navigate("north") } label: {
                    ZStack {
                        Image(systemName: "triangle.fill").font(.system(size: 7)).foregroundStyle(.red)
                            .offset(y: -13).rotationEffect(.degrees(-heading))
                        Text("北").font(.system(size: 12, weight: .medium))
                    }.frame(width: 40, height: 40)
                }.glassEffect(.clear.interactive(), in: Circle())
                    .help("回到正北")
                    .accessibilityLabel("指南针，回到正北")
                VStack(spacing: 0) {
                    Button { navigate("zoomIn") } label: {
                        Image(systemName: "plus").frame(width: 40, height: 38)
                    }.help("放大地图")
                    Divider().padding(.horizontal, 9)
                    Button { navigate("zoomOut") } label: {
                        Image(systemName: "minus").frame(width: 40, height: 38)
                    }.help("缩小地图")
                }.frame(width: 40).glassEffect(.clear.interactive(), in: Capsule())
            }
        }.buttonStyle(.plain)
    }
}

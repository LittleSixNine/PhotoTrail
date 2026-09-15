# GeoTag CN 开发说明

基于 marchyman/GeoTag v6.0.2（2663c879）。已接入高德地图点选、官方地点搜索和本地收藏；完整跨格式验收仍在进行。
原项目许可证见 LICENSE；坐标公式来源及许可证见 THIRD_PARTY_NOTICES.md。

## 构建与测试

需要支持 Swift 6.2、macOS 26 或更新 SDK 的完整 Xcode，以及 XcodeGen、SwiftLint。

```sh
xcodegen generate
xcodebuild -project GeoTag.xcodeproj -scheme GeoTag -configuration Debug -destination 'platform=macOS' build
node --test scripts/test-amap.mjs
swift test --package-path Coords
swift test --package-path Metadata
swift test --package-path Exiftool
swift test --package-path Imagetool
xcodebuild -project GeoTag.xcodeproj -scheme GeoTag -destination 'platform=macOS' \
  GEOTAG_CN_BUNDLE_ID=local.GeoTagCN.Validation -only-testing:GeoTagTests test
```

本机开发采用 ad-hoc 签名，应用名为 GeoTag CN，标识为 local.GeoTagCN，与原版分开。
分发所需的开发者签名、公证与发布流程尚未配置。

## 高德点选

1. 打开测试照片副本，选择照片右侧的“高德”。
2. 在“高德设置”中填写自己的 Web 端 JS API Key 和 securityJsCode，保存到本机专用钥匙串记录。
3. 选中可编辑照片，在地图点选位置。程序先查询行政区，再将 GCJ-02 本地转换为 WGS84；调用一次高德官方正向转换检查，回到点击点的误差须不大于 5 米。
4. 检查提示后保存，关闭并重新打开副本验证。新位置标记 GPSMapDatum=WGS-84、GPSProcessingMethod=MANUAL。

地图默认仍为 Apple。启用高德后，显示照片和校验选点会发送经纬度到高德；照片文件不会上传。
安全密钥会进入地图 JavaScript 运行环境；钥匙串仅保护本机存储。本原型采用官方文档中的开发方式，公开服务需要另行配置安全代理。

## 数据约定与范围

- 高德经纬度仅用于地图交互；高德确认的新位置写入照片前转换为 WGS84。
- 原照片未声明 GPSMapDatum 时，只暂按 WGS84 显示，不据此修改或补标原始坐标系。明确声明其他基准的照片不显示原标记。
- 仅修改日期或地址时，保留 GPS；用户显式开启原版“更新 GPS 时间戳”选项时仍按该设置更新 GPS 时间。
- 本原型仅允许高德行政区代码确认为中国大陆的选点，未知、境外及港澳台点暂不写入。公式的数值边界不是国界判断。
- 高德原型只显示主选照片，点选作用于全部选中可编辑照片。地址回填、全部照片标记、GPX 轨迹叠加尚未接入高德；这些原有功能仍在 Apple 地图中。
- 本地逆转换是近似算法。往返误差测试验证计算一致性，不能证明实际拍摄位置精度。每次官方正向复核也不替代真实地点验收。
- Photos 图库通过苹果接口更新位置，不能自行设置图库导出照片的 EXIF 基准标签；需另行验证导出行为。

## 验收要求

先用公开地点和生成图片完成点选→保存→重开，再用私人目录的照片副本验收。
至少验证 JPEG、HEIC、RAW+XMP，以及取消保存、断网、快速切换照片、连续点选。
真实服务测试需要有效凭据；未提供凭据时，仅运行公式、元数据和地图交互的离线测试，不把模拟测试写成实测通过。
私人照片、真实拍摄位置、凭据和构建日志放在工作区同级 geotag-cn-private，不提交到代码仓库。

## 搜索与收藏

照片右侧集中显示地图切换、状态、定位详情、搜索和收藏，可收起面板。
高德搜索使用官方 JS API 的 AMap.PlaceSearch，输入后显示候选地点；选中候选只预览，点击“应用”才修改选中照片的位置，仍需手动保存。
收藏支持名称、备注、编辑和删除，保存为 WGS84，存放在应用私有 Application Support/GeoTagCN/Favorites.json，独立于公开代码。点击收藏名称预览，点击“应用”设置选中照片的位置。读取失败时保留原文件并禁止覆盖。
高德标记使用内嵌 SVG，不依赖默认图标的外部资源加载。应用菜单、主要窗口、设置及提示已加入简体中文。

单元测试方案设置 GEOTAG_CN_OFFLINE_TESTS=1，不加载私人收藏、凭据或交互窗口。独立测试 bundle 标识避免打断日常应用；单元测试不等于真实界面或在线接口验收。

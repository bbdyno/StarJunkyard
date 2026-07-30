import SpriteKit
import UIKit

struct PixelViewport: Equatable {
    static let laneSize = CGSize(width: 360, height: 800)

    let sceneSize: CGSize
    let laneFrame: CGRect
    let safeFrame: CGRect
    let integerScale: Int

    var usesTabletRails: Bool {
        sceneSize.width - Self.laneSize.width >= 180
    }

    init(viewSize: CGSize, safeAreaInsets: UIEdgeInsets, nativeScale: CGFloat) {
        let density = max(1, nativeScale)
        let pixelWidth = max(Self.laneSize.width, floor(viewSize.width * density))
        let pixelHeight = max(Self.laneSize.height, floor(viewSize.height * density))
        integerScale = max(1, Int(floor(min(
            pixelWidth / Self.laneSize.width,
            pixelHeight / Self.laneSize.height
        ))))
        let unit = CGFloat(integerScale)
        sceneSize = CGSize(width: pixelWidth / unit, height: pixelHeight / unit)

        let lanePixelX = floor((pixelWidth - Self.laneSize.width * unit) / 2)
        let lanePixelY = floor((pixelHeight - Self.laneSize.height * unit) / 2)
        laneFrame = CGRect(
            x: lanePixelX / unit,
            y: lanePixelY / unit,
            width: Self.laneSize.width,
            height: Self.laneSize.height
        )

        let left = ceil(safeAreaInsets.left * density) / unit
        let right = ceil(safeAreaInsets.right * density) / unit
        let bottom = ceil(safeAreaInsets.bottom * density) / unit
        let top = ceil(safeAreaInsets.top * density) / unit
        safeFrame = CGRect(
            x: left,
            y: bottom,
            width: max(1, sceneSize.width - left - right),
            height: max(1, sceneSize.height - bottom - top)
        )
    }

    static let phoneFallback = PixelViewport(
        viewSize: laneSize,
        safeAreaInsets: .zero,
        nativeScale: 1
    )
}

@MainActor
protocol AdaptivePixelScene: AnyObject {
    func applyViewport(_ viewport: PixelViewport)
}

extension PixelViewport {
    @MainActor
    init(view: UIView) {
        self.init(
            viewSize: view.bounds.size,
            safeAreaInsets: view.safeAreaInsets,
            nativeScale: view.window?.screen.nativeScale ?? view.contentScaleFactor
        )
    }
}

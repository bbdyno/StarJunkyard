import SpriteKit

@MainActor
enum PixelArt {
    struct Block {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let color: SKColor
    }

    static func asset(_ identifier: String, scale: CGFloat = 1) -> SKSpriteNode {
        let texture = SKTexture(imageNamed: identifier)
        texture.filteringMode = .nearest
        let node = SKSpriteNode(texture: texture)
        node.name = identifier
        node.setScale(scale)
        return node
    }

    static func sprite(blocks: [Block], name: String) -> SKNode {
        let root = SKNode()
        root.name = name
        for block in blocks {
            let node = SKSpriteNode(
                color: block.color,
                size: CGSize(width: block.width, height: block.height)
            )
            node.anchorPoint = .zero
            node.position = CGPoint(x: block.x, y: block.y)
            root.addChild(node)
        }
        return root
    }

    static func panel(size: CGSize, name: String) -> SKNode {
        let width = Int(size.width)
        let height = Int(size.height)
        return sprite(blocks: [
            Block(x: 0, y: 0, width: width, height: height, color: PixelPalette.ink),
            Block(x: 2, y: 2, width: width - 4, height: height - 4, color: PixelPalette.darkIron),
            Block(x: 4, y: 4, width: width - 8, height: height - 8, color: PixelPalette.deepNavy),
            Block(x: 6, y: height - 7, width: 3, height: 3, color: PixelPalette.warningAmber),
            Block(x: width - 9, y: height - 7, width: 3, height: 3, color: PixelPalette.warningAmber)
        ], name: name)
    }
}

import SpriteKit

#if DEBUG
@MainActor
enum DebugPixelArt {
    struct Block {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let color: SKColor
    }

    static func sprite(blocks: [Block], name: String) -> SKNode {
        let root = SKNode()
        root.name = name
        for block in blocks {
            let node = SKSpriteNode(
                color: block.color,
                size: CGSize(width: block.width, height: block.height)
            )
            node.anchorPoint = CGPoint(x: 0, y: 0)
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

    static func mechanic() -> SKNode {
        sprite(blocks: [
            Block(x: 5, y: 0, width: 18, height: 6, color: PixelPalette.ink),
            Block(x: 7, y: 5, width: 15, height: 20, color: PixelPalette.darkIron),
            Block(x: 9, y: 23, width: 12, height: 12, color: PixelPalette.rust),
            Block(x: 10, y: 26, width: 10, height: 8, color: PixelPalette.sparkOrange),
            Block(x: 12, y: 29, width: 2, height: 2, color: PixelPalette.workWhite),
            Block(x: 7, y: 7, width: 4, height: 14, color: PixelPalette.teal),
            Block(x: 0, y: 10, width: 8, height: 8, color: PixelPalette.ink),
            Block(x: 1, y: 12, width: 9, height: 4, color: PixelPalette.lightIron),
            Block(x: 0, y: 13, width: 3, height: 2, color: PixelPalette.warningAmber)
        ], name: "mechanic_mo_debug")
    }

    static func rivetDrone() -> SKNode {
        sprite(blocks: [
            Block(x: 5, y: 8, width: 14, height: 14, color: PixelPalette.ink),
            Block(x: 7, y: 10, width: 10, height: 10, color: PixelPalette.teal),
            Block(x: 9, y: 13, width: 6, height: 4, color: PixelPalette.workWhite),
            Block(x: 11, y: 14, width: 3, height: 2, color: PixelPalette.warningAmber),
            Block(x: 3, y: 21, width: 18, height: 2, color: PixelPalette.lightIron),
            Block(x: 2, y: 23, width: 4, height: 2, color: PixelPalette.rust),
            Block(x: 18, y: 23, width: 4, height: 2, color: PixelPalette.rust),
            Block(x: 10, y: 3, width: 3, height: 6, color: PixelPalette.darkIron),
            Block(x: 7, y: 0, width: 3, height: 5, color: PixelPalette.sparkOrange),
            Block(x: 13, y: 0, width: 3, height: 5, color: PixelPalette.teal)
        ], name: "drone_riv0_debug")
    }

    static func enemy(id: String) -> SKNode {
        switch id {
        case "umbrella_crab":
            return sprite(blocks: [
                Block(x: 2, y: 10, width: 36, height: 5, color: PixelPalette.ink),
                Block(x: 5, y: 15, width: 30, height: 10, color: PixelPalette.workBlue),
                Block(x: 10, y: 5, width: 20, height: 12, color: PixelPalette.rust),
                Block(x: 5, y: 1, width: 5, height: 7, color: PixelPalette.darkIron),
                Block(x: 30, y: 1, width: 5, height: 7, color: PixelPalette.darkIron),
                Block(x: 17, y: 9, width: 3, height: 3, color: PixelPalette.workWhite)
            ], name: "enemy_umbrella_crab_debug")
        case "fan_bat":
            return sprite(blocks: [
                Block(x: 13, y: 8, width: 14, height: 14, color: PixelPalette.ink),
                Block(x: 15, y: 10, width: 10, height: 10, color: PixelPalette.lightIron),
                Block(x: 18, y: 11, width: 4, height: 8, color: PixelPalette.deepNavy),
                Block(x: 4, y: 11, width: 10, height: 5, color: PixelPalette.darkTeal),
                Block(x: 26, y: 11, width: 10, height: 5, color: PixelPalette.darkTeal),
                Block(x: 19, y: 14, width: 2, height: 2, color: PixelPalette.warningAmber)
            ], name: "enemy_fan_bat_debug")
        case "vending_knight":
            return sprite(blocks: [
                Block(x: 7, y: 3, width: 40, height: 52, color: PixelPalette.ink),
                Block(x: 10, y: 6, width: 34, height: 46, color: PixelPalette.darkRust),
                Block(x: 14, y: 31, width: 26, height: 16, color: PixelPalette.deepNavy),
                Block(x: 16, y: 34, width: 5, height: 5, color: PixelPalette.warningAmber),
                Block(x: 24, y: 34, width: 5, height: 5, color: PixelPalette.teal),
                Block(x: 32, y: 34, width: 5, height: 5, color: PixelPalette.memoryMagenta),
                Block(x: 20, y: 11, width: 14, height: 12, color: PixelPalette.lightIron)
            ], name: "elite_vending_knight_debug")
        case "cancrab_king":
            return sprite(blocks: [
                Block(x: 19, y: 12, width: 58, height: 48, color: PixelPalette.ink),
                Block(x: 23, y: 16, width: 50, height: 40, color: PixelPalette.rust),
                Block(x: 0, y: 23, width: 25, height: 28, color: PixelPalette.ink),
                Block(x: 3, y: 27, width: 20, height: 20, color: PixelPalette.darkIron),
                Block(x: 71, y: 23, width: 25, height: 28, color: PixelPalette.ink),
                Block(x: 73, y: 27, width: 20, height: 20, color: PixelPalette.sparkOrange),
                Block(x: 39, y: 31, width: 18, height: 12, color: PixelPalette.deepNavy),
                Block(x: 44, y: 35, width: 8, height: 5, color: PixelPalette.warningAmber),
                Block(x: 27, y: 4, width: 10, height: 10, color: PixelPalette.darkIron),
                Block(x: 60, y: 4, width: 10, height: 10, color: PixelPalette.darkIron)
            ], name: "boss_cancrab_king_debug")
        default:
            return sprite(blocks: [
                Block(x: 5, y: 8, width: 22, height: 14, color: PixelPalette.ink),
                Block(x: 7, y: 10, width: 18, height: 10, color: PixelPalette.midIron),
                Block(x: 10, y: 12, width: 12, height: 3, color: PixelPalette.rust),
                Block(x: 3, y: 3, width: 5, height: 7, color: PixelPalette.darkIron),
                Block(x: 24, y: 3, width: 5, height: 7, color: PixelPalette.darkIron),
                Block(x: 22, y: 14, width: 3, height: 3, color: PixelPalette.warningAmber)
            ], name: "enemy_can_bug_debug")
        }
    }
}
#endif

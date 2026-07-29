import Foundation

struct PCG32: Sendable {
    private(set) var state: UInt64
    let stream: UInt64

    init(seed: UInt64, stream: UInt64) {
        self.state = 0
        self.stream = stream
        _ = next()
        self.state = self.state &+ seed
        _ = next()
    }

    mutating func next() -> UInt32 {
        let oldState = state
        let increment = (stream &<< 1) | 1
        state = oldState &* 6_364_136_223_846_793_005 &+ increment
        let xorShifted = UInt32(truncatingIfNeeded: ((oldState >> 18) ^ oldState) >> 27)
        let rotation = UInt32(oldState >> 59)
        return (xorShifted >> rotation) | (xorShifted &<< ((0 &- rotation) & 31))
    }

    mutating func bounded(_ bound: UInt32) -> UInt32 {
        precondition(bound > 0)
        let threshold = (0 &- bound) % bound
        while true {
            let value = next()
            if value >= threshold {
                return value % bound
            }
        }
    }
}

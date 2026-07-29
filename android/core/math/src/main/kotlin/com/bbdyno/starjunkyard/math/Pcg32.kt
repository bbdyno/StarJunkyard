package com.bbdyno.starjunkyard.math

class Pcg32(seed: ULong, val stream: ULong) {
    var state: ULong = 0uL
        private set

    init {
        nextUInt()
        state += seed
        nextUInt()
    }

    fun nextUInt(): UInt {
        val oldState = state
        val increment = (stream shl 1) or 1uL
        state = oldState * 6_364_136_223_846_793_005uL + increment
        val xorShifted = (((oldState shr 18) xor oldState) shr 27).toUInt()
        val rotation = (oldState shr 59).toInt()
        return (xorShifted shr rotation) or (xorShifted shl ((-rotation) and 31))
    }

    fun bounded(bound: UInt): UInt {
        require(bound > 0u)
        val threshold = (0u - bound) % bound
        while (true) {
            val value = nextUInt()
            if (value >= threshold) return value % bound
        }
    }
}

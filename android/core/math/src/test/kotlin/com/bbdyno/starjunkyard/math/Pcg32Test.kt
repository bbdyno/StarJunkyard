package com.bbdyno.starjunkyard.math

import org.junit.Assert.assertEquals
import org.junit.Test

class Pcg32Test {
    @Test
    fun matchesSharedReferenceSequence() {
        val generator = Pcg32(seed = 42uL, stream = 54uL)
        val values = List(5) { generator.nextUInt().toLong() }

        assertEquals(
            listOf(2_707_161_783L, 2_068_313_097L, 3_122_475_824L, 2_211_639_955L, 3_215_226_955L),
            values,
        )
        assertEquals(9_440_484_487_994_590_321uL, generator.state)
    }
}

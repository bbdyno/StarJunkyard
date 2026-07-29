package com.bbdyno.starjunkyard.content

import org.junit.Assert.assertEquals
import org.junit.Test

class VerticalSliceDecoderTest {
    @Test
    fun decodesSharedTwentyStageSlice() {
        val stream = checkNotNull(javaClass.getResourceAsStream("/r1_vertical_slice.json"))
        val content = stream.bufferedReader().use { VerticalSliceDecoder.decode(it.readText()) }

        assertEquals("0.1.0", content.contentVersion)
        assertEquals((1..20).toList(), content.stages.map { it.number })
        assertEquals(5, content.enemies.size)
    }
}

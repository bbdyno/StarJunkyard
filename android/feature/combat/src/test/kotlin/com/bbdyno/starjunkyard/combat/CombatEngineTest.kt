package com.bbdyno.starjunkyard.combat

import com.bbdyno.starjunkyard.content.VerticalSliceDecoder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CombatEngineTest {
    @Test
    fun sharedContentDrivesAutomaticCombatAndOverclock() {
        val stream = checkNotNull(javaClass.getResourceAsStream("/r1_vertical_slice.json"))
        val content = stream.bufferedReader().use { VerticalSliceDecoder.decode(it.readText()) }
        val engine = CombatEngine(content)

        engine.activateOverclock()
        repeat(80) { engine.tick() }
        val snapshot = engine.snapshot()

        assertTrue(snapshot.stage >= 1)
        assertTrue(snapshot.credits > 0)
        assertTrue(snapshot.parts > 0)
        assertEquals(80, snapshot.tick)
        assertTrue(snapshot.overclockTicks > 0)
    }
}

import QtQuick
import QtTest
import "../ClockFreshness.js" as ClockFreshness

TestCase {
    name: "ClockFreshness"

    function test_resumeDetection_data() {
        return [
            { tag: "first observation", previousMs: -1, currentMs: 1000, expected: false },
            { tag: "normal minute", previousMs: 1000, currentMs: 61000, expected: false },
            { tag: "threshold boundary", previousMs: 1000, currentMs: 301000, expected: false },
            { tag: "past threshold", previousMs: 1000, currentMs: 301001, expected: true },
            { tag: "clock moved backward", previousMs: 301000, currentMs: 1000, expected: false }
        ];
    }

    function test_resumeDetection(data) {
        compare(
            ClockFreshness.resumeDetected(data.previousMs, data.currentMs, 300),
            data.expected
        );
    }

    function test_cacheAgeBoundaries() {
        const currentMs = 20000 * 1000;

        compare(ClockFreshness.cacheAgeSeconds(20000 - 10800, currentMs), 10800);
        verify(!ClockFreshness.cacheIsStale(20000 - 10800, currentMs, 10800));
        verify(ClockFreshness.cacheIsStale(20000 - 10801, currentMs, 10800));
        verify(ClockFreshness.cacheIsStale(20001, currentMs, 10800));
    }

    function test_postResumeGrace() {
        const currentMs = 20000 * 1000;
        const staleUpdatedAt = 20000 - 10801;
        const graceUntilMs = currentMs + 1200 * 1000;

        verify(ClockFreshness.resumeDetected(currentMs - 6 * 60 * 1000, currentMs, 300));
        verify(ClockFreshness.cacheIsStale(staleUpdatedAt, currentMs, 10800));
        verify(ClockFreshness.withinGracePeriod(currentMs, graceUntilMs));
        verify(!ClockFreshness.withinGracePeriod(graceUntilMs, graceUntilMs));
    }
}

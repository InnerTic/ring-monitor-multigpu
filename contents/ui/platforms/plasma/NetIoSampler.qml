import QtQuick
import org.kde.ksysguard.sensors as Sensors
import "../../core/DiskIoScale.js" as DiskIo

// Plasma source for the network throughput ring — the sibling of the
// disk-I/O sampler, satisfying the same surface (active / io) from
// ksysguard's network/all/{download,upload} byte/s sensors. ksysguard
// reports the RATE directly (no sample delta needed), so each tick just
// reads .value and scales it onto the arc via the shared DiskIoScale
// rolling peak. Download maps to the read half, upload to the write half,
// so split mode reads "down on the left, up on the right" like the disk
// ring's read|write. Sensors are `enabled: active` so ksysguard isn't
// subscribed while the ring is off-screen (same gate ProcessSampler
// uses). Split out of MetricsBackend.qml to keep that adapter under the
// 500-line cap.
//
// Public surface (mirrors the disk sampler byte-for-byte):
//   active  - gate; sampling runs only while true.
//   io      - { readBps, writeBps, combinedBps, readPercent, writePercent,
//              combinedPercent }. The *Bps are the real rates (MB/s label);
//              the *Percent drive the arc, each against its own rolling peak.

Item {
    id: sampler

    property bool active: false

    // Reactive on _tick (bumped each Timer tick). A property, not a function,
    // so a binding tracks it (core/CLAUDE.md "expose as a property").
    readonly property var io: {
        sampler._tick;
        return {
            "readBps": sampler._readBps,
            "writeBps": sampler._writeBps,
            "combinedBps": sampler._combinedBps,
            "readPercent": DiskIo.rateToPercent(sampler._readBps, sampler._peakRead),
            "writePercent": DiskIo.rateToPercent(sampler._writeBps, sampler._peakWrite),
            "combinedPercent": DiskIo.rateToPercent(sampler._combinedBps, sampler._peakCombined)
        };
    }

    property int _tick: 0
    property real _readBps: 0
    property real _writeBps: 0
    property real _combinedBps: 0
    // Per-component rolling peaks (the arc ceilings) — see DiskIoScale.updatePeak.
    property real _peakRead: 0
    property real _peakWrite: 0
    property real _peakCombined: 0

    // ksysguard byte/s rate sensors. enabled: active so the daemon isn't
    // subscribed while the ring is off-screen. On a host without these leaves
    // .value stays NaN (coerced to 0 below) — the ring just reads idle.
    Sensors.Sensor {
        id: downloadSensor
        sensorId: "network/all/download"
        enabled: sampler.active
    }
    Sensors.Sensor {
        id: uploadSensor
        sensorId: "network/all/upload"
        enabled: sampler.active
    }

    function _sample() {
        // Coerce an unread sensor (NaN/undefined before the first push) to 0 so
        // io.readBps matches the disk sampler surface (a finite number, never NaN).
        sampler._readBps = isFinite(downloadSensor.value) ? downloadSensor.value : 0;
        sampler._writeBps = isFinite(uploadSensor.value) ? uploadSensor.value : 0;
        sampler._combinedBps = DiskIo.combinedRate(sampler._readBps, sampler._writeBps);
        // Network traffic is typically far lighter than disk I/O (a home link is
        // 1-100 MB/s against a drive's hundreds), so the arc uses the lower
        // NET_PEAK_FLOOR_BPS — see DiskIoScale.js.
        sampler._peakRead = DiskIo.updatePeak(sampler._peakRead, sampler._readBps, DiskIo.NET_PEAK_FLOOR_BPS);
        sampler._peakWrite = DiskIo.updatePeak(sampler._peakWrite, sampler._writeBps, DiskIo.NET_PEAK_FLOOR_BPS);
        sampler._peakCombined = DiskIo.updatePeak(sampler._peakCombined, sampler._combinedBps, DiskIo.NET_PEAK_FLOOR_BPS);
        sampler._tick++;
    }

    function _reset() {
        // Zero the rates so a re-shown ring doesn't flash the last value; peaks
        // are KEPT so it resumes its learned scale (matches the disk sampler).
        sampler._readBps = 0;
        sampler._writeBps = 0;
        sampler._combinedBps = 0;
        sampler._tick++;
    }

    onActiveChanged: if (!active)
        sampler._reset()

    // 500 ms = the ksysguard daemon push cadence; snapshots .value + updates the
    // peaks. running: active is the "no background subscription" gate;
    // triggeredOnStart fills the ring immediately on show.
    Timer {
        interval: 500
        running: sampler.active
        repeat: true
        triggeredOnStart: true
        onTriggered: sampler._sample()
    }
}

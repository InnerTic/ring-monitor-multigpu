import QtQuick
import org.kde.ksysguard.sensors as Sensors

// Plasma tooltip-gated GPU detail sensors for the GPU ring hover tooltip
// (issue #71). Owns the dynamic Sensor instances for aggregate VRAM and
// per-device name/power/coreFrequency. Gated by `active` so the ksysguard
// daemon does not push these leaves when no tooltip is shown — same gate
// pattern as DiskPartitionSensors / ProcessSampler.
//
// Why aggregate sensors for VRAM but per-device for power/clock/name:
// ksysguard exposes `gpu/all/usedVram` + `gpu/all/totalVram` at the
// aggregate level, but has NO `gpu/all/power`, `gpu/all/coreFrequency`,
// or `gpu/all/name` — those leaves exist only per device
// (`gpu/gpuN/...`). The single-panel tooltip picks the first-Ready
// device for those three fields.
//
// Inputs:
//   gpuDeviceIds - sorted device bases from classifyDiscoveredIds()
//                  (e.g. ["gpu/gpu0"] or ["gpu/gpu1"]). Driven by
//                  MetricsBackend._gpuDeviceIds.
//   active       - true only while the GPU tooltip is shown. Gates every
//                  Sensor subscription so the daemon pushes nothing while
//                  no tooltip is up.
// Surface (forwarded by MetricsBackend):
//   details (readonly property var) - per-device {model, powerW, clockMhz},
//                                     aligned to gpuDeviceIds (split-GPU mode)
//   detail  (readonly property var) - {model, vramUsedBytes, vramTotalBytes, powerW, clockMhz}

Item {
    id: gpuDetail

    property var gpuDeviceIds: []
    property bool active: false

    property int _tick: 0

    // Aggregate VRAM — ksysguard exposes gpu/all/usedVram + totalVram as
    // uint64 bytes. These are the only aggregate-level VRAM leaves.
    Sensors.Sensor {
        id: vramUsedSensor
        sensorId: "gpu/all/usedVram"
        enabled: gpuDetail.active
        onValueChanged: gpuDetail._tick++
    }

    Sensors.Sensor {
        id: vramTotalSensor
        sensorId: "gpu/all/totalVram"
        enabled: gpuDetail.active
        onValueChanged: gpuDetail._tick++
    }

    // Per-device leaves: name (string), power (integer watts),
    // coreFrequency (integer MHz). The Instantiator rebuilds its
    // delegates whenever gpuDeviceIds changes (hot-plug / discovery).
    Instantiator {
        id: deviceInst
        model: gpuDetail.gpuDeviceIds
        delegate: Item {
            required property string modelData
            readonly property alias nameSensor: devName
            readonly property alias powerSensor: devPower
            readonly property alias clockSensor: devClock
            Sensors.Sensor {
                id: devName
                sensorId: modelData + "/name"
                enabled: gpuDetail.active
                onValueChanged: gpuDetail._tick++
            }
            Sensors.Sensor {
                id: devPower
                sensorId: modelData + "/power"
                enabled: gpuDetail.active
                onValueChanged: gpuDetail._tick++
            }
            Sensors.Sensor {
                id: devClock
                sensorId: modelData + "/coreFrequency"
                enabled: gpuDetail.active
                onValueChanged: gpuDetail._tick++
            }
        }
        onObjectAdded: gpuDetail._tick++
        onObjectRemoved: gpuDetail._tick++
    }

    // A ksysguard sensor's numeric value, or `fallback` when it hasn't
    // resolved (just-built, missing leaf, or daemon not yet reporting it).
    function _num(sensor, fallback) {
        if (sensor && sensor.status === Sensors.Sensor.Ready && typeof sensor.value === "number" && !isNaN(sensor.value))
            return sensor.value;
        return fallback;
    }

    // Per-device model/power/clock, aligned to gpuDeviceIds — the split-GPU
    // rings read this via MetricsBackend.gpuDetails. VRAM stays aggregate-only
    // (ksysguard has no per-device VRAM leaves), so it is merged there rather
    // than here. Reading _tick first makes every device sensor a reactive
    // dependency; readonly property var (not a function) keeps the binding live.
    readonly property var details: {
        gpuDetail._tick;
        var out = [];
        for (var i = 0; i < deviceInst.count; i++) {
            var d = deviceInst.objectAt(i);
            if (!d)
                continue;
            out.push({
                "model": (d.nameSensor.status === Sensors.Sensor.Ready && d.nameSensor.value) ? String(d.nameSensor.value) : undefined,
                "powerW": _num(d.powerSensor, undefined),
                "clockMhz": _num(d.clockSensor, undefined)
            });
        }
        return out;
    }

    // Detail object for the single-panel GPU tooltip (issue #71): aggregate
    // VRAM + the first Ready device's model/power/clock. Derived from
    // `details` so both tooltip paths share one per-device read. Reading
    // `details` (reactive on _tick) keeps this binding live too.
    readonly property var detail: {
        gpuDetail._tick;

        // Aggregate VRAM — use undefined when not Ready so buildStatRows
        // hides the row (0 would render as "0 B / 0 B", misleading).
        var vramUsed = _num(vramUsedSensor, undefined);
        var vramTotal = _num(vramTotalSensor, undefined);

        // First Ready device's model/power/clock. undefined when no device
        // is Ready yet — buildStatRows skips the row.
        var powerW = undefined;
        var clockMhz = undefined;
        var model = undefined;
        var ds = gpuDetail.details;
        for (var i = 0; i < ds.length; i++) {
            if (powerW === undefined && ds[i].powerW !== undefined)
                powerW = ds[i].powerW;
            if (clockMhz === undefined && ds[i].clockMhz !== undefined)
                clockMhz = ds[i].clockMhz;
            if (model === undefined && ds[i].model !== undefined)
                model = ds[i].model;
        }

        return {
            "model": model,
            "vramUsedBytes": vramUsed,
            "vramTotalBytes": vramTotal,
            "powerW": powerW,
            "clockMhz": clockMhz
        };
    }
}

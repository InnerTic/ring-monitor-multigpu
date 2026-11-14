import { test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert";

// Text-level guard for MainContent.qml's tooltip placement wiring.
//
// MainContent gains two linked features:
//   1. `windowAnchorCorner` (string) — injected by the standalone Main.qml;
//      empty string on Plasma (whose large overlay doesn't need Window-popup
//      placement control).
//   2. `_tooltipOpenRight` (readonly bool) — derived from windowAnchorCorner:
//      true when the widget is left-anchored (corner = "top-left" or
//      "bottom-left"), so the tooltip grows into the screen rather than off it.
//   3. All four tooltip instances (cpuTooltip, memTooltip, diskTooltip,
//      gpuTooltip) receive `openRight: content._tooltipOpenRight`.
//
// The derivation logic lives in a QML binding (not a JS module), so it can't
// be unit-tested via a Node require().  A text guard is the appropriate tool
// here — same rationale as config-store.test.mjs and standalone-theme.test.mjs.
// The QML binding tests in tst_MainContent.qml complement this by exercising
// the runtime behaviour (GridLayout sizing etc.); the derivation expression
// itself is asserted structurally here.

const __dirname = dirname(fileURLToPath(import.meta.url));
const MAIN_CONTENT = readFileSync(
    join(__dirname, "..", "contents", "ui", "core", "MainContent.qml"),
    "utf8"
);

// ── 1. windowAnchorCorner input ─────────────────────────────────────

test("MainContent declares property string windowAnchorCorner", () => {
    assert.match(
        MAIN_CONTENT,
        /property\s+string\s+windowAnchorCorner\s*:/,
        "MainContent.qml must declare 'property string windowAnchorCorner'"
    );
});

test("MainContent defaults windowAnchorCorner to the empty string", () => {
    // Default "" means Plasma (no corner pinning): tooltips default to openRight:
    // false — the same as before the feature was added.
    assert.match(
        MAIN_CONTENT,
        /property\s+string\s+windowAnchorCorner\s*:\s*""/,
        "MainContent.qml windowAnchorCorner must default to \"\""
    );
});

// ── 2. _tooltipOpenRight derivation ─────────────────────────────────
//
// The expression must test for the two left-anchored corners:
//   "top-left" → true, "bottom-left" → true
//   "top-right" → false, "bottom-right" → false, "" → false
//
// Assert the exact derivation expression; the QML runtime evaluates it as a
// reactive binding so each corner value produces the correct result
// automatically — the expression IS the specification.

test("MainContent declares readonly property bool _tooltipOpenRight", () => {
    assert.match(
        MAIN_CONTENT,
        /readonly\s+property\s+bool\s+_tooltipOpenRight\s*:/,
        "MainContent.qml must declare 'readonly property bool _tooltipOpenRight'"
    );
});

test("MainContent _tooltipOpenRight is true for top-left corner", () => {
    // The binding must include the literal string "top-left" as a trigger value.
    assert.match(
        MAIN_CONTENT,
        /_tooltipOpenRight\s*:.*"top-left"/,
        "MainContent._tooltipOpenRight must test for \"top-left\""
    );
});

test("MainContent _tooltipOpenRight is true for bottom-left corner", () => {
    // The binding must include the literal string "bottom-left" as a trigger value.
    assert.match(
        MAIN_CONTENT,
        /_tooltipOpenRight\s*:.*"bottom-left"/,
        "MainContent._tooltipOpenRight must test for \"bottom-left\""
    );
});

test("MainContent _tooltipOpenRight reads from content.windowAnchorCorner", () => {
    // Ensures the binding reads its own input (not a stale global) so the
    // reactive update fires when the corner changes.
    assert.match(
        MAIN_CONTENT,
        /_tooltipOpenRight\s*:.*content\.windowAnchorCorner/,
        "MainContent._tooltipOpenRight must be derived from content.windowAnchorCorner"
    );
});

// ── 3. Three tooltips each receive openRight: content._tooltipOpenRight ─

// ProcessTooltip for CPU ring
test("MainContent wires cpuTooltip openRight from content._tooltipOpenRight", () => {
    // The cpu tooltip is an armed ProcessTooltip; its openRight is wired from
    // the content-scope derived bool.  Search for 'openRight:' adjacent to
    // 'content._tooltipOpenRight' — the exact pattern used in the source.
    assert.match(
        MAIN_CONTENT,
        /openRight\s*:\s*content\._tooltipOpenRight/,
        "MainContent.qml must pass 'openRight: content._tooltipOpenRight' to the tooltips"
    );
});

// Count exactly four occurrences (cpuTooltip, memTooltip, diskTooltip, gpuTooltip).
test("MainContent passes openRight: content._tooltipOpenRight to all four tooltips", () => {
    const hits = [...MAIN_CONTENT.matchAll(/openRight\s*:\s*content\._tooltipOpenRight/g)];
    assert.strictEqual(
        hits.length,
        4,
        `Expected exactly 4 occurrences of 'openRight: content._tooltipOpenRight' (cpuTooltip, memTooltip, diskTooltip, gpuTooltip), got ${hits.length}`
    );
});

// ── 4. GPU tooltip wiring (#71) ─────────────────────────────────────
//
// The gpu tooltip arms on the aggregate gpu ring AND on every per-GPU usage
// ring produced by the splitGpuDevices expansion. Each armed delegate writes
// the content-scope _gpuTooltipHovered fan-in, and gpuDetailSamplingActive is
// bound to that fan-in so the gated detail sensors run only while some GPU
// tooltip is hovered.

test("MainContent instantiates a GpuTooltip armed on the aggregate and every per-GPU ring", () => {
    assert.match(
        MAIN_CONTENT,
        /GpuTooltip\s*\{[\s\S]*?armed\s*:\s*ringDelegate\._gpuArmed/,
        "MainContent.qml must instantiate GpuTooltip with armed: ringDelegate._gpuArmed"
    );
    assert.match(
        MAIN_CONTENT,
        /_gpuArmed\s*:\s*ringDelegate\.modelData\s*===\s*"gpu"\s*\|\|\s*ringDelegate\._isGpuUsage/,
        "MainContent._gpuArmed must cover the aggregate gpu ring and every per-GPU usage ring"
    );
});

test("MainContent reads metrics.gpuDetail only while the gpu tooltip samples", () => {
    // Gated on samplingActive so the backend's NVML/sysfs detail reads stay off
    // when no tooltip is up — mirrors the disk tooltip's details binding.
    assert.match(
        MAIN_CONTENT,
        /detail\s*:.*gpuTooltip\.samplingActive.*content\.metrics\.gpuDetail/,
        "GpuTooltip.detail must be gated on gpuTooltip.samplingActive and read content.metrics.gpuDetail"
    );
});

test("MainContent reads metrics.gpuProcesses only while the gpu tooltip samples", () => {
    assert.match(
        MAIN_CONTENT,
        /processes\s*:.*gpuTooltip\.samplingActive.*content\.metrics\.gpuProcesses/,
        "GpuTooltip.processes must be gated on gpuTooltip.samplingActive and read content.metrics.gpuProcesses"
    );
});

test("MainContent fans the GPU tooltip hover into gpuDetailSamplingActive", () => {
    assert.match(
        MAIN_CONTENT,
        /property\s*:\s*"_gpuTooltipHovered"[\s\S]*?value\s*:\s*gpuTooltip\.samplingActive[\s\S]*?when\s*:\s*ringDelegate\._gpuArmed/,
        "MainContent.qml must fan gpuTooltip.samplingActive into content._gpuTooltipHovered while armed"
    );
    assert.match(
        MAIN_CONTENT,
        /property\s*:\s*"gpuDetailSamplingActive"[\s\S]*?value\s*:\s*content\._gpuTooltipHovered[\s\S]*?when\s*:.*gpuDetailSamplingActive\s*!==\s*undefined/,
        "MainContent.qml must bind metrics.gpuDetailSamplingActive to content._gpuTooltipHovered"
    );
});

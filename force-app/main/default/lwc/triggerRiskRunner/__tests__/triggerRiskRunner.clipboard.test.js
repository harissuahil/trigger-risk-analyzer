/* eslint-disable @lwc/lwc/no-async-operation */
import { createElement } from "lwc";
import TriggerRiskRunner from "c/triggerRiskRunner";

import getTriggerNames from "@salesforce/apex/DeploymentAnalysisController.getTriggerNames";
import startRun from "@salesforce/apex/DeploymentAnalysisController.startRun";
import getRunStatus from "@salesforce/apex/DeploymentAnalysisController.getRunStatus";
import getRunItems from "@salesforce/apex/DeploymentAnalysisController.getRunItems";

// See triggerRiskRunner.test.js for full mock-pattern explanation.
// We mock all five Apex methods even though only four are exercised
// here, because the component imports getItemDetail at module load and
// without the virtual mock sfdx-lwc-jest fails to resolve the path.
jest.mock(
  "@salesforce/apex/DeploymentAnalysisController.getTriggerNames",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DeploymentAnalysisController.startRun",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DeploymentAnalysisController.getRunStatus",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DeploymentAnalysisController.getRunItems",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/DeploymentAnalysisController.getItemDetail",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flushPromises = () => new Promise((resolve) => setTimeout(resolve));

// ─────────────────────────────────────────────────────────────────────
// DOM query helpers
// ─────────────────────────────────────────────────────────────────────

// Find a lightning-button by its label. Same triple-fallback pattern
// proven across the other test files in this codebase.
function findButtonByLabel(element, label) {
  const buttons = [...element.shadowRoot.querySelectorAll("lightning-button")];
  return buttons.find(
    (b) =>
      b.label === label ||
      b.getAttribute("label") === label ||
      (b.textContent || "").trim() === label
  );
}

// ─────────────────────────────────────────────────────────────────────
// Test fixtures
// ─────────────────────────────────────────────────────────────────────

// Run status with BLOCKED gate decision and rich content. We use this
// shape so both summary and release-decision builders have realistic
// data to format. The summary cares about counts, overallRisk, and
// topRisks. The release-decision text cares about gate fields, top
// risks, architect impacts, rationale, and required fixes.
function blockedRunStatus() {
  return {
    status: "Done",
    totalTriggers: 1,
    processedTriggers: 1,
    highCount: 1,
    mediumCount: 0,
    lowCount: 0,
    overallRisk: "High",
    releaseDecision: "BLOCKED",
    policyProfile: "Standard",
    gateVersion: "7.0.1",
    releaseRecommendation: "NOT RECOMMENDED",
    architectImpacts: "Bulk/Limit Risk",
    releaseRationale:
      "1) SOQL inside loops can exceed governor limits under bulk load.",
    requiredFixes: "1) Move SOQL outside the loop and bulkify the query.",
    topRisks: ["SOQL inside loops may fail under bulk load."],
    executiveSummary:
      "EXECUTIVE SIGNAL:\n" +
      "- Overall Deployment Risk: High\n" +
      "\n" +
      "RELEASE GATE (Policy: Standard, Version: 7.0.1):\n" +
      "- Release Decision: BLOCKED\n" +
      "- Release Recommendation: NOT RECOMMENDED\n" +
      "\n" +
      "Rationale:\n" +
      "1) SOQL inside loops can exceed governor limits under bulk load.\n" +
      "\n" +
      "Required Fixes (to unblock release):\n" +
      "1) Move SOQL outside the loop and bulkify the query.\n",
    errorMessage: null,
    lastUpdated: new Date().toISOString(),
    completedAt: new Date().toISOString()
  };
}

// One BLOCKED finding row. Field shape from
// DeploymentAnalysisController.ItemRowDTO.
function blockedFindingRow() {
  return {
    itemId: "a01000000000001AAA",
    triggerName: "TRA_SoqlInLoop_Bad",
    severity: "High",
    severitySort: 3,
    ruleKeys: "SOQL_IN_LOOP",
    ruleLabel: "SOQL in Loop",
    category: "BulkRisk",
    lineNumber: 7,
    messageShort: "SOQL inside a loop can hit query limits.",
    hasSnippet: true
  };
}

// ─────────────────────────────────────────────────────────────────────
// Setup helper: drive the component to a completed BLOCKED run state
// so that summary and release-decision builders have data to format.
// ─────────────────────────────────────────────────────────────────────
async function setupCompletedBlockedRun() {
  const element = createElement("c-trigger-risk-runner", {
    is: TriggerRiskRunner
  });

  getTriggerNames.mockResolvedValue(["TRA_SoqlInLoop_Bad"]);
  document.body.appendChild(element);
  await flushPromises();

  const cb = element.shadowRoot.querySelector(
    'lightning-input[data-name="TRA_SoqlInLoop_Bad"]'
  );
  expect(cb).not.toBeNull();
  cb.checked = true;
  cb.dispatchEvent(new CustomEvent("change", { bubbles: false }));
  await flushPromises();

  startRun.mockResolvedValue("a02000000000001AAA");
  getRunStatus.mockResolvedValue(blockedRunStatus());
  getRunItems.mockResolvedValue([blockedFindingRow()]);

  // Click Run Analysis (the only lightning-button before run completes)
  const buttons = element.shadowRoot.querySelectorAll("lightning-button");
  expect(buttons.length).toBe(1);
  buttons[0].dispatchEvent(new CustomEvent("click", { bubbles: true }));

  await flushPromises();
  await flushPromises();
  await flushPromises();

  return element;
}

describe("c-trigger-risk-runner — copy to clipboard", () => {
  // ────────────────────────────────────────────────────────────────
  // Navigator and document.createElement state management
  //
  // The component's copy handlers branch on whether navigator.clipboard
  // is available:
  //
  //   if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
  //     await navigator.clipboard.writeText(text);
  //     return;
  //   }
  //   // textarea fallback path
  //   const ta = document.createElement("textarea");
  //   ta.value = text;
  //   document.body.appendChild(ta);
  //   ta.select();
  //   document.execCommand("copy");
  //   document.body.removeChild(ta);
  //
  // Tests 1 and 2 inject a writeText stub to exercise the modern path.
  // Test 3 deletes the stub to exercise the textarea fallback.
  //
  // We also spy on document.createElement to capture the fallback's
  // textarea — same pattern as the export test file. The spy lets us
  // assert WHAT was copied (textarea.value) and verify the textarea
  // was cleaned up (removed from the DOM body).
  //
  // jsdom doesn't implement HTMLTextAreaElement.select() reliably, so
  // we stub it on captured textareas to prevent it from throwing.
  // Same for document.execCommand which is deprecated and may be
  // undefined in newer jsdom. Both are wrapped to log call invocation
  // for assertion purposes.
  // ────────────────────────────────────────────────────────────────
  let originalClipboard;
  let originalCreateElement;
  let originalExecCommand;
  let createdTextareas;
  let writeTextMock;

  beforeEach(() => {
    // Track the original state so we can restore exactly in afterEach
    originalClipboard = navigator.clipboard;
    originalCreateElement = document.createElement.bind(document);
    originalExecCommand = document.execCommand;

    // Spy on createElement to capture textarea elements created by the
    // fallback path. We also stub .select() on the captured element
    // because jsdom doesn't reliably implement HTMLTextAreaElement.select.
    createdTextareas = [];
    document.createElement = jest.fn((tagName) => {
      const el = originalCreateElement(tagName);
      if (String(tagName).toLowerCase() === "textarea") {
        el.select = jest.fn();
        createdTextareas.push(el);
      }
      return el;
    });

    // Stub document.execCommand so the fallback path doesn't blow up
    // in jsdom (which may not implement it). jest.fn() also lets us
    // assert it was called with "copy".
    document.execCommand = jest.fn();

    // Default: provide a writeText stub for navigator.clipboard. Test 3
    // overrides this by deleting the property entirely.
    writeTextMock = jest.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText: writeTextMock },
      configurable: true,
      writable: true
    });
  });

  afterEach(() => {
    // Restore in reverse order
    if (originalClipboard === undefined) {
      delete navigator.clipboard;
    } else {
      Object.defineProperty(navigator, "clipboard", {
        value: originalClipboard,
        configurable: true,
        writable: true
      });
    }
    document.execCommand = originalExecCommand;
    document.createElement = originalCreateElement;

    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 1: Copy Summary uses navigator.clipboard with summary content
  //
  // SOURCE — copySummaryToClipboard:
  //   const summary = this.buildShareableSummary();
  //   if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
  //     await navigator.clipboard.writeText(summary);
  //     return;
  //   }
  //   // ... textarea fallback ...
  //
  // SOURCE — buildShareableSummary builds a multi-section text:
  //   "Trigger Risk Analysis completed.\n\n" +
  //   "Scope:\n" +
  //   `- Triggers selected: ${selected}\n` +
  //   `- Triggers analyzed: ${analyzed}\n\n` +
  //   "Findings overview:\n" +
  //   `- High severity: ${hi}\n` +
  //   ...
  //   "Overall assessment:\n" +
  //   `Overall Risk: ${risk}\n` +
  //   ...
  //
  // We assert on the multi-section structure (key headers + content
  // markers) rather than exact byte layout, so the test stays robust
  // to small formatting changes. The keystone is that buildShareableSummary
  // → navigator.clipboard.writeText pipeline produces the user-visible
  // summary text the user expects to paste into a ticket or Slack.
  // ─────────────────────────────────────────────────────────────────
  it("Copy Summary calls navigator.clipboard.writeText with shareable summary text", async () => {
    const element = await setupCompletedBlockedRun();

    // Sanity-check that setup actually drove the component to a
    // completed-run state. If any of these counts is wrong, the test's
    // failure signal in the assertions below would point at the
    // clipboard mechanics rather than at the broken setup, which would
    // be misleading. These three assertions act as a fast preflight.
    expect(startRun).toHaveBeenCalledTimes(1);
    expect(getRunStatus).toHaveBeenCalledTimes(1);
    expect(getRunItems).toHaveBeenCalledTimes(1);

    const copyBtn = findButtonByLabel(element, "Copy Summary");
    expect(copyBtn).toBeTruthy();
    copyBtn.dispatchEvent(new CustomEvent("click", { bubbles: true }));

    // Drain the async copy handler (awaits writeText)
    await flushPromises();
    await flushPromises();

    // The modern path was taken — writeText called exactly once
    expect(writeTextMock).toHaveBeenCalledTimes(1);

    // Capture the text passed to writeText for content assertions
    const copiedText = writeTextMock.mock.calls[0][0];

    // Header and section markers
    expect(copiedText).toContain("Trigger Risk Analysis completed.");
    expect(copiedText).toContain("Scope:");
    expect(copiedText).toContain("Findings overview:");
    expect(copiedText).toContain("Overall assessment:");

    // Content from the run status
    expect(copiedText).toContain("Triggers selected: 1");
    expect(copiedText).toContain("Triggers analyzed: 1");
    expect(copiedText).toContain("High severity: 1");
    expect(copiedText).toContain("Total findings: 1");
    expect(copiedText).toContain("Overall Risk: High");

    // Top risks line bridges from the run status into the summary
    expect(copiedText).toContain("SOQL inside loops may fail under bulk load.");

    // Belt-and-suspenders: the fallback path did NOT fire. No textarea
    // should have been created. If a future refactor accidentally
    // takes both paths (or takes the fallback when modern is available),
    // this assertion catches it.
    expect(createdTextareas.length).toBe(0);
    expect(document.execCommand).not.toHaveBeenCalled();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 2: Copy Release Decision uses navigator.clipboard with executive text
  //
  // SOURCE — copyReleaseDecisionToClipboard:
  //   const text = this.buildReleaseDecisionExecutiveText();
  //   if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
  //     await navigator.clipboard.writeText(text);
  //     return;
  //   }
  //
  // SOURCE — buildReleaseDecisionExecutiveText builds the CAB-friendly
  // executive output:
  //   "Release Decision (Executive)\n" +
  //   `Build: ${TRA_BUILD_LABEL}\n` +
  //   "===========================\n\n" +
  //   `Gate Outcome: ${this.releaseGateDecisionLabel}\n` +
  //   `Overall Risk: ${risk}\n` +
  //   ...
  //   "Architect Impacts:\n" +
  //   "Top Risks:\n" +
  //   "Rationale:\n" +
  //   ...
  //
  // Why this matters: this text is intended for CAB / audit evidence.
  // It shares structural elements with the Release Decision Export
  // file (Test 4 in export.test.js) but is shorter and oriented for
  // pasting into Slack/email rather than file artifact. The two paths
  // must produce coherent, distinct outputs — this test locks down
  // that the clipboard text contains the executive markers, separate
  // from but adjacent to the file export.
  // ─────────────────────────────────────────────────────────────────
  it("Copy Release Decision calls navigator.clipboard.writeText with executive text", async () => {
    const element = await setupCompletedBlockedRun();

    // Same setup preflight as Test 1 — proves we reached completed
    // run state before exercising the clipboard handler.
    expect(startRun).toHaveBeenCalledTimes(1);
    expect(getRunStatus).toHaveBeenCalledTimes(1);
    expect(getRunItems).toHaveBeenCalledTimes(1);

    const copyBtn = findButtonByLabel(element, "Copy Release Decision");
    expect(copyBtn).toBeTruthy();
    copyBtn.dispatchEvent(new CustomEvent("click", { bubbles: true }));

    await flushPromises();
    await flushPromises();

    expect(writeTextMock).toHaveBeenCalledTimes(1);
    const copiedText = writeTextMock.mock.calls[0][0];

    // Top-level structure
    expect(copiedText).toContain("Release Decision (Executive)");
    expect(copiedText).toContain("Build: GOLD Phase 7 Validated");

    // Gate fields
    expect(copiedText).toContain("Gate Outcome: BLOCKED");
    expect(copiedText).toContain("Overall Risk: High");
    expect(copiedText).toContain("Release Recommendation: BLOCKED");
    expect(copiedText).toContain("Policy: Standard (7.0.1)");

    // Section headers from the executive structure
    expect(copiedText).toContain("Architect Impacts:");
    expect(copiedText).toContain("Top Risks:");
    expect(copiedText).toContain("Rationale:");

    // Content bridged from the gate fields
    expect(copiedText).toContain("Bulk/Limit Risk");
    expect(copiedText).toContain("SOQL inside loops may fail under bulk load.");
    expect(copiedText).toContain(
      "SOQL inside loops can exceed governor limits under bulk load."
    );

    // No fallback textarea was created
    expect(createdTextareas.length).toBe(0);
    expect(document.execCommand).not.toHaveBeenCalled();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 3: When navigator.clipboard is unavailable, fallback uses textarea
  //
  // SOURCE — fallback path in copySummaryToClipboard:
  //   const ta = document.createElement("textarea");
  //   ta.value = summary;
  //   ta.style.position = "fixed";
  //   ta.style.left = "-9999px";
  //   document.body.appendChild(ta);
  //   ta.select();
  //   document.execCommand("copy");
  //   document.body.removeChild(ta);
  //
  // The component checks `navigator && navigator.clipboard &&
  // navigator.clipboard.writeText` — if any link is missing, it falls
  // through to the textarea-based copy. This test forces the fallback
  // by deleting navigator.clipboard, then verifies the full DOM dance
  // happens correctly:
  //
  //   1. A textarea element is created
  //   2. Its value contains the summary text
  //   3. Off-screen positioning is applied (so users don't see it flash)
  //   4. select() is called on the textarea
  //   5. document.execCommand("copy") fires
  //   6. The textarea is removed from document.body afterward
  //
  // We test the fallback only on Copy Summary because both buttons share
  // identical fallback code. Testing both would double the test count
  // without adding regression coverage.
  //
  // Why this matters: in non-secure-context iframes, older browsers, or
  // certain enterprise locked-down environments, navigator.clipboard
  // may genuinely be unavailable. The fallback is the user's only
  // working copy mechanism in those cases — silently breaking it would
  // leave users with no way to share findings.
  // ─────────────────────────────────────────────────────────────────
  it("Copy falls back to textarea + execCommand when navigator.clipboard is unavailable", async () => {
    // Force the fallback path by removing navigator.clipboard entirely.
    // The component's guard `navigator && navigator.clipboard &&
    // navigator.clipboard.writeText` will short-circuit on the second
    // term and skip to the textarea fallback.
    delete navigator.clipboard;

    const element = await setupCompletedBlockedRun();

    const copyBtn = findButtonByLabel(element, "Copy Summary");
    expect(copyBtn).toBeTruthy();
    copyBtn.dispatchEvent(new CustomEvent("click", { bubbles: true }));

    await flushPromises();
    await flushPromises();

    // The modern path's writeText must NOT have been called — we
    // deleted navigator.clipboard, so writeTextMock was never accessible.
    expect(writeTextMock).not.toHaveBeenCalled();

    // Exactly one textarea should have been created and captured
    expect(createdTextareas.length).toBe(1);
    const ta = createdTextareas[0];

    // The textarea value contains the summary text. We assert on a
    // strong content marker rather than exact equality so the test
    // stays robust to small summary formatting changes.
    expect(ta.value).toContain("Trigger Risk Analysis completed.");
    expect(ta.value).toContain("Overall Risk: High");

    // Off-screen positioning applied — the user never sees the textarea
    // flash on screen. If a regression drops the positioning, the
    // textarea would briefly appear visually, which would be jarring.
    expect(ta.style.position).toBe("fixed");
    expect(ta.style.left).toBe("-9999px");

    // select() was called on the textarea (we stubbed it on capture)
    expect(ta.select).toHaveBeenCalledTimes(1);

    // execCommand("copy") fired
    expect(document.execCommand).toHaveBeenCalledTimes(1);
    expect(document.execCommand).toHaveBeenCalledWith("copy");

    // The textarea was removed from document.body after the copy
    // completed. The component does:
    //   document.body.appendChild(ta);
    //   ta.select();
    //   document.execCommand("copy");
    //   document.body.removeChild(ta);
    // After this sequence, the textarea must NOT be a child of body —
    // a regression that drops the removeChild would leak DOM nodes.
    expect(document.body.contains(ta)).toBe(false);
  });
});

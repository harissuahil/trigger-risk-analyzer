/* eslint-disable @lwc/lwc/no-async-operation */
import { createElement } from "lwc";
import TriggerRiskRunner from "c/triggerRiskRunner";
import getTriggerNames from "@salesforce/apex/DeploymentAnalysisController.getTriggerNames";
import startRun from "@salesforce/apex/DeploymentAnalysisController.startRun";
import getRunStatus from "@salesforce/apex/DeploymentAnalysisController.getRunStatus";
import getRunItems from "@salesforce/apex/DeploymentAnalysisController.getRunItems";
// Note: getItemDetail is NOT imported here because we do not assert against it.
// The jest.mock(...) below is still required because the component itself
// imports getItemDetail — without the mock, the component import would fail
// to resolve under sfdx-lwc-jest.

// The automatic moduleNameMapper in jest.config.js maps all @salesforce/apex/*
// imports to the same apex.js stub, which exports a plain function — not a
// jest.fn(). Plain functions do not have mockResolvedValue.
//
// We override with explicit jest.mock() PER METHOD so each import gets its own
// jest.fn() instance that supports mockResolvedValue/mockRejectedValue.
//
// { virtual: true } is required — these module paths don't exist as real files.
// The factory must return { default: jest.fn() } because @lwc/jest-transformer
// accesses .default on required modules. Returning jest.fn() directly gives
// undefined when the transformer does require('...').default.
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

// Drain all pending microtasks by yielding to a macrotask.
// Called multiple times to handle deeply chained async calls:
//   runAnalysis → startRun → refreshRun → getRunStatus → getRunItems
const flushPromises = () => new Promise((resolve) => setTimeout(resolve));

// ─────────────────────────────────────────────────────────────────────
// DOM query helpers
// ─────────────────────────────────────────────────────────────────────

// Find a .badge element whose trimmed text content matches the given label.
// This is stronger than querySelector('.badge') which returns the first match
// regardless of content. The release gate card and executive signal area both
// render badge-class spans — we want the one displaying the specific decision.
function findBadgeByLabel(element, label) {
  return [...element.shadowRoot.querySelectorAll(".badge")].find(
    (el) => (el.textContent || "").trim() === label
  );
}

// Find the Run Analysis button.
// Before any run, lightning-button appears exactly once in the shadow DOM —
// the export/copy buttons are inside <template if:true={runId}> which is
// null until after the run completes. We explicitly assert exactly one
// button exists so that if a future UI change adds another pre-run button,
// this test fails with a clear reason instead of silently clicking the
// wrong button.
// Note: btn.label property access is unreliable in sfdx-lwc-jest 7.x stubs
// because the LWC engine sets props through its vnode system rather than
// as directly readable JS properties on the stub element.
function findRunButton(element) {
  const buttons = element.shadowRoot.querySelectorAll("lightning-button");
  expect(buttons.length).toBe(1);
  return buttons[0];
}

// Find a .metaChip element whose text includes the given substring.
// Used to verify policy and version chips in the gate card.
function findChipByText(element, text) {
  return [...element.shadowRoot.querySelectorAll(".metaChip")].find((el) =>
    (el.textContent || "").includes(text)
  );
}

// ─────────────────────────────────────────────────────────────────────
// Shared helper: create the component, load one trigger, select it,
// and run an analysis against a given getRunStatus response.
// ─────────────────────────────────────────────────────────────────────
async function runAnalysisWithStatus(runStatusOverrides) {
  const element = createElement("c-trigger-risk-runner", {
    is: TriggerRiskRunner
  });

  getTriggerNames.mockResolvedValue(["TRA_Test"]);
  document.body.appendChild(element);
  await flushPromises();

  // Select the trigger so isRunDisabled becomes false
  const cb = element.shadowRoot.querySelector(
    'lightning-input[data-name="TRA_Test"]'
  );
  expect(cb).not.toBeNull();
  cb.checked = true;
  cb.dispatchEvent(new CustomEvent("change", { bubbles: false }));
  await flushPromises();

  // Wire up run mocks — baseline is a clean APPROVED with no gate data
  startRun.mockResolvedValue("testRunId");
  getRunStatus.mockResolvedValue({
    status: "Done",
    totalTriggers: 1,
    processedTriggers: 1,
    highCount: 0,
    mediumCount: 0,
    lowCount: 0,
    overallRisk: "Low",
    releaseDecision: null,
    policyProfile: null,
    gateVersion: null,
    releaseRecommendation: null,
    architectImpacts: null,
    releaseRationale: null,
    requiredFixes: null,
    topRisks: [],
    executiveSummary: null,
    errorMessage: null,
    lastUpdated: new Date().toISOString(),
    completedAt: new Date().toISOString(),
    ...runStatusOverrides
  });
  getRunItems.mockResolvedValue([]);

  // Find Run Analysis by label property — must be defined before clicking
  const btn = findRunButton(element);
  expect(btn).toBeDefined();
  btn.dispatchEvent(new CustomEvent("click", { bubbles: true }));

  // Flush multiple times to drain the full async chain
  await flushPromises();
  await flushPromises();
  await flushPromises();

  // Verify the UI called the correct Apex methods with the correct arguments.
  // This proves the component is driving the run flow correctly, not just
  // rendering whatever the mocks return.
  expect(startRun).toHaveBeenCalledWith({
    releaseLabel: expect.stringMatching(/^R-\d{4}\.\d{2}\.\d{2}$/),
    triggerNames: ["TRA_Test"]
  });
  expect(getRunStatus).toHaveBeenCalledWith({ runId: "testRunId" });
  expect(getRunItems).toHaveBeenCalledWith({ runId: "testRunId" });

  return element;
}

describe("c-trigger-risk-runner — gate display and field priority", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 1: Structured BLOCKED field → badge-high + correct label
  //
  // SOURCE: releaseGateBadgeClass getter:
  //   if (d === 'BLOCKED') return 'badge badge-high';
  // SOURCE: releaseGateDecisionLabel getter:
  //   returns d (the raw decision string) for BLOCKED
  // ─────────────────────────────────────────────────────────────────
  it("renders BLOCKED label with badge-high class when structured releaseDecision is BLOCKED", async () => {
    const element = await runAnalysisWithStatus({
      highCount: 1,
      overallRisk: "High",
      releaseDecision: "BLOCKED",
      policyProfile: "Standard",
      gateVersion: "7.0.1",
      releaseRecommendation: "NOT RECOMMENDED"
    });

    await flushPromises();

    // Find by displayed text to ensure we're checking the right badge
    const badge = findBadgeByLabel(element, "BLOCKED");
    expect(badge).toBeTruthy();
    expect(badge.classList.contains("badge-high")).toBe(true);
    expect(badge.classList.contains("badge-low")).toBe(false);

    // Also confirm structured policy/version chips rendered correctly
    expect(findChipByText(element, "Policy: Standard")).toBeTruthy();
    expect(findChipByText(element, "Version: 7.0.1")).toBeTruthy();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 2: APPROVED_WITH_CONDITIONS → badge-medium + display label
  //
  // SOURCE: releaseGateDecisionLabel getter:
  //   if (d === 'APPROVED_WITH_CONDITIONS') return 'APPROVED WITH CONDITIONS';
  // SOURCE: releaseGateBadgeClass getter:
  //   if (d === 'APPROVED_WITH_CONDITIONS') return 'badge badge-medium';
  //
  // This is the third core Phase 4 outcome. The component intentionally
  // converts the raw value to a human-readable display label — both the
  // label and the styling must be verified together.
  // ─────────────────────────────────────────────────────────────────
  it("renders APPROVED WITH CONDITIONS label with badge-medium class", async () => {
    const element = await runAnalysisWithStatus({
      mediumCount: 1,
      overallRisk: "Medium",
      releaseDecision: "APPROVED_WITH_CONDITIONS",
      policyProfile: "Standard",
      gateVersion: "7.0.1",
      releaseRecommendation: "PROCEED WITH CAUTION"
    });

    await flushPromises();

    // Component converts raw value to display label 'APPROVED WITH CONDITIONS'
    const badge = findBadgeByLabel(element, "APPROVED WITH CONDITIONS");
    expect(badge).toBeTruthy();
    expect(badge.classList.contains("badge-medium")).toBe(true);
    expect(badge.classList.contains("badge-high")).toBe(false);
    expect(badge.classList.contains("badge-low")).toBe(false);
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 3: Structured field wins over conflicting summary text
  //
  // SOURCE: refreshRun() order in the component:
  //   1. parseReleaseGateFromSummary(executiveSummary) → sets APPROVED
  //   2. structured field override (not null) → sets BLOCKED
  // BLOCKED must be the displayed value after both steps run.
  //
  // This directly validates the architecture fix: structured fields
  // now override summary-text parsing when present.
  // ─────────────────────────────────────────────────────────────────
  it("structured releaseDecision overrides conflicting summary-parsed value", async () => {
    const element = await runAnalysisWithStatus({
      highCount: 1,
      overallRisk: "High",
      releaseDecision: "BLOCKED", // structured: BLOCKED
      policyProfile: "Standard",
      gateVersion: "7.0.1",
      releaseRecommendation: "NOT RECOMMENDED",
      // summary text: APPROVED
      executiveSummary:
        "RELEASE GATE (Policy: Standard, Version: 7.0.1):\n" +
        "- Release Decision: APPROVED\n" +
        "- Release Recommendation: PROCEED\n"
    });

    await flushPromises();

    // BLOCKED (structured) must win — APPROVED badge must not exist
    const blockedBadge = findBadgeByLabel(element, "BLOCKED");
    expect(blockedBadge).toBeTruthy();
    expect(blockedBadge.classList.contains("badge-high")).toBe(true);

    const approvedBadge = findBadgeByLabel(element, "APPROVED");
    expect(approvedBadge).toBeFalsy();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 4: Summary parsing fires as fallback when structured fields null
  //
  // SOURCE: refreshRun() fallback — parseReleaseGateFromSummary()
  // extracts releaseDecision, policyProfile, and gateVersion from text
  // when structured fields come back null from getRunStatus().
  //
  // This validates that older DAR records (created before the structured
  // fields existed) still render the gate card correctly.
  // Also asserts Policy and Version chips — confirming the parser
  // extracted the full gate block, not just the decision.
  // ─────────────────────────────────────────────────────────────────
  it("falls back to summary parsing and renders policy and version chips when structured fields are null", async () => {
    const element = await runAnalysisWithStatus({
      highCount: 0,
      overallRisk: "Low",
      releaseDecision: null, // null → trigger summary fallback
      policyProfile: null,
      gateVersion: null,
      executiveSummary:
        "RELEASE GATE (Policy: Standard, Version: 7.0.1):\n" +
        "- Release Decision: APPROVED\n" +
        "- Release Recommendation: PROCEED\n"
    });

    await flushPromises();

    // APPROVED decision was parsed from summary → badge-low
    const badge = findBadgeByLabel(element, "APPROVED");
    expect(badge).toBeTruthy();
    expect(badge.classList.contains("badge-low")).toBe(true);

    // Policy and Version were also parsed — confirm chips render
    const policyChip = findChipByText(element, "Policy: Standard");
    const versionChip = findChipByText(element, "Version: 7.0.1");
    expect(policyChip).toBeTruthy();
    expect(versionChip).toBeTruthy();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 5: Structured releaseRationale and requiredFixes render to DOM
  //
  // The Phase 5 architecture fix added 8 structured fields, not just 3.
  // Tests 1-4 cover releaseDecision / policyProfile / gateVersion.
  // This test covers the remaining structured-field rendering path:
  // Release_Rationale__c → releaseRationale → gate rationale section
  // Required_Fixes__c    → requiredFixes    → required fixes section
  // This verifies that structured gate fields from the DTO reach the rendered UI.
  // Uses textContent.toContain() so the test stays robust to changes in
  // the exact getter names or DOM structure — what matters is that the
  // text the gate engine produced reaches the user.
  // ─────────────────────────────────────────────────────────────────
  it("renders structured rationale and required fixes from gate fields", async () => {
    const element = await runAnalysisWithStatus({
      highCount: 1,
      overallRisk: "High",
      releaseDecision: "BLOCKED",
      policyProfile: "Standard",
      gateVersion: "7.0.1",
      releaseRecommendation: "NOT RECOMMENDED",
      releaseRationale:
        "1) SOQL inside loops can exceed governor limits under bulk load.",
      requiredFixes: "1) Move SOQL outside the loop and bulkify the query."
    });

    await flushPromises();

    // Both structured strings must appear in the rendered DOM
    expect(element.shadowRoot.textContent).toContain(
      "SOQL inside loops can exceed governor limits under bulk load."
    );
    expect(element.shadowRoot.textContent).toContain(
      "Move SOQL outside the loop and bulkify the query."
    );
  });
});

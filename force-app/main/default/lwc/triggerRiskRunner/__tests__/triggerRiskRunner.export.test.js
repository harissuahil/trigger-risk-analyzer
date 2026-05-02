/* eslint-disable @lwc/lwc/no-async-operation */
import { createElement } from "lwc";
import TriggerRiskRunner from "c/triggerRiskRunner";

import getTriggerNames from "@salesforce/apex/DeploymentAnalysisController.getTriggerNames";
import startRun from "@salesforce/apex/DeploymentAnalysisController.startRun";
import getRunStatus from "@salesforce/apex/DeploymentAnalysisController.getRunStatus";
import getRunItems from "@salesforce/apex/DeploymentAnalysisController.getRunItems";

// See triggerRiskRunner.test.js for full explanation of these mocks.
// Same pattern: { virtual: true } and factory returning { default: jest.fn() }
// because the @lwc/jest-transformer accesses .default on required modules
// and the module paths don't exist as real files on disk.
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

// Find a lightning-button by its label.
//
// The sfdx-lwc-jest stub for lightning-button has historically been
// inconsistent about how the label="..." template attribute surfaces:
//   - Sometimes readable as a JS property (b.label)
//   - Sometimes readable only as a DOM attribute (b.getAttribute('label'))
//   - Sometimes only present in textContent
//
// We check all three to make the helper robust across stub variations.
// If none match, returns undefined and the caller's assertions will fail
// with a clear message rather than silently picking the wrong button.
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
// Test data builders
// ─────────────────────────────────────────────────────────────────────

// One BLOCKED finding row that flows from getRunItems → exportCsv.
// Field shape verified from DeploymentAnalysisController.ItemRowDTO.
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

// Full BLOCKED-status payload that exercises the gate fields. Used by
// the CSV-with-findings and ReleaseDecision tests to confirm the export
// content includes the same fields shown in the UI.
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

// ─────────────────────────────────────────────────────────────────────
// Shared setup: create the component, load triggers, select one,
// and run an analysis. Returns the element after the run completes.
// ─────────────────────────────────────────────────────────────────────
async function setupCompletedRun(runStatus, items) {
  const element = createElement("c-trigger-risk-runner", {
    is: TriggerRiskRunner
  });

  getTriggerNames.mockResolvedValue(["TRA_SoqlInLoop_Bad"]);
  document.body.appendChild(element);
  await flushPromises();

  // Select the trigger
  const cb = element.shadowRoot.querySelector(
    'lightning-input[data-name="TRA_SoqlInLoop_Bad"]'
  );
  expect(cb).not.toBeNull();
  cb.checked = true;
  cb.dispatchEvent(new CustomEvent("change", { bubbles: false }));
  await flushPromises();

  startRun.mockResolvedValue("a02000000000001AAA");
  getRunStatus.mockResolvedValue(runStatus);
  getRunItems.mockResolvedValue(items);

  // Click Run Analysis (the only lightning-button before run completes)
  const buttons = element.shadowRoot.querySelectorAll("lightning-button");
  expect(buttons.length).toBe(1);
  buttons[0].dispatchEvent(new CustomEvent("click", { bubbles: true }));

  // Drain the runAnalysis → startRun → refreshRun → getRunStatus → getRunItems chain
  await flushPromises();
  await flushPromises();
  await flushPromises();

  return element;
}

describe("c-trigger-risk-runner — export buttons", () => {
  // We spy on document.createElement to capture the <a> element that
  // downloadTextFile() creates. The text content lives in the href as a
  // URL-encoded data URI; the filename lives in the download attribute;
  // the MIME type is the literal prefix between "data:" and ",".
  //
  // WHY NOT spy on TriggerRiskRunner.prototype.downloadTextFile:
  //   The LWC compiler emits component class methods as non-configurable
  //   properties, so jest.spyOn rejects them with:
  //     "Cannot assign to read only property 'downloadTextFile'"
  //   Spying on document.createElement is the standard fallback for
  //   verifying file downloads in LWC Jest.
  //
  // We also stub element.click = jest.fn() on captured anchors. This
  // prevents jsdom from logging "Not implemented: navigation (except
  // hash changes)" warnings every time downloadTextFile triggers the
  // download, AND lets us assert that click was actually called — a
  // meaningful contract check (created anchor + non-fired click would
  // mean the download never happened in the browser).
  //
  // Each captured anchor exposes:
  //   anchor.href     — full data: URI (we decode for content assertions)
  //   anchor.download — filename
  //   anchor.click    — jest.fn() stub we assert was invoked
  //
  // Helpers:
  //   anchorText(anchor) — decodes the URL-encoded text from the data URI
  //   anchorMime(anchor) — extracts MIME from the data URI prefix
  let createdAnchors;
  let originalCreateElement;

  // Pull the text content out of a captured anchor's data URI.
  // Source: downloadTextFile builds href as:
  //   `data:application/octet-stream;charset=utf-8,${encodeURIComponent(safeText)}`
  function anchorText(anchor) {
    const href = anchor.href || "";
    const commaIdx = href.indexOf(",");
    if (commaIdx < 0) return "";
    return decodeURIComponent(href.substring(commaIdx + 1));
  }

  // Pull the MIME type out of a captured anchor's data URI.
  function anchorMime(anchor) {
    const href = anchor.href || "";
    if (!href.startsWith("data:")) return "";
    const commaIdx = href.indexOf(",");
    if (commaIdx < 0) return "";
    return href.substring("data:".length, commaIdx);
  }

  beforeEach(() => {
    createdAnchors = [];
    originalCreateElement = document.createElement.bind(document);

    // Replace document.createElement with a wrapper that captures
    // anchor elements so we can assert on their final href/download
    // attributes after downloadTextFile() runs them. We also stub
    // element.click to a jest.fn() — this prevents jsdom from
    // attempting navigation (which logs noisy warnings in this
    // environment) AND lets each test verify click was actually
    // invoked as part of the download contract.
    document.createElement = jest.fn((tagName) => {
      const element = originalCreateElement(tagName);
      if (String(tagName).toLowerCase() === "a") {
        element.click = jest.fn();
        createdAnchors.push(element);
      }
      return element;
    });
  });

  afterEach(() => {
    document.createElement = originalCreateElement;
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 1: Export CSV does not produce a file before a run completes
  //
  // EXPORT CONTRACT: a CSV export must only happen for a completed run.
  // No run, no file. This protects against managers/auditors getting
  // partial or empty artifacts.
  //
  // SOURCE — disableExport getter:
  //   const canExport = !!this.runId && this.isRunComplete;
  //   return this.isLoading || !canExport;
  // SOURCE — isRunComplete getter:
  //   return this.status === 'Done' || this.status === 'Failed';
  //
  // Before any run, runId is null → canExport=false → disabled=true.
  // The button being disabled is the real protection; we also assert
  // downloadTextFile was not called as a belt-and-suspenders contract
  // check.
  //
  // Note: the Export CSV button is inside <template if:true={runId}>,
  // so before a run starts it does NOT exist in the DOM at all. This
  // test creates the component fresh, does NOT trigger a run, and
  // verifies no Export CSV button is rendered (the strongest possible
  // protection — you can't click what doesn't exist).
  // ─────────────────────────────────────────────────────────────────
  it("Export CSV does not produce a file before a run completes", async () => {
    const element = createElement("c-trigger-risk-runner", {
      is: TriggerRiskRunner
    });

    getTriggerNames.mockResolvedValue(["TRA_SoqlInLoop_Bad"]);
    document.body.appendChild(element);
    await flushPromises();

    // No run started → Export CSV button must not be rendered.
    // The button lives inside <template if:true={runId}> and runId
    // is still null at this point.
    const exportBtn = findButtonByLabel(element, "Export CSV");
    expect(exportBtn).toBeFalsy();

    // Belt-and-suspenders: no anchor element was created for download.
    // (downloadTextFile is the only path that creates an <a> with a
    // data: href, and we filter for those below.)
    const downloadAnchors = createdAnchors.filter((a) =>
      (a.href || "").startsWith("data:")
    );
    expect(downloadAnchors.length).toBe(0);
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 2: Export CSV produces a CSV with executive signal and finding row
  //
  // SOURCE: exportCsv() builds a CSV string with:
  //   - header lines (TRA Build, Policy, Version, Run ID, Release Label, ...)
  //   - executive signal block (Overall Risk, Release Recommendation, ...)
  //   - column header row: Severity,Trigger,Rule,Category,Line,Message
  //   - one row per finding via filteredItems
  //
  // We verify the file CONTENT, name pattern, and MIME type — not the
  // exact header/byte layout, which would couple the test to formatting.
  // ─────────────────────────────────────────────────────────────────
  it("Export CSV generates file with executive signal block and finding row", async () => {
    const element = await setupCompletedRun(blockedRunStatus(), [
      blockedFindingRow()
    ]);

    const exportBtn = findButtonByLabel(element, "Export CSV");
    expect(exportBtn).toBeTruthy();
    exportBtn.dispatchEvent(new CustomEvent("click", { bubbles: true }));
    await flushPromises();

    // Find the download anchor created by exportCsv → downloadTextFile
    const downloadAnchors = createdAnchors.filter((a) =>
      (a.href || "").startsWith("data:")
    );
    expect(downloadAnchors.length).toBe(1);

    const anchor = downloadAnchors[0];
    const csvText = anchorText(anchor);
    const fileName = anchor.download;
    const mimeType = anchorMime(anchor);

    // Verify the download was actually triggered (not just the anchor created)
    expect(anchor.click).toHaveBeenCalledTimes(1);

    // Header content
    expect(csvText).toContain("Trigger Risk Analyzer Export");
    expect(csvText).toContain("GOLD Phase 7 Validated");
    expect(csvText).toContain("Release Gate Policy: Standard");
    expect(csvText).toContain("Release Gate Version: 7.0.1");
    expect(csvText).toContain("Release Label: UI-RUN");

    // Executive signal block
    expect(csvText).toContain("EXECUTIVE SIGNAL");
    expect(csvText).toContain("Overall Risk: High");
    expect(csvText).toContain("Release Recommendation: BLOCKED");

    // Column header + finding row data
    expect(csvText).toContain("Severity,Trigger,Rule,Category,Line,Message");
    expect(csvText).toContain("TRA_SoqlInLoop_Bad");
    expect(csvText).toContain("SOQL in Loop");
    expect(csvText).toContain("SOQL inside a loop can hit query limits.");

    // Filename pattern: TRA_<release>_<runId>_<ymd>.csv
    expect(fileName).toMatch(
      /^TRA_UI-RUN_a02000000000001AAA_\d{4}-\d{2}-\d{2}\.csv$/
    );

    // MIME type from the data URI.
    //
    // KNOWN COMPONENT BUG (worth flagging in cleanup pass):
    //   downloadTextFile(text, fileName, mimeType) declares a mimeType
    //   parameter but IGNORES it. The href is hardcoded as:
    //     `data:application/octet-stream;charset=utf-8,${encoded}`
    //   So every export — CSV, Release Decision, anything else —
    //   produces the same MIME regardless of the passed value.
    //
    // The test asserts what the component ACTUALLY does, not what
    // exportCsv() passes in. If the component is fixed later to
    // honor the mimeType parameter, this assertion will need to
    // change to 'application/octet-stream;charset=utf-8;' (with
    // trailing semicolon) to match the value that exportCsv passes.
    expect(mimeType).toBe("application/octet-stream;charset=utf-8");
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 3: Export CSV with zero findings produces clean export with placeholder
  //
  // SOURCE: exportCsv() includes:
  //   if (!rows.length) {
  //       lines.push(this.csvEscape('No findings detected for current filters.'));
  //   }
  //
  // This protects the "clean trigger proves nothing wrong" use case —
  // managers/auditors still get a CSV artifact even when there are
  // no findings to list.
  // ─────────────────────────────────────────────────────────────────
  it("Export CSV with zero findings includes placeholder text and no data row", async () => {
    const cleanRunStatus = {
      ...blockedRunStatus(),
      highCount: 0,
      mediumCount: 0,
      lowCount: 0,
      overallRisk: "Low",
      releaseDecision: "APPROVED",
      releaseRecommendation: "PROCEED"
    };

    const element = await setupCompletedRun(cleanRunStatus, []);

    const exportBtn = findButtonByLabel(element, "Export CSV");
    expect(exportBtn).toBeTruthy();
    exportBtn.dispatchEvent(new CustomEvent("click", { bubbles: true }));
    await flushPromises();

    const downloadAnchors = createdAnchors.filter((a) =>
      (a.href || "").startsWith("data:")
    );
    expect(downloadAnchors.length).toBe(1);

    const anchor = downloadAnchors[0];
    const csvText = anchorText(anchor);

    // Verify the download was actually triggered
    expect(anchor.click).toHaveBeenCalledTimes(1);

    // Placeholder line is present
    expect(csvText).toContain("No findings detected for current filters.");

    // No finding-row data leaked through. We assert on rule label and
    // message text rather than trigger name — the trigger name could
    // legitimately appear in CSV metadata later (e.g., a "Selected
    // Triggers:" header line) without indicating a finding row leak.
    // Rule label and message text only appear when there's an actual
    // finding being exported.
    expect(csvText).not.toContain("SOQL in Loop");
    expect(csvText).not.toContain("SOQL inside a loop can hit query limits.");
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 4: Export Release Decision generates text file with gate sections
  //
  // SOURCE: buildReleaseDecisionText(now) builds a multi-section text:
  //   - Header with Build label, Run Id, Release Label, Generated At
  //   - EXECUTIVE SIGNAL (Overall Risk, Release Recommendation, Architect Impacts, Top Risks)
  //   - RELEASE GATE (Gate Outcome, Policy, Version, Rationale, Required Fixes)
  //
  // We verify section headers and key field values reach the file.
  // Filename matches exportReleaseDecision(); MIME currently reflects
  // the known downloadTextFile behavior where the mimeType parameter
  // is ignored (see Test 2 comment for full bug description).
  // ─────────────────────────────────────────────────────────────────
  it("Export Release Decision generates text file with executive and gate sections", async () => {
    const element = await setupCompletedRun(blockedRunStatus(), [
      blockedFindingRow()
    ]);

    const exportBtn = findButtonByLabel(element, "Export Release Decision");
    expect(exportBtn).toBeTruthy();
    exportBtn.dispatchEvent(new CustomEvent("click", { bubbles: true }));
    await flushPromises();

    const downloadAnchors = createdAnchors.filter((a) =>
      (a.href || "").startsWith("data:")
    );
    expect(downloadAnchors.length).toBe(1);

    const anchor = downloadAnchors[0];
    const text = anchorText(anchor);
    const fileName = anchor.download;
    const mimeType = anchorMime(anchor);

    // Verify the download was actually triggered
    expect(anchor.click).toHaveBeenCalledTimes(1);

    // Top-level structure
    expect(text).toContain("Trigger Risk Analyzer - Release Decision");
    expect(text).toContain("Build: GOLD Phase 7 Validated");

    // Executive signal section
    expect(text).toContain("EXECUTIVE SIGNAL");
    expect(text).toContain("Overall Risk: High");
    expect(text).toContain("Release Recommendation: BLOCKED");

    // Release gate section
    expect(text).toContain("RELEASE GATE");
    expect(text).toContain("Gate Outcome: BLOCKED");
    expect(text).toContain("Policy: Standard");
    expect(text).toContain("Version: 7.0.1");

    // Rationale and required fixes content (provided in blockedRunStatus)
    expect(text).toContain("Rationale:");
    expect(text).toContain(
      "SOQL inside loops can exceed governor limits under bulk load."
    );
    expect(text).toContain("Required Fixes (to unblock):");
    expect(text).toContain("Move SOQL outside the loop and bulkify the query.");

    // Filename pattern: TRA_ReleaseDecision_<release>_<runId>_<ymd>.txt
    expect(fileName).toMatch(
      /^TRA_ReleaseDecision_UI-RUN_a02000000000001AAA_\d{4}-\d{2}-\d{2}\.txt$/
    );

    // MIME type from the data URI.
    // See Test 2 for explanation of the component bug — downloadTextFile
    // ignores the mimeType parameter and always uses application/octet-stream.
    // exportReleaseDecision passes 'text/plain;charset=utf-8;' but the
    // component drops it on the floor. We assert what the component
    // actually does. Filename extension (.txt) and content are still
    // correct, so end users get the right file behaviorally.
    expect(mimeType).toBe("application/octet-stream;charset=utf-8");
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 5: Export Release Decision omits Required Fixes section when empty
  //
  // SOURCE: buildReleaseDecisionText():
  //   if (fixLines.length) {
  //       out += '\nRequired Fixes (to unblock):\n';
  //       fixLines.forEach((l, i) => { out += `${i + 1}) ${l}\n`; });
  //   }
  //
  // The Required Fixes section is conditional. APPROVED runs don't
  // produce required-fix lines, so the section header itself must not
  // appear in the file. This protects the manager-facing artifact:
  // an APPROVED file shouldn't show an empty "Required Fixes" header
  // that implies missing data.
  // ─────────────────────────────────────────────────────────────────
  it("Export Release Decision omits Required Fixes section when no fixes exist", async () => {
    const approvedRunStatus = {
      ...blockedRunStatus(),
      highCount: 0,
      mediumCount: 0,
      lowCount: 0,
      overallRisk: "Low",
      releaseDecision: "APPROVED",
      releaseRecommendation: "PROCEED",
      releaseRationale: "", // no rationale
      requiredFixes: "", // no fixes — section must be omitted
      executiveSummary:
        "EXECUTIVE SIGNAL:\n" +
        "- Overall Deployment Risk: Low\n" +
        "\n" +
        "RELEASE GATE (Policy: Standard, Version: 7.0.1):\n" +
        "- Release Decision: APPROVED\n" +
        "- Release Recommendation: PROCEED\n"
    };

    const element = await setupCompletedRun(approvedRunStatus, []);

    const exportBtn = findButtonByLabel(element, "Export Release Decision");
    expect(exportBtn).toBeTruthy();
    exportBtn.dispatchEvent(new CustomEvent("click", { bubbles: true }));
    await flushPromises();

    const downloadAnchors = createdAnchors.filter((a) =>
      (a.href || "").startsWith("data:")
    );
    expect(downloadAnchors.length).toBe(1);

    const anchor = downloadAnchors[0];
    const text = anchorText(anchor);

    // Verify the download was actually triggered
    expect(anchor.click).toHaveBeenCalledTimes(1);

    // Top-level structure still present
    expect(text).toContain("Gate Outcome: APPROVED");

    // Required Fixes section header MUST NOT appear when no fixes
    expect(text).not.toContain("Required Fixes (to unblock):");
  });
});

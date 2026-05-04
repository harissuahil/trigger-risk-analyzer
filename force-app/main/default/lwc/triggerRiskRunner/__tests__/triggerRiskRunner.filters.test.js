/* eslint-disable @lwc/lwc/no-async-operation */
import { createElement } from "lwc";
import TriggerRiskRunner from "c/triggerRiskRunner";

import getTriggerNames from "@salesforce/apex/DeploymentAnalysisController.getTriggerNames";
import startRun from "@salesforce/apex/DeploymentAnalysisController.startRun";
import getRunStatus from "@salesforce/apex/DeploymentAnalysisController.getRunStatus";
import getRunItems from "@salesforce/apex/DeploymentAnalysisController.getRunItems";

// See triggerRiskRunner.test.js for full mock-pattern explanation.
// Same per-method jest.mock pattern with { virtual: true } and factory
// returning { default: jest.fn() } — required because @lwc/jest-transformer
// accesses .default on required modules and the apex paths don't exist
// as real files on disk.
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

// Find a lightning-combobox by its label attribute. Two comboboxes
// (Severity and Category) live side-by-side in the filters area, so
// querySelector('lightning-combobox') alone would silently grab the
// wrong one. Same triple-fallback pattern used for lightning-button
// because sfdx-lwc-jest 7.x stubs are inconsistent about whether
// template attributes surface as JS properties or DOM attributes.
function findComboboxByLabel(element, label) {
  const combos = [...element.shadowRoot.querySelectorAll("lightning-combobox")];
  return combos.find(
    (c) =>
      c.label === label ||
      c.getAttribute("label") === label ||
      (c.textContent || "").trim() === label
  );
}

// Find a lightning-input by its label attribute. Used for the findings
// search input ("Search") — distinct from the trigger-list search input
// ("Search triggers") which lives in a different part of the component.
function findInputByLabel(element, label) {
  const inputs = [...element.shadowRoot.querySelectorAll("lightning-input")];
  return inputs.find(
    (i) =>
      i.label === label ||
      i.getAttribute("label") === label ||
      (i.textContent || "").trim() === label
  );
}

// Find a lightning-button by its label.
// Same approach as triggerRiskRunner.export.test.js — robust across
// stub variations.
function findButtonByLabel(element, label) {
  const buttons = [...element.shadowRoot.querySelectorAll("lightning-button")];
  return buttons.find(
    (b) =>
      b.label === label ||
      b.getAttribute("label") === label ||
      (b.textContent || "").trim() === label
  );
}

// Set a lightning-combobox value and dispatch its change event in the
// shape the component expects. The component's handleSeverityFilter /
// handleCategoryFilter handlers read e.detail.value (the LWC standard
// for lightning-combobox), NOT e.target.value.
async function setComboboxValue(combo, value) {
  combo.value = value;
  combo.dispatchEvent(new CustomEvent("change", { detail: { value } }));
  await flushPromises();
}

// Set a lightning-input value and dispatch its change event. The
// component's handleSearchChange reads e.target.value (the LWC default
// for lightning-input), so we set the .value property on the stub
// element itself before dispatching. jsdom's CustomEvent makes the
// dispatching element available as event.target in the handler.
async function setSearchText(input, value) {
  input.value = value;
  input.dispatchEvent(new CustomEvent("change"));
  await flushPromises();
}

// ─────────────────────────────────────────────────────────────────────
// Test data builders
// ─────────────────────────────────────────────────────────────────────

// Three findings spanning all three severity tiers AND three distinct
// categories. This single dataset exercises both severity and category
// filter paths, plus the multi-field search scope.
//
// Field shapes verified from DeploymentAnalysisController.ItemRowDTO and
// from the existing triggerRiskRunner.export.test.js fixture.
//
// The component sorts items by severitySort descending in refreshRun,
// so the order seen by lightning-datatable will be: High, Medium, Low.
function highFindingRow() {
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

function mediumFindingRow() {
  return {
    itemId: "a01000000000002AAA",
    triggerName: "TRA_MixedDml_Sample",
    severity: "Medium",
    severitySort: 2,
    ruleKeys: "MIXED_DML",
    ruleLabel: "Mixed DML",
    category: "TransactionRisk",
    lineNumber: 12,
    messageShort:
      "Mixed DML on setup and non-setup objects in same transaction.",
    hasSnippet: true
  };
}

function lowFindingRow() {
  return {
    itemId: "a01000000000003AAA",
    triggerName: "TRA_HandlerMissing_Lite",
    severity: "Low",
    severitySort: 1,
    ruleKeys: "TRIGGER_HANDLER_MISSING",
    ruleLabel: "Trigger Handler Missing",
    category: "Maintainability",
    lineNumber: 1,
    messageShort: "Trigger should delegate to a handler class.",
    hasSnippet: false
  };
}

// Multi-finding run status. Counts must match the item list because
// hasAnyFindings (used by the zero-result UI state) reads findingsCount
// from getRunStatus, NOT from items.length. If counts are zero, the
// zero-result test would see the wrong "No findings detected" message
// instead of "No findings match the current filters."
function multiFindingRunStatus() {
  return {
    status: "Done",
    totalTriggers: 1,
    processedTriggers: 1,
    highCount: 1,
    mediumCount: 1,
    lowCount: 1,
    overallRisk: "High",
    releaseDecision: "BLOCKED",
    policyProfile: "Standard",
    gateVersion: "7.0.1",
    releaseRecommendation: "NOT RECOMMENDED",
    architectImpacts: "Bulk/Limit Risk",
    releaseRationale: "1) Multiple risk patterns detected.",
    requiredFixes: "1) Address findings before deployment.",
    topRisks: ["SOQL inside loops may fail under bulk load."],
    executiveSummary: null,
    errorMessage: null,
    lastUpdated: new Date().toISOString(),
    completedAt: new Date().toISOString()
  };
}

// ─────────────────────────────────────────────────────────────────────
// Shared setup: create the component, run analysis, return the element
// after the run completes with all three findings loaded.
// ─────────────────────────────────────────────────────────────────────
async function setupRunWithThreeFindings() {
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
  getRunStatus.mockResolvedValue(multiFindingRunStatus());
  getRunItems.mockResolvedValue([
    highFindingRow(),
    mediumFindingRow(),
    lowFindingRow()
  ]);

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

describe("c-trigger-risk-runner — filters and filtered export", () => {
  // The export test (Test 5) needs to capture the <a> element created
  // by downloadTextFile. Same pattern as triggerRiskRunner.export.test.js:
  // spy on document.createElement, stub anchor.click to prevent jsdom
  // navigation warnings.
  let createdAnchors;
  let originalCreateElement;

  function anchorText(anchor) {
    const href = anchor.href || "";
    const commaIdx = href.indexOf(",");
    if (commaIdx < 0) return "";
    return decodeURIComponent(href.substring(commaIdx + 1));
  }

  beforeEach(() => {
    createdAnchors = [];
    originalCreateElement = document.createElement.bind(document);
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
  // Test 1: Severity filter narrows the datatable data
  //
  // SOURCE: filteredItems getter (triggerRiskRunner.js):
  //   if (sev && sev !== "All" && r.severity !== sev) return false;
  //
  // SOURCE: HTML binds <lightning-datatable data={filteredItems} ...>
  //
  // Three findings are loaded (High/Medium/Low). Selecting "High" in
  // the severity combobox must shrink dt.data to just the High row.
  // ─────────────────────────────────────────────────────────────────
  it("severity filter narrows datatable data to matching findings", async () => {
    const element = await setupRunWithThreeFindings();

    // Baseline: all three findings visible
    let dt = element.shadowRoot.querySelector("lightning-datatable");
    expect(dt).toBeTruthy();
    expect(dt.data).toHaveLength(3);

    // Apply severity filter = High
    const severityCombo = findComboboxByLabel(element, "Severity");
    expect(severityCombo).toBeTruthy();
    await setComboboxValue(severityCombo, "High");

    // Re-query datatable — same element, but data should now be filtered
    dt = element.shadowRoot.querySelector("lightning-datatable");
    expect(dt).toBeTruthy();
    expect(dt.data).toHaveLength(1);
    expect(dt.data[0].severity).toBe("High");
    expect(dt.data[0].triggerName).toBe("TRA_SoqlInLoop_Bad");

    // Restore "All" — verify all three return
    await setComboboxValue(severityCombo, "All");
    dt = element.shadowRoot.querySelector("lightning-datatable");
    expect(dt.data).toHaveLength(3);
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 2: Category filter narrows the datatable data
  //
  // SOURCE: filteredItems getter:
  //   if (cat && cat !== "All" && r.category !== cat) return false;
  //
  // SOURCE: categoryOptions getter derives options from this.items —
  // so available options after the run will be: All, BulkRisk,
  // Maintainability, TransactionRisk (alphabetically sorted).
  //
  // Selecting "TransactionRisk" must narrow dt.data to just the Medium
  // row (which is in the TransactionRisk category).
  // ─────────────────────────────────────────────────────────────────
  it("category filter narrows datatable data to matching findings", async () => {
    const element = await setupRunWithThreeFindings();

    // Apply category filter = TransactionRisk (only the Medium row)
    const categoryCombo = findComboboxByLabel(element, "Category");
    expect(categoryCombo).toBeTruthy();
    await setComboboxValue(categoryCombo, "TransactionRisk");

    const dt = element.shadowRoot.querySelector("lightning-datatable");
    expect(dt).toBeTruthy();
    expect(dt.data).toHaveLength(1);
    expect(dt.data[0].category).toBe("TransactionRisk");
    expect(dt.data[0].severity).toBe("Medium");
    expect(dt.data[0].triggerName).toBe("TRA_MixedDml_Sample");
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 3: Search filter matches across the multi-field scope
  //
  // SOURCE: filteredItems getter haystack:
  //   const hay = [r.triggerName, r.ruleLabel, r.ruleKeys || r.ruleKey,
  //                r.category, r.messageShort, r.severity]
  //     .filter(Boolean).join(" ").toLowerCase();
  //   return hay.includes(q);
  //
  // We exercise three separate fields to lock down the documented
  // search scope:
  //   - "Maintainability"     — only in row 3's category field    → 1 match
  //   - "MIXED_DML"          — only in row 2's ruleKeys field    → 1 match
  //   - "TRA_SoqlInLoop_Bad" — only in row 1's triggerName field → 1 match
  //
  // The MIXED_DML assertion is the keystone: it proves the haystack
  // reads ruleKeys (the actual ItemRowDTO field name) and not the
  // misnamed ruleKey fallback alone. Real Apex data uses ruleKeys.
  //
  // The trigger-name assertion covers the most common search path
  // users actually take ("find the trigger I'm worried about").
  //
  // No-match search behavior (search returns zero rows + UI shows
  // "No findings match the current filters." message) is tested
  // separately in Test 4 to keep this test focused on positive
  // multi-field matching.
  // ─────────────────────────────────────────────────────────────────
  it("search filter matches across trigger name, category, and ruleKeys fields", async () => {
    const element = await setupRunWithThreeFindings();

    const searchInput = findInputByLabel(element, "Search");
    expect(searchInput).toBeTruthy();

    // Search by category → matches the Low row only
    await setSearchText(searchInput, "Maintainability");
    let dt = element.shadowRoot.querySelector("lightning-datatable");
    expect(dt).toBeTruthy();
    expect(dt.data).toHaveLength(1);
    expect(dt.data[0].category).toBe("Maintainability");

    // Search by ruleKeys → matches the Medium row only.
    // This proves the haystack reads ruleKeys (plural — matches the
    // real ItemRowDTO field), not the misnamed ruleKey.
    await setSearchText(searchInput, "MIXED_DML");
    dt = element.shadowRoot.querySelector("lightning-datatable");
    expect(dt).toBeTruthy();
    expect(dt.data).toHaveLength(1);
    expect(dt.data[0].ruleKeys).toBe("MIXED_DML");
    // Identity assertions: prove the SINGLE returned row is the right
    // one, not just "some row." Without these, a future haystack
    // regression that accidentally matched the wrong row (e.g., reading
    // the wrong index) would still pass the length=1 check.
    expect(dt.data[0].triggerName).toBe("TRA_MixedDml_Sample");
    expect(dt.data[0].ruleLabel).toBe("Mixed DML");

    // Search by trigger name → matches the High row only. This is the
    // most common search path users take ("find the trigger I'm worried
    // about"), and locks down trigger name as part of the haystack scope.
    await setSearchText(searchInput, "TRA_SoqlInLoop_Bad");
    dt = element.shadowRoot.querySelector("lightning-datatable");
    expect(dt).toBeTruthy();
    expect(dt.data).toHaveLength(1);
    expect(dt.data[0].triggerName).toBe("TRA_SoqlInLoop_Bad");
    expect(dt.data[0].ruleKeys).toBe("SOQL_IN_LOOP");

    // Clearing the search restores all three rows — proves the search
    // input drives filteredItems and isn't getting stuck on stale state.
    await setSearchText(searchInput, "");
    dt = element.shadowRoot.querySelector("lightning-datatable");
    expect(dt.data).toHaveLength(3);
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 4: Zero-result filter shows the right message and removes table
  //
  // SOURCE: HTML template structure:
  //   <template if:true={showTable}>
  //     <lightning-datatable .../>
  //   </template>
  //   <template if:false={showTable}>
  //     <template if:false={hasAnyFindings}>
  //       No findings detected. This trigger passed all active rules.
  //     </template>
  //     <template if:true={hasAnyFindings}>
  //       No findings match the current filters.
  //     </template>
  //   </template>
  //
  // SOURCE: showTable getter:
  //   return this.runId && this.filteredItems && this.filteredItems.length > 0;
  //
  // SOURCE: hasAnyFindings getter:
  //   return (this.findingsCount || 0) > 0;
  //   (findingsCount is set from getRunStatus, NOT items.length —
  //    that's why multiFindingRunStatus seeds counts > 0)
  //
  // After applying an impossible filter, the user must see "No findings
  // match the current filters." — NOT "No findings detected." — because
  // the run did produce findings, they're just being filtered out.
  // Distinguishing between "clean run" and "filtered to nothing" matters
  // for users deciding whether to clear filters or accept the result.
  // ─────────────────────────────────────────────────────────────────
  it("zero-result filter renders 'No findings match' message and removes datatable", async () => {
    const element = await setupRunWithThreeFindings();

    // Apply a search that no field will match
    const searchInput = findInputByLabel(element, "Search");
    expect(searchInput).toBeTruthy();
    await setSearchText(searchInput, "QQQXYZ_NO_MATCH_ANYWHERE");

    // Datatable must be removed from DOM (because showTable went false)
    const dt = element.shadowRoot.querySelector("lightning-datatable");
    expect(dt).toBeFalsy();

    // The "no match" message must appear (because hasAnyFindings is
    // still true — findingsCount is 3 from the run status)
    expect(element.shadowRoot.textContent).toContain(
      "No findings match the current filters."
    );

    // The "no findings detected" message must NOT appear — that's the
    // wrong message for a filter-induced empty state and would mislead
    // the user about what the run actually produced.
    expect(element.shadowRoot.textContent).not.toContain(
      "No findings detected. This trigger passed all active rules."
    );
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 5 (KEYSTONE): Export CSV respects the active filter
  //
  // SOURCE: exportCsv() (triggerRiskRunner.js):
  //   const rows = this.filteredItems || [];
  //   ...
  //   rows.forEach((r) => { ... });
  //
  // exportCsv reads filteredItems, NOT items. So when a filter is
  // active, only the filtered findings end up in the CSV. This is
  // the contract that matters most to managers and auditors:
  // the artifact they download must match what they see on screen.
  //
  // We apply severity=High, click Export CSV, decode the resulting
  // data: URI, and verify:
  //   - The High row's data IS in the CSV
  //   - The Medium and Low row's data are NOT in the CSV (no leak)
  //
  // The keystone proves the filter slice and the export slice
  // (covered in triggerRiskRunner.export.test.js) work together
  // correctly — neither test alone catches a regression where filters
  // visually narrow the table but exportCsv reads the unfiltered items.
  // ─────────────────────────────────────────────────────────────────
  it("Export CSV includes only filtered rows (severity=High excludes Medium and Low)", async () => {
    const element = await setupRunWithThreeFindings();

    // Apply severity = High filter
    const severityCombo = findComboboxByLabel(element, "Severity");
    expect(severityCombo).toBeTruthy();
    await setComboboxValue(severityCombo, "High");

    // Verify the table now shows only the High row before exporting
    const dt = element.shadowRoot.querySelector("lightning-datatable");
    expect(dt.data).toHaveLength(1);
    expect(dt.data[0].severity).toBe("High");

    // Click Export CSV
    const exportBtn = findButtonByLabel(element, "Export CSV");
    expect(exportBtn).toBeTruthy();
    exportBtn.dispatchEvent(new CustomEvent("click", { bubbles: true }));
    await flushPromises();

    // Capture the download anchor created by exportCsv → downloadTextFile
    const downloadAnchors = createdAnchors.filter((a) =>
      (a.href || "").startsWith("data:")
    );
    expect(downloadAnchors.length).toBe(1);

    const anchor = downloadAnchors[0];
    const csvText = anchorText(anchor);
    expect(anchor.click).toHaveBeenCalledTimes(1);

    // High row's data IS present
    expect(csvText).toContain("TRA_SoqlInLoop_Bad");
    expect(csvText).toContain("SOQL in Loop");
    expect(csvText).toContain("SOQL inside a loop can hit query limits.");

    // Medium row's data is NOT present — check identifying fields that
    // only appear when a finding row is exported (rule label, message)
    expect(csvText).not.toContain("TRA_MixedDml_Sample");
    expect(csvText).not.toContain("Mixed DML on setup and non-setup objects");

    // Low row's data is NOT present
    expect(csvText).not.toContain("TRA_HandlerMissing_Lite");
    expect(csvText).not.toContain("Trigger should delegate to a handler class");

    // The filter selection itself should be reflected in the CSV
    // metadata header line:
    //   "Filters: Severity=High; Category=All"
    // This is a bonus assertion — it proves the CSV documents which
    // filter produced its content, which matters for audit traceability.
    expect(csvText).toContain("Filters: Severity=High");
  });
});

/* eslint-disable @lwc/lwc/no-async-operation */
import { createElement } from "lwc";
import TriggerRiskRunner from "c/triggerRiskRunner";

import getTriggerNames from "@salesforce/apex/DeploymentAnalysisController.getTriggerNames";
import startRun from "@salesforce/apex/DeploymentAnalysisController.startRun";
import getRunStatus from "@salesforce/apex/DeploymentAnalysisController.getRunStatus";
import getRunItems from "@salesforce/apex/DeploymentAnalysisController.getRunItems";
import getItemDetail from "@salesforce/apex/DeploymentAnalysisController.getItemDetail";

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
// Error shapes
// ─────────────────────────────────────────────────────────────────────

// Apex-style error envelope. Verified from triggerRiskRunner.js
// normalizeError():
//   if (err && err.body && err.body.message) return err.body.message;
//   if (err && err.message) return err.message;
//   return JSON.stringify(err);
//
// Salesforce LDS / @wire / imperative Apex calls reject with this shape
// when the controller throws an AuraHandledException. Using it here
// instead of plain Error() exercises the realistic production path.
function apexError(message) {
  return { body: { message } };
}

// ─────────────────────────────────────────────────────────────────────
// Test data builders (minimal — error tests don't need full fixtures)
// ─────────────────────────────────────────────────────────────────────

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

function singleFindingRunStatus() {
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
    releaseRationale: "1) SOQL inside loops can fail under bulk load.",
    requiredFixes: "1) Move SOQL outside the loop.",
    topRisks: ["SOQL inside loops may fail under bulk load."],
    executiveSummary: null,
    errorMessage: null,
    lastUpdated: new Date().toISOString(),
    completedAt: new Date().toISOString()
  };
}

// Helper to drive a successful run-to-completion as a precondition for
// Test 3. Mirrors the pattern from the export and modal slices but
// trimmed to the minimum needed.
async function setupCompletedRun() {
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
  getRunStatus.mockResolvedValue(singleFindingRunStatus());
  getRunItems.mockResolvedValue([highFindingRow()]);

  const buttons = element.shadowRoot.querySelectorAll("lightning-button");
  expect(buttons.length).toBe(1);
  buttons[0].dispatchEvent(new CustomEvent("click", { bubbles: true }));

  await flushPromises();
  await flushPromises();
  await flushPromises();

  return element;
}

describe("c-trigger-risk-runner — error handling", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 1: loadTriggers failure surfaces error to the user
  //
  // SOURCE — connectedCallback calls loadTriggers:
  //   connectedCallback() { this.loadTriggers(); }
  //
  // SOURCE — loadTriggers (triggerRiskRunner.js):
  //   async loadTriggers() {
  //     this.isLoading = true;
  //     this.errorMsg = null;
  //     try {
  //       const names = await getTriggerNames();
  //       this.triggers = names || [];
  //     } catch (err) {
  //       this.errorMsg = this.normalizeError(err);
  //     } finally {
  //       this.isLoading = false;
  //     }
  //   }
  //
  // SOURCE — error message rendering:
  //   <template if:true={errorMsg}>
  //     <div class="slds-m-top_medium slds-text-color_error">{errorMsg}</div>
  //   </template>
  //
  // Why this matters: loadTriggers runs at component mount. If the
  // Tooling API callout fails (permissions, timeout, transient 5xx),
  // the user must see the actual error — not a silently empty trigger
  // list that looks like "no triggers in this org."
  // ─────────────────────────────────────────────────────────────────
  it("loadTriggers failure shows the error message to the user", async () => {
    const element = createElement("c-trigger-risk-runner", {
      is: TriggerRiskRunner
    });

    // Reject with the realistic Apex error shape
    getTriggerNames.mockRejectedValue(
      apexError("Tooling API permission denied for ApexTrigger")
    );

    document.body.appendChild(element);
    // Drain connectedCallback → loadTriggers → catch → errorMsg set
    await flushPromises();
    await flushPromises();

    // Error message visible in the shadow DOM
    const rootText = element.shadowRoot.textContent || "";
    expect(rootText).toContain("Tooling API permission denied for ApexTrigger");

    // Call-shape contract: the component actually attempted the
    // Apex call before catching its rejection. If a future refactor
    // accidentally short-circuits loadTriggers (e.g., adds an
    // isLoading guard that returns early), this assertion fails
    // with a clear signal — distinguishing "Apex was called and
    // failed" from "Apex was never called."
    expect(getTriggerNames).toHaveBeenCalledTimes(1);

    // No trigger checkbox rows should render. The component initializes
    // triggers as an empty array (@track triggers = []), and because
    // getTriggerNames rejects, no trigger names are added to it.
    const triggerCheckboxes = element.shadowRoot.querySelectorAll(
      'lightning-input[type="checkbox"]'
    );
    expect(triggerCheckboxes.length).toBe(0);
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 2: runAnalysis failure shows error and does not render run UI
  //
  // SOURCE — runAnalysis (triggerRiskRunner.js):
  //   async runAnalysis() {
  //     this.isLoading = true;
  //     this.errorMsg = null;
  //     this.runId = null;             // ← set BEFORE try
  //     this.items = [];
  //     this.resetRunStatus();
  //     this.stopPolling();
  //     // ... clears gate fields ...
  //     try {
  //       const triggerNames = Array.from(this.selected);
  //       const id = await startRun({ ... });
  //       this.runId = id;              // ← set AFTER successful await
  //       await this.refreshRun();
  //       this.startPolling();
  //     } catch (err) {
  //       this.errorMsg = this.normalizeError(err);
  //     }
  //   }
  //
  // The `this.runId = null` BEFORE the try is the key contract. When
  // startRun rejects, runId stays null, which means every UI section
  // gated by <template if:true={runId}> stays out of the DOM:
  //   - Executive Signal panel
  //   - Release Gate card
  //   - Detailed Findings table
  //   - Export / Copy / Refresh buttons
  //
  // The user sees the error message and a clean pre-run state — not
  // a half-rendered dashboard with stale data from a previous run.
  // We assert directly on the result sections and datatable instead of
  // relying on button counts. That keeps the test focused on the real
  // contract: no run-result UI should appear when startRun fails.
  // ─────────────────────────────────────────────────────────────────
  it("runAnalysis failure shows error and does not render run-result UI", async () => {
    const element = createElement("c-trigger-risk-runner", {
      is: TriggerRiskRunner
    });

    getTriggerNames.mockResolvedValue(["TRA_SoqlInLoop_Bad"]);
    document.body.appendChild(element);
    await flushPromises();

    // Select the trigger so isRunDisabled becomes false
    const cb = element.shadowRoot.querySelector(
      'lightning-input[data-name="TRA_SoqlInLoop_Bad"]'
    );
    expect(cb).not.toBeNull();
    cb.checked = true;
    cb.dispatchEvent(new CustomEvent("change", { bubbles: false }));
    await flushPromises();

    // startRun rejects with the Apex error shape
    startRun.mockRejectedValue(
      apexError("Insufficient access rights on Deployment_Analysis_Run__c")
    );

    // Click Run Analysis (the only lightning-button before run completes)
    const buttonsBefore =
      element.shadowRoot.querySelectorAll("lightning-button");
    expect(buttonsBefore.length).toBe(1);
    buttonsBefore[0].dispatchEvent(new CustomEvent("click", { bubbles: true }));

    // Drain runAnalysis → startRun(reject) → catch → errorMsg set
    await flushPromises();
    await flushPromises();
    await flushPromises();

    // Error message visible in shadow DOM
    const rootText = element.shadowRoot.textContent || "";
    expect(rootText).toContain(
      "Insufficient access rights on Deployment_Analysis_Run__c"
    );

    // Call-shape contract: startRun was called with the correct
    // payload before rejecting. This proves the component constructed
    // the right request from the selected trigger and the default
    // releaseLabel — distinguishing "request was malformed" from
    // "Apex genuinely rejected a valid request."
    expect(startRun).toHaveBeenCalledTimes(1);
    expect(startRun).toHaveBeenCalledWith({
      releaseLabel: "UI-RUN",
      triggerNames: ["TRA_SoqlInLoop_Bad"]
    });

    // No run-result UI rendered. The post-run sections are gated by
    // <template if:true={runId}>, and runId stays null when startRun
    // rejects. We assert directly on what the user would see (or not):
    expect(rootText).not.toContain("Executive Signal");
    expect(rootText).not.toContain("Release Gate");
    expect(rootText).not.toContain("Findings");
    expect(element.shadowRoot.querySelector("lightning-datatable")).toBeFalsy();

    // refreshRun must NOT have been called — the catch fired before
    // it. This proves the failure didn't accidentally fall through to
    // the data-loading path with a stale runId.
    expect(getRunStatus).not.toHaveBeenCalled();
    expect(getRunItems).not.toHaveBeenCalled();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 3: getItemDetail failure shows error and does not open modal
  //
  // SOURCE — handleRowAction (triggerRiskRunner.js):
  //   try {
  //     const d = await getItemDetail({ itemId: row.itemId });
  //     this.detail = d;            // ← set AFTER successful await
  //     this.isModalOpen = true;    // ← set AFTER successful await
  //     // ... snippet processing ...
  //   } catch (err) {
  //     this.errorMsg = this.normalizeError(err);
  //   }
  //
  // Both `detail = d` and `isModalOpen = true` are AFTER the await.
  // When getItemDetail rejects, control jumps to catch and neither
  // assignment happens. The modal HTML is wrapped in
  // <template if:true={isModalOpen}>, so the entire <section.slds-modal>
  // stays out of the DOM.
  //
  // Scope: this test covers the clean failure path — no existing modal
  // open, getItemDetail rejects, errorMsg is shown, modal does not
  // open. It does NOT cover the stale-detail-after-prior-success
  // scenario (open modal A → close → open modal B fails → assert A's
  // content does not reappear). That's a stronger separate test worth
  // adding later if we want to lock down the close+reopen behavior.
  // ─────────────────────────────────────────────────────────────────
  it("getItemDetail failure shows error and modal does not open", async () => {
    const element = await setupCompletedRun();

    // Confirm setup is clean — no stale errorMsg, no modal open
    let rootText = element.shadowRoot.textContent || "";
    expect(rootText).not.toContain("Detail load failed");
    expect(element.shadowRoot.querySelector("section.slds-modal")).toBeFalsy();

    // getItemDetail rejects on the View click
    getItemDetail.mockRejectedValue(
      apexError("Detail load failed: record locked by another process")
    );

    // Dispatch the rowaction event with action.name='view'
    const dt = element.shadowRoot.querySelector("lightning-datatable");
    expect(dt).toBeTruthy();
    dt.dispatchEvent(
      new CustomEvent("rowaction", {
        detail: {
          action: { name: "view" },
          row: { itemId: "a01000000000001AAA" }
        }
      })
    );

    // Drain handleRowAction → getItemDetail(reject) → catch → errorMsg set
    await flushPromises();
    await flushPromises();

    // Error message visible
    rootText = element.shadowRoot.textContent || "";
    expect(rootText).toContain(
      "Detail load failed: record locked by another process"
    );

    // Call-shape contract: getItemDetail was called with the correct
    // itemId from the row payload. This proves the rowaction handler
    // forwarded event.detail.row.itemId correctly — distinguishing
    // "wrong itemId sent and Apex rejected" from "right itemId sent
    // and the controller genuinely rejected."
    expect(getItemDetail).toHaveBeenCalledTimes(1);
    expect(getItemDetail).toHaveBeenCalledWith({
      itemId: "a01000000000001AAA"
    });

    // Modal did NOT open. The <section.slds-modal> only renders when
    // isModalOpen is true; the failure path never sets it.
    const modal = element.shadowRoot.querySelector("section.slds-modal");
    expect(modal).toBeFalsy();
  });
});

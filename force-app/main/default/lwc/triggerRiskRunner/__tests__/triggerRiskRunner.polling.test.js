/* eslint-disable @lwc/lwc/no-async-operation */
import { createElement } from "lwc";
import TriggerRiskRunner from "c/triggerRiskRunner";

import getTriggerNames from "@salesforce/apex/DeploymentAnalysisController.getTriggerNames";
import startRun from "@salesforce/apex/DeploymentAnalysisController.startRun";
import getRunStatus from "@salesforce/apex/DeploymentAnalysisController.getRunStatus";
import getRunItems from "@salesforce/apex/DeploymentAnalysisController.getRunItems";

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

// Status payload shaped to keep refreshRun() in the non-terminal branch:
// when status is not "Done"/"Failed", refreshRun does NOT call getRunItems,
// and runAnalysis proceeds to startPolling().
function runningRunStatus() {
  return {
    status: "Running",
    totalTriggers: 1,
    processedTriggers: 0,
    highCount: 0,
    mediumCount: 0,
    lowCount: 0,
    overallRisk: null,
    releaseDecision: null,
    policyProfile: null,
    gateVersion: null,
    architectImpacts: null,
    releaseRationale: null,
    requiredFixes: null,
    topRisks: [],
    errorMessage: null,
    lastUpdated: new Date().toISOString(),
    completedAt: null
  };
}

// Done status — drives refreshRun() into the terminal branch where
// getRunItems is fetched and the polling tick decides to stopPolling.
function doneRunStatus() {
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
    architectImpacts: "Bulk/Limit Risk",
    releaseRationale:
      "1) SOQL inside loops can exceed governor limits under bulk load.",
    requiredFixes: "1) Move SOQL outside the loop and bulkify the query.",
    topRisks: ["SOQL inside loops may fail under bulk load."],
    errorMessage: null,
    lastUpdated: new Date().toISOString(),
    completedAt: new Date().toISOString()
  };
}

// One BLOCKED finding row. Field shape from ItemRowDTO.
function findingRow() {
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

describe("c-trigger-risk-runner — polling", () => {
  let setIntervalSpy;
  let clearIntervalSpy;
  let element;

  beforeEach(() => {
    // Spy on window.setInterval. The component calls bare setInterval(...),
    // which resolves to window.setInterval in browser/jsdom. Spying on
    // window (not global) matches the runtime lookup chain LWC uses.
    setIntervalSpy = jest.spyOn(window, "setInterval");
    // Same reasoning for clearInterval. Lifted to describe-level so the
    // spy is restored even if a test fails before reaching its end.
    clearIntervalSpy = jest.spyOn(window, "clearInterval");
  });

  afterEach(() => {
    // Defensive: clear any intervals scheduled during the test that
    // weren't stopped explicitly. setInterval's return value is the
    // timer ID; the spy records each call's return.
    if (setIntervalSpy) {
      setIntervalSpy.mock.results.forEach((r) => {
        if (r.type === "return") clearInterval(r.value);
      });
    }
    // Removing the element triggers disconnectedCallback. Standard LWC
    // pattern is to call stopPolling() there to clear the interval.
    // If a regression drops that, leftover intervals would leak across
    // tests — surfacing as flaky cross-suite failures.
    if (element && element.parentNode) {
      element.parentNode.removeChild(element);
    }
    setIntervalSpy.mockRestore();
    clearIntervalSpy.mockRestore();
    jest.clearAllMocks();
  });

  // ──────────────────────────────────────────────────────────────────
  // Test 1: starts polling after Run Analysis when initial status is Running
  //
  // VERIFIED SOURCE FACTS (from triggerRiskRunner.js):
  //
  //   pollIntervalMs = 2000;
  //   maxPolls = 60;
  //
  //   runAnalysis() does, in order:
  //     - resetRunStatus(), stopPolling(), clear gate fields
  //     - id = await startRun({ releaseLabel, triggerNames })
  //     - this.runId = id
  //     - await this.refreshRun()
  //     - this.startPolling()           ← unconditional if no throw
  //
  //   refreshRun() only calls getRunItems when status is "Done" or "Failed".
  //   With status "Running", getRunItems is NOT called.
  //
  //   startPolling():
  //     this.stopPolling();
  //     this.pollCount = 0;
  //     this.pollTimer = setInterval(async () => { ... }, this.pollIntervalMs);
  //
  // What this test locks down: clicking Run Analysis with a non-terminal
  // initial status results in setInterval being scheduled with the
  // verified 2000ms cadence, and getRunItems is NOT called yet (because
  // status is "Running", not "Done"/"Failed").
  //
  // releaseLabel is asserted as "UI-RUN" — verified default in the
  // component source.
  //
  // We do not advance fake timers here. This test only asserts that
  // polling was scheduled, not that subsequent ticks behave correctly.
  // Tick behavior is a separate concern for a future test.
  // ──────────────────────────────────────────────────────────────────
  it("starts polling after Run Analysis when initial status is Running", async () => {
    element = createElement("c-trigger-risk-runner", {
      is: TriggerRiskRunner
    });

    getTriggerNames.mockResolvedValue(["TRA_SoqlInLoop_Bad"]);
    document.body.appendChild(element);
    await flushPromises();

    // Select the only trigger
    const cb = element.shadowRoot.querySelector(
      'lightning-input[data-name="TRA_SoqlInLoop_Bad"]'
    );
    expect(cb).not.toBeNull();
    cb.checked = true;
    cb.dispatchEvent(new CustomEvent("change", { bubbles: false }));
    await flushPromises();

    // startRun returns the new runId; getRunStatus returns "Running" so
    // refreshRun stays in the non-terminal branch and runAnalysis
    // proceeds to call startPolling().
    startRun.mockResolvedValue("a02000000000001AAA");
    getRunStatus.mockResolvedValue(runningRunStatus());

    // Click Run Analysis (only lightning-button rendered pre-run)
    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    expect(buttons.length).toBe(1);
    buttons[0].dispatchEvent(new CustomEvent("click", { bubbles: true }));

    // Drain the runAnalysis chain: startRun → refreshRun → startPolling
    await flushPromises();
    await flushPromises();
    await flushPromises();

    // Apex calls happened with the expected payloads
    expect(startRun).toHaveBeenCalledTimes(1);
    expect(startRun).toHaveBeenCalledWith({
      releaseLabel: "UI-RUN",
      triggerNames: ["TRA_SoqlInLoop_Bad"]
    });
    expect(getRunStatus).toHaveBeenCalledTimes(1);
    expect(getRunStatus).toHaveBeenCalledWith({
      runId: "a02000000000001AAA"
    });

    // Status is "Running" → refreshRun must NOT have called getRunItems.
    // This protects the "no premature item fetch on non-terminal status"
    // contract that the polling loop depends on.
    expect(getRunItems).not.toHaveBeenCalled();

    // startPolling() ran. Verified source: setInterval(callback, pollIntervalMs)
    // with pollIntervalMs = 2000.
    expect(setIntervalSpy).toHaveBeenCalledTimes(1);
    expect(setIntervalSpy).toHaveBeenLastCalledWith(expect.any(Function), 2000);
  });

  // ──────────────────────────────────────────────────────────────────
  // Test 2: stops polling and loads items when a poll tick returns Done
  //
  // Verified flow on a Done tick:
  //   1. setInterval callback runs → pollCount++
  //   2. await refreshRun()
  //        → getRunStatus returns Done
  //        → status assigned, gate fields populated
  //        → status === "Done" → getRunItems({ runId }) called
  //   3. Back in callback: status === "Done" → stopPolling()
  //        → clearInterval(pollTimer); pollTimer = null
  //
  // We capture the interval callback from the spy and invoke it
  // directly. This sidesteps fake timers (which would conflict with
  // flushPromises's setTimeout-based wait) while exercising exactly
  // what setInterval would call on a real tick.
  // ──────────────────────────────────────────────────────────────────
  it("stops polling and loads items when a poll tick returns Done", async () => {
    element = createElement("c-trigger-risk-runner", {
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

    // First refreshRun (in runAnalysis) sees "Running" so polling
    // schedules. The tick will then see "Done".
    startRun.mockResolvedValue("a02000000000001AAA");
    getRunStatus
      .mockResolvedValueOnce(runningRunStatus())
      .mockResolvedValueOnce(doneRunStatus());
    getRunItems.mockResolvedValue([findingRow()]);

    const buttons = element.shadowRoot.querySelectorAll("lightning-button");
    expect(buttons.length).toBe(1);
    buttons[0].dispatchEvent(new CustomEvent("click", { bubbles: true }));

    await flushPromises();
    await flushPromises();
    await flushPromises();

    // Preflight: setup reached the polling-scheduled state and items
    // were not fetched yet (status was Running on first refreshRun).
    expect(setIntervalSpy).toHaveBeenCalledTimes(1);
    expect(getRunItems).not.toHaveBeenCalled();

    // Capture and invoke the interval callback to simulate one tick.
    const intervalCallback = setIntervalSpy.mock.calls[0][0];
    await intervalCallback();
    await flushPromises();

    // Tick triggered the second getRunStatus, refreshRun saw Done and
    // called getRunItems, then the callback called stopPolling().
    expect(getRunStatus).toHaveBeenCalledTimes(2);
    expect(getRunStatus).toHaveBeenLastCalledWith({
      runId: "a02000000000001AAA"
    });
    expect(getRunItems).toHaveBeenCalledTimes(1);
    expect(getRunItems).toHaveBeenCalledWith({
      runId: "a02000000000001AAA"
    });
    expect(clearIntervalSpy).toHaveBeenCalledTimes(1);
  });
});

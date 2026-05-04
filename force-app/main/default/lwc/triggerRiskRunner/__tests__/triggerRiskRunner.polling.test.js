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

describe("c-trigger-risk-runner — polling", () => {
  let setIntervalSpy;
  let element;

  beforeEach(() => {
    // Spy on window.setInterval. The component calls bare setInterval(...),
    // which resolves to window.setInterval in browser/jsdom. Spying on
    // window (not global) matches the runtime lookup chain LWC uses.
    setIntervalSpy = jest.spyOn(window, "setInterval");
  });

  afterEach(() => {
    // Removing the element triggers disconnectedCallback. Standard LWC
    // pattern is to call stopPolling() there to clear the interval.
    // If a regression drops that, leftover intervals would leak across
    // tests — surfacing as flaky cross-suite failures.
    if (element && element.parentNode) {
      element.parentNode.removeChild(element);
    }
    setIntervalSpy.mockRestore();
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
});

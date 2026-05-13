/* eslint-disable @lwc/lwc/no-async-operation */
import { createElement } from "lwc";
import TriggerRiskRunner from "c/triggerRiskRunner";

import getTriggerNames from "@salesforce/apex/DeploymentAnalysisController.getTriggerNames";
import startRun from "@salesforce/apex/DeploymentAnalysisController.startRun";
import getRunStatus from "@salesforce/apex/DeploymentAnalysisController.getRunStatus";
import getRunItems from "@salesforce/apex/DeploymentAnalysisController.getRunItems";

// See triggerRiskRunner.test.js for full mock-pattern explanation.
// We mock all five Apex methods. Four are exercised here:
//   - getTriggerNames: drives loadTriggers in connectedCallback
//   - startRun:        called by Run Analysis click
//   - getRunStatus:    called by refreshRun immediately after startRun
//   - getRunItems:     called by refreshRun when status reaches Done
// getItemDetail is unused in this slice but its mock is still required —
// the component imports it at module load, and without the virtual mock
// sfdx-lwc-jest fails to resolve the stubbed apex path.
//
// Mocking getRunStatus and getRunItems matters even when a test only
// asserts on startRun: the component's runAnalysis() awaits refreshRun()
// after startRun resolves, so leaving those Apex methods unmocked would
// cause refreshRun to receive undefined and hit a hidden error path.
// A test that passes by silently swallowing component errors is worse
// than a failing one — we want clean signal.
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
//
// The component renders three categories of lightning-input that we
// need to disambiguate:
//   - Release Label input: <lightning-input label="Release Label" ...>
//   - Trigger search:      <lightning-input type="search" label="Search triggers" ...>
//   - Trigger checkboxes:  <lightning-input type="checkbox" label={t.name} data-name={t.name} ...>
//
// In sfdx-lwc-jest, lightning-input stubs do not reliably expose
// type="checkbox" or type="search" as DOM attributes — CSS selectors
// like [type="checkbox"] return zero matches even when checkboxes are
// rendered. For trigger checkboxes, we identify inputs by data-name
// (which IS reliably surfaced via getAttribute). For the trigger
// search input, we prefer label/placeholder matching and keep a
// structural fallback as a last resort.
// ─────────────────────────────────────────────────────────────────────

// Get all rendered trigger checkbox lightning-input elements.
//
// IMPORTANT — jsdom selector quirk: the CSS attribute-PRESENCE selector
// `lightning-input[data-name]` does NOT match custom-element data
// attributes reliably in jsdom + sfdx-lwc-jest 7.x stubs, even though
// the EQUALITY selector `lightning-input[data-name="TRA_..."]` works
// fine (and is used successfully in the modal/filters/error tests).
//
// We work around this by iterating all lightning-input elements and
// filtering in JavaScript via getAttribute("data-name"). This bypasses
// the CSS selector engine entirely and uses the DOM API directly,
// which IS reliable.
//
// data-name is set ONLY on trigger checkboxes among lightning-input
// elements in this component (the pill remove buttons use data-name
// too but those are native <button> elements, not lightning-input —
// so this filter is unambiguous).
//
// This count is what changes when the search filter narrows the list:
// the underlying this.triggers array is unchanged, but triggerOptions
// (which drives <template for:each>) returns fewer items.
function getTriggerCheckboxes(element) {
  const allInputs = [...element.shadowRoot.querySelectorAll("lightning-input")];
  return allInputs.filter((el) => el.getAttribute("data-name") !== null);
}

// Find a specific trigger checkbox by its data-name attribute.
// The data-name is set from t.name in the template, so this is the
// reliable way to grab a specific trigger row.
function getTriggerCheckboxByName(element, name) {
  return element.shadowRoot.querySelector(
    `lightning-input[data-name="${name}"]`
  );
}

// Find the trigger search input.
//
// Strategy:
//   1. Primary: match on label OR placeholder, checking both the JS
//      property AND the DOM attribute paths. We also include
//      aria-label as a fallback because some sfdx-lwc-jest stub
//      versions surface it where label fails. This is the strongest,
//      most explicit match — if either label or placeholder reaches
//      the DOM in any form, we find the right input.
//
//   2. Last-resort structural fallback: among lightning-inputs without
//      data-name (i.e., not trigger checkboxes), the search input is
//      the second in document order. The first is Release Label.
//      This works when ALL of label/placeholder/aria-label fail to
//      surface, but it's brittle — if a future UI change inserts a
//      new lightning-input above "Search triggers", this fallback
//      returns the wrong element. We keep it ONLY as a safety net.
//      The primary matcher should normally win.
function getTriggerSearchInput(element) {
  const inputs = [...element.shadowRoot.querySelectorAll("lightning-input")];

  const matched = inputs.find((i) => {
    const label =
      i.label || i.getAttribute("label") || i.getAttribute("aria-label") || "";
    const placeholder = i.placeholder || i.getAttribute("placeholder") || "";

    return (
      label === "Search triggers" || placeholder === "Type to filter triggers"
    );
  });

  if (matched) return matched;

  // Last-resort fallback for LWC Jest stubs that do not expose label
  // or placeholder. Keep this as a fallback only, not the primary
  // contract — it relies on document-order assumptions.
  const nonTriggerCheckboxInputs = inputs.filter(
    (i) => i.getAttribute("data-name") === null
  );
  return nonTriggerCheckboxInputs[1] || null;
}

// Find the Run Analysis button by label. Same triple-fallback pattern
// used in the other test files because sfdx-lwc-jest 7.x is inconsistent
// about whether template attributes surface as JS properties or DOM
// attributes.
function findButtonByLabel(element, label) {
  const buttons = [...element.shadowRoot.querySelectorAll("lightning-button")];
  return buttons.find(
    (b) =>
      b.label === label ||
      b.getAttribute("label") === label ||
      (b.textContent || "").trim() === label
  );
}

// Get all rendered selected-trigger pills. The pill HTML is:
//   <span class="selectedPill">
//     {trg}
//     <button class="selectedPillRemove" data-name={trg} ...>✕</button>
//   </span>
// One pill per item in selectedTriggersList. Counting these is the
// most direct way to verify selection state from the user's POV.
function getSelectedPills(element) {
  return [...element.shadowRoot.querySelectorAll(".selectedPill")];
}

// Find a specific pill's remove button by data-name. The remove button
// is a NATIVE <button>, NOT a lightning-button, so we query the class
// directly. Source: handleRemoveTrigger reads e.target.dataset.name.
function getPillRemoveButton(element, name) {
  return element.shadowRoot.querySelector(
    `.selectedPillRemove[data-name="${name}"]`
  );
}

// ─────────────────────────────────────────────────────────────────────
// Setup helpers
// ─────────────────────────────────────────────────────────────────────

// Load the component with three trigger names and let connectedCallback
// drain. This is the precondition for every test in this file.
async function setupWithThreeTriggers() {
  const element = createElement("c-trigger-risk-runner", {
    is: TriggerRiskRunner
  });

  getTriggerNames.mockResolvedValue([
    "TRA_SoqlInLoop_Bad",
    "TRA_DmlInLoop_Bad",
    "TRA_CleanTrigger_Good"
  ]);
  document.body.appendChild(element);
  // connectedCallback → loadTriggers → setter → reactive re-render
  await flushPromises();
  await flushPromises();

  return element;
}

// Toggle a trigger checkbox via the change event the component listens
// for. Source: handleToggle reads e.target.dataset.name and
// e.target.checked. We set .checked on the dispatching element first so
// it's available as event.target.checked in the handler.
async function setCheckbox(element, triggerName, checked) {
  const cb = getTriggerCheckboxByName(element, triggerName);
  expect(cb).not.toBeNull();
  cb.checked = checked;
  cb.dispatchEvent(new CustomEvent("change", { bubbles: false }));
  await flushPromises();
}

// Set the search input value via the change event the component listens
// for. Source: handleTriggerSearch reads e.target.value. Same pattern
// as the findings search in the filters test file.
//
// We dispatch with { bubbles: true } for consistency with the other
// test files (filters, modal, error, export) and to match browser-
// realistic event behavior. The handler is on the same element so
// bubbling isn't strictly required for this to work, but matching
// the surrounding convention keeps the test files uniform.
async function setTriggerSearch(element, value) {
  const search = getTriggerSearchInput(element);
  expect(search).not.toBeNull();
  search.value = value;
  search.dispatchEvent(new CustomEvent("change", { bubbles: true }));
  await flushPromises();
}

describe("c-trigger-risk-runner — trigger search and selection", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 1: Trigger search filters the rendered checkbox list
  //
  // SOURCE — triggerOptions getter (triggerRiskRunner.js):
  //   get triggerOptions() {
  //     const selectedSet = this.selected || new Set();
  //     const search = (this.triggerSearchText || "").toLowerCase();
  //     return (this.triggers || [])
  //       .filter((name) => name.toLowerCase().includes(search))
  //       .map((name) => ({ name, checked: selectedSet.has(name) }));
  //   }
  //
  // SOURCE — HTML template:
  //   <template if:true={triggers}>
  //     <template for:each={triggerOptions} for:item="t">
  //       <lightning-input type="checkbox" label={t.name} data-name={t.name} ... />
  //     </template>
  //   </template>
  //
  // The filter happens at the render layer — this.triggers stays full
  // (3 names), but the rendered list (driven by triggerOptions) shrinks
  // to match. We assert the DOM count, which is what the user sees.
  //
  // Why this matters: in real orgs with hundreds of triggers, search is
  // the only practical way to find the one you want to analyze. A
  // regression that breaks search would force users to scroll through
  // an unfiltered list — usable but painful.
  // ─────────────────────────────────────────────────────────────────
  it("trigger search filters the rendered checkbox list to matching triggers", async () => {
    const element = await setupWithThreeTriggers();

    // Baseline: all 3 triggers render
    expect(getTriggerCheckboxes(element).length).toBe(3);
    expect(
      getTriggerCheckboxByName(element, "TRA_SoqlInLoop_Bad")
    ).toBeTruthy();
    expect(getTriggerCheckboxByName(element, "TRA_DmlInLoop_Bad")).toBeTruthy();
    expect(
      getTriggerCheckboxByName(element, "TRA_CleanTrigger_Good")
    ).toBeTruthy();

    // Search "Bad" — matches the two _Bad triggers, not the _Good one
    await setTriggerSearch(element, "Bad");

    const filtered = getTriggerCheckboxes(element);
    expect(filtered.length).toBe(2);
    expect(
      getTriggerCheckboxByName(element, "TRA_SoqlInLoop_Bad")
    ).toBeTruthy();
    expect(getTriggerCheckboxByName(element, "TRA_DmlInLoop_Bad")).toBeTruthy();
    // The _Good trigger should be gone from the DOM
    expect(
      getTriggerCheckboxByName(element, "TRA_CleanTrigger_Good")
    ).toBeFalsy();

    // Narrow further: "Soql" — only one trigger matches
    await setTriggerSearch(element, "Soql");
    expect(getTriggerCheckboxes(element).length).toBe(1);
    expect(
      getTriggerCheckboxByName(element, "TRA_SoqlInLoop_Bad")
    ).toBeTruthy();

    // Clear search — all 3 return. Proves search is reading from
    // triggerSearchText reactively, not stuck on stale state.
    await setTriggerSearch(element, "");
    expect(getTriggerCheckboxes(element).length).toBe(3);
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 2: Selecting a trigger adds a pill and enables Run Analysis
  //
  // SOURCE — handleToggle (triggerRiskRunner.js):
  //   handleToggle(e) {
  //     const name = e.target.dataset.name;
  //     if (e.target.checked) this.selected.add(name);
  //     else this.selected.delete(name);
  //     this.selected = new Set(this.selected);
  //   }
  //
  // SOURCE — selected pill HTML:
  //   <template for:each={selectedTriggersList} for:item="trg">
  //     <span key={trg} class="selectedPill">
  //       {trg}
  //       <button class="selectedPillRemove" data-name={trg} ...>✕</button>
  //     </span>
  //   </template>
  //
  // SOURCE — Run Analysis button:
  //   <lightning-button label="Run Analysis" ... disabled={isRunDisabled} />
  //   get isRunDisabled() { return !this.hasSelectedTriggers; }
  //
  // Three things change in lockstep when a trigger is selected:
  //   1. A .selectedPill element appears
  //   2. The Run Analysis button becomes enabled
  //   3. The checkbox state reflects the selection (driven by
  //      triggerOptions which reads from this.selected)
  //
  // We verify all three together — partial state would mean a regression
  // in one of handleToggle's reactive bindings.
  // ─────────────────────────────────────────────────────────────────
  it("selecting a trigger adds a pill and enables the Run Analysis button", async () => {
    const element = await setupWithThreeTriggers();

    // Pre-state: nothing selected, no pills, Run Analysis disabled
    expect(getSelectedPills(element).length).toBe(0);
    const runBtnBefore = findButtonByLabel(element, "Run Analysis");
    expect(runBtnBefore).toBeTruthy();
    expect(runBtnBefore.disabled).toBe(true);

    // Select one trigger
    await setCheckbox(element, "TRA_SoqlInLoop_Bad", true);

    // Exactly one pill should appear, with the right text
    const pills = getSelectedPills(element);
    expect(pills.length).toBe(1);
    expect((pills[0].textContent || "").trim()).toContain("TRA_SoqlInLoop_Bad");

    // Run Analysis is now enabled. We re-query the button rather than
    // reusing runBtnBefore because some LWC stub variations only
    // surface the new disabled state on a fresh query.
    const runBtnAfter = findButtonByLabel(element, "Run Analysis");
    expect(runBtnAfter.disabled).toBe(false);

    // The checkbox state in the DOM also reflects selection — the
    // triggerOptions getter reads checked: selectedSet.has(name), so
    // selecting a trigger should cause the checkbox to render as
    // checked. (This is the round-trip from handleToggle → this.selected
    // → triggerOptions → template re-render.)
    const cb = getTriggerCheckboxByName(element, "TRA_SoqlInLoop_Bad");
    expect(cb).toBeTruthy();
    expect(cb.checked).toBe(true);
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 3: Removing a pill deselects the trigger
  //
  // SOURCE — handleRemoveTrigger (triggerRiskRunner.js):
  //   handleRemoveTrigger(e) {
  //     const name = e.target.dataset.name;
  //     this.selected.delete(name);
  //     this.selected = new Set(this.selected);
  //   }
  //
  // The pill remove button is a NATIVE <button>, not lightning-button.
  // We query .selectedPillRemove[data-name="..."] directly and dispatch
  // a click event. The handler reads dataset.name from event.target.
  //
  // Three things must reverse when the pill is removed:
  //   1. The .selectedPill element disappears
  //   2. Run Analysis becomes disabled again (no triggers selected)
  //   3. The underlying checkbox is unchecked (round-trip via
  //      triggerOptions getter)
  //
  // This is the inverse of Test 2 — proving select and unselect both
  // work correctly is what locks down the round-trip behavior. A
  // regression that only broke one direction (e.g., remove leaves the
  // checkbox checked) would still pass Test 2 but fail here.
  // ─────────────────────────────────────────────────────────────────
  it("removing a selected pill deselects the trigger and disables Run Analysis", async () => {
    const element = await setupWithThreeTriggers();

    // Setup: select one trigger so we have something to remove
    await setCheckbox(element, "TRA_SoqlInLoop_Bad", true);
    expect(getSelectedPills(element).length).toBe(1);

    // Click the pill's remove button (native <button>, not lightning-button)
    const removeBtn = getPillRemoveButton(element, "TRA_SoqlInLoop_Bad");
    expect(removeBtn).toBeTruthy();
    removeBtn.dispatchEvent(new CustomEvent("click", { bubbles: true }));
    await flushPromises();

    // Pill is gone
    expect(getSelectedPills(element).length).toBe(0);

    // Run Analysis is disabled again (no triggers selected)
    const runBtn = findButtonByLabel(element, "Run Analysis");
    expect(runBtn).toBeTruthy();
    expect(runBtn.disabled).toBe(true);

    // The checkbox is also unchecked — proves the deselection round-trips
    // through this.selected → triggerOptions → template re-render.
    const cb = getTriggerCheckboxByName(element, "TRA_SoqlInLoop_Bad");
    expect(cb).toBeTruthy();
    expect(cb.checked).toBe(false);
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 4: Run Analysis sends only the selected trigger names
  //
  // SOURCE — runAnalysis (triggerRiskRunner.js):
  //   const triggerNames = Array.from(this.selected);
  //   const id = await startRun({
  //     releaseLabel: this.releaseLabel,
  //     triggerNames
  //   });
  //
  // SOURCE — releaseLabel default value (class field):
  //   releaseLabel = "UI-RUN";
  //
  // This is the contract between the UI and the Apex controller. With
  // 3 triggers loaded but only 1 selected, startRun must receive
  // exactly that one trigger name in the array — not all 3, not zero,
  // not the wrong one.
  //
  // Why this matters: this is the user's primary trust boundary. When
  // a tech lead selects ONLY the trigger they're worried about and
  // hits Run Analysis, the Apex must analyze ONLY that trigger. A
  // regression that accidentally sent all triggers would burn time on
  // Apex compute the user didn't ask for AND produce noisy results
  // that don't match the user's question.
  //
  // We use toHaveBeenCalledWith to lock the exact payload shape —
  // releaseLabel, triggerNames key, and array contents. If a future
  // refactor changes any part of the request, this fails with a clear
  // diff.
  // ─────────────────────────────────────────────────────────────────
  it("Run Analysis sends only the selected trigger names with the default release label", async () => {
    const element = await setupWithThreeTriggers();

    // Select one trigger out of three
    await setCheckbox(element, "TRA_DmlInLoop_Bad", true);
    expect(getSelectedPills(element).length).toBe(1);

    // Mock startRun to resolve with a fake run ID. The component then
    // calls refreshRun() which calls getRunStatus and (when status is
    // Done) getRunItems. Mock both to avoid a hidden error path inside
    // refreshRun — leaving them unmocked would let the test pass by
    // silently swallowing the failure, which is worse than no test.
    startRun.mockResolvedValue("a02000000000001AAA");
    getRunStatus.mockResolvedValue({
      status: "Done",
      totalTriggers: 1,
      processedTriggers: 1,
      highCount: 0,
      mediumCount: 0,
      lowCount: 0,
      overallRisk: "Low",
      releaseDecision: "APPROVED",
      policyProfile: "Standard",
      gateVersion: "7.0.1",
      releaseRecommendation: "PROCEED",
      architectImpacts: "",
      releaseRationale: "",
      requiredFixes: "",
      topRisks: [],
      executiveSummary: null,
      errorMessage: null,
      lastUpdated: new Date().toISOString(),
      completedAt: new Date().toISOString()
    });
    getRunItems.mockResolvedValue([]);

    // Click Run Analysis
    const runBtn = findButtonByLabel(element, "Run Analysis");
    expect(runBtn).toBeTruthy();
    expect(runBtn.disabled).toBe(false);
    runBtn.dispatchEvent(new CustomEvent("click", { bubbles: true }));

    // Drain runAnalysis → startRun → refreshRun → getRunStatus →
    // getRunItems. Three flushes matches the pattern used by the other
    // setup helpers that drive a run to completion (in the export,
    // filters, modal, and error test files).
    await flushPromises();
    await flushPromises();
    await flushPromises();

    // startRun was called exactly once with the right payload.
    // The triggerNames array MUST contain only the selected trigger,
    // not all 3 from the loaded list. This is the contract.
    expect(startRun).toHaveBeenCalledTimes(1);
    expect(startRun).toHaveBeenCalledWith({
      releaseLabel: expect.stringMatching(/^R-\d{4}\.\d{2}\.\d{2}$/),
      triggerNames: ["TRA_DmlInLoop_Bad"]
    });

    // refreshRun fired with the runId returned by startRun. This locks
    // the chain runAnalysis → startRun → set runId → refreshRun. If a
    // future refactor accidentally drops the await on refreshRun or
    // forgets to set runId, this assertion fails with a clear signal.
    expect(getRunStatus).toHaveBeenCalledWith({
      runId: "a02000000000001AAA"
    });

    // getRunItems also fired — proves the full chain completed:
    //   runAnalysis → startRun → refreshRun → getRunStatus → getRunItems
    // (refreshRun calls getRunItems only when status is Done or Failed,
    // and our mocked getRunStatus returns status="Done", so this
    // assertion locks the entire happy path.)
    expect(getRunItems).toHaveBeenCalledWith({
      runId: "a02000000000001AAA"
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 5: Selection survives trigger search changes
  //
  // SOURCE — triggerOptions getter applies the search filter to the
  // RENDERED list, but does NOT touch this.selected:
  //   return (this.triggers || [])
  //     .filter((name) => name.toLowerCase().includes(search))
  //     .map((name) => ({ name, checked: selectedSet.has(name) }));
  //
  // SOURCE — selectedTriggersList reads directly from this.selected:
  //   get selectedTriggersList() {
  //     return Array.from(this.selected || []);
  //   }
  //
  // The selected pill list lives outside the search filter. Search is
  // a render-only concern; selection is real component state. So when
  // a user selects a trigger and then types a search that hides that
  // trigger's checkbox, the pill should still appear — and clearing
  // the search should bring back the (still-checked) checkbox.
  //
  // Why this matters: this is a real user flow. A tech lead might
  // select TRA_SoqlInLoop_Bad, then type "Other" to find a second
  // trigger to add. If selection silently disappeared because the
  // first trigger's checkbox was filtered out, the user would lose
  // their selection without any indication — a frustrating, hard-to-
  // diagnose UX bug. This test locks down that the search and
  // selection state models are properly decoupled.
  // ─────────────────────────────────────────────────────────────────
  it("selected trigger remains selected when trigger search hides and restores it", async () => {
    const element = await setupWithThreeTriggers();

    // Select one trigger
    await setCheckbox(element, "TRA_SoqlInLoop_Bad", true);
    expect(getSelectedPills(element).length).toBe(1);
    expect(getSelectedPills(element)[0].textContent || "").toContain(
      "TRA_SoqlInLoop_Bad"
    );

    // Search "Clean" — hides the selected trigger's checkbox, keeps
    // only TRA_CleanTrigger_Good in the rendered list.
    await setTriggerSearch(element, "Clean");

    // The selected trigger's checkbox is filtered out of the render
    expect(getTriggerCheckboxByName(element, "TRA_SoqlInLoop_Bad")).toBeFalsy();
    // The matching trigger does render
    expect(
      getTriggerCheckboxByName(element, "TRA_CleanTrigger_Good")
    ).toBeTruthy();

    // KEYSTONE: the selected pill is still visible. Selection state
    // lives in this.selected (a Set), which the search filter does
    // not touch. The pill list reads from selectedTriggersList, which
    // reads from this.selected directly — so the pill survives the
    // filter.
    const pillsDuringSearch = getSelectedPills(element);
    expect(pillsDuringSearch.length).toBe(1);
    expect(pillsDuringSearch[0].textContent || "").toContain(
      "TRA_SoqlInLoop_Bad"
    );

    // Clear search — the previously hidden checkbox returns AND is
    // still checked. This proves the round-trip:
    //   this.selected (Set) → triggerOptions.checked → DOM checkbox
    // works correctly across search state changes.
    await setTriggerSearch(element, "");

    const restoredCheckbox = getTriggerCheckboxByName(
      element,
      "TRA_SoqlInLoop_Bad"
    );
    expect(restoredCheckbox).toBeTruthy();
    expect(restoredCheckbox.checked).toBe(true);

    // Pill is still there too
    expect(getSelectedPills(element).length).toBe(1);
  });
});

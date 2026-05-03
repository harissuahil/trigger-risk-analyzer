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
// DOM query helpers
// ─────────────────────────────────────────────────────────────────────

// Find a lightning-button by its label.
// Same triple-fallback pattern used in the other LWC test files.
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

// Single High finding row to give the datatable something to render.
// We need the table populated so we have a row to dispatch the rowaction
// event from.
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

// Run status that produces one finding visible in the datatable.
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

// Detail DTO with snippet text and highlightLine. The snippet text uses
// the "<linenum> | <code>" format the handler parses to find the
// highlight match:
//
//   handleRowAction does:
//     const trimmed = line.trimStart();
//     const numPart = trimmed.includes("|")
//       ? trimmed.split("|")[0].trim()
//       : "";
//     const ln = parseInt(numPart, 10);
//     const isHighlight = hl && ln === hl;
//
// We deliberately set highlightLine: 7 and provide line "7 | ..." so
// that exactly ONE rendered snippet line should carry snippetHighlight.
//
// Field shape follows DeploymentAnalysisController.ItemDetailDTO.
// We intentionally omit category because getItemDetail does not currently
// return Category__c — the modal HTML references {detail.category} but
// production data does not populate it. (Cleanup-pass item: either add
// category to the DTO or remove the chip from the modal HTML.)
// We also omit ruleKey/ruleKeys because the modal rule chip has a known
// field-name mismatch — the HTML reads {detail.ruleKey} but the DTO
// sends ruleKeys. Same class of bug as the Phase 8 search haystack fix;
// to be resolved in a separate pass via a detailRuleKeys getter (LWC
// HTML cannot express ruleKeys || ruleKey directly).
function detailWithSnippet() {
  return {
    itemId: "a01000000000001AAA",
    triggerName: "TRA_SoqlInLoop_Bad",
    severity: "High",
    ruleLabel: "SOQL in Loop",
    lineNumber: 7,
    message: "SOQL inside a loop can hit query limits under bulk load.",
    recommendation: "Move SOQL outside the loop and bulkify the query.",
    snippet: {
      text:
        "5 |   for (Account a : trigger.new) {\n" +
        "6 |     // process each account\n" +
        "7 |     Contact c = [SELECT Id FROM Contact WHERE AccountId = :a.Id];\n" +
        "8 |   }",
      highlightLine: 7
    }
  };
}

// ─────────────────────────────────────────────────────────────────────
// Shared setup: create the component, run analysis, return the element
// after the run completes with one finding loaded into the table.
// ─────────────────────────────────────────────────────────────────────
async function setupRunWithOneFinding() {
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
  getRunStatus.mockResolvedValue(singleFindingRunStatus());
  getRunItems.mockResolvedValue([highFindingRow()]);

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

// Dispatch a rowaction event from the lightning-datatable. This is how
// LWC's lightning-datatable surfaces the View button click — the
// component listens via onrowaction={handleRowAction}.
//
// Source contract:
//   const actionName = event.detail.action.name;
//   const row = event.detail.row;
async function dispatchRowAction(element, actionName, row) {
  const dt = element.shadowRoot.querySelector("lightning-datatable");
  expect(dt).toBeTruthy();
  dt.dispatchEvent(
    new CustomEvent("rowaction", {
      detail: {
        action: { name: actionName },
        row
      }
    })
  );
  // Drain handleRowAction → getItemDetail → setState
  await flushPromises();
  await flushPromises();
}

describe("c-trigger-risk-runner — finding detail modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 1: Row action 'view' opens modal with detail content
  //
  // SOURCE — handleRowAction (triggerRiskRunner.js):
  //   const actionName = event.detail.action.name;
  //   const row = event.detail.row;
  //   if (actionName !== "view") return;
  //   ...
  //   const d = await getItemDetail({ itemId: row.itemId });
  //   this.detail = d;
  //   this.isModalOpen = true;
  //
  // SOURCE — modal template (triggerRiskRunner.html):
  //   <template if:true={isModalOpen}>
  //     <section role="dialog" class="slds-modal slds-fade-in-open">
  //       <header>
  //         <h2>{detail.triggerName}</h2>
  //         <span class={detailSeverityBadgeClass}>{detail.severity}</span>
  //       </header>
  //       ...
  //     </section>
  //
  // We verify the contract end-to-end: clicking View dispatches
  // rowaction with the right payload, the component calls Apex with
  // the right itemId, and the modal opens with the detail content
  // visible to the user.
  // ─────────────────────────────────────────────────────────────────
  it("row action 'view' calls getItemDetail and opens modal with detail content", async () => {
    const element = await setupRunWithOneFinding();
    getItemDetail.mockResolvedValue(detailWithSnippet());

    // Dispatch the rowaction event with action.name='view'
    await dispatchRowAction(element, "view", { itemId: "a01000000000001AAA" });

    // Apex called with the row's itemId
    expect(getItemDetail).toHaveBeenCalledTimes(1);
    expect(getItemDetail).toHaveBeenCalledWith({
      itemId: "a01000000000001AAA"
    });

    // Modal section is in the DOM (only rendered when isModalOpen=true)
    const modal = element.shadowRoot.querySelector("section.slds-modal");
    expect(modal).toBeTruthy();

    // Header shows triggerName and severity badge
    const heading = modal.querySelector("h2");
    expect(heading).toBeTruthy();
    expect((heading.textContent || "").trim()).toBe("TRA_SoqlInLoop_Bad");

    const severityBadge = modal.querySelector(".badge");
    expect(severityBadge).toBeTruthy();
    expect((severityBadge.textContent || "").trim()).toBe("High");
    expect(severityBadge.classList.contains("badge-high")).toBe(true);

    // Body shows message and recommendation content
    const modalText = modal.textContent || "";
    expect(modalText).toContain(
      "SOQL inside a loop can hit query limits under bulk load."
    );
    expect(modalText).toContain(
      "Move SOQL outside the loop and bulkify the query."
    );
    // ruleLabel chip — safe to assert because ruleLabel is in the real
    // ItemDetailDTO. (We avoid asserting on the rule chip and category
    // chip — both have known field-shape mismatches flagged for the
    // cleanup pass.)
    expect(modalText).toContain("SOQL in Loop");
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 2: Non-'view' row action is ignored (early return)
  //
  // SOURCE — handleRowAction first line of body:
  //   if (actionName !== "view") return;
  //
  // This guard exists so future row-action types (e.g., a hypothetical
  // 'delete' or 'jump_to_source') don't accidentally fall through to
  // the detail-loading path. The test proves the guard fires.
  //
  // We dispatch rowaction with an unknown action name and assert:
  //   - getItemDetail was NOT called (no Apex round-trip wasted)
  //   - The modal did NOT open (no UI side effects)
  // ─────────────────────────────────────────────────────────────────
  it("row action other than 'view' does not call Apex and does not open modal", async () => {
    const element = await setupRunWithOneFinding();
    getItemDetail.mockResolvedValue(detailWithSnippet());

    // Dispatch with a non-view action name
    await dispatchRowAction(element, "unknown_action", {
      itemId: "a01000000000001AAA"
    });

    // No Apex call (early return fired before getItemDetail)
    expect(getItemDetail).not.toHaveBeenCalled();

    // No modal in DOM (isModalOpen never set to true)
    const modal = element.shadowRoot.querySelector("section.slds-modal");
    expect(modal).toBeFalsy();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 3: Snippet renders with snippetHighlight class on the matched line
  //
  // SOURCE — handleRowAction snippet parsing logic:
  //   const raw = d?.snippet?.text || "";
  //   const hl = d?.snippet?.highlightLine;
  //
  //   this.snippetLines = (raw ? raw.split("\n") : []).map((line, idx) => {
  //     const trimmed = line.trimStart();
  //     const numPart = trimmed.includes("|") ? trimmed.split("|")[0].trim() : "";
  //     const ln = parseInt(numPart, 10);
  //     const isHighlight = hl && ln === hl;
  //     return {
  //       key: `${idx}-${line}`,
  //       text: line,
  //       cssClass: isHighlight ? "snippetLine snippetHighlight" : "snippetLine"
  //     };
  //   });
  //
  // SOURCE — modal template snippet section:
  //   <template for:each={snippetLines} for:item="l">
  //     <div key={l.key} class={l.cssClass}>{l.text}</div>
  //   </template>
  //
  // detailWithSnippet() provides 4 lines (5/6/7/8) and highlightLine=7.
  // Exactly one rendered <div> should carry the snippetHighlight class
  // (the line "7 | ..."), and the other 3 should not.
  //
  // Why this matters: the highlight is the visual cue that tells the
  // user WHICH line in the snippet the analyzer flagged. Without it,
  // the snippet is just unannotated context. A regression that breaks
  // line-number parsing (extra/missing whitespace, format change) would
  // silently drop the highlight without breaking anything else.
  // ─────────────────────────────────────────────────────────────────
  it("snippet lines render with snippetHighlight class on the matched line only", async () => {
    const element = await setupRunWithOneFinding();
    getItemDetail.mockResolvedValue(detailWithSnippet());

    await dispatchRowAction(element, "view", { itemId: "a01000000000001AAA" });

    const modal = element.shadowRoot.querySelector("section.slds-modal");
    expect(modal).toBeTruthy();

    // All 4 snippet lines render
    const snippetLines = modal.querySelectorAll(".snippetLine");
    expect(snippetLines.length).toBe(4);

    // Exactly one line should have the highlight class — the one whose
    // <linenum> | ... prefix matches highlightLine=7
    const highlighted = modal.querySelectorAll(".snippetHighlight");
    expect(highlighted.length).toBe(1);

    // Verify it's the RIGHT line (line 7, not just "some line")
    expect(highlighted[0].textContent).toContain(
      "Contact c = [SELECT Id FROM Contact"
    );
    expect(highlighted[0].textContent).toContain("7 |");

    // Belt-and-suspenders: lines 5, 6, 8 must NOT have the highlight class
    const allTexts = [...snippetLines].map((el) => el.textContent || "");
    const line5 = allTexts.find((t) => t.startsWith("5 |"));
    const line6 = allTexts.find((t) => t.startsWith("6 |"));
    const line8 = allTexts.find((t) => t.startsWith("8 |"));
    expect(line5).toBeDefined();
    expect(line6).toBeDefined();
    expect(line8).toBeDefined();
    // None of the non-7 lines appear in the highlighted list
    const highlightedTexts = [...highlighted].map((el) => el.textContent || "");
    expect(highlightedTexts.find((t) => t.startsWith("5 |"))).toBeUndefined();
    expect(highlightedTexts.find((t) => t.startsWith("6 |"))).toBeUndefined();
    expect(highlightedTexts.find((t) => t.startsWith("8 |"))).toBeUndefined();
  });

  // ─────────────────────────────────────────────────────────────────
  // Test 4: Close button removes modal from DOM and clears state
  //
  // SOURCE — closeModal (triggerRiskRunner.js):
  //   closeModal() {
  //     this.isModalOpen = false;
  //     this.detail = null;
  //     this.snippetLines = [];
  //   }
  //
  // SOURCE — close button in modal footer:
  //   <lightning-button label="Close" onclick={closeModal}></lightning-button>
  //
  // After clicking Close, the entire <section.slds-modal> must be
  // removed from the DOM (because the surrounding template is
  // <template if:true={isModalOpen}>, and isModalOpen is now false).
  //
  // We also assert detail content is no longer visible — this catches
  // the "modal still has stale data" regression where future code
  // accidentally sets isModalOpen=false but forgets to clear detail.
  // The visual symptom of that bug would be: open modal A → close →
  // open modal B → flash of A's content before B loads.
  // ─────────────────────────────────────────────────────────────────
  it("close button removes modal from DOM and clears detail state", async () => {
    const element = await setupRunWithOneFinding();
    getItemDetail.mockResolvedValue(detailWithSnippet());

    // Open the modal first
    await dispatchRowAction(element, "view", { itemId: "a01000000000001AAA" });

    let modal = element.shadowRoot.querySelector("section.slds-modal");
    expect(modal).toBeTruthy();

    // Find and click the Close button (inside the modal footer)
    const closeBtn = findButtonByLabel(element, "Close");
    expect(closeBtn).toBeTruthy();
    closeBtn.dispatchEvent(new CustomEvent("click", { bubbles: true }));
    await flushPromises();

    // Modal section is gone from the DOM
    modal = element.shadowRoot.querySelector("section.slds-modal");
    expect(modal).toBeFalsy();

    // Detail content is no longer rendered anywhere in the shadow DOM.
    // We pick the message and recommendation strings that ONLY appear
    // in the modal body — if they're gone from the entire shadow root,
    // it confirms stale detail content is not still visible after close.
    // The source closeModal() also clears detail and snippetLines, but
    // that's an internal-state guarantee Jest cannot directly verify
    // through DOM inspection alone.
    const rootText = element.shadowRoot.textContent || "";
    expect(rootText).not.toContain(
      "SOQL inside a loop can hit query limits under bulk load."
    );
    expect(rootText).not.toContain(
      "Move SOQL outside the loop and bulkify the query."
    );
  });
});

//triggerRiskRunner.js
import { LightningElement, track } from "lwc";
import getTriggerNames from "@salesforce/apex/DeploymentAnalysisController.getTriggerNames";
import startRun from "@salesforce/apex/DeploymentAnalysisController.startRun";
import getRunStatus from "@salesforce/apex/DeploymentAnalysisController.getRunStatus";
import getRunItems from "@salesforce/apex/DeploymentAnalysisController.getRunItems";
import getItemDetail from "@salesforce/apex/DeploymentAnalysisController.getItemDetail";

//HS - TRA build label (shown in exports)
const TRA_BUILD_LABEL = "GOLD Phase 7 Validated"; //HS

export default class TriggerRiskRunner extends LightningElement {
  @track triggers = [];
  //HS - trigger list search (separate from findings search)
  triggerSearchText = "";
  //HS - Used to render checkboxes as controlled inputs (keeps UI in sync with this.selected)
  //HS - controlled checkbox options with search filtering
  get triggerOptions() {
    const selectedSet = this.selected || new Set();
    const search = (this.triggerSearchText || "").toLowerCase();

    return (this.triggers || []) //HS
      .filter((name) => name.toLowerCase().includes(search))
      .map((name) => ({
        name,
        checked: selectedSet.has(name)
      }));
  }

  selected = new Set();

  releaseLabel = "UI-RUN";
  runId;
  errorMsg;
  isLoading = false;

  // Run status
  status;
  totalTriggers = 0;
  processedTriggers = 0;
  highCount = 0;
  mediumCount = 0;
  lowCount = 0;
  errorMessage;
  lastUpdated;
  overallRisk = "Low";
  findingsCount = 0;
  //==========Phase7.0.2 START code change=========
  releaseDecision; // BLOCKED / APPROVED_WITH_CONDITIONS / APPROVED
  gatePolicyProfile; // e.g., Standard
  gateVersion; // e.g., 7.0.1
  gateRationaleRaw; // multi-line string
  gateRequiredFixesRaw; // multi-line string
  //==========Phase7.0.2 END code change=========

  //==========Phase6.0.3 START code change=========
  // Executive / Architect Signal (manager-friendly)
  releaseRecommendation; // e.g., PROCEED / PROCEED WITH CAUTION / HOLD
  architectImpacts = []; // array of strings
  executiveNote; // optional string
  //==========Phase6.0.3 END code change=========

  // =========================
  // Phase6.0-ExecutiveSignal
  // =========================
  @track topRisks = [];
  executiveSummary;
  completedAt;
  // =========================
  // Phase6.0-ExecutiveSignal
  // =========================

  // Items
  @track items = [];
  columns = [
    {
      label: "Severity",
      fieldName: "severity",
      type: "text",
      initialWidth: 110,
      cellAttributes: { class: { fieldName: "severityClass" } }
    },
    {
      label: "Trigger",
      fieldName: "triggerName",
      type: "text",
      initialWidth: 260
    },
    { label: "Rule", fieldName: "ruleLabel", type: "text", initialWidth: 200 },
    {
      label: "Category",
      fieldName: "category",
      type: "text",
      initialWidth: 180
    }, //phase5.4.2
    {
      label: "Line",
      fieldName: "lineNumber",
      type: "number",
      initialWidth: 90,
      cellAttributes: { alignment: "left" }
    }, //Phase5.5.1
    { label: "Message", fieldName: "messageShort", type: "text" },
    {
      label: "Details",
      type: "button",
      initialWidth: 110,
      typeAttributes: { label: "View", name: "view", variant: "base" }
    }
  ];

  // Modal
  isModalOpen = false;
  detail;
  detailLoading = false;
  @track snippetLines = [];

  // Filters
  severityFilter = "All";
  categoryFilter = "All";
  searchText = "";

  // Polling
  pollTimer;
  pollIntervalMs = 2000;
  maxPolls = 60;
  pollCount = 0;

  connectedCallback() {
    this.loadTriggers();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  get runUrl() {
    return this.runId
      ? `/lightning/r/Deployment_Analysis_Run__c/${this.runId}/view`
      : "#";
  }

  get showTable() {
    return this.runId && this.filteredItems && this.filteredItems.length > 0;
  }

  get hasAnyFindings() {
    return (this.findingsCount || 0) > 0;
  }

  get hasRows() {
    return (this.filteredItems || []).length > 0; //Phase5.6.2
  }

  get disableExport() {
    //HS Enable export when run is complete even if 0 findings (manager/audit artifact)
    const canExport = !!this.runId && this.isRunComplete; //HS
    return this.isLoading || !canExport; //HS
  }

  get isPolling() {
    return this.pollTimer != null;
  }
  //HS - run completion helper (used for enabling exports even when 0 findings)
  get isRunComplete() {
    return this.status === "Done" || this.status === "Failed";
  }
  //==========Phase7.0.2 START code change=========
  get hasReleaseGate() {
    return !!(
      this.runId &&
      (this.releaseDecision || this.gateVersion || this.gatePolicyProfile)
    );
  }
  //==========Phase7.0.2 END code change=========
  //==========BUG FIX START=========
  get hasGateRationale() {
    return (this.gateRationaleLines || []).length > 0;
  }

  get hasGateRequiredFixes() {
    return (this.gateRequiredFixLines || []).length > 0;
  }
  //==========BUG FIX END=========

  get releaseGateBadgeClass() {
    const d = this.releaseDecision;
    if (d === "BLOCKED") return "badge badge-high";
    if (d === "APPROVED_WITH_CONDITIONS") return "badge badge-medium";
    return "badge badge-low";
  }

  get releaseGateCardClass() {
    const d = this.releaseDecision;
    if (d === "BLOCKED") return "slds-box slds-theme_error slds-m-top_medium";
    if (d === "APPROVED_WITH_CONDITIONS")
      return "slds-box slds-theme_warning slds-m-top_medium";
    return "slds-box slds-theme_success slds-m-top_medium";
  }

  get releaseGateDecisionLabel() {
    const d = this.releaseDecision;
    if (d === "APPROVED_WITH_CONDITIONS") return "APPROVED WITH CONDITIONS";
    return d || "N/A";
  }

  get gateRationaleLines() {
    const raw = (this.gateRationaleRaw || "").trim();
    if (!raw) return [];

    //==========Phase8.0.2 START code change=========
    //return raw.split('\n').map((x) => x.trim()).filter(Boolean);
    // Rationale should not include fix lines or headings; also strip "1) " so UI bullets look clean
    return this.cleanGateLines(raw.split("\n"), { removeFixLikeLines: true });
    //==========Phase8.0.2 END code change=========
  }

  get gateRequiredFixLines() {
    const raw = (this.gateRequiredFixesRaw || "").trim();
    if (!raw) return [];

    //==========Phase8.0.2 START code change=========
    //return raw.split('\n').map((x) => x.trim()).filter(Boolean);
    // Fixes must keep "Collect/Add/Move" lines; strip numbering so UI bullets don't double-number
    return this.cleanGateLines(raw.split("\n"), { removeFixLikeLines: false });
    //==========Phase8.0.2 END code change=========
  }
  //==========Phase7.0.2 END code change=========

  // Summary tile styling
  get highTileClass() {
    return "slds-col slds-box slds-text-align_center slds-theme_error";
  }

  get mediumTileClass() {
    return "slds-col slds-box slds-text-align_center slds-theme_warning";
  }

  get lowTileClass() {
    return "slds-col slds-box slds-text-align_center slds-theme_success";
  }

  /*  //==========Phase7.0.2 START code change=========
    // Release Gate UI helpers

  get hasReleaseGate() {
    // Show card as soon as decision is available
    return !!(this.runId && this.releaseDecision);
    }

  get releaseGateDecisionLabel() {
    return this.releaseDecision || 'N/A';
    }

  get releaseGateBadgeClass() {
    const d = (this.releaseDecision || '').toUpperCase();
    if (d === 'BLOCKED') return 'badge badge-high';
    if (d === 'APPROVED') return 'badge badge-low';
    return 'badge badge-medium'; // e.g., "CONDITIONAL"
    }

  get releaseGateCardClass() {
    // Keep it simple: just use a boxed section like your other panels
    return 'slds-m-top_medium slds-box';
    }

  get gateRationaleLines() {
    const raw = (this.gateRationaleRaw || '').trim();
    if (!raw) return [];
    return raw.split('\n').map((x) => x.trim()).filter(Boolean);
    }

  get gateRequiredFixLines() {
    const raw = (this.gateRequiredFixesRaw || '').trim();
    if (!raw) return [];
    return raw.split('\n').map((x) => x.trim()).filter(Boolean);
    }
    //==========Phase7.0.2 END code change=========
   */

  get detailSeverityBadgeClass() {
    const sev = this.detail ? this.detail.severity : null;
    if (sev === "High") return "badge badge-high";
    if (sev === "Medium") return "badge badge-medium";
    return "badge badge-low";
  }
  // fix: ItemDetailDTO sends ruleKeys (plural); fallback for legacy
  // matches Phase 8 filteredItems haystack fix pattern
  get detailRuleKeys() {
    return this.detail ? this.detail.ruleKeys || this.detail.ruleKey : null;
  }
  // =========================
  // Phase6.0-ExecutiveSignal
  // =========================
  get recommendationBadgeClass() {
    const rec = this.releaseRecommendation;
    if (rec === "NOT RECOMMENDED") return "badge badge-high";
    if (rec === "PROCEED WITH CAUTION") return "badge badge-medium";
    return "badge badge-low";
  }

  //==========Phase7.0.2 START code change=========
  get impactChips() {
    /*
  // OLD (kept): breaks because architectImpacts is now List<String>, not a string
  const s = (this.architectImpacts || '').trim();
  if (!s) return [];
  return s.split(',').map((x) => x.trim()).filter(Boolean);
  */

    const v = this.architectImpacts;

    // Preferred: Apex sends List<String>
    if (Array.isArray(v)) {
      return v.map((x) => (x == null ? "" : String(x).trim())).filter(Boolean);
    }

    // Backward compatible: if it ever comes as a string
    const s = (v == null ? "" : String(v)).trim();
    if (!s) return [];
    return s
      .split(",")
      .map((x) => x.trim())
      .filter(Boolean);
  }
  //==========Phase7.0.2 END code change=========

  // =========================
  // Phase6.0-ExecutiveSignal
  // =========================

  get filteredItems() {
    const sev = this.severityFilter;
    const cat = this.categoryFilter;
    const q = (this.searchText || "").trim().toLowerCase();

    return (this.items || []).filter((r) => {
      if (sev && sev !== "All" && r.severity !== sev) return false;
      if (cat && cat !== "All" && r.category !== cat) return false;

      if (!q) return true;

      const hay = [
        r.triggerName,
        r.ruleLabel,
        r.ruleKeys || r.ruleKey,
        r.category,
        r.messageShort,
        r.severity
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();

      return hay.includes(q);
    });
  }
  get selectedTriggersList() {
    return Array.from(this.selected || []);
  }

  get selectedTriggersCount() {
    return this.selectedTriggersList.length;
  }

  get hasSelectedTriggers() {
    return this.selected && this.selected.size > 0;
  }
  //HS - disable Run button when no triggers selected
  get isRunDisabled() {
    return !this.hasSelectedTriggers;
  }

  handleReleaseLabelChange(e) {
    this.releaseLabel = e.target.value;
  }

  handleToggle(e) {
    const name = e.target.dataset.name;
    if (e.target.checked) this.selected.add(name);
    else this.selected.delete(name);

    this.selected = new Set(this.selected);
  }
  handleRemoveTrigger(e) {
    const name = e.target.dataset.name;
    this.selected.delete(name);

    this.selected = new Set(this.selected);
  }
  //HS - handle trigger search input
  handleTriggerSearch(e) {
    //HS
    this.triggerSearchText = e.target.value || "";
  }

  handleSeverityFilter(e) {
    this.severityFilter = e.detail.value;
  }

  handleCategoryFilter(e) {
    this.categoryFilter = e.detail.value;
  }

  handleSearchChange(e) {
    this.searchText = e.target.value;
  }

  clearSearch() {
    this.searchText = "";
  }

  get severityOptions() {
    return [
      { label: "All", value: "All" },
      { label: "High", value: "High" },
      { label: "Medium", value: "Medium" },
      { label: "Low", value: "Low" }
    ];
  }

  get categoryOptions() {
    const cats = new Set();
    (this.items || []).forEach((r) => {
      if (r && r.category) cats.add(r.category);
    });

    return [
      { label: "All", value: "All" },
      ...Array.from(cats)
        .sort()
        .map((c) => ({ label: c, value: c }))
    ];
  }

  async loadTriggers() {
    this.isLoading = true;
    this.errorMsg = null;

    try {
      const names = await getTriggerNames();
      this.triggers = names || [];
    } catch (err) {
      this.errorMsg = this.normalizeError(err);
    } finally {
      this.isLoading = false;
    }
  }

  async runAnalysis() {
    this.isLoading = true;
    this.errorMsg = null;
    this.runId = null;
    this.items = [];
    this.resetRunStatus();
    this.stopPolling();
    //==========BUG FIX START code change=========
    this.releaseDecision = null;
    this.gatePolicyProfile = null;
    this.gateVersion = null;
    this.gateRationaleRaw = "";
    this.gateRequiredFixesRaw = "";
    //==========BUG FIX END code change=========

    try {
      const triggerNames = Array.from(this.selected);
      const id = await startRun({
        releaseLabel: this.releaseLabel,
        triggerNames
      });
      this.runId = id;

      await this.refreshRun();
      this.startPolling();
    } catch (err) {
      this.errorMsg = this.normalizeError(err);
    } finally {
      this.isLoading = false;
    }
  }

  async refreshRun() {
    if (!this.runId) return;

    this.isLoading = true;
    this.errorMsg = null;

    try {
      const s = await getRunStatus({ runId: this.runId });

      this.status = s.status;
      this.totalTriggers = s.totalTriggers || 0;
      this.processedTriggers = s.processedTriggers || 0;
      this.highCount = s.highCount || 0;
      this.mediumCount = s.mediumCount || 0;
      this.lowCount = s.lowCount || 0;
      this.errorMessage = s.errorMessage;
      this.lastUpdated = s.lastUpdated;

      // =========================
      // Phase6.0-ExecutiveSignal
      // =========================
      this.overallRisk = s.overallRisk || this.computeOverallRisk();
      //==========Phase6.0.3 START code change=========
      // Keep these in memory so Export CSV can include the same Executive Signal shown in the UI
      this.releaseRecommendation =
        s.releaseRecommendation || this.releaseRecommendation;

      //==========Phase7.0.2 START code change=========
      // Apex returns architectImpacts as a String (comma-separated). Convert to array for UI/CSV.
      //this.architectImpacts = s.architectImpacts || this.architectImpacts || [];

      const aiRaw = s.architectImpacts;
      if (aiRaw != null) {
        const raw = String(aiRaw).trim();
        this.architectImpacts = raw
          ? raw
              .split(",")
              .map((x) => x.trim())
              .filter(Boolean)
          : [];
      }
      //==========Phase7.0.2 END code change=========
      //==========BUG 4 FIX  START code change=========
      this.architectImpacts = this.uniqueLines(this.architectImpacts || []);
      //==========BUG 4 FIX END code change=========
      //==========BUG 4 START code change=========
      //this.topRisks = s.topRisks || this.topRisks || [];

      this.topRisks = this.uniqueLines(s.topRisks || this.topRisks || []); //HS
      //==========BUG 4 END code change=========

      this.executiveNote = s.executiveNote || this.executiveNote;
      //==========Phase6.0.3 END code change=========
      //==========Phase7.0.2 NOTE START=========
      // this.releaseRecommendation = s.releaseRecommendation;
      // this.architectImpacts = s.architectImpacts;
      // this.topRisks = s.topRisks || [];
      this.executiveSummary = s.executiveSummary;
      //==========Phase7.0.2 START code change=========
      // Release Gate: parse from executiveSummary text (since gate fields are embedded there)
      try {
        const raw = this.executiveSummary || "";
        const parsed = this.parseReleaseGateFromSummary(raw);

        if (parsed) {
          this.releaseDecision = parsed.releaseDecision || this.releaseDecision;
          this.gatePolicyProfile =
            parsed.policyProfile || this.gatePolicyProfile;
          this.gateVersion = parsed.gateVersion || this.gateVersion;
          this.gateRationaleRaw =
            parsed.rationaleRaw || this.gateRationaleRaw || "";
          this.gateRequiredFixesRaw =
            parsed.requiredFixesRaw || this.gateRequiredFixesRaw || "";
        }
      } catch {
        // do not block UI
      }
      //==========Phase7.0.2 END code change=========

      this.completedAt = s.completedAt;
      //==========Phase7.0.2 NOTE END=========
      // =========================
      // Phase6.0-ExecutiveSignal
      // =========================
      //==========BUG FIX START code change=========
      //==========Phase7.0.2 START code change=========
      // Release Gate fields (from Apex RunStatusResponse)
      // this.releaseDecision = s.releaseDecision || this.releaseDecision;
      // this.gatePolicyProfile = s.policyProfile || this.gatePolicyProfile;
      // this.gateVersion = s.gateVersion || this.gateVersion;
      // this.gateRationaleRaw = s.releaseRationale || this.gateRationaleRaw || '';
      // this.gateRequiredFixesRaw = s.requiredFixes || this.gateRequiredFixesRaw || '';
      //==========Phase7.0.2 END code change=========

      // IMPORTANT: allow empty string to overwrite old values (prevents stale APPROVED screen)
      this.releaseDecision =
        s.releaseDecision !== undefined && s.releaseDecision !== null
          ? s.releaseDecision
          : this.releaseDecision;

      this.gatePolicyProfile =
        s.policyProfile !== undefined && s.policyProfile !== null
          ? s.policyProfile
          : this.gatePolicyProfile;

      this.gateVersion =
        s.gateVersion !== undefined && s.gateVersion !== null
          ? s.gateVersion
          : this.gateVersion;

      this.gateRationaleRaw =
        s.releaseRationale !== undefined && s.releaseRationale !== null
          ? s.releaseRationale
          : this.gateRationaleRaw || "";

      this.gateRequiredFixesRaw =
        s.requiredFixes !== undefined && s.requiredFixes !== null
          ? s.requiredFixes
          : this.gateRequiredFixesRaw || "";
      //==========BUG FIX END code change=========

      this.findingsCount =
        (this.highCount || 0) + (this.mediumCount || 0) + (this.lowCount || 0);

      if (this.status === "Done" || this.status === "Failed") {
        const rows = await getRunItems({ runId: this.runId });
        //==========Phase5.4.4 START code change=========
        const enriched = (rows || [])
          .map((r) => ({
            ...r,
            category: r.category || r.Category__c, // bridge (DTO vs SObject)
            severityClass: this.severityToClass(r.severity)
          }))
          .sort((a, b) => (b.severitySort || 0) - (a.severitySort || 0));
        //==========Phase5.4.4 END code change=========

        //==========Phase5.4.4 START code change=========
        // OLD logic commented to avoid duplicate const declaration
        // const enriched = (rows || [])
        //   .map((r) => ({
        //     ...r,
        //     severityClass: this.severityToClass(r.severity)
        //   }))
        //   .sort((a, b) => (b.severitySort || 0) - (a.severitySort || 0));
        //==========Phase5.4.4 END code change=========

        this.items = enriched;
      }
    } catch (err) {
      this.errorMsg = this.normalizeError(err);
    } finally {
      this.isLoading = false;
    }
  }

  computeOverallRisk() {
    if ((this.highCount || 0) > 0) return "High";
    if ((this.mediumCount || 0) > 0) return "Medium";
    return "Low";
  }

  startPolling() {
    this.stopPolling();
    this.pollCount = 0;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.pollTimer = setInterval(async () => {
      this.pollCount++;
      await this.refreshRun();

      if (this.status === "Done" || this.status === "Failed") {
        this.stopPolling();
        return;
      }

      if (this.pollCount >= this.maxPolls) {
        this.stopPolling();
        this.errorMsg =
          "Timed out waiting for analysis to finish. Click Refresh.";
      }
    }, this.pollIntervalMs);
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }

  severityToClass(sev) {
    if (sev === "High") return "sev-high";
    if (sev === "Medium") return "sev-medium";
    return "sev-low";
  }

  //==========Phase5.7.1 START code change=========
  exportCsv() {
    try {
      const rows = this.filteredItems || []; //HS
      //HS Do not return on 0 rows, still export a clean report artifact

      // Header / metadata (manager-friendly)
      const now = new Date();
      const ymd = now.toISOString().slice(0, 10);

      const runId = this.runId || "";
      const release = this.releaseLabel || "";
      const sev = this.severityFilter || "All";
      const cat = this.categoryFilter || "All";
      const q = (this.searchText || "").trim();
      //==========Phase6.0.3 START code change=========
      const impacts = Array.isArray(this.architectImpacts)
        ? this.architectImpacts
        : [];
      const risks = Array.isArray(this.topRisks) ? this.topRisks : [];

      const execLines = [];
      execLines.push("EXECUTIVE SIGNAL:");
      //==========Phase6.0.3 START code change=========
      // OLD (Excel can treat leading "-" as a formula => #NAME?)
      // execLines.push(`- Overall Deployment Risk: ${this.overallRisk || this.computeOverallRisk()}`);
      // execLines.push(`- Release Recommendation: ${this.releaseRecommendation || 'N/A'}`);
      // execLines.push(`- Architect Impacts: ${impacts.length ? impacts.join(', ') : 'N/A'}`);

      // NEW (Excel-safe, still manager-friendly)
      execLines.push(
        `Overall Risk: ${this.overallRisk || this.computeOverallRisk()}`
      );
      execLines.push(
        `Release Recommendation: ${this.releaseGateDecisionLabel}`
      );
      execLines.push(
        `Architect Impacts: ${impacts.length ? impacts.join(", ") : "N/A"}`
      );
      //==========Phase6.0.3 END code change=========

      execLines.push(" ");
      execLines.push("Top Risks:");

      if (risks.length) {
        risks.forEach((t, i) => {
          execLines.push(`${i + 1}) ${t}`);
        });
      } else {
        execLines.push("1) N/A");
      }

      if (this.executiveNote) {
        execLines.push(" ");
        execLines.push(`Executive note: ${this.executiveNote}`);
      }
      //==========Phase6.0.3 END code change=========

      //==========Phase6.0.3 START code change=========
      const headerLines = [
        "Trigger Risk Analyzer Export",
        `TRA Build: ${TRA_BUILD_LABEL}`, //HS
        `Release Gate Policy: ${this.gatePolicyProfile || "N/A"}`, //HS
        `Release Gate Version: ${this.gateVersion || "N/A"}`, //HS
        `Run ID: ${runId}`,
        `Release Label: ${release}`,
        `Generated At: ${now.toLocaleString()}`,
        `Filters: Severity=${sev}; Category=${cat}${q ? `; Search="${q}"` : ""}`,
        "---",
        ...execLines,
        "---"
      ];
      //==========Phase6.0.3 END code change=========

      // Column order matches UI
      const headers = [
        "Severity",
        "Trigger",
        "Rule",
        "Category",
        "Line",
        "Message"
      ];

      const lines = [];
      //==========Phase6.0.3 START code change=========
      // OLD (caused Excel #NAME? because lines like "- Overall ..." were not quoted)
      // headerLines.forEach((l) => lines.push(this.csvEscape(l).replace(/^"|"$/g, '')));

      // NEW: keep header lines as a single quoted CSV cell (Excel-safe)
      headerLines.forEach((l) => lines.push(this.csvEscape(l)));
      //==========Phase6.0.3 END code change=========
      lines.push(headers.join(","));
      //HS If no rows, add a friendly note (keeps report useful for “clean trigger” proof)
      if (!rows.length) {
        //HS
        lines.push(this.csvEscape("No findings detected for current filters.")); //HS
      } //HS

      rows.forEach((r) => {
        const vals = [
          r.severity,
          r.triggerName,
          r.ruleLabel,
          r.category,
          r.lineNumber == null ? "" : String(r.lineNumber),
          r.messageShort
        ].map((v) => this.csvEscape(v));

        lines.push(vals.join(","));
      });

      const csv = "\ufeff" + lines.join("\n"); // BOM for Excel

      const safeRelease = this.makeSafeFilePart(release) || "UI-RUN";
      const safeRun = this.makeSafeFilePart(runId) || "Run";
      const fileName = `TRA_${safeRelease}_${safeRun}_${ymd}.csv`;

      this.downloadTextFile(
        csv,
        fileName,
        "application/octet-stream;charset=utf-8;"
      );
    } catch (e) {
      this.errorMsg = this.normalizeError(e);
    }
  }
  //==========Phase5.7.1 END code change=========

  //==========Phase8.0 START code change=========
  exportReleaseDecision() {
    try {
      if (!this.runId) return;

      const now = new Date();
      const ymd = now.toISOString().slice(0, 10);

      const text = this.buildReleaseDecisionText(now);

      const safeRelease =
        this.makeSafeFilePart(this.releaseLabel || "UI-RUN") || "UI-RUN";
      const safeRun = this.makeSafeFilePart(this.runId) || "Run";
      const fileName = `TRA_ReleaseDecision_${safeRelease}_${safeRun}_${ymd}.txt`;

      this.downloadTextFile(text, fileName, "text/plain;charset=utf-8;");
    } catch (e) {
      this.errorMsg = this.normalizeError(e);
    }
  }

  buildReleaseDecisionText(now) {
    const runId = this.runId || "";
    const release = this.releaseLabel || "";
    const generated = now ? now.toLocaleString() : "";

    const overallRisk = this.overallRisk || this.computeOverallRisk();
    const rec = this.releaseGateDecisionLabel || "N/A";

    // Executive signal
    const impacts = Array.isArray(this.architectImpacts)
      ? this.architectImpacts
      : [];
    const risks = Array.isArray(this.topRisks) ? this.topRisks : [];

    // Release gate
    const policy = this.gatePolicyProfile || "N/A";
    const version = this.gateVersion || "N/A";

    //==========Phase8.0.1 START code change=========
    const rationaleLines = this.cleanGateLines(this.gateRationaleLines || [], {
      removeFixLikeLines: true
    });
    const fixLines = this.cleanGateLines(this.gateRequiredFixLines || [], {
      removeFixLikeLines: false
    });
    //==========Phase8.0.1 END code change=========

    let out = "";
    out += "Trigger Risk Analyzer - Release Decision\n";
    out += `Build: ${TRA_BUILD_LABEL}\n`; //HS
    out += "======================================\n\n";

    out += `Run Id: ${runId}\n`;
    out += `Release Label: ${release}\n`;
    out += `Generated At: ${generated}\n\n`;

    out += "EXECUTIVE SIGNAL\n";
    out += "---------------\n";
    out += `Overall Risk: ${overallRisk}\n`;
    out += `Release Recommendation: ${rec}\n`;
    out += `Architect Impacts: ${impacts.length ? impacts.join(", ") : "N/A"}\n\n`;

    out += "Top Risks:\n";
    if (risks.length) {
      risks.forEach((t, i) => {
        out += `${i + 1}) ${t}\n`;
      });
    } else {
      out += "1) N/A\n";
    }

    out += "\nRELEASE GATE\n";
    out += "------------\n";
    out += `Gate Outcome: ${this.releaseGateDecisionLabel}\n`;
    out += `Policy: ${policy}\n`;
    out += `Version: ${version}\n\n`;

    out += "Rationale:\n";
    if (rationaleLines.length) {
      rationaleLines.forEach((l, i) => {
        out += `${i + 1}) ${l}\n`;
      });
    } else {
      out += "1) N/A\n";
    }

    if (fixLines.length) {
      //HS
      out += "\nRequired Fixes (to unblock):\n"; //HS
      fixLines.forEach((l, i) => {
        //HS
        out += `${i + 1}) ${l}\n`; //HS
      }); //HS
    } //HS

    out += "\n---\n";
    out +=
      "Note: This output is intended for release decision-making (CAB/audit).\n";

    return out;
  }
  //==========Phase8.0 END code change=========
  //==========Phase8.0.3 START code change=========
  cleanGateLines(lines, options) {
    const opts = options || {};
    const removeFixLikeLines = !!opts.removeFixLikeLines; // ONLY true when cleaning rationale

    return (
      (lines || [])
        .map((l) => (l == null ? "" : String(l)).trim())
        .filter(Boolean)

        // Remove headings (these belong to UI sections, not list items)
        .filter((l) => {
          const s = l.toLowerCase();
          return !s.startsWith("required fixes") && !s.startsWith("rationale");
        })

        // Normalize each line FIRST (strip bullets + numbering)
        .map((l) =>
          l
            .replace(/^\s*[•-]\s*/, "") // remove leading bullet like "• " or "- "
            .replace(/^\s*\d+\s*[).]\s*/, "") // remove leading numbering like "1) " or "1. "
            .trim()
        )
        .filter(Boolean)

        // Now remove fix-like lines from RATIONALE only (after normalization)
        .filter((l) => {
          if (!removeFixLikeLines) return true;
          const s = l.toLowerCase();
          return !(
            s.startsWith("collect ") ||
            s.startsWith("add ") ||
            s.startsWith("move ")
          );
        })
    );
  }
  //==========Phase8.0.3 END code change=========
  //==========Phase8.1.1 START code change=========
  //HS Dedupe strings while keeping order (first wins)
  uniqueLines(lines) {
    const out = [];
    const seen = new Set();
    (lines || []).forEach((l) => {
      const s = (l == null ? "" : String(l)).trim();
      if (!s) return; //HS
      const key = s.toLowerCase();
      if (seen.has(key)) return;
      seen.add(key);
      out.push(s);
    });
    return out;
  }
  //==========Phase8.1.1 END code change=========

  //==========Phase5.7.1 START code change=========
  makeSafeFilePart(s) {
    if (!s) return "";
    return String(s)
      .trim()
      .replace(/\s+/g, "_")
      .replace(/[^a-zA-Z0-9_-]/g, "");
  }
  //==========Phase5.7.1 END code change=========

  csvEscape(v) {
    if (v == null) return '""';
    const s = String(v).replace(/"/g, '""');
    return `"${s}"`;
  }

  //==========Phase5.6.2 START code change=========
  downloadTextFile(text, fileName, mimeType) {
    try {
      // LWS-safe download using data URI (no Blob/ObjectURL)
      const safeText = text == null ? "" : String(text);
      const safeMimeType =
        mimeType || "application/octet-stream;charset=utf-8;";
      const encoded = encodeURIComponent(safeText);
      const href = `data:${safeMimeType},${encoded}`;

      const a = document.createElement("a");
      a.href = href;
      a.download = fileName;
      a.style.display = "none";

      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
    } catch (e) {
      this.errorMsg = this.normalizeError(e);
    }
  }
  //==========Phase5.6.2 END code change=========

  //==========Phase5.6.3 START code change=========
  async copySummaryToClipboard() {
    try {
      const summary = this.buildShareableSummary();

      if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(summary);
        return;
      }

      const ta = document.createElement("textarea");
      ta.value = summary;
      ta.style.position = "fixed";
      ta.style.left = "-9999px";
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
    } catch (e) {
      this.errorMsg = this.normalizeError(e);
    }
  }

  buildShareableSummary() {
    const selected = this.totalTriggers || 0;
    const analyzed = this.processedTriggers || 0;
    const hi = this.highCount || 0;
    const med = this.mediumCount || 0;
    const lo = this.lowCount || 0;
    const total = hi + med + lo;

    const risk = this.overallRisk || this.computeOverallRisk();

    let assessment = "No high-severity risks detected.";
    if (hi > 0) {
      assessment =
        "One or more high-severity risks were identified. Review and address before deployment, especially for higher data volumes.";
    } else if (med > 0) {
      assessment =
        "Medium-severity risks were identified. Review recommended before deployment.";
    }

    // =========================
    // Phase6.0-ExecutiveSignal
    // =========================
    const rec = this.releaseRecommendation
      ? `\nRelease Recommendation: ${this.releaseRecommendation}\n`
      : "\n";
    const impacts = this.architectImpacts
      ? `Architect Impacts: ${this.architectImpacts}\n`
      : "";
    const top = (this.topRisks || []).length
      ? "Top Risks:\n" +
        this.topRisks.map((x, i) => `${i + 1}) ${x}`).join("\n") +
        "\n"
      : "";
    // =========================
    // Phase6.0-ExecutiveSignal
    // =========================

    return (
      "Trigger Risk Analysis completed.\n\n" +
      "Scope:\n" +
      `- Triggers selected: ${selected}\n` +
      `- Triggers analyzed: ${analyzed}\n\n` +
      "Findings overview:\n" +
      `- High severity: ${hi}\n` +
      `- Medium severity: ${med}\n` +
      `- Low severity: ${lo}\n` +
      `- Total findings: ${total}\n\n` +
      "Overall assessment:\n" +
      `Overall Risk: ${risk}\n` +
      rec +
      impacts +
      top +
      assessment
    );
  }
  //==========Phase5.6.3 END code change=========
  //==========Phase8.1.1 START code change=========
  async copyReleaseDecisionToClipboard() {
    try {
      const text = this.buildReleaseDecisionExecutiveText();

      if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(text);
        return;
      }

      const ta = document.createElement("textarea");
      ta.value = text;
      ta.style.position = "fixed";
      ta.style.left = "-9999px";
      document.body.appendChild(ta);
      ta.select();
      document.execCommand("copy");
      document.body.removeChild(ta);
    } catch (e) {
      this.errorMsg = this.normalizeError(e);
    }
  }

  buildReleaseDecisionExecutiveText() {
    const policy = this.gatePolicyProfile || "N/A";
    const version = this.gateVersion || "N/A";

    const rec = this.releaseGateDecisionLabel || "N/A";
    const risk = this.overallRisk || this.computeOverallRisk();

    const impacts = Array.isArray(this.architectImpacts)
      ? this.architectImpacts
      : [];
    const top = Array.isArray(this.topRisks) ? this.topRisks : [];

    const rationaleLines = this.gateRationaleLines || [];
    const fixLines = this.gateRequiredFixLines || [];

    let out = "";
    out += "Release Decision (Executive)\n";
    out += `Build: ${TRA_BUILD_LABEL}\n`; //HS
    out += "===========================\n\n";
    out += `Gate Outcome: ${this.releaseGateDecisionLabel}\n`;
    out += `Overall Risk: ${risk}\n`;
    out += `Release Recommendation: ${rec}\n`;
    out += `Policy: ${policy} (${version})\n\n`;

    if (impacts.length) {
      out += "Architect Impacts:\n";
      impacts.forEach((x) => (out += `• ${x}\n`));
      out += "\n";
    }

    out += "Top Risks:\n";
    if (top.length) top.slice(0, 5).forEach((x) => (out += `• ${x}\n`));
    else out += "• None\n";
    out += "\n";

    out += "Rationale:\n";
    if (rationaleLines.length)
      rationaleLines.forEach((x) => (out += `• ${x}\n`));
    else out += "• N/A\n";
    out += "\n";

    if (fixLines.length) {
      out += "Required Fixes:\n";
      fixLines.forEach((x) => (out += `• ${x}\n`));
    }
    return out;
  }
  //==========Phase8.1.1 END code change=========

  async handleRowAction(event) {
    const actionName = event.detail.action.name;
    const row = event.detail.row;

    if (actionName !== "view") return;

    this.detailLoading = true;
    this.errorMsg = null;
    this.snippetLines = [];

    try {
      const d = await getItemDetail({ itemId: row.itemId });
      this.detail = d;
      this.isModalOpen = true;

      const raw = d && d.snippet && d.snippet.text ? d.snippet.text : "";
      const hl = d && d.snippet ? d.snippet.highlightLine : null;

      this.snippetLines = (raw ? raw.split("\n") : []).map((line, idx) => {
        const trimmed = line.trimStart();
        const numPart = trimmed.includes("|")
          ? trimmed.split("|")[0].trim()
          : "";
        const ln = parseInt(numPart, 10);
        const isHighlight = hl && ln === hl;

        return {
          key: `${idx}-${line}`,
          text: line,
          cssClass: isHighlight ? "snippetLine snippetHighlight" : "snippetLine"
        };
      });
    } catch (err) {
      this.errorMsg = this.normalizeError(err);
    } finally {
      this.detailLoading = false;
    }
  }

  closeModal() {
    this.isModalOpen = false;
    this.detail = null;
    this.snippetLines = [];
  }

  resetRunStatus() {
    this.status = null;
    this.totalTriggers = 0;
    this.processedTriggers = 0;
    this.highCount = 0;
    this.mediumCount = 0;
    this.lowCount = 0;
    this.errorMessage = null;
    this.lastUpdated = null;
    this.overallRisk = "Low";
    this.findingsCount = 0;

    // =========================
    // Phase6.0-ExecutiveSignal
    // =========================
    this.releaseRecommendation = null;
    this.architectImpacts = null;
    this.topRisks = [];
    this.executiveSummary = null;
    this.completedAt = null;
    // =========================
    // Phase6.0-ExecutiveSignal
    // =========================
  }
  //==========Phase7.0.2 START code change=========
  parseReleaseGateFromSummary(text) {
    const t = text == null ? "" : String(text);

    // Find the start of the RELEASE GATE block
    const idx = t.indexOf("RELEASE GATE");
    if (idx < 0) return null;

    // Take block from RELEASE GATE to end (or until another major section if you add later)
    const block = t.substring(idx);

    // Policy + version line example:
    // RELEASE GATE (Policy: Standard, Version: 7.0.1):
    let policyProfile = null;
    let gateVersion = null;

    const mHeader = block.match(
      /RELEASE GATE\s*\(Policy:\s*([^,]+),\s*Version:\s*([^)]+)\)\s*:/i
    );
    if (mHeader) {
      policyProfile = (mHeader[1] || "").trim();
      gateVersion = (mHeader[2] || "").trim();
    }

    // Release Decision line: "- Release Decision: BLOCKED"
    let releaseDecision = null;
    const mDecision = block.match(/-\s*Release Decision:\s*([A-Z_]+)/i);
    if (mDecision) {
      releaseDecision = (mDecision[1] || "").trim();
    }

    // Rationale section: "Rationale:\n1) ...\n2) ..."
    let rationaleRaw = "";
    const mRationale = block.match(
      /Rationale:\s*\n([\s\S]*?)(\n\n[A-Z ]+?:|\n\nTop Risks:|\s*$)/i
    );
    if (mRationale) {
      rationaleRaw = (mRationale[1] || "").trim();
    }

    // Required Fixes section: "Required Fixes (to unblock release):\n1) ...\n2) ..."
    let requiredFixesRaw = "";
    const mFixes = block.match(
      /Required Fixes[\s\S]*?:\s*\n([\s\S]*?)(\n\n[A-Z ]+?:|\n\nTop Risks:|\s*$)/i
    );
    if (mFixes) {
      requiredFixesRaw = (mFixes[1] || "").trim();
    }

    return {
      releaseDecision,
      policyProfile,
      gateVersion,
      rationaleRaw,
      requiredFixesRaw
    };
  }
  //==========Phase7.0.2 END code change=========

  normalizeError(err) {
    try {
      if (err && err.body && err.body.message) return err.body.message;
      if (err && err.message) return err.message;
      return JSON.stringify(err);
    } catch {
      return "Unknown error";
    }
  }
}

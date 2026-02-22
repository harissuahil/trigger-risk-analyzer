import { LightningElement, track } from 'lwc';

import getRunStatus from '@salesforce/apex/DeploymentAnalysisController.getRunStatus';
import getRunItems from '@salesforce/apex/DeploymentAnalysisController.getRunItems';
import getItemDetail from '@salesforce/apex/DeploymentAnalysisController.getItemDetail';

const TRA_BUILD_LABEL = 'GOLD Phase 7 Validated';

export default class TraEvidencePackExporter extends LightningElement {
  @track runId = '';
  @track isLoading = false;
  @track errorMsg = '';

  // Raw payloads from the SAME sources as TRA
  runStatus;
  items = [];
  detailsById = {};

  // Progress
  detailsTotal = 0;
  detailsLoaded = 0;

  // Rendered outputs (exactly what buttons output)
  @track summaryText = '';
  @track execDecisionText = '';
  @track csvText = '';
  @track releaseDecisionText = '';

  // Debounce
  _debounce;

  get hasData() {
    return !!(this.runStatus);
  }

  get noFindings() {
    return !this.items || this.items.length === 0;
  }

  get detailCards() {
    const rows = this.items || [];
    return rows.map((r) => {
      const d = this.detailsById[r.itemId];
      const label = `${r.severity} | ${r.triggerName} | ${r.ruleLabel} | Line ${r.lineNumber || ''}`.trim();
      return {
        itemId: r.itemId,
        label,
        severity: d?.severity || r.severity,
        triggerName: d?.triggerName || r.triggerName,
        ruleLabel: d?.ruleLabel || r.ruleLabel,
        lineNumber: d?.lineNumber || r.lineNumber,
        message: d?.message || '',
        recommendation: d?.recommendation || '',
        hasSnippet: !!(d?.snippet?.text),
        snippetText: d?.snippet?.text || ''
      };
    });
  }

  handleRunIdChange(e) {
    this.runId = (e.target.value || '').trim();

    // Auto-load when Run ID looks valid (15 or 18 chars)
    clearTimeout(this._debounce);
    this._debounce = setTimeout(() => {
      if (this.isLikelySalesforceId(this.runId)) {
        this.loadAll(this.runId);
      }
    }, 450);
  }

  handleLoad() {
    this.loadAll(this.runId);
  }

  handleReset() {
    this.runId = '';
    this.errorMsg = '';
    this.isLoading = false;

    this.runStatus = null;
    this.items = [];
    this.detailsById = {};

    this.detailsTotal = 0;
    this.detailsLoaded = 0;

    this.summaryText = '';
    this.execDecisionText = '';
    this.csvText = '';
    this.releaseDecisionText = '';
  }

  async loadAll(runId) {
    this.errorMsg = '';
    if (!this.isLikelySalesforceId(runId)) {
      this.errorMsg = 'Please paste a valid Run ID (15 or 18 characters).';
      return;
    }

    this.isLoading = true;
    this.runStatus = null;
    this.items = [];
    this.detailsById = {};
    this.detailsLoaded = 0;
    this.detailsTotal = 0;

    try {
      // 1) Load the same run status and items that TRA uses
      const s = await getRunStatus({ runId });
      const rows = await getRunItems({ runId });

      this.runStatus = s;
      this.items = Array.isArray(rows) ? rows : [];

      // 2) Hydrate the same in-memory fields TRA uses, so button builders match
      this.applyRunStatusToLocalState(s);

      // 3) Fetch ALL details (same source as View button)
      this.detailsTotal = this.items.length;
      await this.fetchAllDetailsWithLimit(this.items, 5);

      // 4) Build the 4 button outputs (same builders as TRA)
      this.summaryText = this.buildShareableSummary();
      this.execDecisionText = this.buildReleaseDecisionExecutiveText();

      // CSV preview should match exportCsv() content (without downloading)
      this.csvText = this.buildCsvTextForExport();

      // Release Decision file text should match Export Release Decision button
      this.releaseDecisionText = this.buildReleaseDecisionText(new Date());

    } catch (e) {
      this.errorMsg = this.normalizeError(e);
    } finally {
      this.isLoading = false;
    }
  }

  // ----------------------------
  // Same data shaping as TRA UI
  // ----------------------------
  status;
  totalTriggers = 0;
  processedTriggers = 0;
  highCount = 0;
  mediumCount = 0;
  lowCount = 0;
  overallRisk = 'Low';
  releaseRecommendation;
  architectImpacts = [];
  topRisks = [];
  executiveNote;
  executiveSummary;

  // Release Gate local fields (same as runner)
  releaseDecision;
  gatePolicyProfile;
  gateVersion;
  gateRationaleRaw = '';
  gateRequiredFixesRaw = '';

  applyRunStatusToLocalState(s) {
    this.status = s.status;
    this.totalTriggers = s.totalTriggers || 0;
    this.processedTriggers = s.processedTriggers || 0;
    this.highCount = s.highCount || 0;
    this.mediumCount = s.mediumCount || 0;
    this.lowCount = s.lowCount || 0;

    this.overallRisk = s.overallRisk || this.computeOverallRisk();

    this.releaseRecommendation = s.releaseRecommendation || this.releaseRecommendation;

    // Runner converts architectImpacts string to array, and makes unique
    const aiRaw = s.architectImpacts;
    if (aiRaw != null) {
      const raw = String(aiRaw).trim();
      const arr = raw ? raw.split(',').map((x) => x.trim()).filter(Boolean) : [];
      this.architectImpacts = this.uniqueLines(arr);
    } else {
      this.architectImpacts = this.uniqueLines(this.architectImpacts || []);
    }

    this.topRisks = this.uniqueLines(s.topRisks || this.topRisks || []);
    this.executiveNote = s.executiveNote || this.executiveNote;

    this.executiveSummary = s.executiveSummary;

    // Runner parses release gate from executiveSummary
    try {
      const raw = this.executiveSummary || '';
      const parsed = this.parseReleaseGateFromSummary(raw);
      if (parsed) {
        this.releaseDecision = parsed.releaseDecision || this.releaseDecision;
        this.gatePolicyProfile = parsed.policyProfile || this.gatePolicyProfile;
        this.gateVersion = parsed.gateVersion || this.gateVersion;
        this.gateRationaleRaw = parsed.rationaleRaw || this.gateRationaleRaw || '';
        this.gateRequiredFixesRaw = parsed.requiredFixesRaw || this.gateRequiredFixesRaw || '';
      }
    } catch (e) {
      // do not block
    }
  }

  // ----------------------------
  // Details fetching (robust)
  // ----------------------------
  async fetchAllDetailsWithLimit(rows, concurrency) {
    const list = Array.isArray(rows) ? rows : [];
    const limit = Math.max(1, Number(concurrency || 1));

    let idx = 0;
    const workers = new Array(limit).fill(0).map(async () => {
      while (idx < list.length) {
        const current = list[idx++];
        if (!current?.itemId) {
          this.detailsLoaded++;
          continue;
        }
        try {
          const d = await getItemDetail({ itemId: current.itemId });
          this.detailsById = { ...this.detailsById, [current.itemId]: d };
        } catch (e) {
          // Store an error placeholder so you can still validate it failed
          this.detailsById = {
            ...this.detailsById,
            [current.itemId]: {
              itemId: current.itemId,
              triggerName: current.triggerName,
              severity: current.severity,
              ruleLabel: current.ruleLabel,
              lineNumber: current.lineNumber,
              message: `DETAIL LOAD FAILED: ${this.normalizeError(e)}`,
              recommendation: '',
              snippet: { text: '' }
            }
          };
        } finally {
          this.detailsLoaded++;
        }
      }
    });

    await Promise.all(workers);
  }

  // ----------------------------
  // Button output builders (copied logic)
  // ----------------------------
  buildShareableSummary() {
    const selected = this.totalTriggers || 0;
    const analyzed = this.processedTriggers || 0;
    const hi = this.highCount || 0;
    const med = this.mediumCount || 0;
    const lo = this.lowCount || 0;
    const total = hi + med + lo;

    const risk = this.overallRisk || this.computeOverallRisk();

    let assessment = 'No high-severity risks detected.';
    if (hi > 0) {
      assessment =
        'One or more high-severity risks were identified. Review and address before deployment, especially for higher data volumes.';
    } else if (med > 0) {
      assessment = 'Medium-severity risks were identified. Review recommended before deployment.';
    }

    const rec = this.releaseRecommendation ? `\nRelease Recommendation: ${this.releaseRecommendation}\n` : '\n';
    const impacts = this.architectImpacts ? `Architect Impacts: ${this.architectImpacts}\n` : '';
    const top =
      (this.topRisks || []).length
        ? 'Top Risks:\n' + this.topRisks.map((x, i) => `${i + 1}) ${x}`).join('\n') + '\n'
        : '';

    return (
      'Trigger Risk Analysis completed.\n\n' +
      'Scope:\n' +
      `- Triggers selected: ${selected}\n` +
      `- Triggers analyzed: ${analyzed}\n\n` +
      'Findings overview:\n' +
      `- High severity: ${hi}\n` +
      `- Medium severity: ${med}\n` +
      `- Low severity: ${lo}\n` +
      `- Total findings: ${total}\n\n` +
      'Overall assessment:\n' +
      `Overall Risk: ${risk}\n` +
      rec +
      impacts +
      top +
      assessment
    );
  }

  buildReleaseDecisionExecutiveText() {
    const decision = this.releaseDecision || 'N/A';
    const policy = this.gatePolicyProfile || 'N/A';
    const version = this.gateVersion || 'N/A';

    const rec = this.releaseRecommendation || 'N/A';
    const risk = this.overallRisk || this.computeOverallRisk();

    const impacts = Array.isArray(this.architectImpacts) ? this.architectImpacts : [];
    const top = Array.isArray(this.topRisks) ? this.topRisks : [];

    const rationaleLines = (this.gateRationaleLines || []);
    const fixLines = (this.gateRequiredFixLines || []);

    let out = '';
    out += 'Release Decision (Executive)\n';
    out += `Build: ${TRA_BUILD_LABEL}\n`;
    out += '===========================\n\n';
    out += `Release Decision: ${decision}\n`;
    out += `Risk Level: ${risk}\n`;
    out += `Recommendation: ${rec}\n`;
    out += `Policy: ${policy} (${version})\n\n`;

    if (impacts.length) {
      out += 'Architect Impacts:\n';
      impacts.forEach((x) => (out += `• ${x}\n`));
      out += '\n';
    }

    out += 'Top Risks:\n';
    if (top.length) top.slice(0, 5).forEach((x) => (out += `• ${x}\n`));
    else out += '• None\n';
    out += '\n';

    out += 'Rationale:\n';
    if (rationaleLines.length) rationaleLines.forEach((x) => (out += `• ${x}\n`));
    else out += '• N/A\n';
    out += '\n';

    out += 'Required Fixes:\n';
    if (fixLines.length) fixLines.forEach((x) => (out += `• ${x}\n`));
    else out += '• Not provided\n';

    return out;
  }

  buildReleaseDecisionText(now) {
    const runId = this.runId || '';
    const release = 'UI-RUN'; // exporter is validation-only
    const generated = now ? now.toLocaleString() : '';

    const overallRisk = this.overallRisk || this.computeOverallRisk();
    const rec = this.releaseRecommendation || 'N/A';

    const impacts = Array.isArray(this.architectImpacts) ? this.architectImpacts : [];
    const risks = Array.isArray(this.topRisks) ? this.topRisks : [];

    const decision = this.releaseDecision || 'N/A';
    const policy = this.gatePolicyProfile || 'N/A';
    const version = this.gateVersion || 'N/A';

    const rationaleLines = this.cleanGateLines(this.gateRationaleLines || [], { removeFixLikeLines: true });
    const fixLines = this.cleanGateLines(this.gateRequiredFixLines || [], { removeFixLikeLines: false });

    let out = '';
    out += 'Trigger Risk Analyzer - Release Decision\n';
    out += `Build: ${TRA_BUILD_LABEL}\n`;
    out += '======================================\n\n';

    out += `Run ID: ${runId}\n`;
    out += `Release Label: ${release}\n`;
    out += `Generated At: ${generated}\n\n`;

    out += 'EXECUTIVE SIGNAL\n';
    out += '---------------\n';
    out += `Overall Deployment Risk: ${overallRisk}\n`;
    out += `Release Recommendation: ${rec}\n`;
    out += `Architect Impacts: ${impacts.length ? impacts.join(', ') : 'N/A'}\n\n`;

    out += 'Top Risks:\n';
    if (risks.length) {
      risks.forEach((t, i) => {
        out += `${i + 1}) ${t}\n`;
      });
    } else {
      out += '1) N/A\n';
    }

    out += '\nRELEASE GATE\n';
    out += '------------\n';
    out += `Release Decision: ${decision}\n`;
    out += `Policy: ${policy}\n`;
    out += `Version: ${version}\n\n`;

    out += 'Rationale:\n';
    if (rationaleLines.length) {
      rationaleLines.forEach((l, i) => {
        out += `${i + 1}) ${l}\n`;
      });
    } else {
      out += '1) N/A\n';
    }

    out += '\nRequired Fixes (to unblock):\n';
    if (fixLines.length) {
      fixLines.forEach((l, i) => {
        out += `${i + 1}) ${l}\n`;
      });
    } else {
      out += '1) Not provided\n';
    }

    out += '\n---\n';
    out += 'Note: This output is intended for release decision-making (CAB/audit).\n';

    return out;
  }

  // CSV builder that matches exportCsv() output (no download)
  severityFilter = 'All';
  categoryFilter = 'All';
  searchText = '';

  get filteredItems() {
    const rows = this.items || [];
    const sev = this.severityFilter || 'All';
    const cat = this.categoryFilter || 'All';
    const q = (this.searchText || '').trim().toLowerCase();

    return rows.filter((r) => {
      if (sev !== 'All' && r.severity !== sev) return false;
      if (cat !== 'All' && r.category !== cat) return false;
      if (q) {
        const blob = `${r.triggerName || ''} ${r.ruleLabel || ''} ${r.messageShort || ''}`.toLowerCase();
        if (!blob.includes(q)) return false;
      }
      return true;
    });
  }

  buildCsvTextForExport() {
    const rows = this.filteredItems || [];

    const now = new Date();
    const ymd = now.toISOString().slice(0, 10);

    const runId = this.runId || '';
    const release = 'UI-RUN';
    const sev = this.severityFilter || 'All';
    const cat = this.categoryFilter || 'All';
    const q = (this.searchText || '').trim();

    const impacts = Array.isArray(this.architectImpacts) ? this.architectImpacts : [];
    const risks = Array.isArray(this.topRisks) ? this.topRisks : [];

    const execLines = [];
    execLines.push('EXECUTIVE SIGNAL:');
    execLines.push(`Overall Deployment Risk: ${this.overallRisk || this.computeOverallRisk()}`);
    execLines.push(`Release Recommendation: ${this.releaseRecommendation || 'N/A'}`);
    execLines.push(`Architect Impacts: ${impacts.length ? impacts.join(', ') : 'N/A'}`);
    execLines.push(' ');
    execLines.push('Top Risks:');

    if (risks.length) {
      risks.forEach((t, i) => {
        execLines.push(`${i + 1}) ${t}`);
      });
    } else {
      execLines.push('1) N/A');
    }

    if (this.executiveNote) {
      execLines.push(' ');
      execLines.push(`Executive note: ${this.executiveNote}`);
    }

    const headerLines = [
      'Trigger Risk Analyzer Export',
      `TRA Build: ${TRA_BUILD_LABEL}`,
      `Release Gate Policy: ${this.gatePolicyProfile || 'N/A'}`,
      `Release Gate Version: ${this.gateVersion || 'N/A'}`,
      `Run ID: ${runId}`,
      `Release Label: ${release}`,
      `Generated At: ${now.toLocaleString()}`,
      `Filters: Severity=${sev}; Category=${cat}${q ? `; Search="${q}"` : ''}`,
      '---',
      ...execLines,
      '---'
    ];

    const headers = ['Severity', 'Trigger', 'Rule', 'Category', 'Line', 'Message'];

    const lines = [];
    headerLines.forEach((l) => lines.push(this.csvEscape(l)));
    lines.push(headers.join(','));

    if (!rows.length) {
      lines.push(this.csvEscape('No findings detected for current filters.'));
    }

    rows.forEach((r) => {
      const vals = [
        r.severity,
        r.triggerName,
        r.ruleLabel,
        r.category,
        r.lineNumber == null ? '' : String(r.lineNumber),
        r.messageShort
      ].map((v) => this.csvEscape(v));

      lines.push(vals.join(','));
    });

    const csv = '\ufeff' + lines.join('\n');
    // For preview we return csv content only
    return csv;
  }

  // ----------------------------
  // Release gate helpers (copied behavior)
  // ----------------------------
  get gateRationaleLines() {
    const raw = (this.gateRationaleRaw || '').trim();
    if (!raw) return [];
    return this.cleanGateLines(raw.split('\n'), { removeFixLikeLines: true });
  }

  get gateRequiredFixLines() {
    const raw = (this.gateRequiredFixesRaw || '').trim();
    if (!raw) return [];
    return this.cleanGateLines(raw.split('\n'), { removeFixLikeLines: false });
  }

  cleanGateLines(lines, options) {
    const opts = options || {};
    const removeFixLikeLines = !!opts.removeFixLikeLines;

    return (lines || [])
      .map((l) => (l == null ? '' : String(l)).trim())
      .filter(Boolean)
      .filter((l) => {
        const s = l.toLowerCase();
        return !s.startsWith('required fixes') && !s.startsWith('rationale');
      })
      .map((l) =>
        l
          .replace(/^\s*[•\-]\s*/, '')
          .replace(/^\s*\d+\s*[\)\.]\s*/, '')
          .trim()
      )
      .filter(Boolean)
      .filter((l) => {
        if (!removeFixLikeLines) return true;
        const s = l.toLowerCase();
        return !(s.startsWith('collect ') || s.startsWith('add ') || s.startsWith('move '));
      });
  }

  parseReleaseGateFromSummary(raw) {
    // This matches the runner concept: parse from executiveSummary text.
    // Keep it tolerant and non-blocking.
    if (!raw) return null;

    const lines = String(raw).split('\n').map((x) => x.trim());
    let decision, policyProfile, gateVersion;
    let rationale = [];
    let fixes = [];

    let inRationale = false;
    let inFixes = false;

    lines.forEach((l) => {
      const low = l.toLowerCase();

      if (low.startsWith('release decision:')) {
        decision = l.split(':').slice(1).join(':').trim();
      }
      if (low.startsWith('policy:')) {
        const rest = l.split(':').slice(1).join(':').trim();
        const m = rest.match(/(.+?)\s*\((.+?)\)\s*$/);
        if (m) {
          policyProfile = m[1].trim();
          gateVersion = m[2].trim();
        } else {
          policyProfile = rest;
        }
      }
      if (low === 'rationale:' || low.startsWith('rationale:')) {
        inRationale = true;
        inFixes = false;
        const after = l.split(':').slice(1).join(':').trim();
        if (after) rationale.push(after);
        return;
      }
      if (low.startsWith('required fixes')) {
        inFixes = true;
        inRationale = false;
        const after = l.split(':').slice(1).join(':').trim();
        if (after) fixes.push(after);
        return;
      }

      if (inRationale) rationale.push(l);
      if (inFixes) fixes.push(l);
    });

    return {
      releaseDecision: decision,
      policyProfile,
      gateVersion,
      rationaleRaw: rationale.filter(Boolean).join('\n'),
      requiredFixesRaw: fixes.filter(Boolean).join('\n')
    };
  }

  uniqueLines(arr) {
    const out = [];
    const seen = new Set();
    (arr || []).forEach((x) => {
      const s = (x == null ? '' : String(x)).trim();
      if (!s) return;
      const key = s.toLowerCase();
      if (seen.has(key)) return;
      seen.add(key);
      out.push(s);
    });
    return out;
  }

  computeOverallRisk() {
    const hi = this.highCount || 0;
    const med = this.mediumCount || 0;
    if (hi > 0) return 'High';
    if (med > 0) return 'Medium';
    return 'Low';
  }

  // ----------------------------
  // Copy + Download actions
  // ----------------------------
  async copySummary() {
    await this.copyToClipboard(this.summaryText);
  }
  async copyExecDecision() {
    await this.copyToClipboard(this.execDecisionText);
  }
  async copyCsv() {
    await this.copyToClipboard(this.csvText);
  }
  async copyReleaseDecision() {
    await this.copyToClipboard(this.releaseDecisionText);
  }

  async copyToClipboard(text) {
    try {
      const t = text || '';
      if (navigator && navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(t);
        return;
      }
      const ta = document.createElement('textarea');
      ta.value = t;
      ta.style.position = 'fixed';
      ta.style.left = '-9999px';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
    } catch (e) {
      this.errorMsg = this.normalizeError(e);
    }
  }

  downloadCsv() {
    const now = new Date();
    const ymd = now.toISOString().slice(0, 10);
    const fileName = `TRA_UI-RUN_${this.runId || 'Run'}_${ymd}.csv`;
    this.downloadTextFile(this.csvText, fileName, 'application/octet-stream;charset=utf-8;');
  }

  downloadReleaseDecision() {
    const now = new Date();
    const ymd = now.toISOString().slice(0, 10);
    const fileName = `TRA_ReleaseDecision_UI-RUN_${this.runId || 'Run'}_${ymd}.txt`;
    this.downloadTextFile(this.releaseDecisionText, fileName, 'text/plain;charset=utf-8;');
  }

  downloadTextFile(text, fileName, mimeType) {
    const safeText = text == null ? '' : String(text);
    const blob = new Blob([safeText], { type: mimeType || 'text/plain;charset=utf-8;' });
    const url = URL.createObjectURL(blob);

    const a = document.createElement('a');
    a.href = url;
    a.download = fileName;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);

    URL.revokeObjectURL(url);
  }

  // ----------------------------
  // Utils
  // ----------------------------
  csvEscape(v) {
    const s = v == null ? '' : String(v);
    const escaped = s.replace(/"/g, '""');
    return `"${escaped}"`;
  }

  normalizeError(e) {
    if (!e) return 'Unknown error';
    if (typeof e === 'string') return e;
    if (e.body && e.body.message) return e.body.message;
    if (e.message) return e.message;
    return JSON.stringify(e);
  }

  isLikelySalesforceId(v) {
    const s = (v || '').trim();
    return (s.length === 15 || s.length === 18) && /^[a-zA-Z0-9]+$/.test(s);
  }
}
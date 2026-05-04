/******************************************************************************************************
 * Queueable job that runs Trigger Risk Analyzer for selected Apex triggers.
 *
 * Responsibilities:
 * - Fetch trigger source through the Tooling API.
 * - Build trigger context for TriggerRiskEngine.
 * - Insert Deployment Analysis Item records for detected findings.
 * - Update the Deployment Analysis Run summary, counts, risk level, and release gate fields.
 *
 * Keep this class focused on orchestration.
 * Detection logic belongs in TriggerRiskEngine, and release decision logic belongs in ReleaseGateEngine.
 *******************************************************************************************************/
public with sharing class DeploymentAnalysisJob implements Queueable, Database.AllowsCallouts {
  private Id runId;
  private List<String> triggerNames;

  public DeploymentAnalysisJob(Id runId, List<String> triggerNames) {
    this.runId = runId;
    this.triggerNames = triggerNames;
  }

  public void execute(QueueableContext context) {
    Deployment_Analysis_Run__c runRec = [
      SELECT
        Id,
        Status__c,
        Total_Triggers__c,
        Processed_Triggers__c,
        High_Count__c,
        Medium_Count__c,
        Low_Count__c,
        Error_Message__c,
        Last_Updated__c,
        Overall_Risk__c,
        Completed_At__c,
        Summary__c
      FROM Deployment_Analysis_Run__c
      WHERE Id = :runId
      LIMIT 1
    ];

    Integer totalSelected = 0;
    Integer triggersAnalyzed = 0;
    Integer highCount = 0;
    Integer mediumCount = 0;
    Integer lowCount = 0;
    Integer findingsCount = 0;
    Integer infoCount = 0;

    Map<String, Integer> ruleKeyCounts = new Map<String, Integer>();
    String overallRisk = 'Low';

    List<Deployment_Analysis_Item__c> itemsToInsert = new List<Deployment_Analysis_Item__c>();

    try {
      List<String> namesToAnalyze = (triggerNames == null ||
        triggerNames.isEmpty())
        ? fetchAllTriggerNames()
        : triggerNames;

      totalSelected = (namesToAnalyze == null) ? 0 : namesToAnalyze.size();

      // Optional: build label lookup (useful if you want to display label from CMDT)
      Map<String, Trigger_Risk_Rule__mdt> ruleByKey = new Map<String, Trigger_Risk_Rule__mdt>();
      for (Trigger_Risk_Rule__mdt r : [
        SELECT DeveloperName, Label, Rule_Key__c, Recommendation__c
        FROM Trigger_Risk_Rule__mdt
      ]) {
        String k = String.isBlank(r.Rule_Key__c)
          ? r.DeveloperName
          : r.Rule_Key__c;
        if (!String.isBlank(k) && !ruleByKey.containsKey(k)) {
          ruleByKey.put(k, r);
        }
      }

      // Build a shared "trigger universe" so the engine can detect cross-trigger cycles.
      Map<String, String> entityIdToApiName = new Map<String, String>(); // cache DurableId -> QualifiedApiName
      List<TriggerFetchService.TriggerInfo> allInfos = TriggerFetchService.fetchByNames(
        namesToAnalyze
      );

      Map<String, TriggerFetchService.TriggerInfo> infoByName = new Map<String, TriggerFetchService.TriggerInfo>();
      Map<String, String> triggerNameToBody = new Map<String, String>();
      Map<String, String> triggerNameToObjectApi = new Map<String, String>();
      Map<String, Set<String>> objectToTriggers = new Map<String, Set<String>>();

      for (TriggerFetchService.TriggerInfo tiAll : allInfos) {
        if (tiAll == null || String.isBlank(tiAll.name))
          continue;

        infoByName.put(tiAll.name, tiAll);

        String objApi = resolveObjectApiName(
          tiAll.tableEnumOrId,
          entityIdToApiName
        );
        triggerNameToBody.put(tiAll.name, tiAll.body);
        triggerNameToObjectApi.put(tiAll.name, objApi);

        if (!String.isBlank(objApi)) {
          if (!objectToTriggers.containsKey(objApi))
            objectToTriggers.put(objApi, new Set<String>());
          objectToTriggers.get(objApi).add(tiAll.name);
        }
      }

      TriggerRiskEngine.TriggerUniverse uni = new TriggerRiskEngine.TriggerUniverse();
      uni.triggerNameToBody = triggerNameToBody;
      uni.triggerNameToObjectApi = triggerNameToObjectApi;
      uni.objectToTriggers = objectToTriggers;

      for (String triggerName : namesToAnalyze) {
        if (String.isBlank(triggerName))
          continue;

        // Prefer bulk-fetched info (faster + enables multi-trigger context)
        TriggerFetchService.TriggerInfo ti = infoByName.containsKey(triggerName)
          ? infoByName.get(triggerName)
          : TriggerFetchService.fetchByName(triggerName);

        if (ti == null || String.isBlank(ti.body))
          continue;

        triggersAnalyzed++;

        // Old single-body call kept (commented) to avoid deleting anything.
        // List<TriggerRiskEngine.Finding> findings = TriggerRiskEngine.analyzeFindings(ti.body);

        TriggerRiskEngine.TriggerContext ctx = new TriggerRiskEngine.TriggerContext();
        ctx.triggerName = triggerName;
        ctx.objectApiName = triggerNameToObjectApi.get(triggerName);
        ctx.body = ti.body;
        ctx.universe = uni;

        List<TriggerRiskEngine.Finding> findings = TriggerRiskEngine.analyzeFindings(
          ctx
        );

        if (findings == null || findings.isEmpty()) {
          continue; // clean trigger => no items
        }
        // Bulkification Confidence Score recommendation should align with High/Medium findings
        Boolean triggerHasHigh = false;
        Boolean triggerHasMedium = false;
        for (TriggerRiskEngine.Finding fx : findings) {
          if (fx == null)
            continue;
          if (fx.ruleKey == 'BULK_CONFIDENCE_SCORE')
            continue;
          if (fx.severity == 'High') {
            triggerHasHigh = true;
          } else if (fx.severity == 'Medium') {
            triggerHasMedium = true;
          }
        }

        for (TriggerRiskEngine.Finding f : findings) {
          if (f == null)
            continue;
          if (!String.isBlank(f.ruleKey)) {
            Integer cur = ruleKeyCounts.containsKey(f.ruleKey)
              ? ruleKeyCounts.get(f.ruleKey)
              : 0;
            ruleKeyCounts.put(f.ruleKey, cur + 1);
          }

          // Bulk score is informational - don't count it in severity totals or overall risk
          Boolean isBulkScore = (f.ruleKey == 'BULK_CONFIDENCE_SCORE');
          if (isBulkScore) {
            infoCount++;
          }

          if (!isBulkScore) {
            if (f.severity == 'High') {
              highCount++;
            } else if (f.severity == 'Medium') {
              mediumCount++;
            } else {
              lowCount++;
            }

            if (rank(f.severity) > rank(overallRisk)) {
              overallRisk = f.severity;
            }
          }

          if (isBulkScore) {
            continue;
          }

          Deployment_Analysis_Item__c item = new Deployment_Analysis_Item__c();
          item.Run__c = runRec.Id;
          item.Trigger_Name__c = triggerName;
          item.Risk__c = f.severity;
          item.Category__c = String.isBlank(f.category)
            ? 'General'
            : f.category; //Phase5.4.1
          item.Severity_Sort__c = rank(f.severity);

          // Store the single-rule context (one item per rule hit)
          item.Matched_Rules__c = f.ruleKey;
          item.Risk_Reasons__c = f.message;
          item.Message__c = f.message;

          // Prefer engine-provided label; fallback to CMDT label; fallback to key
          String labelFromEngine = f.ruleLabel;
          String labelFromCmdt = (f.ruleKey != null &&
            ruleByKey.containsKey(f.ruleKey))
            ? ruleByKey.get(f.ruleKey).Label
            : null;

          item.Rule_Label__c = !String.isBlank(labelFromEngine)
            ? labelFromEngine
            : !String.isBlank(labelFromCmdt) ? labelFromCmdt : f.ruleKey;

          String recFromCmdt = (f.ruleKey != null &&
            ruleByKey.containsKey(f.ruleKey))
            ? ruleByKey.get(f.ruleKey).Recommendation__c
            : null;

          String finalRec = !String.isBlank(recFromCmdt)
            ? recFromCmdt
            : buildRecommendation(f.ruleKey);

          if ('BULK_CONFIDENCE_SCORE' == f.ruleKey) {
            if (triggerHasHigh) {
              finalRec = 'Action required. High-severity risks detected. Address required fixes before deployment.';
            } else if (triggerHasMedium) {
              finalRec = 'Improvements recommended. Review medium-severity findings before deploying to high-volume environments.';
            } else {
              finalRec = 'No action needed. Trigger looks bulk-safe based on detected patterns.';
            }
          }

          item.Recommendation__c = finalRec;

          item.Line_Number__c = f.lineNumber;
          item.Highlight_Line__c = f.lineNumber;

          SnippetResult sn = buildSnippet(
            ti.body,
            (f.lineNumber == null) ? null : Decimal.valueOf(f.lineNumber)
          );
          item.Snippet_Text__c = sn.text;
          item.Snippet_Start_Line__c = sn.startLine;
          item.Snippet_End_Line__c = sn.endLine;

          itemsToInsert.add(item);
          findingsCount++;
        }
      }

      if (!itemsToInsert.isEmpty()) {
        insert itemsToInsert;
      }

      runRec.Status__c = 'Done';
      runRec.Total_Triggers__c = totalSelected;
      runRec.Processed_Triggers__c = triggersAnalyzed;
      runRec.High_Count__c = highCount;
      runRec.Medium_Count__c = mediumCount;
      runRec.Low_Count__c = lowCount;
      runRec.Overall_Risk__c = overallRisk;
      runRec.Completed_At__c = System.now();
      runRec.Last_Updated__c = System.now();
      runRec.Error_Message__c = null;

      String summary = 'Trigger Risk Analysis completed.\n\n';

      summary += 'Scope:\n';
      summary += '- Triggers selected: ' + totalSelected + '\n';
      summary += '- Triggers analyzed: ' + triggersAnalyzed + '\n\n';

      summary += 'Findings overview:\n';
      summary += '- High severity: ' + highCount + '\n';
      summary += '- Medium severity: ' + mediumCount + '\n';
      summary += '- Low severity: ' + lowCount + '\n';

      // summary += '- Informational (not counted toward risk): ' + infoCount + '\n';
      summary += '\nOverall assessment:\n';

      if (highCount > 0) {
        summary +=
          'One or more high-severity risks were identified. ' +
          'These findings should be reviewed and addressed before deployment, ' +
          'especially for environments with moderate to high data volume.';
      } else if (mediumCount > 0) {
        summary +=
          'No high-severity risks were identified. ' +
          'Some medium-severity findings are present and should be reviewed ' +
          'to improve maintainability and bulk safety.';
      } else {
        summary +=
          'No high or medium severity risks were identified. ' +
          'The analyzed triggers follow generally safe deployment patterns.';
      }
      List<String> actions = buildRecommendedNextSteps(ruleKeyCounts);
      if (actions != null && !actions.isEmpty()) {
        summary += '\n\nRecommended next steps:\n';
        Integer maxActions = Math.min(3, actions.size());
        for (Integer i = 0; i < maxActions; i++) {
          summary += (i + 1) + ') ' + actions[i] + '\n';
        }
      }

      // Append an executive/architect signal block that is sellable without explanation.
      // This is additive and does not change existing summary content.
      summary += buildExecutiveSignalBlock(
        overallRisk,
        highCount,
        mediumCount,
        lowCount,
        ruleKeyCounts
      );

      runRec.Summary__c = summary;
      // Compute Release Gate decision + persist as Summary block
      ReleaseGateEngine.GateResult gate;
      gate = ReleaseGateEngine.evaluate(
        ruleKeyCounts,
        highCount,
        mediumCount,
        lowCount
      );

      String gateBlock =
        '\n\nRELEASE GATE (Policy: ' +
        gate.policyProfile +
        ', Version: ' +
        gate.gateVersion +
        '):\n';
      gateBlock += '- Release Decision: ' + gate.decision + '\n';
      gateBlock += '- Release Recommendation: ' + gate.recommendation + '\n';

      String impacts = (gate.architectImpacts == null ||
        gate.architectImpacts.isEmpty())
        ? 'N/A'
        : String.join(gate.architectImpacts, ', ');
      gateBlock += '- Architect Impacts: ' + impacts + '\n';

      if (gate.rationale != null && !gate.rationale.isEmpty()) {
        gateBlock += '\nRationale:\n';
        for (Integer i = 0; i < Math.min(3, gate.rationale.size()); i++) {
          gateBlock += (i + 1) + ') ' + gate.rationale[i] + '\n';
        }
      }

      if (gate.requiredFixes != null && !gate.requiredFixes.isEmpty()) {
        gateBlock += '\nRequired Fixes (to unblock release):\n';
        for (Integer i = 0; i < Math.min(3, gate.requiredFixes.size()); i++) {
          gateBlock += (i + 1) + ') ' + gate.requiredFixes[i] + '\n';
        }
      }

      if (gate.topRisks != null && !gate.topRisks.isEmpty()) {
        gateBlock += '\nTop Risks:\n';
        for (Integer i = 0; i < Math.min(3, gate.topRisks.size()); i++) {
          gateBlock += (i + 1) + ') ' + gate.topRisks[i] + '\n';
        }
      }

      // Append to Summary__c (never remove existing content)
      runRec.Summary__c =
        (runRec.Summary__c == null ? '' : runRec.Summary__c) + gateBlock;

      // Optional: persist to fields IF they exist (dynamic, safe)
      Map<String, Schema.SObjectField> fMap = runRec.getSObjectType()
        .getDescribe()
        .fields.getMap();

      safePut(runRec, fMap, 'Release_Decision__c', gate.decision);
      safePut(runRec, fMap, 'Release_Recommendation__c', gate.recommendation);
      safePut(runRec, fMap, 'Policy_Profile__c', gate.policyProfile);
      safePut(runRec, fMap, 'Gate_Version__c', gate.gateVersion);

      safePut(runRec, fMap, 'Architect_Impacts__c', impacts);
      safePut(
        runRec,
        fMap,
        'Release_Rationale__c',
        (gate.rationale == null || gate.rationale.isEmpty())
          ? null
          : String.join(gate.rationale, '\n')
      );
      safePut(
        runRec,
        fMap,
        'Required_Fixes__c',
        (gate.requiredFixes == null || gate.requiredFixes.isEmpty())
          ? null
          : String.join(gate.requiredFixes, '\n')
      );
      safePut(
        runRec,
        fMap,
        'Top_Risks__c',
        (gate.topRisks == null || gate.topRisks.isEmpty())
          ? null
          : String.join(gate.topRisks, '\n')
      );
      //==========Phase7.0.1 END code change=========

      update runRec;
    } catch (Exception e) {
      runRec.Status__c = 'Failed';
      runRec.Total_Triggers__c = totalSelected;
      runRec.Processed_Triggers__c = triggersAnalyzed;
      runRec.High_Count__c = highCount;
      runRec.Medium_Count__c = mediumCount;
      runRec.Low_Count__c = lowCount;
      runRec.Error_Message__c = e.getMessage();
      runRec.Last_Updated__c = System.now();

      update runRec;
      throw e;
    }
  }

  // =====================
  // Helpers
  // =====================
  private static List<String> fetchAllTriggerNames() {
    Map<String, Object> r = ToolingApiClient.queryUntyped(
      'SELECT Name FROM ApexTrigger ORDER BY Name'
    );

    List<Object> recs = (List<Object>) r.get('records');
    List<String> out = new List<String>();

    if (recs != null) {
      for (Object o : recs) {
        Map<String, Object> row = (Map<String, Object>) o;
        out.add((String) row.get('Name'));
      }
    }
    return out;
  }

  private static Integer rank(String risk) {
    if (risk == 'High')
      return 3;
    if (risk == 'Medium')
      return 2;
    return 1;
  }

  private class SnippetResult {
    Decimal startLine;
    Decimal endLine;
    Decimal highlightLine;
    String text;
  }

  private static String buildRecommendation(String ruleKey) {
    if (String.isBlank(ruleKey))
      return null;

    if (ruleKey == 'TRIGGER_HANDLER_MISSING') {
      return 'Move trigger logic into a handler class (e.g., SomeObjectTriggerHandler.run()) so the trigger stays small, testable, and consistent.';
    }
    if (ruleKey == 'HARDCODED_ID') {
      return 'Avoid hardcoded Ids. Store them in Custom Metadata/Settings or query by a stable external key.';
    }
    if (ruleKey == 'SOQL_IN_LOOP') {
      return 'Move SOQL query outside the loop and query once.';
    }
    if (ruleKey == 'DML_IN_LOOP') {
      return 'Collect records in a list and do one DML outside the loop.';
    }
    if (ruleKey == 'EMAIL_IN_TRIGGER') {
      return 'Avoid sending emails directly in triggers; use async or a platform event.';
    }
    if (ruleKey == 'CALLOUT_IN_TRIGGER') {
      return 'Move callouts out of triggers; use Queueable/@future with AllowsCallouts.';
    }
    if (ruleKey == 'MIXED_DML') {
      return 'Separate setup-object DML (User/PermSet/Group) from business-object DML by moving one side to async.';
    }
    if (ruleKey == 'CROSS_TRIGGER_RECURSION_CYCLE') {
      return 'Cross-trigger recursion cycle detected. Consider adding a clear recursion guard, reducing cross-object DML in triggers, and moving orchestration to async (Queueable/Platform Event) so triggers do not call each other indirectly.';
    }
    if (ruleKey == 'MULTIPLE_TRIGGERS_SAME_OBJECT') {
      return 'Multiple triggers on the same object can execute in unpredictable order. ' +
        'Consider consolidating logic into a single trigger with a handler framework.';
    }
    if (ruleKey == 'DML_IN_BEFORE_TRIGGER') {
      return 'Avoid performing DML in BEFORE triggers. ' +
        'Move DML to AFTER triggers or async processing to prevent recursion.';
    }
    if (ruleKey == 'AFTER_TRIGGER_MUTATION') {
      return 'Avoid modifying Trigger.new in AFTER triggers. ' +
        'Move field updates to BEFORE triggers where possible.';
    }
    if (ruleKey == 'BULK_CONFIDENCE_SCORE') {
      return 'No action needed. Trigger looks bulk-safe based on detected patterns.';
    }
    return 'Review the trigger logic and follow bulk-safe patterns.';
  }

  private static SnippetResult buildSnippet(String body, Decimal lineNumber) {
    SnippetResult r = new SnippetResult();
    if (String.isBlank(body))
      return r;

    List<String> lines = body.split('\n', -1);
    Integer total = lines.size();

    Integer hl = (lineNumber == null)
      ? null
      : Integer.valueOf(String.valueOf(lineNumber));

    if (hl == null || hl <= 0 || hl > total) {
      Integer start = 1;
      Integer endL = Math.min(15, total);

      r.startLine = start;
      r.endLine = endL;
      r.highlightLine = null;
      r.text = joinSnippet(lines, start, endL);
      return r;
    }

    Integer startLine = Math.max(1, hl - 3);
    Integer endLine = Math.min(total, hl + 3);

    r.startLine = startLine;
    r.endLine = endLine;
    r.highlightLine = hl;
    r.text = joinSnippet(lines, startLine, endLine);

    return r;
  }

  private static String joinSnippet(
    List<String> lines,
    Integer startLine,
    Integer endLine
  ) {
    List<String> out = new List<String>();

    for (Integer i = startLine; i <= endLine; i++) {
      String prefix = String.valueOf(i).leftPad(4, ' ') + ' | ';
      out.add(prefix + lines[i - 1]);
    }
    return String.join(out, '\n');
  }

  // Resolve TableEnumOrId to an API name (best effort).
  // - If TableEnumOrId already looks like "Account" or "MyObj__c", return it.
  // - If it looks like an object DurableId (starts with 01I), query EntityDefinition and cache it.
  private static String resolveObjectApiName(
    String tableEnumOrId,
    Map<String, String> cache
  ) {
    if (String.isBlank(tableEnumOrId))
      return null;
    if (!tableEnumOrId.startsWith('01I'))
      return tableEnumOrId;

    if (cache != null && cache.containsKey(tableEnumOrId)) {
      return cache.get(tableEnumOrId);
    }

    String soql =
      'SELECT QualifiedApiName, DurableId ' +
      'FROM EntityDefinition ' +
      'WHERE DurableId = \'' +
      String.escapeSingleQuotes(tableEnumOrId) +
      '\' ' +
      'LIMIT 1';

    Map<String, Object> r = ToolingApiClient.queryUntyped(soql);
    List<Object> recs = (List<Object>) r.get('records');
    String apiName;

    if (recs != null && !recs.isEmpty()) {
      Map<String, Object> row = (Map<String, Object>) recs[0];
      apiName = (String) row.get('QualifiedApiName');
    }

    if (cache != null)
      cache.put(tableEnumOrId, apiName);
    return apiName;
  }

  private static List<String> buildRecommendedNextSteps(
    Map<String, Integer> ruleKeyCounts
  ) {
    List<String> out = new List<String>();
    if (ruleKeyCounts == null || ruleKeyCounts.isEmpty())
      return out;

    // Priority order: items most likely to block or cause production incidents first
    if (
      ruleKeyCounts.containsKey('SOQL_IN_LOOP') ||
      ruleKeyCounts.containsKey('DML_IN_LOOP')
    ) {
      out.add(
        'Address SOQL/DML inside loops by collecting records and performing one query/DML outside the loop.'
      );
    }
    if (
      ruleKeyCounts.containsKey('CROSS_TRIGGER_RECURSION_CYCLE') ||
      ruleKeyCounts.containsKey('RECURSION_RISK')
    ) {
      out.add(
        'Review recursion risks and add/verify a recursion guard; consider async orchestration if triggers call each other.'
      );
    }
    if (ruleKeyCounts.containsKey('CALLOUT_IN_TRIGGER')) {
      out.add(
        'Move HTTP callouts out of triggers into async processing (Queueable/@future) or Platform Events.'
      );
    }
    if (ruleKeyCounts.containsKey('EMAIL_IN_TRIGGER')) {
      out.add(
        'Avoid sending emails directly in triggers; move to async or an event-driven approach.'
      );
    }
    if (ruleKeyCounts.containsKey('MIXED_DML')) {
      out.add(
        'Separate setup-object DML (User/PermSet/Group) from business-object DML by moving one side to async.'
      );
    }
    if (ruleKeyCounts.containsKey('TRIGGER_HANDLER_MISSING')) {
      out.add(
        'Consider consolidating trigger logic into a handler framework for maintainability and consistent patterns.'
      );
    }
    if (ruleKeyCounts.containsKey('HARDCODED_ID')) {
      out.add(
        'Replace hardcoded Ids with Custom Metadata/Settings or query by stable external identifiers.'
      );
    }

    return out;
  }

  // =========================================================
  // ExecutiveSignal Helpers (ADD ONLY)
  // =========================================================

  private static String buildExecutiveSignalBlock(
    String overallRisk,
    Integer highCount,
    Integer mediumCount,
    Integer lowCount,
    Map<String, Integer> ruleKeyCounts
  ) {
    // ExecutiveSignal: keep this deterministic + manager-readable.
    String risk = String.isBlank(overallRisk) ? 'Low' : overallRisk;

    String impacts = buildArchitectImpacts(ruleKeyCounts); // Phase6.0-ArchitectSignal

    String out = '\n\nEXECUTIVE SIGNAL:\n'; // Phase6.0-ExecutiveSignal
    out += '- Overall Deployment Risk: ' + risk + '\n'; // Phase6.0-ExecutiveSignal
    out +=
      '- Architect Impacts: ' +
      (String.isBlank(impacts) ? 'None detected' : impacts) +
      '\n'; // Phase6.0-ArchitectSignal

    // Short closure line for managers
    out += '\nExecutive note: This signal summarizes detected patterns. See the RELEASE GATE section for release recommendation and top risks.\n'; // Phase6.0-ExecutiveSignal
    return out;
  }

  //ExecutiveSignal
  private static List<String> buildTopRisks(
    Map<String, Integer> ruleKeyCounts
  ) {
    List<String> out = new List<String>();
    if (ruleKeyCounts == null || ruleKeyCounts.isEmpty())
      return out;

    // Priority order: most production-impacting first
    if (ruleKeyCounts.containsKey('CROSS_TRIGGER_RECURSION_CYCLE')) {
      out.add(
        'Cross-trigger recursion may cause repeated execution and deployment instability.'
      );
    }
    if (ruleKeyCounts.containsKey('RECURSION_RISK')) {
      out.add(
        'Recursion risk may cause triggers to re-run unexpectedly and create instability.'
      );
    }
    if (ruleKeyCounts.containsKey('SOQL_IN_LOOP')) {
      out.add(
        'SOQL inside loops may fail under bulk load due to governor limits.'
      );
    }
    if (ruleKeyCounts.containsKey('DML_IN_LOOP')) {
      out.add(
        'DML inside loops may fail under bulk load due to governor limits.'
      );
    }
    if (ruleKeyCounts.containsKey('MIXED_DML')) {
      out.add(
        'Mixed DML may cause runtime failures when setup and business records are updated together.'
      );
    }
    if (ruleKeyCounts.containsKey('CALLOUT_IN_TRIGGER')) {
      out.add(
        'HTTP callouts in triggers increase failure risk and reduce reliability.'
      );
    }
    if (ruleKeyCounts.containsKey('DML_IN_BEFORE_TRIGGER')) {
      out.add(
        'DML inside BEFORE triggers can cause recursion and makes execution harder to predict.'
      );
    }
    if (ruleKeyCounts.containsKey('MULTIPLE_TRIGGERS_SAME_OBJECT')) {
      out.add(
        'Multiple triggers on the same object may cause unpredictable execution order.'
      );
    }
    if (ruleKeyCounts.containsKey('AFTER_TRIGGER_MUTATION')) {
      out.add(
        'Updating Trigger.new in AFTER triggers may cause inconsistent behavior.'
      );
    }
    if (ruleKeyCounts.containsKey('TRIGGER_HANDLER_MISSING')) {
      out.add(
        'Trigger logic is not centralized in a handler, increasing maintenance and change risk.'
      );
    }
    if (ruleKeyCounts.containsKey('HARDCODED_ID')) {
      out.add(
        'Hardcoded Ids increase environment migration risk and reduce reliability.'
      );
    }

    return out;
  }

  //ArchitectSignal
  private static String buildArchitectImpacts(
    Map<String, Integer> ruleKeyCounts
  ) {
    if (ruleKeyCounts == null || ruleKeyCounts.isEmpty())
      return null;

    Set<String> impacts = new Set<String>();

    // Runtime / limits
    if (
      ruleKeyCounts.containsKey('SOQL_IN_LOOP') ||
      ruleKeyCounts.containsKey('DML_IN_LOOP')
    ) {
      impacts.add('Runtime Governor Limit Risk');
    }
    if (ruleKeyCounts.containsKey('CALLOUT_IN_TRIGGER')) {
      impacts.add('Integration Reliability Risk');
    }
    if (ruleKeyCounts.containsKey('MIXED_DML')) {
      impacts.add('Runtime Transaction Risk');
    }

    // Deployment / stability
    if (
      ruleKeyCounts.containsKey('RECURSION_RISK') ||
      ruleKeyCounts.containsKey('CROSS_TRIGGER_RECURSION_CYCLE')
    ) {
      impacts.add('Deployment Stability Risk');
    }
    if (ruleKeyCounts.containsKey('MULTIPLE_TRIGGERS_SAME_OBJECT')) {
      impacts.add('Order-of-Execution Risk');
    }

    // Maintainability
    if (ruleKeyCounts.containsKey('TRIGGER_HANDLER_MISSING')) {
      impacts.add('Operational Maintainability Risk');
    }

    // Data integrity (keep conservative)
    if (ruleKeyCounts.containsKey('AFTER_TRIGGER_MUTATION')) {
      impacts.add('Data Consistency Risk');
    }

    if (impacts.isEmpty())
      return null;

    List<String> out = new List<String>();
    out.addAll(impacts);
    out.sort();
    return String.join(out, ', ');
  }

  private static void safePut(
    SObject sob,
    Map<String, Schema.SObjectField> fMap,
    String fieldApi,
    Object val
  ) {
    try {
      if (sob == null || fMap == null || String.isBlank(fieldApi))
        return;
      if (!fMap.containsKey(fieldApi))
        return; // field not present in this org
      sob.put(fieldApi, val);
    } catch (Exception ex) {
      // never fail the job because an optional field write failed
    }
  }
}

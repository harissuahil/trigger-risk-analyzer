/******************************************************************************************************
 * Apex controller used by the Trigger Risk Analyzer LWC.
 *
 * Responsibilities:
 * - Return Apex trigger names for the runner UI.
 * - Start Deployment Analysis Runs for selected triggers.
 * - Return run status, finding rows, and finding detail data to the LWC.
 * - Map Deployment Analysis records into simple DTOs for the UI.
 * - Preserve fallback parsing for older Summary__c-based run data.
 *
 * Keep this class focused on UI-facing orchestration and DTO mapping.
 * Detection logic belongs in TriggerRiskEngine, and queueable run processing belongs in DeploymentAnalysisJob.
 *******************************************************************************************************/
public with sharing class DeploymentAnalysisController {
  @AuraEnabled(cacheable=true)
  public static List<String> getTriggerNames() {
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

  @AuraEnabled
  public static Id startRun(String releaseLabel, List<String> triggerNames) {
    if (String.isBlank(releaseLabel))
      releaseLabel = 'UI-RUN';

    if (triggerNames == null || triggerNames.isEmpty()) {
      return DeploymentAnalysisService.startRun(releaseLabel);
    }
    return DeploymentAnalysisService.startRunForTriggers(
      releaseLabel,
      triggerNames
    );
  }

  //DTO for polling run status
  public class RunStatusResponse {
    @AuraEnabled
    public Id runId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public Integer totalTriggers;
    @AuraEnabled
    public Integer processedTriggers;
    @AuraEnabled
    public Integer highCount;
    @AuraEnabled
    public Integer mediumCount;
    @AuraEnabled
    public Integer lowCount;
    @AuraEnabled
    public String errorMessage;
    @AuraEnabled
    public Datetime lastUpdated;
    @AuraEnabled
    public String overallRisk;
    @AuraEnabled
    public String releaseRecommendation;
    @AuraEnabled
    public String architectImpacts;
    @AuraEnabled
    public List<String> topRisks;
    @AuraEnabled
    public String executiveSummary;
    @AuraEnabled
    public Datetime completedAt;
    @AuraEnabled
    public String releaseDecision;
    @AuraEnabled
    public String policyProfile;
    @AuraEnabled
    public String gateVersion;
    @AuraEnabled
    public String releaseRationale;
    @AuraEnabled
    public String requiredFixes;
  }

  @AuraEnabled
  public static RunStatusResponse getRunStatus(Id runId) {
    Deployment_Analysis_Run__c r = [
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
        Summary__c,
        Completed_At__c,
        Release_Decision__c,
        Release_Recommendation__c,
        Policy_Profile__c,
        Gate_Version__c,
        Architect_Impacts__c,
        Release_Rationale__c,
        Required_Fixes__c,
        Top_Risks__c
      FROM Deployment_Analysis_Run__c
      WHERE Id = :runId
      LIMIT 1
    ];

    RunStatusResponse resp = new RunStatusResponse();
    resp.runId = r.Id;
    resp.status = r.Status__c;
    resp.totalTriggers = (Integer) r.Total_Triggers__c;
    resp.processedTriggers = (Integer) r.Processed_Triggers__c;
    resp.highCount = (Integer) r.High_Count__c;
    resp.mediumCount = (Integer) r.Medium_Count__c;
    resp.lowCount = (Integer) r.Low_Count__c;
    resp.errorMessage = r.Error_Message__c;
    resp.lastUpdated = r.Last_Updated__c;
    Map<String, Schema.SObjectField> fMap = r.getSObjectType()
      .getDescribe()
      .fields.getMap();

    resp.releaseDecision = r.Release_Decision__c;
    resp.releaseRecommendation = r.Release_Recommendation__c;
    resp.policyProfile = r.Policy_Profile__c;
    resp.gateVersion = r.Gate_Version__c;
    resp.architectImpacts = r.Architect_Impacts__c;
    resp.releaseRationale = r.Release_Rationale__c;
    resp.requiredFixes = r.Required_Fixes__c;
    String risksRaw = r.Top_Risks__c;
    if (!String.isBlank(risksRaw)) {
      resp.topRisks = risksRaw.split('\n');
    } else {
      resp.topRisks = new List<String>();
    }

    resp.overallRisk = r.Overall_Risk__c;
    resp.completedAt = r.Completed_At__c;

    String summary = r.Summary__c;
    resp.executiveSummary = extractExecutiveBlock(summary);
    // Do NOT overwrite Release Gate fields (Release_Decision__c, Policy_Profile__c, etc.)
    if (String.isBlank(resp.releaseRecommendation)) {
      resp.releaseRecommendation = extractSingleLineValue(
        summary,
        'Release Recommendation:'
      );
    }

    // Only fill if blank.
    if (String.isBlank(resp.architectImpacts)) {
      resp.architectImpacts = extractSingleLineValue(
        summary,
        'Architect Impacts:'
      );
    }

    if (resp.topRisks == null || resp.topRisks.isEmpty()) {
      resp.topRisks = extractTopRisks(summary);
    }
    return resp;
  }

  //DTO for datatable rows
  public class ItemRowDTO {
    @AuraEnabled
    public Id itemId;
    @AuraEnabled
    public String triggerName;
    @AuraEnabled
    public String severity;
    @AuraEnabled
    public Integer severitySort;
    @AuraEnabled
    public String ruleKeys;
    @AuraEnabled
    public String ruleLabel;
    @AuraEnabled
    public Integer lineNumber;
    @AuraEnabled
    public String messageShort;
    @AuraEnabled
    public Boolean hasSnippet;
    @AuraEnabled
    public String category;
  }

  @AuraEnabled
  public static List<ItemRowDTO> getRunItems(Id runId) {
    List<Deployment_Analysis_Item__c> items = [
      SELECT
        Id,
        Trigger_Name__c,
        Risk__c,
        Severity_Sort__c,
        Matched_Rules__c,
        Rule_Label__c,
        Line_Number__c,
        Message__c,
        Snippet_Text__c,
        Category__c
      FROM Deployment_Analysis_Item__c
      WHERE Run__c = :runId
      ORDER BY Severity_Sort__c DESC, Trigger_Name__c ASC
    ];
    List<ItemRowDTO> out = new List<ItemRowDTO>();
    for (Deployment_Analysis_Item__c it : items) {
      if (it.Matched_Rules__c == 'BULK_CONFIDENCE_SCORE') {
        continue;
      }
      ItemRowDTO row = new ItemRowDTO();
      row.itemId = it.Id;
      row.triggerName = it.Trigger_Name__c;
      row.severity = it.Risk__c;
      row.severitySort = (it.Severity_Sort__c == null)
        ? null
        : Integer.valueOf(String.valueOf(it.Severity_Sort__c));
      row.ruleKeys = it.Matched_Rules__c;
      row.ruleLabel = it.Rule_Label__c;
      row.lineNumber = (it.Line_Number__c == null)
        ? null
        : Integer.valueOf(String.valueOf(it.Line_Number__c));
      row.category = it.Category__c;
      String msg = it.Message__c;
      row.messageShort = String.isBlank(msg)
        ? null
        : (msg.length() > 140 ? msg.substring(0, 140) + '…' : msg);
      row.hasSnippet = !String.isBlank(it.Snippet_Text__c);
      out.add(row);
    }
    return out;
  }

  //DTO for modal snippet
  public class SnippetDTO {
    @AuraEnabled
    public Integer startLine;
    @AuraEnabled
    public Integer endLine;
    @AuraEnabled
    public Integer highlightLine;
    @AuraEnabled
    public String text;
  }

  // DTO for modal details
  public class ItemDetailDTO {
    @AuraEnabled
    public Id itemId;
    @AuraEnabled
    public String triggerName;
    @AuraEnabled
    public String severity;
    @AuraEnabled
    public String ruleKeys;
    @AuraEnabled
    public String ruleLabel;
    @AuraEnabled
    public String category;
    @AuraEnabled
    public Integer lineNumber;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String recommendation;
    @AuraEnabled
    public SnippetDTO snippet;
  }

  @AuraEnabled(cacheable=true)
  public static ItemDetailDTO getItemDetail(Id itemId) {
    Deployment_Analysis_Item__c it = [
      SELECT
        Id,
        Trigger_Name__c,
        Risk__c,
        Matched_Rules__c,
        Rule_Label__c,
        Line_Number__c,
        Message__c,
        Recommendation__c,
        Snippet_Text__c,
        Snippet_Start_Line__c,
        Snippet_End_Line__c,
        Highlight_Line__c,
        Category__c
      FROM Deployment_Analysis_Item__c
      WHERE Id = :itemId
      LIMIT 1
    ];

    ItemDetailDTO d = new ItemDetailDTO();

    d.itemId = it.Id;
    d.triggerName = it.Trigger_Name__c;
    d.severity = it.Risk__c;
    d.ruleKeys = it.Matched_Rules__c;
    d.ruleLabel = it.Rule_Label__c;
    d.lineNumber = (it.Line_Number__c == null)
      ? null
      : Integer.valueOf(String.valueOf(it.Line_Number__c));
    d.message = it.Message__c;
    d.recommendation = it.Recommendation__c;
    d.category = it.Category__c;

    SnippetDTO sn = new SnippetDTO();
    sn.text = it.Snippet_Text__c;
    sn.startLine = (it.Snippet_Start_Line__c == null)
      ? null
      : Integer.valueOf(String.valueOf(it.Snippet_Start_Line__c));
    sn.endLine = (it.Snippet_End_Line__c == null)
      ? null
      : Integer.valueOf(String.valueOf(it.Snippet_End_Line__c));
    sn.highlightLine = (it.Highlight_Line__c == null)
      ? d.lineNumber
      : Integer.valueOf(String.valueOf(it.Highlight_Line__c));
    d.snippet = sn;
    return d;
  }

  private static String extractExecutiveBlock(String summary) {
    if (String.isBlank(summary))
      return null;

    Integer p = summary.indexOf('\n\nEXECUTIVE SIGNAL:\n');
    if (p < 0) {
      // Also accept if it starts at beginning
      p = summary.indexOf('EXECUTIVE SIGNAL:');
      if (p < 0)
        return null;
    }

    return summary.substring(p).trim();
  }

  private static String extractSingleLineValue(String summary, String key) {
    if (String.isBlank(summary) || String.isBlank(key))
      return null;

    Integer p = summary.indexOf(key);
    if (p < 0)
      return null;

    Integer start = p + key.length();
    String tail = summary.substring(start).trim();

    // take first line only
    Integer eol = tail.indexOf('\n');
    if (eol >= 0)
      tail = tail.substring(0, eol);

    return tail.trim();
  }

  private static List<String> extractTopRisks(String summary) {
    List<String> out = new List<String>();
    if (String.isBlank(summary))
      return out;

    Integer p = summary.indexOf('\nTop Risks:\n');
    if (p < 0)
      return out;

    String tail = summary.substring(p + '\nTop Risks:\n'.length());

    // read up to 3 lines that start with "1)" / "2)" / "3)"
    for (Integer i = 1; i <= 3; i++) {
      String prefix = String.valueOf(i) + ')';
      Integer li = tail.indexOf(prefix);
      if (li < 0)
        continue;

      String lineTail = tail.substring(li + prefix.length()).trim();
      Integer eol = lineTail.indexOf('\n');
      if (eol >= 0)
        lineTail = lineTail.substring(0, eol);

      if (!String.isBlank(lineTail))
        out.add(lineTail.trim());
    }
    return out;
  }

  private static String safeGetString(
    SObject sob,
    Map<String, Schema.SObjectField> fMap,
    String fieldApi
  ) {
    try {
      if (sob == null || fMap == null || String.isBlank(fieldApi))
        return null;
      if (!fMap.containsKey(fieldApi))
        return null;
      Object v = sob.get(fieldApi);
      return (v == null) ? null : String.valueOf(v);
    } catch (Exception ex) {
      return null;
    }
  }
}

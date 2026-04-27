//CLASS: DeploymentAnalysisController
public with sharing class DeploymentAnalysisController {

    @AuraEnabled(cacheable=true)
    public static List<String> getTriggerNames() {
        Map<String, Object> r =
            ToolingApiClient.queryUntyped('SELECT Name FROM ApexTrigger ORDER BY Name');

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
        if (String.isBlank(releaseLabel)) releaseLabel = 'UI-RUN';

        if (triggerNames == null || triggerNames.isEmpty()) {
            return DeploymentAnalysisService.startRun(releaseLabel);
        }
        return DeploymentAnalysisService.startRunForTriggers(releaseLabel, triggerNames);
    }

    //HS DTO for polling run status
    public class RunStatusResponse {
        //HS
        @AuraEnabled public Id runId; //HS
        @AuraEnabled public String status; //HS
        @AuraEnabled public Integer totalTriggers; //HS
        @AuraEnabled public Integer processedTriggers; //HS
        @AuraEnabled public Integer highCount; //HS
        @AuraEnabled public Integer mediumCount; //HS
        @AuraEnabled public Integer lowCount; //HS
        @AuraEnabled public String errorMessage; //HS
        @AuraEnabled public Datetime lastUpdated; //HS

        // ============================
        // Phase6.0-ExecutiveSignal
        // ============================
        @AuraEnabled public String overallRisk; // Phase6.0-ExecutiveSignal
        @AuraEnabled public String releaseRecommendation; // Phase6.0-ExecutiveSignal
        @AuraEnabled public String architectImpacts; // Phase6.0-ArchitectSignal
        @AuraEnabled public List<String> topRisks; // Phase6.0-ExecutiveSignal
        @AuraEnabled public String executiveSummary; // Phase6.0-ExecutiveSignal
        @AuraEnabled public Datetime completedAt; // Phase6.0-ExecutiveSignal
        // ============================
        // Phase6.0-ExecutiveSignal
        // ============================
        //==========Phase7.0.1 START code change=========
        @AuraEnabled public String releaseDecision;
        @AuraEnabled public String policyProfile;
        @AuraEnabled public String gateVersion;
        @AuraEnabled public String releaseRationale;
        @AuraEnabled public String requiredFixes;
        //==========Phase7.0.1 END code change=========

    }

    //HS
    @AuraEnabled
    public static RunStatusResponse getRunStatus(Id runId) {
        
        Deployment_Analysis_Run__c r = [
            SELECT Id, Status__c, Total_Triggers__c, Processed_Triggers__c,
            High_Count__c, Medium_Count__c, Low_Count__c,
            Error_Message__c, Last_Updated__c,
            Overall_Risk__c, Summary__c, Completed_At__c,
            Release_Decision__c, Release_Recommendation__c,
            Policy_Profile__c, Gate_Version__c,
            Architect_Impacts__c, Release_Rationale__c,
            Required_Fixes__c, Top_Risks__c
            FROM Deployment_Analysis_Run__c
            WHERE Id = :runId
            LIMIT 1
        ];
        
        RunStatusResponse resp = new RunStatusResponse();
        //HS
        resp.runId = r.Id; //HS
        resp.status = r.Status__c; //HS
        resp.totalTriggers = (Integer) r.Total_Triggers__c; //HS
        resp.processedTriggers = (Integer) r.Processed_Triggers__c; //HS
        resp.highCount = (Integer) r.High_Count__c; //HS
        resp.mediumCount = (Integer) r.Medium_Count__c; //HS
        resp.lowCount = (Integer) r.Low_Count__c; //HS
        resp.errorMessage = r.Error_Message__c; //HS
        resp.lastUpdated = r.Last_Updated__c; //HS
        //==========Phase7.0.1 START code change=========
        Map<String, Schema.SObjectField> fMap = r.getSObjectType().getDescribe().fields.getMap();
        
        resp.releaseDecision = r.Release_Decision__c;
        resp.releaseRecommendation = r.Release_Recommendation__c;
        resp.policyProfile = r.Policy_Profile__c;
        resp.gateVersion = r.Gate_Version__c;
        resp.architectImpacts = r.Architect_Impacts__c;
        resp.releaseRationale = r.Release_Rationale__c;
        resp.requiredFixes = r.Required_Fixes__c;
        //==========Phase7.0.1 START code change=========
        // Top_Risks__c is stored as Long Text (String) -> convert to List<String>
        String risksRaw = r.Top_Risks__c;
        if (!String.isBlank(risksRaw)) {
            resp.topRisks = risksRaw.split('\n');
        } else {
            resp.topRisks = new List<String>();
        }
        //==========Phase7.0.1 END code change=========

        //==========Phase7.0.1 END code change=========


        // ============================
        // Phase6.0-ExecutiveSignal START
        // ============================
        resp.overallRisk = r.Overall_Risk__c; // Phase6.0-ExecutiveSignal
        resp.completedAt = r.Completed_At__c; // Phase6.0-ExecutiveSignal

        // We store the executive block inside Summary__c (no schema changes).
        // Extract signal fields from the Summary__c block if present.
        String summary = r.Summary__c; // Phase6.0-ExecutiveSignal
        resp.executiveSummary = extractExecutiveBlock(summary); // Phase6.0-ExecutiveSignal
       //==========Phase7.0.2 START code change=========
        // Do NOT overwrite Release Gate fields (Release_Decision__c, Policy_Profile__c, etc.)
        // Keep Phase6 parsed values only if the structured fields are blank.
        if (String.isBlank(resp.releaseRecommendation)) {
            resp.releaseRecommendation = extractSingleLineValue(summary, 'Release Recommendation:'); // Phase6.0-ExecutiveSignal
        }
        
        // Phase6 architect impacts (summary) should not overwrite Phase7 gate architect impacts field.
        // Only fill if blank.
        if (String.isBlank(resp.architectImpacts)) {
            resp.architectImpacts = extractSingleLineValue(summary, 'Architect Impacts:'); // Phase6.0-ArchitectSignal
        }
        
        // Only fill top risks from Summary if Phase7 didn't already set them.
        if (resp.topRisks == null || resp.topRisks.isEmpty()) {
            resp.topRisks = extractTopRisks(summary); // Phase6.0-ExecutiveSignal
        }
        //==========Phase7.0.2 END code change=========

        // ============================
        // Phase6.0-ExecutiveSignal END
        // ============================

        return resp; //HS
        //HS
    }

    //HS
    //HS DTO for datatable rows
    public class ItemRowDTO {
        //HS
        @AuraEnabled public Id itemId; //HS
        @AuraEnabled public String triggerName; //HS
        @AuraEnabled public String severity; //HS
        @AuraEnabled public Integer severitySort; //HS
        @AuraEnabled public String ruleKeys; //HS
        @AuraEnabled public String ruleLabel; //HS
        @AuraEnabled public Integer lineNumber; //HS
        @AuraEnabled public String messageShort; //HS
        @AuraEnabled public Boolean hasSnippet; //HS
        @AuraEnabled public String category; //Phase5.4.3
    }

    //HS
    @AuraEnabled
    public static List<ItemRowDTO> getRunItems(Id runId) {
        //HS
        List<Deployment_Analysis_Item__c> items = [
            //HS
            SELECT Id, Trigger_Name__c, Risk__c, Severity_Sort__c, Matched_Rules__c,
                   Rule_Label__c, Line_Number__c, Message__c, Snippet_Text__c,
                    Category__c //Phase5.4.3
            FROM Deployment_Analysis_Item__c
            //HS
            WHERE Run__c = :runId
            //HS
            ORDER BY Severity_Sort__c DESC, Trigger_Name__c ASC
            //HS
        ];
        //HS
        List<ItemRowDTO> out = new List<ItemRowDTO>();
        //HS
        for (Deployment_Analysis_Item__c it : items) {
            //HS
            if (it.Matched_Rules__c == 'BULK_CONFIDENCE_SCORE') { continue; } //HS
            //HS
            ItemRowDTO row = new ItemRowDTO();

            //HS
            row.itemId = it.Id; //HS
            row.triggerName = it.Trigger_Name__c; //HS
            row.severity = it.Risk__c; //HS
            row.severitySort =
                (it.Severity_Sort__c == null)
                ? null
                : Integer.valueOf(String.valueOf(it.Severity_Sort__c)); //HS
            row.ruleKeys = it.Matched_Rules__c; //HS
            row.ruleLabel = it.Rule_Label__c; //HS
            row.lineNumber =
                (it.Line_Number__c == null)
                ? null
                : Integer.valueOf(String.valueOf(it.Line_Number__c)); //HS
            row.category = it.Category__c; //Phase5.4.3
            //HS
            String msg = it.Message__c; //HS
            row.messageShort =
                String.isBlank(msg)
                ? null
                : (msg.length() > 140 ? msg.substring(0, 140) + '…' : msg); //HS
            row.hasSnippet = !String.isBlank(it.Snippet_Text__c); //HS
            out.add(row); //HS
        }
        //HS
        return out; //HS
        //HS
    }

    //HS
    //HS DTO for modal snippet
    public class SnippetDTO {
        //HS
        @AuraEnabled public Integer startLine; //HS
        @AuraEnabled public Integer endLine; //HS
        @AuraEnabled public Integer highlightLine; //HS
        @AuraEnabled public String text; //HS
        //HS
    }

    //HS
    //HS DTO for modal details
    public class ItemDetailDTO {
        //HS
        @AuraEnabled public Id itemId; //HS
        @AuraEnabled public String triggerName; //HS
        @AuraEnabled public String severity; //HS
        @AuraEnabled public String ruleKeys; //HS
        @AuraEnabled public String ruleLabel; //HS
        @AuraEnabled public Integer lineNumber; //HS
        @AuraEnabled public String message; //HS
        @AuraEnabled public String recommendation; //HS
        @AuraEnabled public SnippetDTO snippet; //HS
        //HS
    }

    //HS
    @AuraEnabled(cacheable=true)
    public static ItemDetailDTO getItemDetail(Id itemId) {
        //HS
        Deployment_Analysis_Item__c it = [
            //HS
            SELECT Id, Trigger_Name__c, Risk__c, Matched_Rules__c, Rule_Label__c,
                   //HS
                   Line_Number__c, Message__c, Recommendation__c,
                   //HS
                   Snippet_Text__c, Snippet_Start_Line__c, Snippet_End_Line__c, Highlight_Line__c
            //HS
            FROM Deployment_Analysis_Item__c
            //HS
            WHERE Id = :itemId
            //HS
            LIMIT 1
            //HS
        ];
        //HS
        ItemDetailDTO d = new ItemDetailDTO();
        //HS
        d.itemId = it.Id; //HS
        d.triggerName = it.Trigger_Name__c; //HS
        d.severity = it.Risk__c; //HS
        d.ruleKeys = it.Matched_Rules__c; //HS
        d.ruleLabel = it.Rule_Label__c; //HS
        d.lineNumber =
            (it.Line_Number__c == null)
            ? null
            : Integer.valueOf(String.valueOf(it.Line_Number__c)); //HS
        d.message = it.Message__c; //HS
        d.recommendation = it.Recommendation__c; //HS

        //HS
        SnippetDTO sn = new SnippetDTO(); //HS
        sn.text = it.Snippet_Text__c; //HS
        sn.startLine =
            (it.Snippet_Start_Line__c == null)
            ? null
            : Integer.valueOf(String.valueOf(it.Snippet_Start_Line__c)); //HS
        sn.endLine =
            (it.Snippet_End_Line__c == null)
            ? null
            : Integer.valueOf(String.valueOf(it.Snippet_End_Line__c)); //HS
        sn.highlightLine =
            (it.Highlight_Line__c == null)
            ? d.lineNumber
            : Integer.valueOf(String.valueOf(it.Highlight_Line__c)); //HS
        d.snippet = sn; //HS
        return d; //HS
        //HS
    }

    // =========================================================
    // Phase6.0-ExecutiveSignal Parsing Helpers (ADD ONLY)
    // =========================================================

    private static String extractExecutiveBlock(String summary) {
        // Phase6.0-ExecutiveSignal
        if (String.isBlank(summary)) return null;

        Integer p = summary.indexOf('\n\nEXECUTIVE SIGNAL:\n');
        if (p < 0) {
            // Also accept if it starts at beginning
            p = summary.indexOf('EXECUTIVE SIGNAL:');
            if (p < 0) return null;
        }

        return summary.substring(p).trim();
    }

    private static String extractSingleLineValue(String summary, String key) {
        // Phase6.0-ExecutiveSignal
        if (String.isBlank(summary) || String.isBlank(key)) return null;

        Integer p = summary.indexOf(key);
        if (p < 0) return null;

        Integer start = p + key.length();
        String tail = summary.substring(start).trim();

        // take first line only
        Integer eol = tail.indexOf('\n');
        if (eol >= 0) tail = tail.substring(0, eol);

        return tail.trim();
    }

    private static List<String> extractTopRisks(String summary) {
        // Phase6.0-ExecutiveSignal
        List<String> out = new List<String>();
        if (String.isBlank(summary)) return out;

        Integer p = summary.indexOf('\nTop Risks:\n');
        if (p < 0) return out;

        String tail = summary.substring(p + '\nTop Risks:\n'.length());

        // read up to 3 lines that start with "1)" / "2)" / "3)"
        for (Integer i = 1; i <= 3; i++) {
            String prefix = String.valueOf(i) + ')';
            Integer li = tail.indexOf(prefix);
            if (li < 0) continue;

            String lineTail = tail.substring(li + prefix.length()).trim();
            Integer eol = lineTail.indexOf('\n');
            if (eol >= 0) lineTail = lineTail.substring(0, eol);

            if (!String.isBlank(lineTail)) out.add(lineTail.trim());
        }
        return out;
    }
    //==========Phase7.0.1 START code change=========
    private static String safeGetString(
        SObject sob,
        Map<String, Schema.SObjectField> fMap,
        String fieldApi
    ) {
        try {
            if (sob == null || fMap == null || String.isBlank(fieldApi)) return null;
            if (!fMap.containsKey(fieldApi)) return null;
            Object v = sob.get(fieldApi);
            return (v == null) ? null : String.valueOf(v);
        } catch (Exception ex) {
            return null;
        }
    }
    //==========Phase7.0.1 END code change=========
}
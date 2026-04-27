@isTest
private class DeploymentAnalysisControllerTest {
    
    // ============================================================
    // IMPORTANT SOURCE NOTES (read before adding tests)
    //
    // 1) getRunStatus SOQL does NOT include Release_Decision__c,
    //    Policy_Profile__c, Gate_Version__c, Architect_Impacts__c,
    //    Release_Rationale__c, Required_Fixes__c, or Top_Risks__c.
    //    safeGetString() calls sob.get() on an unqueried field, Salesforce
    //    throws SObjectException, safeGetString catches it, returns null.
    //    These DTO fields are therefore always null from this method.
    //    The LWC gets gate data by calling parseReleaseGateFromSummary()
    //    on the executiveSummary text — NOT from structured Apex DTO fields.
    //
    // 2) releaseRecommendation, architectImpacts, and topRisks ARE
    //    backfilled from Summary__c text via extractSingleLineValue()
    //    and extractTopRisks() when the structured fields are blank.
    //
    // 3) Top_Risks__c is not in the uploaded object metadata either,
    //    so safeGetString returns null for it; topRisks always arrives
    //    via the summary-text fallback in practice.
    // ============================================================
    
    // ============================================================
    // Test Helpers
    // ============================================================
    
    private static Deployment_Analysis_Run__c insertRun(
        String status,
        Integer high,
        Integer med,
        Integer low
    ) {
        Deployment_Analysis_Run__c r = new Deployment_Analysis_Run__c(
            Status__c       = status,
            High_Count__c   = high,
            Medium_Count__c = med,
            Low_Count__c    = low,
            Overall_Risk__c = (high > 0) ? 'High' : ((med > 0) ? 'Medium' : 'Low'),
            Last_Updated__c = System.now()
        );
        insert r;
        return r;
    }
    
    private static Deployment_Analysis_Item__c insertItem(
        Id     runId,
        String triggerName,
        String severity,
        Integer severitySort,
        String ruleKey,
        String ruleLabel,
        String message,
        String snippetText
    ) {
        Deployment_Analysis_Item__c it = new Deployment_Analysis_Item__c(
            Run__c            = runId,
            Trigger_Name__c   = triggerName,
            Risk__c           = severity,
            Severity_Sort__c  = severitySort,
            Matched_Rules__c  = ruleKey,
            Rule_Label__c     = ruleLabel,
            Message__c        = message,
            Snippet_Text__c   = snippetText,
            Line_Number__c    = 5,
            Highlight_Line__c = 5,
            Category__c       = 'BulkRisk'
        );
        insert it;
        return it;
    }
    
    // ============================================================
    // getRunStatus — core field mapping (4 tests)
    // ============================================================
    
    @isTest
    static void getRunStatus_coreFields_shouldMapCorrectly() {
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c             = 'Done',
            Total_Triggers__c     = 5,
            Processed_Triggers__c = 5,
            High_Count__c         = 2,
            Medium_Count__c       = 1,
            Low_Count__c          = 3,
            Overall_Risk__c       = 'High',
            Last_Updated__c       = System.now()
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertEquals(run.Id, resp.runId,        'runId should match');
        System.assertEquals('Done', resp.status,       'status should map');
        System.assertEquals(5, resp.totalTriggers,     'totalTriggers should map');
        System.assertEquals(5, resp.processedTriggers, 'processedTriggers should map');
        System.assertEquals(2, resp.highCount,         'highCount should map');
        System.assertEquals(1, resp.mediumCount,       'mediumCount should map');
        System.assertEquals(3, resp.lowCount,          'lowCount should map');
        System.assertEquals('High', resp.overallRisk,  'overallRisk should map');
    }
    
    @isTest
    static void getRunStatus_nullCounts_shouldReturnNull() {
        // SOURCE: (Integer) r.Total_Triggers__c — casting null Decimal gives null.
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c = 'Running'
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertEquals('Running', resp.status,       'status should be Running');
        System.assertEquals(null, resp.totalTriggers,     'totalTriggers should be null when not set');
        System.assertEquals(null, resp.highCount,         'highCount should be null when not set');
    }
    
    @isTest
    static void getRunStatus_errorMessage_shouldMap() {
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c        = 'Failed',
            Error_Message__c = 'Callout timed out'
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertEquals('Failed', resp.status,             'status should be Failed');
        System.assertEquals('Callout timed out', resp.errorMessage, 'errorMessage should map');
    }
    
    @isTest
    static void getRunStatus_completedAt_shouldMap() {
        // SOURCE: Completed_At__c IS in the SOQL, so it always maps.
        Datetime now = System.now();
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c       = 'Done',
            Completed_At__c = now
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertNotEquals(null, resp.completedAt,
                               'completedAt should not be null when Completed_At__c is set');
    }
    
    // ============================================================
    // getRunStatus — executiveSummary extraction (3 tests)
    // SOURCE: extractExecutiveBlock() accepts two patterns:
    //   (a) '\n\nEXECUTIVE SIGNAL:\n'  — embedded mid-summary
    //   (b) 'EXECUTIVE SIGNAL:' fallback — at start of summary
    //   (c) neither found => null
    // ============================================================
    
    @isTest
    static void getRunStatus_executiveSummary_embeddedBlock_shouldExtract() {
        String summary =
            'Trigger Risk Analysis completed.\n\n' +
            'EXECUTIVE SIGNAL:\n' +
            '- Overall Deployment Risk: High\n' +
            '- Architect Impacts: Runtime Governor Limit Risk\n';
        
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c = 'Done', Summary__c = summary
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertNotEquals(null, resp.executiveSummary,
                               'executiveSummary must not be null when EXECUTIVE SIGNAL block is present');
        System.assert(resp.executiveSummary.contains('EXECUTIVE SIGNAL'),
                      'executiveSummary must contain the EXECUTIVE SIGNAL header');
    }
    
    @isTest
    static void getRunStatus_executiveSummary_atStartOfSummary_shouldExtract() {
        // Pattern (b): extractExecutiveBlock falls back to plain indexOf when
        // '\n\nEXECUTIVE SIGNAL:\n' is not found.
        String summary = 'EXECUTIVE SIGNAL:\n- Overall Deployment Risk: Low\n';
        
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c = 'Done', Summary__c = summary
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertNotEquals(null, resp.executiveSummary,
                               'executiveSummary must not be null when EXECUTIVE SIGNAL starts the summary');
        System.assert(resp.executiveSummary.startsWith('EXECUTIVE SIGNAL'),
                      'executiveSummary should start with EXECUTIVE SIGNAL in this pattern');
    }
    
    @isTest
    static void getRunStatus_noExecutiveBlock_shouldReturnNullExecutiveSummary() {
        // Pattern (c): no EXECUTIVE SIGNAL keyword anywhere.
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c  = 'Done',
            Summary__c = 'Trigger Risk Analysis completed.\n\nScope:\n- Triggers: 1\n'
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertEquals(null, resp.executiveSummary,
                            'executiveSummary must be null when no EXECUTIVE SIGNAL block is in Summary__c');
    }
    
    // ============================================================
    // getRunStatus — topRisks from Summary__c fallback (2 tests)
    // SOURCE: Phase 7.0.2:
    //   if (resp.topRisks == null || resp.topRisks.isEmpty())
    //       resp.topRisks = extractTopRisks(summary);
    // extractTopRisks reads lines prefixed '1)' '2)' '3)' after '\nTop Risks:\n'.
    // ============================================================
    
    @isTest
    static void getRunStatus_topRisks_shouldParseFromSummaryFallback() {
        String summary =
            'Overall assessment: High risk.\n' +
            '\nTop Risks:\n' +
            '1) SOQL inside loops may fail under bulk load.\n' +
            '2) Cross-trigger recursion may cause repeated execution.\n' +
            '3) DML inside loops may fail under bulk load.\n';
        
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c = 'Done', High_Count__c = 2, Summary__c = summary
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertNotEquals(null, resp.topRisks,     'topRisks should never be null');
        System.assertEquals(3, resp.topRisks.size(),
                            'extractTopRisks should parse 3 numbered lines from summary');
        System.assert(resp.topRisks[0].contains('SOQL'),
                      'First top risk should contain SOQL text');
    }
    
    @isTest
    static void getRunStatus_topRisks_noSummary_shouldBeEmptyList() {
        // SOURCE: topRisks initialized to new List<String>() when blank.
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c = 'Done'
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertNotEquals(null, resp.topRisks,
                               'topRisks should never be null');
        System.assertEquals(0, resp.topRisks.size(),
                            'topRisks should be empty list when no summary data exists');
    }
    
    // ============================================================
    // getRunStatus — releaseRecommendation fallback (1 test)
    // SOURCE: Phase 7.0.2:
    //   if (String.isBlank(resp.releaseRecommendation))
    //       resp.releaseRecommendation =
    //           extractSingleLineValue(summary, 'Release Recommendation:');
    // The structured field is always blank (not in SOQL), so fallback always fires.
    // ============================================================
    
    @isTest
    static void getRunStatus_releaseRecommendation_shouldParseFromSummary() {
        String summary =
            'Some content.\n' +
            'Release Recommendation: PROCEED WITH CAUTION\n' +
            'More content.\n';
        
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c = 'Done', Summary__c = summary
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertEquals('PROCEED WITH CAUTION', resp.releaseRecommendation,
                            'releaseRecommendation must be parsed from Summary__c via extractSingleLineValue');
    }
    
    // ============================================================
    // getRunItems — DTO mapping, filtering, truncation, sorting
    // ============================================================
    
    @isTest
    static void getRunItems_basicRow_shouldMapAllFields() {
        Deployment_Analysis_Run__c run = insertRun('Done', 1, 0, 0);
        
        Deployment_Analysis_Item__c item = new Deployment_Analysis_Item__c(
            Run__c           = run.Id,
            Trigger_Name__c  = 'MyTrigger',
            Risk__c          = 'High',
            Severity_Sort__c = 3,
            Matched_Rules__c = 'SOQL_IN_LOOP',
            Rule_Label__c    = 'SOQL in Loop',
            Message__c       = 'SOQL inside a loop can hit query limits.',
            Line_Number__c   = 10,
            Category__c      = 'BulkRisk',
            Snippet_Text__c  = '   10 | List<Contact> cs = [SELECT Id FROM Contact];'
        );
        insert item;
        
        List<DeploymentAnalysisController.ItemRowDTO> rows =
            DeploymentAnalysisController.getRunItems(run.Id);
        
        System.assertEquals(1, rows.size(),                 'Should return exactly 1 row');
        System.assertEquals(item.Id, rows[0].itemId,        'itemId should match');
        System.assertEquals('MyTrigger', rows[0].triggerName,'triggerName should match');
        System.assertEquals('High', rows[0].severity,       'severity should be High');
        System.assertEquals(3, rows[0].severitySort,        'severitySort should be 3');
        System.assertEquals('SOQL_IN_LOOP', rows[0].ruleKeys,'ruleKeys should match');
        System.assertEquals('SOQL in Loop', rows[0].ruleLabel,'ruleLabel should match');
        System.assertEquals(10, rows[0].lineNumber,         'lineNumber should be 10');
        System.assertEquals('BulkRisk', rows[0].category,   'category should be BulkRisk');
        System.assertEquals(true, rows[0].hasSnippet,       'hasSnippet should be true');
    }
    
    @isTest
    static void getRunItems_bulkConfidenceScore_shouldBeFilteredOut() {
        // SOURCE: if (it.Matched_Rules__c == 'BULK_CONFIDENCE_SCORE') { continue; }
        Deployment_Analysis_Run__c run = insertRun('Done', 1, 0, 0);
        
        insertItem(run.Id, 'T', 'High', 3, 'SOQL_IN_LOOP',         'SOQL in Loop',           'SOQL in loop', null);
        insertItem(run.Id, 'T', 'Low',  1, 'BULK_CONFIDENCE_SCORE', 'Bulkification Confidence','Bulk score',  null);
        
        List<DeploymentAnalysisController.ItemRowDTO> rows =
            DeploymentAnalysisController.getRunItems(run.Id);
        
        System.assertEquals(1, rows.size(),
                            'BULK_CONFIDENCE_SCORE must be filtered out of returned rows');
        System.assertEquals('SOQL_IN_LOOP', rows[0].ruleKeys,
                            'Only the SOQL_IN_LOOP finding should remain');
    }
    
    @isTest
    static void getRunItems_longMessage_shouldTruncateAt140WithEllipsis() {
        // SOURCE: msg.length() > 140 ? msg.substring(0, 140) + '…' : msg
        Deployment_Analysis_Run__c run = insertRun('Done', 0, 1, 0);
        
        String longMsg = 'X'.repeat(200);
        insertItem(run.Id, 'T', 'Medium', 2, 'EMAIL_IN_TRIGGER', 'Email in Trigger', longMsg, null);
        
        List<DeploymentAnalysisController.ItemRowDTO> rows =
            DeploymentAnalysisController.getRunItems(run.Id);
        
        System.assertEquals(141, rows[0].messageShort.length(),
                            'messageShort should be exactly 141 chars (140 + single ellipsis char)');
        System.assert(rows[0].messageShort.endsWith('…'),
                      'messageShort should end with the ellipsis character');
    }
    
    @isTest
    static void getRunItems_shortMessage_shouldNotBeTruncated() {
        Deployment_Analysis_Run__c run = insertRun('Done', 0, 0, 1);
        
        String shortMsg = 'Short message.';
        insertItem(run.Id, 'T', 'Low', 1, 'HARDCODED_ID', 'Hardcoded Id', shortMsg, null);
        
        List<DeploymentAnalysisController.ItemRowDTO> rows =
            DeploymentAnalysisController.getRunItems(run.Id);
        
        System.assertEquals(shortMsg, rows[0].messageShort,
                            'Short messages must not be truncated');
    }
    
    @isTest
    static void getRunItems_nullMessage_shouldReturnNullMessageShort() {
        // SOURCE: String.isBlank(msg) ? null : (msg.length() > 140 ? ... : msg)
        Deployment_Analysis_Run__c run = insertRun('Done', 0, 0, 1);
        
        Deployment_Analysis_Item__c item = new Deployment_Analysis_Item__c(
            Run__c = run.Id, Trigger_Name__c = 'T', Risk__c = 'Low',
            Severity_Sort__c = 1, Matched_Rules__c = 'CATCH_DEBUG_ONLY',
            Rule_Label__c = 'Catch only debug', Message__c = null
        );
        insert item;
        
        List<DeploymentAnalysisController.ItemRowDTO> rows =
            DeploymentAnalysisController.getRunItems(run.Id);
        
        System.assertEquals(null, rows[0].messageShort,
                            'Null message should yield null messageShort');
    }
    
    @isTest
    static void getRunItems_hasSnippet_trueWhenTextPresent() {
        Deployment_Analysis_Run__c run = insertRun('Done', 1, 0, 0);
        insertItem(run.Id, 'T', 'High', 3, 'DML_IN_LOOP', 'DML in Loop',
                   'DML in loop', 'some snippet text');
        
        List<DeploymentAnalysisController.ItemRowDTO> rows =
            DeploymentAnalysisController.getRunItems(run.Id);
        
        System.assertEquals(true, rows[0].hasSnippet,
                            'hasSnippet should be true when Snippet_Text__c is not blank');
    }
    
    @isTest
    static void getRunItems_hasSnippet_falseWhenTextNull() {
        Deployment_Analysis_Run__c run = insertRun('Done', 1, 0, 0);
        insertItem(run.Id, 'T', 'High', 3, 'DML_IN_LOOP', 'DML in Loop',
                   'DML in loop', null);
        
        List<DeploymentAnalysisController.ItemRowDTO> rows =
            DeploymentAnalysisController.getRunItems(run.Id);
        
        System.assertEquals(false, rows[0].hasSnippet,
                            'hasSnippet should be false when Snippet_Text__c is null');
    }
    
    @isTest
    static void getRunItems_sortedBySeverityDesc_thenTriggerNameAsc() {
        // SOURCE: ORDER BY Severity_Sort__c DESC, Trigger_Name__c ASC
        Deployment_Analysis_Run__c run = insertRun('Done', 2, 1, 1);
        
        insertItem(run.Id, 'ZTrigger', 'High',   3, 'SOQL_IN_LOOP',     'SOQL in Loop',     'high-z', null);
        insertItem(run.Id, 'ATrigger', 'High',   3, 'DML_IN_LOOP',      'DML in Loop',      'high-a', null);
        insertItem(run.Id, 'MTrigger', 'Low',    1, 'HARDCODED_ID',     'Hardcoded Id',     'low',    null);
        insertItem(run.Id, 'BTrigger', 'Medium', 2, 'EMAIL_IN_TRIGGER', 'Email in Trigger', 'medium', null);
        
        List<DeploymentAnalysisController.ItemRowDTO> rows =
            DeploymentAnalysisController.getRunItems(run.Id);
        
        System.assertEquals(4, rows.size(),                    'Should have 4 rows');
        System.assertEquals('High', rows[0].severity,         'Row 0 must be High');
        System.assertEquals('ATrigger', rows[0].triggerName,
                            'Among equal High severity, ATrigger must sort before ZTrigger');
        System.assertEquals('High', rows[1].severity,         'Row 1 must be High');
        System.assertEquals('ZTrigger', rows[1].triggerName,  'ZTrigger follows ATrigger');
        System.assertEquals('Medium', rows[2].severity,       'Row 2 must be Medium');
        System.assertEquals('Low', rows[3].severity,          'Row 3 must be Low');
    }
    
    @isTest
    static void getRunItems_nullLineNumber_shouldReturnNull() {
        // SOURCE: row.lineNumber = (it.Line_Number__c == null) ? null : Integer.valueOf(...)
        Deployment_Analysis_Run__c run = insertRun('Done', 0, 1, 0);
        
        Deployment_Analysis_Item__c item = new Deployment_Analysis_Item__c(
            Run__c = run.Id, Trigger_Name__c = 'T', Risk__c = 'Medium',
            Severity_Sort__c = 2, Matched_Rules__c = 'TRIGGER_HANDLER_MISSING',
            Rule_Label__c = 'Missing Trigger Handler', Message__c = 'No handler.',
            Line_Number__c = null
        );
        insert item;
        
        List<DeploymentAnalysisController.ItemRowDTO> rows =
            DeploymentAnalysisController.getRunItems(run.Id);
        
        System.assertEquals(null, rows[0].lineNumber,
                            'lineNumber in DTO should be null when Line_Number__c is null');
    }
    
    @isTest
    static void getRunItems_nullSeveritySort_shouldReturnNull() {
        // SOURCE: row.severitySort = (it.Severity_Sort__c == null) ? null : Integer.valueOf(...)
        Deployment_Analysis_Run__c run = insertRun('Done', 0, 0, 1);
        
        Deployment_Analysis_Item__c item = new Deployment_Analysis_Item__c(
            Run__c = run.Id, Trigger_Name__c = 'T', Risk__c = 'Low',
            Severity_Sort__c = null, Matched_Rules__c = 'CATCH_DEBUG_ONLY',
            Rule_Label__c = 'Catch only debug', Message__c = 'Debug only.'
        );
        insert item;
        
        List<DeploymentAnalysisController.ItemRowDTO> rows =
            DeploymentAnalysisController.getRunItems(run.Id);
        
        System.assertEquals(null, rows[0].severitySort,
                            'severitySort in DTO should be null when Severity_Sort__c is null');
    }
    
    @isTest
    static void getRunItems_noFindings_shouldReturnEmptyList() {
        Deployment_Analysis_Run__c run = insertRun('Done', 0, 0, 0);
        
        List<DeploymentAnalysisController.ItemRowDTO> rows =
            DeploymentAnalysisController.getRunItems(run.Id);
        
        System.assertEquals(0, rows.size(),
                            'Run with no DAI items should return empty list');
    }
    
    // ============================================================
    // getItemDetail — DTO mapping, snippet fields, fallback logic
    // ============================================================
    
    @isTest
    static void getItemDetail_coreFields_shouldMap() {
        Deployment_Analysis_Run__c run = insertRun('Done', 1, 0, 0);
        
        Deployment_Analysis_Item__c item = new Deployment_Analysis_Item__c(
            Run__c            = run.Id,
            Trigger_Name__c   = 'MyTrigger',
            Risk__c           = 'High',
            Matched_Rules__c  = 'DML_IN_LOOP',
            Rule_Label__c     = 'DML in Loop',
            Message__c        = 'DML inside a loop can hit governor limits.',
            Recommendation__c = 'Collect records and perform one DML outside the loop.',
            Line_Number__c    = 7,
            Highlight_Line__c = 7,
            Snippet_Text__c   = '   7 | update a;',
            Snippet_Start_Line__c = 5,
            Snippet_End_Line__c   = 9
        );
        insert item;
        
        DeploymentAnalysisController.ItemDetailDTO d =
            DeploymentAnalysisController.getItemDetail(item.Id);
        
        System.assertEquals(item.Id, d.itemId,          'itemId should match');
        System.assertEquals('MyTrigger', d.triggerName, 'triggerName should match');
        System.assertEquals('High', d.severity,         'severity should be High');
        System.assertEquals('DML_IN_LOOP', d.ruleKeys,  'ruleKeys should match');
        System.assertEquals('DML in Loop', d.ruleLabel, 'ruleLabel should match');
        System.assertEquals(7, d.lineNumber,            'lineNumber should be 7');
        System.assertEquals('DML inside a loop can hit governor limits.', d.message,
                            'message must map without truncation');
        System.assertEquals('Collect records and perform one DML outside the loop.', d.recommendation,
                            'recommendation should map');
    }
    
    @isTest
    static void getItemDetail_snippetFields_shouldMap() {
        Deployment_Analysis_Run__c run = insertRun('Done', 1, 0, 0);
        
        Deployment_Analysis_Item__c item = new Deployment_Analysis_Item__c(
            Run__c                = run.Id,
            Trigger_Name__c       = 'T',
            Risk__c               = 'High',
            Matched_Rules__c      = 'SOQL_IN_LOOP',
            Rule_Label__c         = 'SOQL in Loop',
            Message__c            = 'SOQL in loop',
            Snippet_Text__c       = '   5 | for (...) {\n   6 |   [SELECT Id FROM C];\n   7 | }',
            Snippet_Start_Line__c = 5,
            Snippet_End_Line__c   = 7,
            Highlight_Line__c     = 6,
            Line_Number__c        = 6
        );
        insert item;
        
        DeploymentAnalysisController.ItemDetailDTO d =
            DeploymentAnalysisController.getItemDetail(item.Id);
        
        System.assertNotEquals(null, d.snippet,              'snippet should not be null');
        System.assertEquals(5, d.snippet.startLine,         'snippet startLine should be 5');
        System.assertEquals(7, d.snippet.endLine,           'snippet endLine should be 7');
        System.assertEquals(6, d.snippet.highlightLine,     'snippet highlightLine should be 6');
        System.assertNotEquals(null, d.snippet.text,        'snippet text should not be null');
    }
    
    @isTest
    static void getItemDetail_nullHighlightLine_fallsBackToLineNumber() {
        // SOURCE: sn.highlightLine = (it.Highlight_Line__c == null)
        //             ? d.lineNumber
        //             : Integer.valueOf(String.valueOf(it.Highlight_Line__c));
        Deployment_Analysis_Run__c run = insertRun('Done', 1, 0, 0);
        
        Deployment_Analysis_Item__c item = new Deployment_Analysis_Item__c(
            Run__c            = run.Id,
            Trigger_Name__c   = 'T',
            Risk__c           = 'High',
            Matched_Rules__c  = 'CALLOUT_IN_TRIGGER',
            Rule_Label__c     = 'Callout in Trigger',
            Message__c        = 'HTTP callout detected.',
            Snippet_Text__c   = 'some snippet',
            Line_Number__c    = 8,
            Highlight_Line__c = null
        );
        insert item;
        
        DeploymentAnalysisController.ItemDetailDTO d =
            DeploymentAnalysisController.getItemDetail(item.Id);
        
        System.assertEquals(8, d.snippet.highlightLine,
                            'When Highlight_Line__c is null, highlightLine must fall back to lineNumber (8)');
    }
    
    @isTest
    static void getItemDetail_nullHighlightAndNullLineNumber_highlightShouldBeNull() {
        // SOURCE: d.lineNumber = null (Line_Number__c is null)
        //         sn.highlightLine = d.lineNumber = null
        Deployment_Analysis_Run__c run = insertRun('Done', 0, 1, 0);
        
        Deployment_Analysis_Item__c item = new Deployment_Analysis_Item__c(
            Run__c            = run.Id,
            Trigger_Name__c   = 'T',
            Risk__c           = 'Medium',
            Matched_Rules__c  = 'TRIGGER_HANDLER_MISSING',
            Rule_Label__c     = 'Missing Trigger Handler',
            Message__c        = 'No handler found.',
            Snippet_Text__c   = 'some snippet',
            Line_Number__c    = null,
            Highlight_Line__c = null
        );
        insert item;
        
        DeploymentAnalysisController.ItemDetailDTO d =
            DeploymentAnalysisController.getItemDetail(item.Id);
        
        System.assertEquals(null, d.lineNumber,
                            'lineNumber should be null when Line_Number__c is null');
        System.assertEquals(null, d.snippet.highlightLine,
                            'highlightLine should be null when both Highlight_Line__c and Line_Number__c are null');
    }
    
    @isTest
    static void getItemDetail_nullSnippetBounds_shouldReturnNull() {
        // SOURCE: sn.startLine = (it.Snippet_Start_Line__c == null) ? null : Integer.valueOf(...)
        //         sn.endLine   = (it.Snippet_End_Line__c == null)   ? null : Integer.valueOf(...)
        Deployment_Analysis_Run__c run = insertRun('Done', 1, 0, 0);
        
        Deployment_Analysis_Item__c item = new Deployment_Analysis_Item__c(
            Run__c                = run.Id,
            Trigger_Name__c       = 'T',
            Risk__c               = 'High',
            Matched_Rules__c      = 'MIXED_DML',
            Rule_Label__c         = 'Mixed DML',
            Message__c            = 'Mixed DML detected.',
            Snippet_Text__c       = 'some text',
            Line_Number__c        = 3,
            Highlight_Line__c     = 3,
            Snippet_Start_Line__c = null,
            Snippet_End_Line__c   = null
        );
        insert item;
        
        DeploymentAnalysisController.ItemDetailDTO d =
            DeploymentAnalysisController.getItemDetail(item.Id);
        
        System.assertEquals(null, d.snippet.startLine,
                            'snippet startLine should be null when Snippet_Start_Line__c is null');
        System.assertEquals(null, d.snippet.endLine,
                            'snippet endLine should be null when Snippet_End_Line__c is null');
    }
    
    @isTest
    static void getItemDetail_nullLineNumber_shouldReturnNull() {
        Deployment_Analysis_Run__c run = insertRun('Done', 0, 1, 0);
        
        Deployment_Analysis_Item__c item = new Deployment_Analysis_Item__c(
            Run__c            = run.Id,
            Trigger_Name__c   = 'T',
            Risk__c           = 'Medium',
            Matched_Rules__c  = 'TRIGGER_HANDLER_MISSING',
            Rule_Label__c     = 'Missing Trigger Handler',
            Message__c        = 'No handler found.',
            Line_Number__c    = null
        );
        insert item;
        
        DeploymentAnalysisController.ItemDetailDTO d =
            DeploymentAnalysisController.getItemDetail(item.Id);
        
        System.assertEquals(null, d.lineNumber,
                            'lineNumber should be null when Line_Number__c is null');
    }
    
    // ============================================================
    // getRunStatus — architectImpacts fallback from Summary__c (1 test)
    // SOURCE: Phase 7.0.2:
    //   if (String.isBlank(resp.architectImpacts))
    //       resp.architectImpacts =
    //           extractSingleLineValue(summary, 'Architect Impacts:');
    // The structured field (Architect_Impacts__c) is always blank because
    // it is NOT in the getRunStatus SOQL, so this fallback always fires.
    // extractSingleLineValue reads the first line after the key, trimmed.
    // ============================================================
    
    @isTest
    static void getRunStatus_architectImpacts_shouldParseFromSummary() {
        String summary =
            'Some content.\n' +
            'Architect Impacts: Runtime Governor Limit Risk, Integration Reliability Risk\n' +
            'More content.\n';
        
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c = 'Done', Summary__c = summary
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertEquals(
            'Runtime Governor Limit Risk, Integration Reliability Risk',
            resp.architectImpacts,
            'architectImpacts must be parsed from Summary__c via extractSingleLineValue'
        );
    }
    
    // ============================================================
    // getRunStatus — Phase 7 structured fields are null (1 test)
    // LABEL: current-implementation contract, not a product-success test.
    // These fields (Release_Decision__c, Policy_Profile__c, Gate_Version__c)
    // are not in the getRunStatus SOQL. safeGetString() calls sob.get() on
    // an unqueried field, catches the SObjectException, and returns null.
    // This test locks that behavior and will alert us if the SOQL is ever
    // updated to include those fields (which would be the correct fix).
    // ============================================================
    
    @isTest
    static void getRunStatus_phase7StructuredFields_shouldMapFromRecord() {
        // Fields now exist and are in the SOQL — they map directly.
        // This test replaces the previous null-contract test which documented
        // the broken state where these fields were not queried.
        Deployment_Analysis_Run__c run = new Deployment_Analysis_Run__c(
            Status__c                 = 'Done',
            Release_Decision__c       = 'BLOCKED',
            Policy_Profile__c         = 'Standard',
            Gate_Version__c           = '7.0.1',
            Release_Recommendation__c = 'NOT RECOMMENDED',
            Architect_Impacts__c      = 'Bulk/Limit Risk, Transaction Safety Risk',
            Release_Rationale__c      = 'SOQL inside loops can exceed governor limits under bulk load.'
        );
        insert run;
        
        DeploymentAnalysisController.RunStatusResponse resp =
            DeploymentAnalysisController.getRunStatus(run.Id);
        
        System.assertEquals('BLOCKED', resp.releaseDecision,
                            'releaseDecision should map directly from Release_Decision__c');
        System.assertEquals('Standard', resp.policyProfile,
                            'policyProfile should map directly from Policy_Profile__c');
        System.assertEquals('7.0.1', resp.gateVersion,
                            'gateVersion should map directly from Gate_Version__c');
        System.assertEquals('NOT RECOMMENDED', resp.releaseRecommendation,
                            'releaseRecommendation should map directly from Release_Recommendation__c');
        System.assertEquals('Bulk/Limit Risk, Transaction Safety Risk', resp.architectImpacts,
                            'architectImpacts should map directly from Architect_Impacts__c');
        System.assertEquals(
            'SOQL inside loops can exceed governor limits under bulk load.',
            resp.releaseRationale,
            'releaseRationale should map directly from Release_Rationale__c');
    }
    
}
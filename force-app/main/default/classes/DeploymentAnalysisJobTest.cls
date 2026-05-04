@isTest
private class DeploymentAnalysisJobTest {
  // ============================================================
  // MOCK STRATEGY
  //
  // DeploymentAnalysisJob makes HTTP callouts via ToolingApiClient
  // to the SF_TOOLING Named Credential. We intercept all callouts
  // with HttpCalloutMock implementations.
  //
  // We set TableEnumOrId to a plain API name (e.g. 'Account') so
  // resolveObjectApiName() returns it directly without a second
  // EntityDefinition callout.
  //
  // CMDT records (Trigger_Risk_Rule__mdt) are queried via regular
  // SOQL and are always available in test context — no mock needed.
  //
  // TRIGGER BODY RULES:
  // - Loop detection uses (?m)^\s*(for|while)\b — requires real \n
  //   line breaks, not single-line bodies.
  // - TRIGGER_HANDLER_MISSING is suppressed by any 'Handler.' match.
  // - NO_EVENT_GUARD is suppressed by any 'Trigger.is' reference.
  // - RECURSION_RISK requires DML — clean bodies produce no finding.
  // ============================================================

  // ============================================================
  // Mock: returns one trigger record with configurable name/body
  // ============================================================
  private class SingleTriggerMock implements HttpCalloutMock {
    private String triggerName;
    private String triggerBody;

    public SingleTriggerMock(String triggerName, String triggerBody) {
      this.triggerName = triggerName;
      this.triggerBody = triggerBody;
    }

    public HttpResponse respond(HttpRequest req) {
      Map<String, Object> record = new Map<String, Object>{
        'Id' => '01q000000000001AAA',
        'Name' => triggerName,
        'Body' => triggerBody,
        'TableEnumOrId' => 'Account'
      };
      Map<String, Object> resp = new Map<String, Object>{
        'records' => new List<Object>{ record }
      };
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(JSON.serialize(resp));
      res.setHeader('Content-Type', 'application/json');
      return res;
    }
  }

  // ============================================================
  // Mock: configurable response for graceful-path scenarios.
  // Handles multiple calls (fetchByNames + fallback fetchByName).
  //
  // Usage:
  //   new EmptyRecordsMock(triggerName, '')   → trigger found, body blank
  //                                             ti.body is blank → skipped
  //   new EmptyRecordsMock(null, null)        → empty records list returned
  //                                             ti = null → skipped
  // In both cases triggersAnalyzed stays 0, Total_Triggers__c = 1.
  // ============================================================
  private class EmptyRecordsMock implements HttpCalloutMock {
    private String triggerName;
    private String triggerBody;

    public EmptyRecordsMock(String triggerName, String triggerBody) {
      this.triggerName = triggerName;
      this.triggerBody = triggerBody;
    }

    public HttpResponse respond(HttpRequest req) {
      List<Object> records = new List<Object>();

      // If name is provided, return the record (body may be empty/null)
      if (!String.isBlank(triggerName)) {
        Map<String, Object> record = new Map<String, Object>{
          'Id' => '01q000000000001AAA',
          'Name' => triggerName,
          'Body' => (triggerBody == null ? '' : triggerBody),
          'TableEnumOrId' => 'Account'
        };
        records.add(record);
      }

      Map<String, Object> resp = new Map<String, Object>{
        'records' => records
      };
      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setBody(JSON.serialize(resp));
      res.setHeader('Content-Type', 'application/json');
      return res;
    }
  }

  // ============================================================
  // Query helpers
  // ============================================================

  private static Deployment_Analysis_Run__c getDAR(Id runId) {
    return [
      SELECT
        Status__c,
        High_Count__c,
        Medium_Count__c,
        Low_Count__c,
        Overall_Risk__c,
        Summary__c,
        Error_Message__c,
        Total_Triggers__c,
        Processed_Triggers__c
      FROM Deployment_Analysis_Run__c
      WHERE Id = :runId
    ];
  }

  private static List<Deployment_Analysis_Item__c> getItems(Id runId) {
    return [
      SELECT
        Matched_Rules__c,
        Risk__c,
        Trigger_Name__c,
        Line_Number__c,
        Category__c
      FROM Deployment_Analysis_Item__c
      WHERE Run__c = :runId
      ORDER BY Severity_Sort__c DESC NULLS LAST
    ];
  }

  // ============================================================
  // Scenario 1: BLOCKED
  // Trigger body: SOQL_IN_LOOP (for-each with bracket SOQL inside)
  // Expected: High_Count >= 1, Summary contains BLOCKED,
  //           DAI has SOQL_IN_LOOP High, no BULK_CONFIDENCE_SCORE
  // ============================================================

  @isTest
  static void job_blocked_soqlInLoop_darFieldsAndItemsAreCorrect() {
    // SOURCE: Loop detection uses (?m)^\s*(for|while)\b — requires \n line breaks.
    // SOQL_IN_LOOP is ENGINE mode, High severity.
    String triggerName = 'TRA_Test_Blocked';
    String triggerBody =
      'trigger TRA_Test_Blocked on Account (before insert) {\n' +
      '    for (Account a : Trigger.new) {\n' +
      '        List<Contact> cs = [SELECT Id FROM Contact LIMIT 1];\n' +
      '    }\n' +
      '}';

    Test.setMock(
      HttpCalloutMock.class,
      new SingleTriggerMock(triggerName, triggerBody)
    );

    Id runId;
    Test.startTest();
    runId = DeploymentAnalysisService.startRunForTriggers(
      'Test-BLOCKED',
      new List<String>{ triggerName }
    );
    Test.stopTest();

    // --- DAR field assertions ---
    Deployment_Analysis_Run__c dar = getDAR(runId);
    System.assertEquals(
      'Done',
      dar.Status__c,
      'Job must complete with Done status'
    );
    System.assert(
      dar.High_Count__c >= 1,
      'BLOCKED scenario must have at least 1 High finding'
    );
    System.assertEquals(
      'High',
      dar.Overall_Risk__c,
      'Overall risk must be High when High findings exist'
    );
    System.assertNotEquals(
      null,
      dar.Summary__c,
      'Summary__c must be populated after job completes'
    );
    System.assert(
      dar.Summary__c.contains('RELEASE GATE'),
      'Summary__c must contain the RELEASE GATE block'
    );
    System.assert(
      dar.Summary__c.contains('Release Decision: BLOCKED'),
      'Summary__c must contain Release Decision: BLOCKED'
    );

    // --- DAI item assertions ---
    List<Deployment_Analysis_Item__c> items = getItems(runId);

    Boolean hasSoqlInLoop = false;
    Boolean hasBulkScore = false;
    String soqlSeverity = null;

    for (Deployment_Analysis_Item__c it : items) {
      if (it.Matched_Rules__c == 'SOQL_IN_LOOP') {
        hasSoqlInLoop = true;
        soqlSeverity = it.Risk__c;
      }
      if (it.Matched_Rules__c == 'BULK_CONFIDENCE_SCORE') {
        hasBulkScore = true;
      }
    }

    System.assert(
      hasSoqlInLoop,
      'SOQL_IN_LOOP finding must be present in DAI records'
    );
    System.assertEquals(
      'High',
      soqlSeverity,
      'SOQL_IN_LOOP DAI item must have High severity'
    );
    System.assert(
      !hasBulkScore,
      'BULK_CONFIDENCE_SCORE must be filtered and never appear in DAI'
    );
  }

  // ============================================================
  // Scenario 2: APPROVED_WITH_CONDITIONS
  // Trigger body: EMAIL_IN_TRIGGER (Messaging.sendEmail call)
  // Expected: High_Count = 0, Medium_Count >= 1, Summary contains
  //           APPROVED_WITH_CONDITIONS, DAI has EMAIL_IN_TRIGGER Medium
  // ============================================================

  @isTest
  static void job_conditions_emailInTrigger_darFieldsAndItemsAreCorrect() {
    // SOURCE: EMAIL_IN_TRIGGER is ENGINE mode, Medium severity.
    // detectEmailInTrigger finds Messaging.sendEmail after masking.
    String triggerName = 'TRA_Test_Conditions';
    String triggerBody =
      'trigger TRA_Test_Conditions on Account (after insert) {\n' +
      '    Messaging.sendEmail(new List<Messaging.SingleEmailMessage>());\n' +
      '}';

    Test.setMock(
      HttpCalloutMock.class,
      new SingleTriggerMock(triggerName, triggerBody)
    );

    Id runId;
    Test.startTest();
    runId = DeploymentAnalysisService.startRunForTriggers(
      'Test-CONDITIONS',
      new List<String>{ triggerName }
    );
    Test.stopTest();

    // --- DAR field assertions ---
    Deployment_Analysis_Run__c dar = getDAR(runId);
    System.assertEquals(
      'Done',
      dar.Status__c,
      'Job must complete with Done status'
    );
    System.assertEquals(
      0,
      Integer.valueOf(String.valueOf(dar.High_Count__c)),
      'CONDITIONS scenario must have 0 High findings'
    );
    System.assert(
      dar.Medium_Count__c >= 1,
      'CONDITIONS scenario must have at least 1 Medium finding'
    );
    System.assertEquals(
      'Medium',
      dar.Overall_Risk__c,
      'Overall risk must be Medium when no High findings and Medium exist'
    );
    System.assert(
      dar.Summary__c.contains('APPROVED_WITH_CONDITIONS'),
      'Summary__c must contain APPROVED_WITH_CONDITIONS'
    );

    // --- DAI item assertions ---
    List<Deployment_Analysis_Item__c> items = getItems(runId);

    Boolean hasEmail = false;
    Boolean hasBulkScore = false;
    String emailSeverity = null;

    for (Deployment_Analysis_Item__c it : items) {
      if (it.Matched_Rules__c == 'EMAIL_IN_TRIGGER') {
        hasEmail = true;
        emailSeverity = it.Risk__c;
      }
      if (it.Matched_Rules__c == 'BULK_CONFIDENCE_SCORE') {
        hasBulkScore = true;
      }
    }

    System.assert(
      hasEmail,
      'EMAIL_IN_TRIGGER finding must be present in DAI records'
    );
    System.assertEquals(
      'Medium',
      emailSeverity,
      'EMAIL_IN_TRIGGER DAI item must have Medium severity'
    );
    System.assert(
      !hasBulkScore,
      'BULK_CONFIDENCE_SCORE must be filtered and never appear in DAI'
    );
  }

  // ============================================================
  // Scenario 3: APPROVED
  // Trigger body: clean — handler call + Trigger.is reference.
  // Expected: all counts 0, Summary contains APPROVED (not
  //           APPROVED_WITH_CONDITIONS), zero DAI records.
  //
  // BODY DESIGN:
  //   - Contains 'Handler.' → suppresses TRIGGER_HANDLER_MISSING
  //   - Contains 'Trigger.isInsert' → suppresses NO_EVENT_GUARD
  //   - No DML → suppresses RECURSION_RISK, DML_IN_BEFORE_TRIGGER
  //   - No SOQL, no callout, no loop → all other rules silent
  // ============================================================

  @isTest
  static void job_approved_cleanTrigger_darFieldsAndZeroItems() {
    String triggerName = 'TRA_Test_Approved';
    String triggerBody =
      'trigger TRA_Test_Approved on Account (before insert, before update) {\n' +
      '    SomeHandler.run(Trigger.new, Trigger.oldMap, Trigger.isInsert, Trigger.isUpdate);\n' +
      '}';

    Test.setMock(
      HttpCalloutMock.class,
      new SingleTriggerMock(triggerName, triggerBody)
    );

    Id runId;
    Test.startTest();
    runId = DeploymentAnalysisService.startRunForTriggers(
      'Test-APPROVED',
      new List<String>{ triggerName }
    );
    Test.stopTest();

    // --- DAR field assertions ---
    Deployment_Analysis_Run__c dar = getDAR(runId);
    System.assertEquals(
      'Done',
      dar.Status__c,
      'Job must complete with Done status'
    );
    System.assertEquals(
      0,
      Integer.valueOf(String.valueOf(dar.High_Count__c)),
      'APPROVED scenario must have 0 High findings'
    );
    System.assertEquals(
      0,
      Integer.valueOf(String.valueOf(dar.Medium_Count__c)),
      'APPROVED scenario must have 0 Medium findings'
    );
    System.assertEquals(
      0,
      Integer.valueOf(String.valueOf(dar.Low_Count__c)),
      'APPROVED scenario must have 0 Low findings'
    );
    System.assertEquals(
      'Low',
      dar.Overall_Risk__c,
      'Overall risk must be Low when no High or Medium findings'
    );
    System.assert(
      dar.Summary__c.contains('Release Decision: APPROVED'),
      'Summary__c must contain Release Decision: APPROVED'
    );
    System.assert(
      !dar.Summary__c.contains('APPROVED_WITH_CONDITIONS'),
      'Summary__c must NOT contain APPROVED_WITH_CONDITIONS for a clean trigger'
    );

    // --- DAI item assertions ---
    List<Deployment_Analysis_Item__c> items = getItems(runId);
    System.assertEquals(
      0,
      items.size(),
      'Clean trigger must produce zero DAI records (BULK_CONFIDENCE_SCORE is filtered)'
    );
  }

  // ============================================================
  // Scenario 4: Empty trigger body
  // SOURCE: if (ti == null || String.isBlank(ti.body)) continue;
  // The trigger is skipped entirely — job completes Done, no items.
  // ============================================================

  @isTest
  static void job_emptyTriggerBody_completesWithNoItems() {
    String triggerName = 'TRA_Test_EmptyBody';

    // EmptyRecordsMock returns the trigger record but with empty body
    Test.setMock(HttpCalloutMock.class, new EmptyRecordsMock(triggerName, ''));

    Id runId;
    Test.startTest();
    runId = DeploymentAnalysisService.startRunForTriggers(
      'Test-EMPTY',
      new List<String>{ triggerName }
    );
    Test.stopTest();

    Deployment_Analysis_Run__c dar = getDAR(runId);
    System.assertEquals(
      'Done',
      dar.Status__c,
      'Job must complete Done even when trigger body is empty'
    );
    // SOURCE: totalSelected = namesToAnalyze.size() = 1
    //         triggersAnalyzed stays 0 because String.isBlank(ti.body)
    //         causes a continue before triggersAnalyzed++
    System.assertEquals(
      1,
      Integer.valueOf(String.valueOf(dar.Total_Triggers__c)),
      'Total_Triggers__c must be 1 — trigger was selected even though body was blank'
    );
    System.assertEquals(
      0,
      Integer.valueOf(String.valueOf(dar.Processed_Triggers__c)),
      'Processed_Triggers__c must be 0 — blank body skips before triggersAnalyzed++'
    );

    List<Deployment_Analysis_Item__c> items = getItems(runId);
    System.assertEquals(
      0,
      items.size(),
      'Empty trigger body must produce zero DAI records'
    );
  }

  // ============================================================
  // Scenario 5: Trigger not found in org
  // SOURCE: EmptyRecordsMock returns empty records for both
  //   fetchByNames and the fallback fetchByName call.
  //   ti = null → continue → job completes Done gracefully.
  // ============================================================

  @isTest
  static void job_triggerNotFound_completesGracefully() {
    // Mock returns empty records for all callout calls
    Test.setMock(HttpCalloutMock.class, new EmptyRecordsMock(null, null));

    Id runId;
    Test.startTest();
    runId = DeploymentAnalysisService.startRunForTriggers(
      'Test-NOTFOUND',
      new List<String>{ 'NonExistentTrigger' }
    );
    Test.stopTest();

    Deployment_Analysis_Run__c dar = getDAR(runId);
    System.assertEquals(
      'Done',
      dar.Status__c,
      'Job must complete Done when requested trigger does not exist in org'
    );
    // SOURCE: totalSelected = 1 (one name was requested)
    //         triggersAnalyzed stays 0 because ti = null
    //         causes a continue before triggersAnalyzed++
    System.assertEquals(
      1,
      Integer.valueOf(String.valueOf(dar.Total_Triggers__c)),
      'Total_Triggers__c must be 1 — trigger name was in the request list'
    );
    System.assertEquals(
      0,
      Integer.valueOf(String.valueOf(dar.Processed_Triggers__c)),
      'Processed_Triggers__c must be 0 — null ti skips before triggersAnalyzed++'
    );
    System.assertEquals(
      0,
      Integer.valueOf(String.valueOf(dar.High_Count__c)),
      'High count must be 0 when no trigger was found'
    );

    List<Deployment_Analysis_Item__c> items = getItems(runId);
    System.assertEquals(
      0,
      items.size(),
      'No DAI records must be created when trigger is not found'
    );
  }

  // ============================================================
  // Scenario 6: Trigger counts on DAR
  // SOURCE: runRec.Total_Triggers__c = totalSelected (size of
  //   namesToAnalyze list passed to job).
  //   runRec.Processed_Triggers__c = triggersAnalyzed (incremented
  //   after null/blank body check, before findings check).
  // ============================================================

  @isTest
  static void job_triggerCounts_setCorrectlyOnDAR() {
    String triggerName = 'TRA_Test_Count';
    // Clean body: handler + Trigger.is → no findings, body is not blank
    // triggersAnalyzed is incremented before the findings isEmpty check
    String triggerBody =
      'trigger TRA_Test_Count on Account (before insert, before update) {\n' +
      '    SomeHandler.run(Trigger.isInsert, Trigger.isUpdate);\n' +
      '}';

    Test.setMock(
      HttpCalloutMock.class,
      new SingleTriggerMock(triggerName, triggerBody)
    );

    Id runId;
    Test.startTest();
    runId = DeploymentAnalysisService.startRunForTriggers(
      'Test-COUNTS',
      new List<String>{ triggerName }
    );
    Test.stopTest();

    Deployment_Analysis_Run__c dar = getDAR(runId);
    System.assertEquals(
      1,
      Integer.valueOf(String.valueOf(dar.Total_Triggers__c)),
      'Total_Triggers__c must be 1 when exactly one trigger name was requested'
    );
    System.assertEquals(
      1,
      Integer.valueOf(String.valueOf(dar.Processed_Triggers__c)),
      'Processed_Triggers__c must be 1 when trigger body was found and analyzed'
    );
  }

  // ============================================================
  // Scenario 7: Null triggerNames → fetchAllTriggerNames() path
  //
  // SOURCE — DeploymentAnalysisJob.execute():
  //   List<String> namesToAnalyze =
  //     (triggerNames == null || triggerNames.isEmpty())
  //       ? fetchAllTriggerNames()
  //       : triggerNames;
  //
  // SOURCE — DeploymentAnalysisService.startRun(label):
  //   System.enqueueJob(new DeploymentAnalysisJob(runRec.Id, null));
  //
  // Scenarios 1–6 all call startRunForTriggers(label, names) which
  // passes a non-empty list — the fetchAllTriggerNames() branch
  // never executes there. This scenario calls startRun(label) so the
  // job is enqueued with null triggerNames, exercising the all-trigger
  // path.
  //
  // The same SingleTriggerMock satisfies both callouts:
  //   1) fetchAllTriggerNames() reads only 'Name' from each record.
  //   2) TriggerFetchService.fetchByNames() reads Id/Name/Body/TableEnumOrId.
  // SingleTriggerMock returns the full record for every callout, which
  // is sufficient because each caller only reads the fields it needs.
  // ============================================================
  @isTest
  static void job_nullTriggerNames_fetchesAllTriggerNamesAndProcessesTrigger() {
    String triggerName = 'TRA_Test_FetchAll';
    // Clean body: handler + Trigger.is → no findings.
    // Keeps assertions focused on the fetch-all path, not on detection.
    String triggerBody =
      'trigger TRA_Test_FetchAll on Account (before insert, before update) {\n' +
      '    SomeHandler.run(Trigger.isInsert, Trigger.isUpdate);\n' +
      '}';

    Test.setMock(
      HttpCalloutMock.class,
      new SingleTriggerMock(triggerName, triggerBody)
    );

    Id runId;
    Test.startTest();
    // startRun(label) — NOT startRunForTriggers — enqueues the job
    // with null triggerNames, forcing fetchAllTriggerNames() to fire.
    runId = DeploymentAnalysisService.startRun('Test-FETCH-ALL');
    Test.stopTest();

    Deployment_Analysis_Run__c dar = getDAR(runId);
    System.assertEquals(
      'Done',
      dar.Status__c,
      'Job must complete Done when fetchAllTriggerNames returns one trigger'
    );
    System.assertEquals(
      null,
      dar.Error_Message__c,
      'Error_Message__c must be null on a successful fetch-all run'
    );
    // SOURCE: totalSelected = namesToAnalyze.size() AFTER fetchAllTriggerNames()
    //   returned its list. A value of 1 proves the branch executed and
    //   parsed the mock response — distinguishing this path from the
    //   selected-list path covered by Scenarios 1–6.
    System.assertEquals(
      1,
      Integer.valueOf(String.valueOf(dar.Total_Triggers__c)),
      'Total_Triggers__c must be 1 — proves fetchAllTriggerNames returned 1 name'
    );
    System.assertEquals(
      1,
      Integer.valueOf(String.valueOf(dar.Processed_Triggers__c)),
      'Processed_Triggers__c must be 1 — trigger body was found and analyzed'
    );
    System.assert(
      dar.Summary__c.contains('RELEASE GATE'),
      'Summary__c must contain RELEASE GATE — proves full happy path completed'
    );
  }

  // ============================================================
  // Mock that returns a non-2xx Tooling API response.
  //
  // SOURCE — ToolingApiClient.queryUntyped:
  //   if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
  //       throw new CalloutException(
  //           'Tooling API call failed: ' + res.getStatus() + ' | ' + res.getBody()
  //       );
  //   }
  //
  // Forces TriggerFetchService.fetchByNames to throw, which propagates
  // into DeploymentAnalysisJob.execute()'s catch block.
  // ============================================================
  private class ToolingErrorMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(500);
      res.setStatus('Internal Server Error');
      res.setBody('mock tooling failure');
      return res;
    }
  }

  // ============================================================
  // Scenario 8: catch-block path — Tooling failure surfaces as Failed
  //
  // SOURCE — DeploymentAnalysisJob.execute() catch (Exception e):
  //   runRec.Status__c = 'Failed';
  //   runRec.Total_Triggers__c = totalSelected;
  //   runRec.Processed_Triggers__c = triggersAnalyzed;
  //   runRec.High_Count__c = highCount;
  //   runRec.Medium_Count__c = mediumCount;
  //   runRec.Low_Count__c = lowCount;
  //   runRec.Error_Message__c = e.getMessage();
  //   runRec.Last_Updated__c = System.now();
  //   update runRec;
  //   throw e;
  //
  // Why this matters: failed runs must surface Status__c='Failed'
  // and Error_Message__c so the LWC can display the error to the
  // user. Scenarios 1–7 only exercise the happy path; this is the
  // first test that drives the catch block.
  //
  // How we trigger the exception: ToolingErrorMock returns 500, which
  // causes ToolingApiClient.queryUntyped to throw CalloutException.
  // This propagates out of TriggerFetchService.fetchByNames into the
  // job's try block.
  //
  // Apex queueable test behavior: when execute() re-throws, the
  // exception surfaces through Test.stopTest(). We wrap it so the
  // test method itself does not fail on the propagation.
  // ============================================================
  @isTest
  static void job_calloutFailure_setsStatusFailedAndErrorMessage() {
    Test.setMock(HttpCalloutMock.class, new ToolingErrorMock());

    Id runId;
    Boolean threw = false;
    String thrownMsg = null;

    Test.startTest();
    runId = DeploymentAnalysisService.startRunForTriggers(
      'Test-FAIL',
      new List<String>{ 'TRA_Test_Failure' }
    );
    try {
      Test.stopTest();
    } catch (Exception ex) {
      threw = true;
      thrownMsg = ex.getMessage();
    }

    // Catch block re-throws — proves the catch path executed end-to-end.
    System.assert(
      threw,
      'Job must re-throw the underlying CalloutException after the catch block runs'
    );
    System.assert(
      thrownMsg != null && thrownMsg.contains('Tooling API call failed'),
      'Thrown exception must carry the Tooling API failure message; actual: ' +
      thrownMsg
    );

    // DAR state — what the LWC actually sees.
    Deployment_Analysis_Run__c dar = getDAR(runId);
    System.assertEquals(
      'Failed',
      dar.Status__c,
      'Status__c must be Failed when the catch block runs — the LWC reads this to show the error'
    );
    System.assertNotEquals(
      null,
      dar.Error_Message__c,
      'Error_Message__c must be populated so the LWC can display the cause'
    );
    System.assert(
      dar.Error_Message__c.contains('Tooling API call failed'),
      'Error_Message__c must contain the Tooling failure message; actual: ' +
      dar.Error_Message__c
    );
    // SOURCE: totalSelected is set before the callout failure in the try block.
    System.assertEquals(
      1,
      Integer.valueOf(String.valueOf(dar.Total_Triggers__c)),
      'Total_Triggers__c must reflect the size of the requested name list'
    );
    // SOURCE: triggersAnalyzed never increments — failure occurs during fetchByNames.
    System.assertEquals(
      0,
      Integer.valueOf(String.valueOf(dar.Processed_Triggers__c)),
      'Processed_Triggers__c must be 0 — failure occurred before any trigger was analyzed'
    );
  }
}

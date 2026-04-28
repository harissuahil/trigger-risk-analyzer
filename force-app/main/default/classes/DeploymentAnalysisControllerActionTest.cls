/**
 * DeploymentAnalysisControllerActionTest
 *
 * Focused coverage for the two ACTION methods on DeploymentAnalysisController:
 *   - getTriggerNames()  → Tooling API callout via ToolingApiClient
 *   - startRun(...)      → label normalization + delegation to
 *                          DeploymentAnalysisService (creates DAR, enqueues job)
 *
 * Why this lives in a separate class from DeploymentAnalysisControllerTest:
 *   The existing class covers DTO/getter mapping (getRunStatus, getRunItems,
 *   getItemDetail) which require neither callouts nor DML. These two methods
 *   are different in shape — they need HttpCalloutMock and they create real
 *   Deployment_Analysis_Run__c records. Keeping them apart keeps both classes
 *   focused and readable.
 *
 * IMPORTANT — startRun and the auto-flushed queueable:
 *   startRun() inserts the DAR synchronously and THEN enqueues
 *   DeploymentAnalysisJob. Even though the startRun_* tests do not call
 *   Test.stopTest(), Salesforce automatically flushes pending queueables
 *   at the end of @IsTest methods. The queueable then makes Tooling API
 *   callouts via ToolingApiClient — which requires an HttpCalloutMock,
 *   otherwise the runtime throws "Methods defined as TestMethod do not
 *   support Web service callouts".
 *
 *   Each startRun_* test therefore sets EmptyToolingMock at the start.
 *   This satisfies the queueable's callout requirement without changing
 *   what the tests assert: they still only verify the synchronously-
 *   inserted DAR fields BEFORE the queueable runs. The queueable's
 *   behavior is fully covered by DeploymentAnalysisJobTest.
 *
 * BRANCH COVERAGE NOTE:
 *   startRun() has two delegation branches based on triggerNames being
 *   null/empty vs non-empty. From the synchronously-inserted DAR alone,
 *   we cannot prove which branch was taken — both branches insert a DAR
 *   with the same fields (Status__c='Running', Release_Label__c, Started_At__c).
 *   The selected-trigger count is set later by DeploymentAnalysisJob, not by
 *   the service. The startRun_emptyTriggerList_* and startRun_selectedTriggerList_*
 *   tests therefore prove that each input shape produces a successful run
 *   creation; they cannot prove branch selection. Branch behavior is implicitly
 *   covered by DeploymentAnalysisJobTest, which tests trigger counts via
 *   startRunForTriggers().
 *
 * @group Tests
 * @author TRA Project
 */
@IsTest(SeeAllData=false)
private class DeploymentAnalysisControllerActionTest {
  // ─────────────────────────────────────────────────────────────────────
  // Mock for getTriggerNames Tooling API callout
  //
  // Returns a fixed JSON response shaped like the Tooling API's
  // queryUntyped output: { "records": [{ "Name": "..." }, ...] }
  //
  // Verified shape from ToolingApiClient.queryUntyped:
  //   return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
  // ─────────────────────────────────────────────────────────────────────
  private class TriggerNamesMock implements HttpCalloutMock {
    private List<String> names;

    public TriggerNamesMock(List<String> names) {
      this.names = names;
    }

    public HttpResponse respond(HttpRequest req) {
      List<Map<String, Object>> records = new List<Map<String, Object>>();
      for (String n : names) {
        records.add(new Map<String, Object>{ 'Name' => n });
      }

      Map<String, Object> body = new Map<String, Object>{
        'size' => names.size(),
        'totalSize' => names.size(),
        'done' => true,
        'records' => records
      };

      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setHeader('Content-Type', 'application/json');
      res.setBody(JSON.serialize(body));
      return res;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Mock that returns a Tooling API response with NO "records" key.
  //
  // Verified from DeploymentAnalysisController.getTriggerNames:
  //   List<Object> recs = (List<Object>) r.get('records');  // → null
  //   if (recs != null) { ... }                              // → branch skipped
  //   return out;                                            // → empty list
  //
  // This mock proves the defensive null-check actually fires when the
  // Tooling API returns an unexpected shape (no records key at all).
  // ─────────────────────────────────────────────────────────────────────
  private class NullRecordsMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      Map<String, Object> body = new Map<String, Object>{
        'done' => true
        // intentionally NO 'records' key
      };

      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setHeader('Content-Type', 'application/json');
      res.setBody(JSON.serialize(body));
      return res;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Mock that returns a non-2xx Tooling API response.
  //
  // Verified from ToolingApiClient.queryUntyped:
  //   if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
  //       throw new CalloutException(
  //           'Tooling API call failed: ' + res.getStatus() + ' | ' + res.getBody()
  //       );
  //   }
  //
  // The controller does NOT catch this exception, so it propagates up
  // through getTriggerNames() to the caller.
  // ─────────────────────────────────────────────────────────────────────
  private class ToolingErrorMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(500);
      res.setStatus('Internal Server Error');
      res.setBody('mock tooling failure');
      return res;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Mock that returns an empty Tooling API response.
  //
  // Used by startRun_* tests to satisfy the queueable's callout requirement.
  //
  // WHY THIS IS NEEDED:
  //   startRun() inserts the DAR synchronously AND enqueues
  //   DeploymentAnalysisJob. Even though the startRun_* tests do not call
  //   Test.stopTest(), Salesforce automatically flushes pending queueables
  //   at the end of @IsTest methods. When DeploymentAnalysisJob.execute()
  //   runs, it makes Tooling API callouts via ToolingApiClient. Without a
  //   mock, the runtime throws:
  //     "Methods defined as TestMethod do not support Web service callouts"
  //
  //   This mock returns an empty records list. The job's TriggerFetchService
  //   sees no triggers, the analysis loop iterates zero times, the DAR is
  //   updated to Done with all-zero counts, and the job exits cleanly.
  //
  //   The mock satisfies the runtime requirement WITHOUT changing what the
  //   startRun_* tests actually assert: those tests still only check the
  //   synchronously-inserted DAR fields (Status__c='Running',
  //   Release_Label__c, Started_At__c) BEFORE the queueable runs. The
  //   queueable's behavior is fully covered by DeploymentAnalysisJobTest.
  // ─────────────────────────────────────────────────────────────────────
  private class EmptyToolingMock implements HttpCalloutMock {
    public HttpResponse respond(HttpRequest req) {
      Map<String, Object> body = new Map<String, Object>{
        'size' => 0,
        'totalSize' => 0,
        'done' => true,
        'records' => new List<Object>()
      };

      HttpResponse res = new HttpResponse();
      res.setStatusCode(200);
      res.setHeader('Content-Type', 'application/json');
      res.setBody(JSON.serialize(body));
      return res;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Test 1: getTriggerNames returns trigger names from Tooling API
  //
  // Verifies:
  //   - The Tooling API mock response is parsed correctly
  //   - The returned list contains exactly the names from the response
  //   - Order is preserved (the Tooling SOQL is "ORDER BY Name" but the
  //     controller doesn't re-sort, so list order matches mock order)
  // ─────────────────────────────────────────────────────────────────────
  @IsTest
  static void getTriggerNames_returnsNamesFromToolingApi() {
    Test.setMock(
      HttpCalloutMock.class,
      new TriggerNamesMock(
        new List<String>{
          'AccountTrigger',
          'ContactTrigger',
          'OpportunityTrigger'
        }
      )
    );

    Test.startTest();
    List<String> result = DeploymentAnalysisController.getTriggerNames();
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should return a non-null list');
    System.assertEquals(
      3,
      result.size(),
      'Should return all three trigger names'
    );
    System.assertEquals('AccountTrigger', result[0], 'First name should match');
    System.assertEquals(
      'ContactTrigger',
      result[1],
      'Second name should match'
    );
    System.assertEquals(
      'OpportunityTrigger',
      result[2],
      'Third name should match'
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Test 2: getTriggerNames handles empty Tooling API records list
  //
  // When the org has no triggers, the Tooling API returns
  // { records: [] } and the controller must return an empty list,
  // not throw or return null.
  //
  // Source path covered:
  //   recs != null (it's an empty list)
  //   → for loop iterates zero times
  //   → returns empty out list
  // ─────────────────────────────────────────────────────────────────────
  @IsTest
  static void getTriggerNames_emptyRecords_returnsEmptyList() {
    Test.setMock(
      HttpCalloutMock.class,
      new TriggerNamesMock(new List<String>())
    );

    Test.startTest();
    List<String> result = DeploymentAnalysisController.getTriggerNames();
    Test.stopTest();

    System.assertNotEquals(
      null,
      result,
      'Should return a non-null list even when empty'
    );
    System.assertEquals(0, result.size(), 'Should return an empty list');
  }

  // ─────────────────────────────────────────────────────────────────────
  // Test 3: getTriggerNames handles missing "records" key in Tooling response
  //
  // VERIFIED SOURCE — DeploymentAnalysisController.getTriggerNames:
  //   List<Object> recs = (List<Object>) r.get('records');
  //   List<String> out = new List<String>();
  //   if (recs != null) { ... iterate ... }
  //   return out;
  //
  // The defensive `if (recs != null)` guard exists. This test proves it
  // actually fires when the Tooling API returns a response with no
  // "records" key at all (returning out = empty list instead of NPE).
  // ─────────────────────────────────────────────────────────────────────
  @IsTest
  static void getTriggerNames_missingRecordsKey_returnsEmptyList() {
    Test.setMock(HttpCalloutMock.class, new NullRecordsMock());

    Test.startTest();
    List<String> result = DeploymentAnalysisController.getTriggerNames();
    Test.stopTest();

    System.assertNotEquals(
      null,
      result,
      'Should return a non-null list when records key is missing'
    );
    System.assertEquals(
      0,
      result.size(),
      'Should return empty list when records key is missing (defensive null-check)'
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Test 4: getTriggerNames propagates Tooling API callout failure
  //
  // VERIFIED SOURCE — ToolingApiClient.queryUntyped:
  //   if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
  //       throw new CalloutException(
  //           'Tooling API call failed: ' + res.getStatus() + ' | ' + res.getBody()
  //       );
  //   }
  //
  // VERIFIED SOURCE — DeploymentAnalysisController.getTriggerNames:
  //   has no try/catch around the queryUntyped call, so the
  //   CalloutException propagates to the caller (the LWC).
  //
  // This test locks that contract: a failing Tooling callout surfaces
  // to the UI as a CalloutException with a recognizable message, NOT
  // silently swallowed and returned as an empty list.
  // ─────────────────────────────────────────────────────────────────────
  @IsTest
  static void getTriggerNames_toolingError_propagatesCalloutException() {
    Test.setMock(HttpCalloutMock.class, new ToolingErrorMock());

    Boolean thrown = false;
    String caughtMessage;

    Test.startTest();
    try {
      DeploymentAnalysisController.getTriggerNames();
    } catch (CalloutException ex) {
      thrown = true;
      caughtMessage = ex.getMessage();
    }
    Test.stopTest();

    System.assertEquals(
      true,
      thrown,
      'Tooling API failure should throw CalloutException'
    );
    System.assert(
      caughtMessage != null &&
      caughtMessage.contains('Tooling API call failed'),
      'CalloutException message should match the ToolingApiClient prefix; ' +
        'actual message: ' +
        caughtMessage
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Test 5: startRun normalizes blank label and creates DAR with UI-RUN
  //
  // VERIFIED SOURCE — DeploymentAnalysisController.startRun:
  //   if (String.isBlank(releaseLabel)) releaseLabel = 'UI-RUN';
  //
  // VERIFIED SOURCE — DeploymentAnalysisService.startRun:
  //   runRec.Status__c = 'Running';
  //   runRec.Release_Label__c = releaseLabel;
  //   runRec.Started_At__c = System.now();
  //   insert runRec;
  //   System.enqueueJob(new DeploymentAnalysisJob(runRec.Id, null));
  //   return runRec.Id;
  //
  // Also exercises the all-trigger path (triggerNames == null), which
  // delegates to DeploymentAnalysisService.startRun(releaseLabel).
  //
  // Does NOT call Test.stopTest() — see class header. We assert on the
  // synchronously-inserted DAR record before the queueable runs.
  // ─────────────────────────────────────────────────────────────────────
  @IsTest
  static void startRun_blankLabelAndNullTriggers_createsRunWithUiRunLabel() {
    // Required: queueable will run at method end and needs a callout mock.
    // See EmptyToolingMock comment for full explanation.
    Test.setMock(HttpCalloutMock.class, new EmptyToolingMock());

    Id runId = DeploymentAnalysisController.startRun('', null);

    System.assertNotEquals(null, runId, 'startRun should return a non-null Id');

    Deployment_Analysis_Run__c dar = [
      SELECT Id, Release_Label__c, Status__c, Started_At__c
      FROM Deployment_Analysis_Run__c
      WHERE Id = :runId
    ];

    System.assertEquals(
      'UI-RUN',
      dar.Release_Label__c,
      'Blank label should be normalized to UI-RUN'
    );
    System.assertEquals(
      'Running',
      dar.Status__c,
      'Newly-created DAR should be in Running status'
    );
    System.assertNotEquals(
      null,
      dar.Started_At__c,
      'Started_At__c should be populated synchronously'
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Test 6: startRun normalizes whitespace-only label to UI-RUN
  //
  // VERIFIED SOURCE — DeploymentAnalysisController.startRun:
  //   if (String.isBlank(releaseLabel)) releaseLabel = 'UI-RUN';
  //
  // String.isBlank() returns true for null, empty, AND whitespace-only
  // strings ('   ', '\t', '\n', etc.). Test 5 covers empty string;
  // this test covers the whitespace case explicitly.
  //
  // Why it matters: if a future refactor swaps String.isBlank() for
  // String.isEmpty() (which only checks null/empty, NOT whitespace),
  // a whitespace label like '   ' would silently leak through and
  // become the Release_Label__c value. This test catches that.
  // ─────────────────────────────────────────────────────────────────────
  @IsTest
  static void startRun_whitespaceLabel_createsRunWithUiRunLabel() {
    Test.setMock(HttpCalloutMock.class, new EmptyToolingMock());

    Id runId = DeploymentAnalysisController.startRun('   ', null);

    System.assertNotEquals(null, runId, 'startRun should return a non-null Id');

    Deployment_Analysis_Run__c dar = [
      SELECT Id, Release_Label__c, Status__c
      FROM Deployment_Analysis_Run__c
      WHERE Id = :runId
    ];

    System.assertEquals(
      'UI-RUN',
      dar.Release_Label__c,
      'Whitespace-only label should be normalized to UI-RUN'
    );
    System.assertEquals(
      'Running',
      dar.Status__c,
      'Newly-created DAR should be in Running status'
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Test 7: startRun normalizes null label to UI-RUN
  //
  // VERIFIED SOURCE — DeploymentAnalysisController.startRun:
  //   if (String.isBlank(releaseLabel)) releaseLabel = 'UI-RUN';
  //
  // String.isBlank() returns true for null. Test 5 covers empty string,
  // Test 6 covers whitespace; this test completes the trio by covering
  // the null case explicitly. The releaseLabel parameter is a String
  // (not a primitive), so null is a realistic input from the LWC if
  // a future caller forgets to pass it.
  // ─────────────────────────────────────────────────────────────────────
  @IsTest
  static void startRun_nullLabel_createsRunWithUiRunLabel() {
    Test.setMock(HttpCalloutMock.class, new EmptyToolingMock());

    Id runId = DeploymentAnalysisController.startRun(null, null);

    System.assertNotEquals(null, runId, 'startRun should return a non-null Id');

    Deployment_Analysis_Run__c dar = [
      SELECT Id, Release_Label__c, Status__c, Started_At__c
      FROM Deployment_Analysis_Run__c
      WHERE Id = :runId
    ];

    System.assertEquals(
      'UI-RUN',
      dar.Release_Label__c,
      'Null label should be normalized to UI-RUN'
    );
    System.assertEquals(
      'Running',
      dar.Status__c,
      'Newly-created DAR should be in Running status'
    );
    System.assertNotEquals(
      null,
      dar.Started_At__c,
      'Started_At__c should be populated synchronously'
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Test 8: startRun with empty trigger list creates run with provided label
  //
  // VERIFIED SOURCE — DeploymentAnalysisController.startRun:
  //   if (triggerNames == null || triggerNames.isEmpty()) {
  //       return DeploymentAnalysisService.startRun(releaseLabel);
  //   }
  //
  // Empty list takes the all-trigger path. The provided label is preserved
  // because it's non-blank (no UI-RUN normalization).
  //
  // NOTE: This test cannot prove branch selection from the DAR alone
  // (see class header). It proves successful DAR creation with the
  // expected label and status when an empty list is passed.
  // ─────────────────────────────────────────────────────────────────────
  @IsTest
  static void startRun_emptyTriggerList_createsRunWithProvidedLabel() {
    Test.setMock(HttpCalloutMock.class, new EmptyToolingMock());

    Id runId = DeploymentAnalysisController.startRun(
      'NIGHTLY-FULL',
      new List<String>()
    );

    System.assertNotEquals(null, runId, 'startRun should return a non-null Id');

    Deployment_Analysis_Run__c dar = [
      SELECT Id, Release_Label__c, Status__c
      FROM Deployment_Analysis_Run__c
      WHERE Id = :runId
    ];

    System.assertEquals(
      'NIGHTLY-FULL',
      dar.Release_Label__c,
      'Provided label should be preserved'
    );
    System.assertEquals(
      'Running',
      dar.Status__c,
      'Newly-created DAR should be in Running status'
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Test 9: startRun with selected triggers creates run with provided label
  //
  // VERIFIED SOURCE — DeploymentAnalysisController.startRun:
  //   return DeploymentAnalysisService.startRunForTriggers(
  //       releaseLabel, triggerNames
  //   );
  //
  // Non-empty list takes the selected-trigger path.
  //
  // VERIFIED SOURCE — DeploymentAnalysisService.startRunForTriggers:
  //   The DAR is created with the SAME fields as startRun() — only
  //   Status__c, Release_Label__c, and Started_At__c. The trigger names
  //   are passed to the queueable, NOT stored on the DAR synchronously.
  //   Total_Triggers__c is set later by DeploymentAnalysisJob.
  //
  // NOTE: This test cannot prove branch selection from the DAR alone
  // (see class header). It proves successful DAR creation with the
  // expected label and status when a non-empty list is passed.
  // The selected-trigger behavior is verified end-to-end by
  // DeploymentAnalysisJobTest scenarios that pass selected triggers.
  // ─────────────────────────────────────────────────────────────────────
  @IsTest
  static void startRun_selectedTriggerList_createsRunWithProvidedLabel() {
    Test.setMock(HttpCalloutMock.class, new EmptyToolingMock());

    List<String> selected = new List<String>{
      'TRA_SoqlInLoop_Bad',
      'TRA_EmailInTrigger_Bad'
    };

    Id runId = DeploymentAnalysisController.startRun('SELECTED-RUN', selected);

    System.assertNotEquals(null, runId, 'startRun should return a non-null Id');

    Deployment_Analysis_Run__c dar = [
      SELECT Id, Release_Label__c, Status__c, Started_At__c
      FROM Deployment_Analysis_Run__c
      WHERE Id = :runId
    ];

    System.assertEquals(
      'SELECTED-RUN',
      dar.Release_Label__c,
      'Provided label should be preserved'
    );
    System.assertEquals(
      'Running',
      dar.Status__c,
      'Newly-created DAR should be in Running status'
    );
    System.assertNotEquals(
      null,
      dar.Started_At__c,
      'Started_At__c should be populated synchronously'
    );
  }
}

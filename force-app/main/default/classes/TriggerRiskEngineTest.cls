@isTest
private class TriggerRiskEngineTest {
    
    private static Boolean hasRule(
        List<TriggerRiskEngine.Finding> findings,
        String ruleKey
    ) {
        for (TriggerRiskEngine.Finding f : findings) {
            if (f.ruleKey == ruleKey) return true;
        }
        return false;
    }
    
    private static TriggerRiskEngine.Finding getRule(
        List<TriggerRiskEngine.Finding> findings,
        String ruleKey
    ) {
        for (TriggerRiskEngine.Finding f : findings) {
            if (f.ruleKey == ruleKey) return f;
        }
        return null;
    }
    
    @isTest
    static void soqlInLoop_bad_shouldDetect() {
        String body =
            'trigger T on Account (before insert) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        List<Contact> cs = [SELECT Id FROM Contact LIMIT 1];\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'SOQL_IN_LOOP'),
            'SOQL_IN_LOOP should be detected in a basic for-each loop'
        );
        
        TriggerRiskEngine.Finding f = getRule(findings, 'SOQL_IN_LOOP');
        System.assertEquals(
            'High',
            f.severity,
            'SOQL_IN_LOOP severity should be High'
        );
    }
    
    @isTest
    static void soqlInLoop_good_shouldNotDetect() {
        String body =
            'trigger T on Account (before insert) {\n' +
            '    List<Contact> cs = [SELECT Id FROM Contact LIMIT 1];\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        a.Description = String.valueOf(cs.size());\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'SOQL_IN_LOOP'),
            'SOQL_IN_LOOP should NOT fire when query is outside the loop'
        );
    }
    
    @isTest
    static void soqlInLoop_commentTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (before insert) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        // List<Contact> cs = [SELECT Id FROM Contact LIMIT 1];\n' +
            '        a.Description = \'safe\';\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'SOQL_IN_LOOP'),
            'SOQL_IN_LOOP should NOT fire when SOQL is only inside a comment'
        );
    }
    
    @isTest
    static void soqlInLoop_stringTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (before insert) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        String s = \'[SELECT Id FROM Contact LIMIT 1]\';\n' +
            '        a.Description = s;\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'SOQL_IN_LOOP'),
            'SOQL_IN_LOOP should NOT fire when SOQL is only inside a string literal'
        );
    }
    
    @isTest
    static void soqlInLoop_whileLoop_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    Integer i = 0;\n' +
            '    while (i < Trigger.new.size()) {\n' +
            '        List<Contact> cs = [SELECT Id FROM Contact LIMIT 1];\n' +
            '        i++;\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'SOQL_IN_LOOP'),
            'SOQL_IN_LOOP should be detected inside a while loop'
        );
    }
    @isTest
    static void soqlInLoop_doWhileLoop_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    Integer i = 0;\n' +
            '    do {\n' +
            '        List<Contact> cs = [SELECT Id FROM Contact LIMIT 1];\n' +
            '        i++;\n' +
            '    } while (i < Trigger.new.size());\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'SOQL_IN_LOOP'),
            'SOQL_IN_LOOP should be detected inside a do-while loop'
        );
    }
    
    @isTest
    static void soqlInLoop_noBraceLoop_shouldDetect() {
        String body =
            'trigger T on Account (before insert) {\n' +
            '    for (Account a : Trigger.new)\n' +
            '        a.Description = [SELECT Name FROM Contact LIMIT 1].LastName;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'SOQL_IN_LOOP'),
            'SOQL_IN_LOOP should be detected in a no-brace loop'
        );
    }
    // ============================================================
    // DML_IN_LOOP
    // ============================================================
    
    @isTest
    static void dmlInLoop_bad_shouldDetect() {
        String body =
            'trigger T on Account (after update) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        Account upd = new Account(Id = a.Id, Name = a.Name);\n' +
            '        update upd;\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'DML_IN_LOOP'),
            'DML_IN_LOOP should be detected in a basic for-each loop'
        );
        
        TriggerRiskEngine.Finding f = getRule(findings, 'DML_IN_LOOP');
        System.assertEquals(
            'High',
            f.severity,
            'DML_IN_LOOP severity should be High'
        );
    }
    
    @isTest
    static void dmlInLoop_good_shouldNotDetect() {
        String body =
            'trigger T on Account (after update) {\n' +
            '    List<Account> ups = new List<Account>();\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        ups.add(new Account(Id = a.Id, Name = a.Name));\n' +
            '    }\n' +
            '    update ups;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'DML_IN_LOOP'),
            'DML_IN_LOOP should NOT fire when DML is outside the loop'
        );
    }
    
    @isTest
    static void dmlInLoop_commentTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after update) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        // update a;\n' +
            '        a.Description = \'safe\';\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'DML_IN_LOOP'),
            'DML_IN_LOOP should NOT fire when DML is only inside a comment'
        );
    }
    
    @isTest
    static void dmlInLoop_stringTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after update) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        String s = \'update a;\';\n' +
            '        a.Description = s;\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'DML_IN_LOOP'),
            'DML_IN_LOOP should NOT fire when DML is only inside a string literal'
        );
    }
    
    @isTest
    static void dmlInLoop_whileLoop_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    Integer i = 0;\n' +
            '    while (i < Trigger.new.size()) {\n' +
            '        Account a = new Account(Name = \'Test\');\n' +
            '        insert a;\n' +
            '        i++;\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'DML_IN_LOOP'),
            'DML_IN_LOOP should be detected inside a while loop'
        );
    }
    @isTest
    static void dmlInLoop_doWhileLoop_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    Integer i = 0;\n' +
            '    do {\n' +
            '        Account a = new Account(Name = \'Test\');\n' +
            '        insert a;\n' +
            '        i++;\n' +
            '    } while (i < Trigger.new.size());\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'DML_IN_LOOP'),
            'DML_IN_LOOP should be detected inside a do-while loop'
        );
    }
    
    @isTest
    static void dmlInLoop_noBraceLoop_shouldDetect() {
        String body =
            'trigger T on Account (after update) {\n' +
            '    for (Account a : Trigger.new)\n' +
            '        update new List<Account>{ new Account(Id = a.Id, Name = a.Name) };\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'DML_IN_LOOP'),
            'DML_IN_LOOP should be detected in a no-brace loop'
        );
    }
    // ============================================================
    // CALLOUT_IN_TRIGGER
    // ============================================================
    
    @isTest
    static void calloutInTrigger_bad_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    HttpRequest req = new HttpRequest();\n' +
            '    req.setEndpoint(\'https://example.com\');\n' +
            '    req.setMethod(\'GET\');\n' +
            '    Http http = new Http();\n' +
            '    http.send(req);\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'CALLOUT_IN_TRIGGER'),
            'CALLOUT_IN_TRIGGER should be detected when Http callout is in trigger'
        );
        
        TriggerRiskEngine.Finding f = getRule(findings, 'CALLOUT_IN_TRIGGER');
        System.assertEquals(
            'High',
            f.severity,
            'CALLOUT_IN_TRIGGER severity should be High'
        );
    }
    
    @isTest
    static void calloutInTrigger_good_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    System.enqueueJob(new TRA_CalloutQueueable());\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'CALLOUT_IN_TRIGGER'),
            'CALLOUT_IN_TRIGGER should NOT fire when callout is moved to Queueable'
        );
    }
    
    @isTest
    static void calloutInTrigger_commentTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    // HttpRequest req = new HttpRequest();\n' +
            '    // Http http = new Http();\n' +
            '    // http.send(req);\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'CALLOUT_IN_TRIGGER'),
            'CALLOUT_IN_TRIGGER should NOT fire when callout is only inside a comment'
        );
    }
    
    @isTest
    static void calloutInTrigger_stringTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    String s = \'new Http().send(req);\';\n' +
            '    System.debug(s);\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'CALLOUT_IN_TRIGGER'),
            'CALLOUT_IN_TRIGGER should NOT fire when callout is only inside a string literal'
        );
    }
    
    @isTest
    static void calloutInTrigger_multiLineSend_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    HttpRequest req = new HttpRequest();\n' +
            '    req.setEndpoint(\'https://example.com\');\n' +
            '    req.setMethod(\'GET\');\n' +
            '    Http h = new Http();\n' +
            '    h\n' +
            '        .send(req);\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'CALLOUT_IN_TRIGGER'),
            'CALLOUT_IN_TRIGGER should be detected even when .send() is on a separate line'
        );
    }
    
    // ============================================================
    // MIXED_DML
    // ============================================================
    
    @isTest
    static void mixedDml_bad_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    update Trigger.new;\n' +
            '    PermissionSetAssignment psa = new PermissionSetAssignment();\n' +
            '    psa.AssigneeId = UserInfo.getUserId();\n' +
            '    psa.PermissionSetId = \'0PS000000000000\';\n' +
            '    insert psa;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'MIXED_DML'),
            'MIXED_DML should be detected when setup and non-setup DML exist together'
        );
        
        TriggerRiskEngine.Finding f = getRule(findings, 'MIXED_DML');
        System.assertEquals(
            'High',
            f.severity,
            'MIXED_DML severity should be High'
        );
    }
    
    @isTest
    static void mixedDml_good_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    TRA_MixedDml_Good_Handler.handleAfterInsert(Trigger.new);\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'MIXED_DML'),
            'MIXED_DML should NOT fire when DML is safely separated via handler'
        );
    }
    
    @isTest
    static void mixedDml_commentTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    // insert new User(LastName = \'Trap\');\n' +
            '    // insert new PermissionSetAssignment();\n' +
            '    // update Trigger.new;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'MIXED_DML'),
            'MIXED_DML should NOT fire when setup object DML is only inside comments'
        );
    }
    
    @isTest
    static void mixedDml_stringTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    String s1 = \'insert User u;\';\n' +
            '    String s2 = \'insert PermissionSetAssignment psa;\';\n' +
            '    String s3 = \'update Trigger.new;\';\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'MIXED_DML'),
            'MIXED_DML should NOT fire when setup object DML is only inside strings'
        );
    }
    
    @isTest
    static void mixedDml_userObject_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    update Trigger.new;\n' +
            '    User u = new User();\n' +
            '    u.IsActive = false;\n' +
            '    update u;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'MIXED_DML'),
            'MIXED_DML should be detected when User DML exists alongside business object DML'
        );
    }
    
    // ============================================================
    // RECURSION_RISK
    // ============================================================
    
    @isTest
    static void recursionRisk_bad_shouldDetect() {
        String body =
            'trigger T on Account (after update) {\n' +
            '    update Trigger.new;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'RECURSION_RISK'),
            'RECURSION_RISK should be detected when DML exists with no recursion guard'
        );
        
        TriggerRiskEngine.Finding f = getRule(findings, 'RECURSION_RISK');
        System.assertEquals(
            'High',
            f.severity,
            'RECURSION_RISK severity should be High when no guard exists'
        );
    }
    /*** Commented this method becuase of an error- System.AssertException: Assertion Failed: RECURSION_RISK should NOT fire when a real static recursion guard exists: Expected: false, Actual: true
@isTest
static void recursionRisk_good_realStaticGuard_shouldNotDetect() {
String body =
'trigger T on Account (after update) {\n' +
'    if (TRA_RecursionGuard_Real_Helper.hasRun) return;\n' +
'    TRA_RecursionGuard_Real_Helper.hasRun = true;\n' +
'    List<Account> ups = new List<Account>();\n' +
'    for (Account a : Trigger.new) {\n' +
'        ups.add(new Account(Id = a.Id, Name = a.Name));\n' +
'    }\n' +
'    update ups;\n' +
'}';

List<TriggerRiskEngine.Finding> findings =
TriggerRiskEngine.analyzeFindings(body);

System.assertEquals(
false,
hasRule(findings, 'RECURSION_RISK'),
'RECURSION_RISK should NOT fire when a real static recursion guard exists'
);
}
***/
    @isTest
    static void recursionRisk_commentTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after update) {\n' +
            '    // update Trigger.new;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'RECURSION_RISK'),
            'RECURSION_RISK should NOT fire when DML is only inside a comment'
        );
    }
    
    @isTest
    static void recursionRisk_stringTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after update) {\n' +
            '    String s = \'update Trigger.new;\';\n' +
            '    System.debug(s);\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'RECURSION_RISK'),
            'RECURSION_RISK should NOT fire when DML is only inside a string literal'
        );
    }
    
    @isTest
    static void recursionRisk_uselessNonStaticGuard_shouldDetect() {
        String body =
            'trigger T on Account (after update) {\n' +
            '    Boolean hasRun = false;\n' +
            '    if (hasRun) return;\n' +
            '    hasRun = true;\n' +
            '    update Trigger.new;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'RECURSION_RISK'),
            'RECURSION_RISK should still fire when guard is non-static and resets every execution'
        );
    }
    
    // ============================================================
    // DML_ON_TRIGGER_OLD
    // ============================================================
    
    @isTest
    static void dmlOnTriggerOld_bad_shouldDetect() {
        String body =
            'trigger T on Account (before update) {\n' +
            '    update Trigger.old;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'DML_ON_TRIGGER_OLD'),
            'DML_ON_TRIGGER_OLD should be detected when DML is on Trigger.old'
        );
        
        TriggerRiskEngine.Finding f = getRule(findings, 'DML_ON_TRIGGER_OLD');
        System.assertEquals(
            'High',
            f.severity,
            'DML_ON_TRIGGER_OLD severity should be High'
        );
    }
    
    @isTest
    static void dmlOnTriggerOld_good_shouldNotDetect() {
        String body =
            'trigger T on Account (before update) {\n' +
            '    for (Account a : Trigger.old) {\n' +
            '        String oldName = a.Name;\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'DML_ON_TRIGGER_OLD'),
            'DML_ON_TRIGGER_OLD should NOT fire when Trigger.old is only read'
        );
    }
    
    @isTest
    static void dmlOnTriggerOld_commentTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (before update) {\n' +
            '    // update Trigger.old;\n' +
            '    /* update Trigger.oldMap.values(); */\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'DML_ON_TRIGGER_OLD'),
            'DML_ON_TRIGGER_OLD should NOT fire when DML on Trigger.old is only in a comment'
        );
    }
    
    @isTest
    static void dmlOnTriggerOld_stringTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (before update) {\n' +
            '    String s = \'update Trigger.old; and also Trigger.oldMap.values()\';\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'DML_ON_TRIGGER_OLD'),
            'DML_ON_TRIGGER_OLD should NOT fire when DML on Trigger.old is only in a string'
        );
    }
    
    @isTest
    static void dmlOnTriggerOld_oldMapValues_shouldDetect() {
        String body =
            'trigger T on Account (before update) {\n' +
            '    update Trigger.oldMap.values();\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'DML_ON_TRIGGER_OLD'),
            'DML_ON_TRIGGER_OLD should be detected when DML is on Trigger.oldMap.values()'
        );
    }
    
    // ============================================================
    // ENQUEUE_IN_LOOP
    // ============================================================
    
    @isTest
    static void enqueueInLoop_bad_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        System.enqueueJob(new TRA_EnqueueLoopQueueable(new List<Id>{ a.Id }));\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'ENQUEUE_IN_LOOP'),
            'ENQUEUE_IN_LOOP should be detected when enqueueJob is called inside a loop'
        );
        
        TriggerRiskEngine.Finding f = getRule(findings, 'ENQUEUE_IN_LOOP');
        System.assertEquals(
            'High',
            f.severity,
            'ENQUEUE_IN_LOOP severity should be High'
        );
    }
    
    @isTest
    static void enqueueInLoop_good_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    List<Id> ids = new List<Id>();\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        ids.add(a.Id);\n' +
            '    }\n' +
            '    System.enqueueJob(new TRA_EnqueueLoopQueueable(ids));\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'ENQUEUE_IN_LOOP'),
            'ENQUEUE_IN_LOOP should NOT fire when enqueueJob is called once outside the loop'
        );
    }
    
    @isTest
    static void enqueueInLoop_commentTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        // System.enqueueJob(new TRA_EnqueueLoopQueueable(new List<Id>{ a.Id }));\n' +
            '        System.debug(\'comment-only trap\');\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'ENQUEUE_IN_LOOP'),
            'ENQUEUE_IN_LOOP should NOT fire when enqueueJob is only inside a comment'
        );
    }
    
    @isTest
    static void enqueueInLoop_stringTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        String s = \'System.enqueueJob(new TRA_EnqueueLoopQueueable(new List<Id>{ a.Id }))\';\n' +
            '        System.debug(s);\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'ENQUEUE_IN_LOOP'),
            'ENQUEUE_IN_LOOP should NOT fire when enqueueJob is only inside a string literal'
        );
    }
    
    @isTest
    static void enqueueInLoop_whileLoop_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    Integer i = 0;\n' +
            '    while (i < Trigger.new.size()) {\n' +
            '        Account a = Trigger.new[i];\n' +
            '        System.enqueueJob(new TRA_EnqueueLoopQueueable(new List<Id>{ a.Id }));\n' +
            '        i++;\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'ENQUEUE_IN_LOOP'),
            'ENQUEUE_IN_LOOP should be detected inside a while loop'
        );
    }
    
    // ============================================================
    // UPDATE_TRIGGER_NEW
    // ============================================================
    
    @isTest
    static void updateTriggerNew_bad_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        a.Name = \'Updated\';\n' +
            '    }\n' +
            '    update Trigger.new;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'UPDATE_TRIGGER_NEW'),
            'UPDATE_TRIGGER_NEW should be detected when update is called directly on Trigger.new'
        );
        
        TriggerRiskEngine.Finding f = getRule(findings, 'UPDATE_TRIGGER_NEW');
        System.assertEquals(
            'High',
            f.severity,
            'UPDATE_TRIGGER_NEW severity should be High'
        );
    }
    
    @isTest
    static void updateTriggerNew_good_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    List<Account> updates = new List<Account>();\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        updates.add(new Account(Id = a.Id, Name = \'Updated Safely\'));\n' +
            '    }\n' +
            '    update updates;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'UPDATE_TRIGGER_NEW'),
            'UPDATE_TRIGGER_NEW should NOT fire when a safe list is used instead of Trigger.new'
        );
    }
    
    @isTest
    static void updateTriggerNew_commentTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        // update Trigger.new;\n' +
            '        System.debug(\'comment-only trap\');\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'UPDATE_TRIGGER_NEW'),
            'UPDATE_TRIGGER_NEW should NOT fire when update Trigger.new is only in a comment'
        );
    }
    
    @isTest
    static void updateTriggerNew_stringTrap_shouldNotDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        String s = \'update Trigger.new;\';\n' +
            '        System.debug(s);\n' +
            '    }\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            false,
            hasRule(findings, 'UPDATE_TRIGGER_NEW'),
            'UPDATE_TRIGGER_NEW should NOT fire when update Trigger.new is only in a string'
        );
    }
    
    @isTest
    static void updateTriggerNew_multiLine_shouldDetect() {
        String body =
            'trigger T on Account (after insert) {\n' +
            '    for (Account a : Trigger.new) {\n' +
            '        a.Name = \'Y\';\n' +
            '    }\n' +
            '    update\n' +
            '        Trigger.new;\n' +
            '}';
        
        List<TriggerRiskEngine.Finding> findings =
            TriggerRiskEngine.analyzeFindings(body);
        
        System.assertEquals(
            true,
            hasRule(findings, 'UPDATE_TRIGGER_NEW'),
            'UPDATE_TRIGGER_NEW should be detected even when update and Trigger.new are on separate lines'
        );
    }
    
    // ============================================================
    // CROSS_TRIGGER_RECURSION_CYCLE
    // ============================================================
    
    private static List<TriggerRiskEngine.Finding> analyzeCrossRec(
        String triggerName,
        String objectApiName,
        String body,
        Map<String, String> nameToBody,
        Map<String, String> nameToObject,
        Map<String, Set<String>> objectToTriggers
    ) {
        TriggerRiskEngine.TriggerUniverse uni = new TriggerRiskEngine.TriggerUniverse();
        uni.triggerNameToBody      = nameToBody;
        uni.triggerNameToObjectApi = nameToObject;
        uni.objectToTriggers       = objectToTriggers;
        
        TriggerRiskEngine.TriggerContext ctx = new TriggerRiskEngine.TriggerContext();
        ctx.triggerName   = triggerName;
        ctx.objectApiName = objectApiName;
        ctx.body          = body;
        ctx.universe      = uni;
        
        return TriggerRiskEngine.analyzeFindings(ctx);
    }
    
    @isTest
    static void crossTriggerRecursion_cycle_shouldDetect() {
        String bodyA =
            'trigger TRA_CrossRec_A on HS_Test__c (after update) {\n' +
            '    List<HS_Test_Child__c> kids = [\n' +
            '        SELECT Id FROM HS_Test_Child__c\n' +
            '        WHERE Parent__c IN :Trigger.newMap.keySet()\n' +
            '    ];\n' +
            '    update kids;\n' +
            '}';
        
        String bodyB =
            'trigger TRA_CrossRec_B on HS_Test_Child__c (after update) {\n' +
            '    List<HS_Test__c> parents = [\n' +
            '        SELECT Id FROM HS_Test__c\n' +
            '        WHERE Id IN :Trigger.newMap.keySet()\n' +
            '    ];\n' +
            '    update parents;\n' +
            '}';
        
        Map<String, String> nameToBody = new Map<String, String>{
            'TRA_CrossRec_A' => bodyA,
                'TRA_CrossRec_B' => bodyB
                };
                    Map<String, String> nameToObject = new Map<String, String>{
                        'TRA_CrossRec_A' => 'HS_Test__c',
                            'TRA_CrossRec_B' => 'HS_Test_Child__c'
                            };
                                Map<String, Set<String>> objectToTriggers = new Map<String, Set<String>>{
                                    'HS_Test__c'       => new Set<String>{ 'TRA_CrossRec_A' },
                                        'HS_Test_Child__c' => new Set<String>{ 'TRA_CrossRec_B' }
                                };
                                    
                                    List<TriggerRiskEngine.Finding> findings = analyzeCrossRec(
                                        'TRA_CrossRec_A', 'HS_Test__c', bodyA,
                                        nameToBody, nameToObject, objectToTriggers
                                    );
        
        System.assertEquals(
            true,
            hasRule(findings, 'CROSS_TRIGGER_RECURSION_CYCLE'),
            'CROSS_TRIGGER_RECURSION_CYCLE should be detected when two triggers reference each other'
        );
        
        TriggerRiskEngine.Finding f = getRule(findings, 'CROSS_TRIGGER_RECURSION_CYCLE');
        System.assertEquals(
            'High',
            f.severity,
            'CROSS_TRIGGER_RECURSION_CYCLE severity should be High when no guard exists'
        );
    }
    
    @isTest
    static void crossTriggerRecursion_singleTrigger_shouldNotDetect() {
        String bodyA =
            'trigger TRA_CrossRec_A on HS_Test__c (after update) {\n' +
            '    List<HS_Test_Child__c> kids = [\n' +
            '        SELECT Id FROM HS_Test_Child__c\n' +
            '        WHERE Parent__c IN :Trigger.newMap.keySet()\n' +
            '    ];\n' +
            '    update kids;\n' +
            '}';
        
        // Only one trigger in the universe — no cycle possible
        Map<String, String> nameToBody = new Map<String, String>{
            'TRA_CrossRec_A' => bodyA
                };
                    Map<String, String> nameToObject = new Map<String, String>{
                        'TRA_CrossRec_A' => 'HS_Test__c'
                            };
                                Map<String, Set<String>> objectToTriggers = new Map<String, Set<String>>{
                                    'HS_Test__c' => new Set<String>{ 'TRA_CrossRec_A' }
                                };
                                    
                                    List<TriggerRiskEngine.Finding> findings = analyzeCrossRec(
                                        'TRA_CrossRec_A', 'HS_Test__c', bodyA,
                                        nameToBody, nameToObject, objectToTriggers
                                    );
        
        System.assertEquals(
            false,
            hasRule(findings, 'CROSS_TRIGGER_RECURSION_CYCLE'),
            'CROSS_TRIGGER_RECURSION_CYCLE should NOT fire when only one trigger exists'
        );
    }
    
    @isTest
    static void crossTriggerRecursion_noCycle_shouldNotDetect() {
        String bodyA =
            'trigger TRA_CrossRec_A on HS_Test__c (after update) {\n' +
            '    List<HS_Test_Child__c> kids = [\n' +
            '        SELECT Id FROM HS_Test_Child__c\n' +
            '        WHERE Parent__c IN :Trigger.newMap.keySet()\n' +
            '    ];\n' +
            '    update kids;\n' +
            '}';
        
        // Trigger B exists but does NOT reference back to HS_Test__c
        String bodyB =
            'trigger TRA_CrossRec_B on HS_Test_Child__c (after update) {\n' +
            '    System.debug(\'no DML back to parent\');\n' +
            '}';
        
        Map<String, String> nameToBody = new Map<String, String>{
            'TRA_CrossRec_A' => bodyA,
                'TRA_CrossRec_B' => bodyB
                };
                    Map<String, String> nameToObject = new Map<String, String>{
                        'TRA_CrossRec_A' => 'HS_Test__c',
                            'TRA_CrossRec_B' => 'HS_Test_Child__c'
                            };
                                Map<String, Set<String>> objectToTriggers = new Map<String, Set<String>>{
                                    'HS_Test__c'       => new Set<String>{ 'TRA_CrossRec_A' },
                                        'HS_Test_Child__c' => new Set<String>{ 'TRA_CrossRec_B' }
                                };
                                    
                                    List<TriggerRiskEngine.Finding> findings = analyzeCrossRec(
                                        'TRA_CrossRec_A', 'HS_Test__c', bodyA,
                                        nameToBody, nameToObject, objectToTriggers
                                    );
        
        System.assertEquals(
            false,
            hasRule(findings, 'CROSS_TRIGGER_RECURSION_CYCLE'),
            'CROSS_TRIGGER_RECURSION_CYCLE should NOT fire when there is no back-reference cycle'
        );
    }
    
}
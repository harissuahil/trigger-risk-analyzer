trigger TRA_SoqlInLoop_NoBrace_Bad on HS_Test__c (before insert) {

    // TEST E: No-brace loop with SOQL inside
    // Expected:
    // - SOQL_IN_LOOP must be detected (High)
    // - Gate should be BLOCKED
    // - No false positives from comments or strings

    for (HS_Test__c t : Trigger.new)
        t.Name = [SELECT Name FROM Account LIMIT 1].Name;

}
trigger TRA_MultiTrigger_Test_One on HS_Test__c (before insert, before update) {
    // Test trigger #1 - intentionally minimal
    if (Trigger.isBefore) {
        // no-op
    }
}
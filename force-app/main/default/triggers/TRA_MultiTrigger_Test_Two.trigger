trigger TRA_MultiTrigger_Test_Two on HS_Test__c (after insert, after update) {
    // Test trigger #2 - intentionally minimal
    if (Trigger.isAfter) {
        // no-op
    }
}
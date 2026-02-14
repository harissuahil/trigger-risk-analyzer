trigger TRA_AfterTriggerMutation_Mixed on HS_Test__c (before update, after update) {
    if (Trigger.isAfter) {
        Trigger.new[0].Name = 'Changed in AFTER';
    }
}
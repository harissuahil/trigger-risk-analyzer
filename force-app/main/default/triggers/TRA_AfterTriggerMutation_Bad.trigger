trigger TRA_AfterTriggerMutation_Bad on HS_Test__c (after update) {
    Trigger.new[0].Name = 'Changed in AFTER';
}
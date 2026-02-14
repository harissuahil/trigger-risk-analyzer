trigger TRA_AfterTriggerMutation_Good on HS_Test__c (after update) {
    // No mutation of Trigger.new
    Integer x = 1;
}
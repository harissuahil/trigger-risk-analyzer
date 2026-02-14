trigger TRA_RecursionRisk_Bad on HS_Test__c (after update) {
    // Updates the same records inside their own trigger => recursion risk
    update Trigger.new;
}
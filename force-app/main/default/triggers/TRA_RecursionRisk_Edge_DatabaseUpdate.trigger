trigger TRA_RecursionRisk_Edge_DatabaseUpdate on HS_Test__c (after update) {
    Database.update(Trigger.new, false);
}
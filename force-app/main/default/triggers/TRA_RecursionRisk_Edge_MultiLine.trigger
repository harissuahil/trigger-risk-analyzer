trigger TRA_RecursionRisk_Edge_MultiLine on HS_Test__c (after update) {
    update
        Trigger.new;
}
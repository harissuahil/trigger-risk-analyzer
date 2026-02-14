trigger TRA_RecursionRisk_Edge_Loop on HS_Test__c (after update) {
    List<HS_Test__c> ups = new List<HS_Test__c>();

    for (HS_Test__c r : Trigger.new) {
        ups.add(r);
    }

    update ups;
}
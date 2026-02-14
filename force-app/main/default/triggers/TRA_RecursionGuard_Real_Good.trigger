trigger TRA_RecursionGuard_Real_Good on HS_Test__c (after update) {
    if (TRA_RecursionGuard_Real_Helper.hasRun) return;
    TRA_RecursionGuard_Real_Helper.hasRun = true;

    List<HS_Test__c> ups = new List<HS_Test__c>();
    for (HS_Test__c r : Trigger.new) {
        ups.add(new HS_Test__c(Id = r.Id, Name = r.Name));
    }
    update ups;
}
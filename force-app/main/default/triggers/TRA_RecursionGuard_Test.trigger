trigger TRA_RecursionGuard_Test on HS_Test__c (after update) {
    if (TRA_RecursionGuard_TestHelper.hasRun) return;
    TRA_RecursionGuard_TestHelper.hasRun = true;

    List<HS_Test__c> ups = new List<HS_Test__c>();
    for (HS_Test__c r : Trigger.new) {
        HS_Test__c x = new HS_Test__c(Id = r.Id);
        x.Name = r.Name;
        ups.add(x);
    }
    update ups;
}
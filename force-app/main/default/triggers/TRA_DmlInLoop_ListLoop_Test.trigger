trigger TRA_DmlInLoop_ListLoop_Test on HS_Test__c (after update) {
    List<HS_Test__c> ups = new List<HS_Test__c>();
    for (HS_Test__c r : Trigger.new) ups.add(new HS_Test__c(Id=r.Id, Name=r.Name));
    for (HS_Test__c x : ups) update new List<HS_Test__c>{ x };
}
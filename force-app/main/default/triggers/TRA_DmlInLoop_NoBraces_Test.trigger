trigger TRA_DmlInLoop_NoBraces_Test on HS_Test__c (after update) {
    for (HS_Test__c r : Trigger.new)
        update new List<HS_Test__c>{ new HS_Test__c(Id = r.Id, Name = r.Name) };
}
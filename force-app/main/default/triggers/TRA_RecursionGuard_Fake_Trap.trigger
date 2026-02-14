trigger TRA_RecursionGuard_Fake_Trap on HS_Test__c (after update) {
    // recursionGuard (fake). This is only a comment, not a real guard.
    String note = 'alreadyProcessed'; // fake guard keyword inside a string

    List<HS_Test__c> ups = new List<HS_Test__c>();
    for (HS_Test__c r : Trigger.new) {
        ups.add(new HS_Test__c(
            Id = r.Id,
            Name = r.Name
        ));
    }

    update ups;
}
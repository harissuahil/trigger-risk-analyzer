trigger TRA_DmlInLoop_SingleRecord_Test on HS_Test__c (after update) {

    // Intentionally bad pattern for testing
    for (HS_Test__c r : Trigger.new) {

        // Single-record DML inside loop (classic anti-pattern)
        HS_Test__c upd = new HS_Test__c(
            Id = r.Id,
            Name = r.Name
        );

        update upd; // <-- this should trigger BOTH rules
    }
}
trigger HS_CaseC_Trigger on Account (after insert) {
    // BLOCKED patterns: SOQL + DML in loop (intentional for testing)
    // Safety guard to avoid endless re-entry / re-updating
    Set<Id> toUpdate = new Set<Id>();

    for (Account a : Trigger.new) {
        // SOQL in loop (intentional)
        List<Contact> cs = [SELECT Id FROM Contact WHERE AccountId = :a.Id LIMIT 1];

        // only mark for update once (avoid repeated updates if other automation re-saves Account)
        toUpdate.add(a.Id);
    }

    List<Account> updates = new List<Account>();
    for (Id aid : toUpdate) {
        updates.add(new Account(
            Id = aid,
            Description = 'Updated by Case C trigger'
        ));
    }

    // one DML, not inside loop (this removes DML_IN_LOOP)
    // If you MUST keep DML_IN_LOOP for testing, tell me and I’ll give a guarded version.
    update updates;
}
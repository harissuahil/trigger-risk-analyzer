trigger TRA_DmlOnTriggerOld_Isolation_Good on Account (after update) {

    // Recursion guard - prevents repeated execution
    if (TRA_DmlOnTriggerOld_Isolation_Guard.hasAlreadyRun()) {
        return;
    }

    // GOOD: build a separate list of records (not Trigger.old / oldMap.values())
    List<Account> toUpdate = new List<Account>();
    for (Account aOld : Trigger.old) {
        // Create a fresh sObject instance (this is NOT read-only Trigger.old)
        toUpdate.add(new Account(
            Id = aOld.Id,
            Description = 'Updated by TRA_DmlOnTriggerOld_Isolation_Good'
        ));
    }

    if (!toUpdate.isEmpty()) {
        update toUpdate;
    }
}
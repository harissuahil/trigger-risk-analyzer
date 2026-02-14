trigger TRA_DmlOnTriggerOld_Isolation_Bad on Account (after update) {

    // Recursion guard - prevents the trigger from re-running DML logic repeatedly
    if (TRA_DmlOnTriggerOld_Isolation_Guard.hasAlreadyRun()) {
        return;
    }

    // Intentionally bad: DML directly on trigger context records (via Trigger.oldMap.values())
    update Trigger.oldMap.values();
}
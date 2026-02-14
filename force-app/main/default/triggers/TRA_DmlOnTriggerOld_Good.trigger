trigger TRA_DmlOnTriggerOld_Good on Account (before update) {
    // Good: use Trigger.old only for comparisons, no DML on it
    for (Account a : Trigger.old) {
        // Example read-only usage
        String oldName = a.Name;
    }
}
trigger TRA_DmlOnTriggerOld_Bad on Account (before update) {
    // Intentionally bad: DML directly on Trigger.old
    update Trigger.old;
}
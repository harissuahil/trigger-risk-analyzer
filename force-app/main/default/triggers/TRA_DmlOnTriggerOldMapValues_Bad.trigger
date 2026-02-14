trigger TRA_DmlOnTriggerOldMapValues_Bad on Account (before update) {
    // Also bad: still trigger context records
    update Trigger.oldMap.values();
}
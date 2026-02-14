trigger TRA_DmlOnTriggerOld_StringOnly_Trap on Account (before update) {
    String s = 'this is a string: update Trigger.old; and also Trigger.oldMap.values()';
}
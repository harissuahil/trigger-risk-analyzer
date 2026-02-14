trigger TRA_DmlOnTriggerOld_Sneaky_Bad on Account (before update) {
    List<Account> x = Trigger.oldMap.values();
    update x;
}
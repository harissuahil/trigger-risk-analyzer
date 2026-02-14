trigger HS_CleanTrigger on Account (before insert, before update) {
    HS_CleanTriggerHandler.run(Trigger.new, Trigger.oldMap, Trigger.isInsert, Trigger.isUpdate);
}
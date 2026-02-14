trigger TRA_HandlerMissing_Bad on HS_Test__c (before insert, after update) {

    // Has logic directly in trigger (should trigger TRIGGER_HANDLER_MISSING)
    if (Trigger.isBefore && Trigger.isInsert) {

        for (HS_Test__c r : Trigger.new) {
            r.Name = 'Updated in trigger';
        }
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        update Trigger.new; // DML directly in trigger (also risky in real life)
    }
}
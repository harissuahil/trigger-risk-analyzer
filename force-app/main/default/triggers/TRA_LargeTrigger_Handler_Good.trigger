trigger TRA_LargeTrigger_Handler_Good on HS_Test__c (before insert, before update, after update) {

    //==========REGRESSION FIXED VERSION - Large Trigger moved to Handler==========
    if (Trigger.isBefore) {
        TRA_LargeTrigger_Handler_Good_Handler.handleBefore(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        TRA_LargeTrigger_Handler_Good_Handler.handleAfterUpdate(Trigger.new);
    }
    //==========END REGRESSION FIXED VERSION==========
}
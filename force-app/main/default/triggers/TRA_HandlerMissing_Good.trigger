trigger TRA_HandlerMissing_Good on HS_Test__c (before insert, after update) {
    HS_TestTriggerHandler.run();
}
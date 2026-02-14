trigger TRA_RecursionGuard_NotStatic_Trap1 on HS_Test_Child__c (after update) {
    TRA_RecurGuardNotStaticTrapHandler h = new TRA_RecurGuardNotStaticTrapHandler();
    h.run(Trigger.new);
}
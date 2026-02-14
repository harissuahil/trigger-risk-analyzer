trigger TRA_RecursionGuard_NotStatic_Trap on HS_Test__c (after update) {
    TRA_RecurGuardNotStaticTrapHandler h = new TRA_RecurGuardNotStaticTrapHandler();
    h.run(Trigger.new);
}
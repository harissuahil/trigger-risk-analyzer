trigger TRA_DmlInLoop_StringOnly_Trap on HS_Test__c (after update) {
    for (HS_Test__c r : Trigger.new) {
        String s = 'update r;'; // string-only, must NOT be detected
    }
}
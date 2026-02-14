trigger TRA_RecursionRisk_StringOnly_Trap on HS_Test__c (after update) {
    String s = 'update Trigger.new;'; // string-only trap, must NOT be detected as real DML
}
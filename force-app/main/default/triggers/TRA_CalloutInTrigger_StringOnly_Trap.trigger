trigger TRA_CalloutInTrigger_StringOnly_Trap on HS_Test__c (after insert) {
    String s = 'new Http().send(req);'; // string-only trap, must NOT be detected
}
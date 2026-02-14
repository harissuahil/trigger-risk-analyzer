trigger TRA_EmailInTrigger_Good on HS_Test__c (after insert) {
    // Intentionally no email logic here
    Integer x = 1;
    x++;
}
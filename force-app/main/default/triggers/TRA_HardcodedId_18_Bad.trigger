trigger TRA_HardcodedId_18_Bad on HS_Test__c (before insert) {
    String x = '001000000000000AAA'; // hardcoded Id literal
}
trigger TRA_HardcodedId_15_Bad on HS_Test__c (before insert) {
    String x = '001000000000000'; // 15-char style Id literal
}
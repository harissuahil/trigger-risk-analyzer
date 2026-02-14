trigger TRA_DmlInLoop_Good_NoDml on HS_Test__c (after update) {
    Integer c = 0;
    for (HS_Test__c r : Trigger.new) {
        c++;
    }
}
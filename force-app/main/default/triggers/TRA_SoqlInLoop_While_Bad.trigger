trigger TRA_SoqlInLoop_While_Bad on HS_Test__c (after insert) { //HS
    Integer i = 0; //HS
    while (i < Trigger.new.size()) { //HS
        List<Account> accs = [SELECT Id FROM Account LIMIT 1]; //HS
        System.debug(accs.size()); //HS
        i++; //HS
    } //HS
} //HS
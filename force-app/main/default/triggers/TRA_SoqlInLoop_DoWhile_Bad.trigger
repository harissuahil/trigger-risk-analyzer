trigger TRA_SoqlInLoop_DoWhile_Bad on HS_Test__c (after insert) { //HS
    Integer i = 0; //HS
    do { //HS
        List<Account> accs = [SELECT Id FROM Account LIMIT 1]; //HS
        System.debug(accs.size()); //HS
        i++; //HS
    } while (i < Trigger.new.size()); //HS
} //HS
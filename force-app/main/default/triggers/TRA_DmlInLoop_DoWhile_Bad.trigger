trigger TRA_DmlInLoop_DoWhile_Bad on HS_Test__c (after insert) { //HS
    Integer i = 0; //HS
    do { //HS
        Account a = new Account(Name = 'TRA DmlInLoop DoWhile'); //HS
        insert a; //HS
        i++; //HS
    } while (i < Trigger.new.size()); //HS
} //HS
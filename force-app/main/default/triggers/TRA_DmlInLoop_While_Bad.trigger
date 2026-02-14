trigger TRA_DmlInLoop_While_Bad on HS_Test__c (after insert) { //HS
    Integer i = 0; //HS
    while (i < Trigger.new.size()) { //HS
        Account a = new Account(Name = 'TRA DmlInLoop While'); //HS
        insert a; //HS
        i++; //HS
    } //HS
} //HS
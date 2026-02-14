trigger TRA_EnqueueInLoop_While_Bad on HS_Test__c (after insert) { //HS
    Integer i = 0; //HS
    while (i < Trigger.new.size()) { //HS
        HS_Test__c r = Trigger.new[i]; //HS
        System.enqueueJob(new TRA_EnqueueLoopQueueable(new List<Id>{ r.Id })); //HS
        i++; //HS
    } //HS
} //HS
trigger TRA_EnqueueInLoop_MultiLine_Bad on HS_Test__c (after insert) { //HS
    for (HS_Test__c r : Trigger.new) { //HS
        System.enqueueJob( //HS
            new TRA_EnqueueLoopQueueable( //HS
                new List<Id>{ r.Id } //HS
            ) //HS
        ); //HS
    } //HS
} //HS
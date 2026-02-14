trigger TRA_EnqueueInLoop_Nested_Bad on HS_Test__c (after insert) { //HS
    for (HS_Test__c outerRec : Trigger.new) { //HS
        for (Integer i = 0; i < 1; i++) { //HS
            System.enqueueJob(new TRA_EnqueueLoopQueueable(new List<Id>{ outerRec.Id })); //HS
        } //HS
    } //HS
} //HS
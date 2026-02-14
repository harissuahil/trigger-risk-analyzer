trigger TRA_EnqueueInLoop_CommentOnly_Trap on HS_Test__c (after insert) { //HS
    for (HS_Test__c r : Trigger.new) { //HS
        // System.enqueueJob(new TRA_EnqueueLoopQueueable(new List<Id>{ r.Id })); //HS
        System.debug('comment-only trap'); //HS
    } //HS
} //HS
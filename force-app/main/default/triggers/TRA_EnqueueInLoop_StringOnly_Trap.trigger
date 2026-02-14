trigger TRA_EnqueueInLoop_StringOnly_Trap on HS_Test__c (after insert) { //HS
    for (HS_Test__c r : Trigger.new) { //HS
        String s = 'System.enqueueJob(new TRA_EnqueueLoopQueueable(new List<Id>{ r.Id }))'; //HS
        System.debug(s); //HS
    } //HS
} //HS
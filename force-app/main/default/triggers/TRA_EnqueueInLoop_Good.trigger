trigger TRA_EnqueueInLoop_Good on HS_Test__c (after insert) { //HS
    List<Id> ids = new List<Id>(); //HS
    for (HS_Test__c r : Trigger.new) { //HS
        ids.add(r.Id); //HS
    } //HS
    System.enqueueJob(new TRA_EnqueueLoopQueueable(ids)); //HS
} //HS
trigger TRA_EnqueueInLoop_HelperCall_Edge on HS_Test__c (after insert) { //HS
    for (HS_Test__c r : Trigger.new) { //HS
        TRA_EnqueueInLoop_Helper.enqueueOne(r.Id); //HS
    } //HS
} //HS
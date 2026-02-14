trigger TRA_CalloutInTrigger_Good on HS_Test__c (after insert) {
    System.enqueueJob(new TRA_CalloutQueueable());
}
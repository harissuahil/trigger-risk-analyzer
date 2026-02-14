trigger TRA_MixedDml_Good on HS_Test__c (after insert) {
    TRA_MixedDml_Good_Handler.handleAfterInsert(Trigger.new);
}
trigger TRA_RecursionRisk_Good on HS_Test__c (after update) { 
    TRA_RecursionRisk_Good_Handler.runAfterUpdate(Trigger.new, Trigger.newMap); 
}
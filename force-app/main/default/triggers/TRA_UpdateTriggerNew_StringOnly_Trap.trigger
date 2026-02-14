trigger TRA_UpdateTriggerNew_StringOnly_Trap on HS_Test__c (after insert) { //HS
    for (HS_Test__c r : Trigger.new) { //HS
        String s = 'update Trigger.new;'; //HS
        System.debug(s); //HS
    } //HS
} //HS
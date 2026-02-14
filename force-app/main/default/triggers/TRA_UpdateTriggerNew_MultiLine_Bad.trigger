trigger TRA_UpdateTriggerNew_MultiLine_Bad on HS_Test__c (after insert) { //HS
    for (HS_Test__c r : Trigger.new) { //HS
        r.Name = 'Y'; //HS
    } //HS
    update //HS
        Trigger.new; //HS
} //HS
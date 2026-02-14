trigger TRA_UpdateTriggerNew_Bad on HS_Test__c (after insert) { //HS
    for (HS_Test__c r : Trigger.new) { //HS
        r.Name = 'Updated In Memory'; //HS
    } //HS
    update Trigger.new; //HS
} //HS
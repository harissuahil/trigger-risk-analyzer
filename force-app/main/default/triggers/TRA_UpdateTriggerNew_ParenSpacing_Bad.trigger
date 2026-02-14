trigger TRA_UpdateTriggerNew_ParenSpacing_Bad on HS_Test__c (after insert) { //HS
    for (HS_Test__c r : Trigger.new) { //HS
        r.Name = 'X'; //HS
    } //HS
    update ( Trigger.new ); //HS
} //HS
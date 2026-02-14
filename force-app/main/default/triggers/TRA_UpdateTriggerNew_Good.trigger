trigger TRA_UpdateTriggerNew_Good on HS_Test__c (after insert) { //HS
    List<HS_Test__c> updates = new List<HS_Test__c>(); //HS
    for (HS_Test__c r : Trigger.new) { //HS
        updates.add(new HS_Test__c(Id = r.Id, Name = 'Updated Safely')); //HS
    } //HS
    update updates; //HS
} //HS
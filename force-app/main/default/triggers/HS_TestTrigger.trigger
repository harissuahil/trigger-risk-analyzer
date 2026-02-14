trigger HS_TestTrigger on HS_Test__c (before insert, before update) {
    for (HS_Test__c rec : Trigger.new) {
        // simple no-op (does nothing)
        rec.Name = rec.Name;
    }
    Messaging.sendEmail(new Messaging.SingleEmailMessage[] {});

}
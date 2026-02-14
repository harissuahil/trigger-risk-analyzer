trigger TRA_EmailInTrigger_CommentOnly_Trap on HS_Test__c (before insert, before update) {
    // Trap 1: looks like email send, but it's only a comment:
    // Messaging.sendEmail(new Messaging.SingleEmailMessage[] { new Messaging.SingleEmailMessage() });

    // Trap 2: looks like email send, but it's only a block comment:
    /*
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { new Messaging.SingleEmailMessage() });
    */

    // Trap 3: looks like email send, but it's only a string:
    String s = 'Messaging.sendEmail(new Messaging.SingleEmailMessage[] { new Messaging.SingleEmailMessage() });';

    // No real email call should exist in executable code.
    if (Trigger.isBefore) {
        // do nothing
    }
}
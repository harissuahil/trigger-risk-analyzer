trigger TRA_EmailInTrigger_Bad on HS_Test__c (after insert) {

    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
    mail.setToAddresses(new List<String>{ 'test@example.com' });
    mail.setSubject('TRA Email Test - Bad');
    mail.setPlainTextBody('This email is sent from a trigger.');

    Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
}
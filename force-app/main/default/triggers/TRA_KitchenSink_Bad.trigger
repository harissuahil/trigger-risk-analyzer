trigger TRA_KitchenSink_Bad on HS_Test__c (before insert, after insert) {

    // Problem #4 (Hardcoded Id)
    Id someId = '001000000000000AAA';

    // Problem #3 (Callout in trigger)
    if (Trigger.isAfter && Trigger.isInsert) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://example.com');
        req.setMethod('GET');
        Http http = new Http();
        HttpResponse res = http.send(req);
    }

    // Problems #1 and #2 (SOQL in loop + DML in loop)
    if (Trigger.isBefore && Trigger.isInsert) {
        for (HS_Test__c t : Trigger.new) {

            // SOQL inside loop
            List<Account> accs = [
                SELECT Id
                FROM Account
                WHERE Name != null
                LIMIT 1
            ];

            // DML inside loop
            if (!accs.isEmpty()) {
                Account a = accs[0];
                a.Description = 'Updated by bad trigger';
                update a;
            }
        }
    }
}
trigger TRA_CalloutInTrigger_Edge_MultiLine on HS_Test__c (after insert) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('https://example.com');
    req.setMethod('GET');

    Http h = new Http();
    h
        .send(req);
}
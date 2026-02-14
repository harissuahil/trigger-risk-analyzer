trigger TRA_CalloutInTrigger_Bad on HS_Test__c (after insert) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('https://example.com');
    req.setMethod('GET');

    Http http = new Http();
    http.send(req);
}
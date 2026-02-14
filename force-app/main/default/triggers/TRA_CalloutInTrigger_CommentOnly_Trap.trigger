trigger TRA_CalloutInTrigger_CommentOnly_Trap on HS_Test__c (after insert) {
    // HttpRequest req = new HttpRequest();
    // req.setEndpoint('https://example.com');
    // req.setMethod('GET');
    // Http http = new Http();
    // http.send(req);  // comment-only trap, must NOT be detected
}
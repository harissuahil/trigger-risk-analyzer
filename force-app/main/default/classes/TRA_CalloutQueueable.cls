public class TRA_CalloutQueueable implements Queueable, Database.AllowsCallouts {
    public void execute(QueueableContext ctx) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://example.com');
        req.setMethod('GET');
        new Http().send(req);
    }
}
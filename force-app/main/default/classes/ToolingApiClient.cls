// CLASS: ToolingApiClient
public with sharing class ToolingApiClient {

    // Returns the raw Tooling API JSON as an untyped Map (easy + flexible)
    public static Map<String, Object> queryUntyped(String soql) {
        if (String.isBlank(soql)) {
            throw new IllegalArgumentException('SOQL cannot be blank.');
        }

        String encoded = EncodingUtil.urlEncode(soql, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint('callout:SF_TOOLING/services/data/v61.0/tooling/query/?q=' + encoded);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new CalloutException('Tooling API call failed: ' + res.getStatus() + ' | ' + res.getBody());
        }

        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }
}
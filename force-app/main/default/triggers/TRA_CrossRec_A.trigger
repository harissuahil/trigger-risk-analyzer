trigger TRA_CrossRec_A on HS_Test__c (after update) {
    Set<Id> parentIds = new Set<Id>();
    for (HS_Test__c p : Trigger.new) {
        if (p.Id != null) parentIds.add(p.Id);
    }
    if (parentIds.isEmpty()) return;

    List<HS_Test_Child__c> kids = [
        SELECT Id, Parent__c
        FROM HS_Test_Child__c
        WHERE Parent__c IN :parentIds
        LIMIT 200
    ];
    if (kids.isEmpty()) return;

    for (HS_Test_Child__c c : kids) {
        c.Name = c.Name; // no-op, but still DML happens
    }

    update kids;
}
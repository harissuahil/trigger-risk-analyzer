trigger TRA_CrossRec_B on HS_Test_Child__c (after update) {
    Set<Id> parentIds = new Set<Id>();
    for (HS_Test_Child__c c : Trigger.new) {
        if (c.Parent__c != null) parentIds.add(c.Parent__c);
    }
    if (parentIds.isEmpty()) return;

    List<HS_Test__c> parents = [
        SELECT Id
        FROM HS_Test__c
        WHERE Id IN :parentIds
        LIMIT 200
    ];
    if (parents.isEmpty()) return;

    for (HS_Test__c p : parents) {
        p.Name = p.Name; // no-op, but still DML happens
    }

    update parents;
}
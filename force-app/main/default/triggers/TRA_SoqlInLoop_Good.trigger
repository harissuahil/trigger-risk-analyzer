trigger TRA_SoqlInLoop_Good on HS_Test__c (before insert, before update) {
    List<Account> accs = [
        SELECT Id
        FROM Account
        WHERE Name != null
    ];

    for (HS_Test__c t : Trigger.new) {
        if (!accs.isEmpty()) {
            t.Name = 'Has Accounts';
        }
    }
}
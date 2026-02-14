trigger TRA_SoqlInLoop_Bad on HS_Test__c (before insert, before update) {
    for (HS_Test__c t : Trigger.new) {
        List<Account> accs = [
            SELECT Id
            FROM Account
            WHERE Name != null
        ];
        if (!accs.isEmpty()) {
            t.Name = 'Has Accounts';
        }
    }
}
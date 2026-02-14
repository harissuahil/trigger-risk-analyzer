trigger TRA_SoqlInLoop_AllScenarios on HS_Test__c (before insert, before update) {

     String accountID = '00Bfj00000IPVGREA5';
    // ============================================================
    // SOQL_IN_LOOP Validation Trigger (All scenarios in one file)
    // Object: HS_Test__c
    //
    // How to use:
    // 1) Deploy this trigger.
    // 2) Run TRA for this trigger name.
    // 3) Expectation:
    //    - With any BAD block enabled: SOQL_IN_LOOP must be detected (High, BulkRisk)
    //    - Traps (comment-only + string-only) must NOT cause detection by themselves.
    //
    // To validate each specific detection pattern:
    // - Keep only ONE BAD block enabled at a time.
    // - Comment out the other BAD blocks.
    // ============================================================

    // ------------------------------
    // A) GOOD baseline (SOQL outside loop) : must NOT trigger SOQL_IN_LOOP by itself
    // ------------------------------
    List<Account> outside = [SELECT Id, Name FROM Account LIMIT 1];

    for (HS_Test__c t : Trigger.new) {
        // Safe use of outside-loop data
        if (!outside.isEmpty()) {
            t.Name = 'OK-' + outside[0].Name;
        } else {
            t.Name = 'OK';
        }
    }

    // ------------------------------
    // B) COMMENT-ONLY trap : must NOT trigger SOQL_IN_LOOP
    // ------------------------------
    /*
    for (HS_Test__c t : Trigger.new) {
        List<Account> accs = [
            SELECT Id
            FROM Account
            WHERE Name != null
        ];
        t.Name = 'COMMENT-TRAP';
    }
    */

    // ------------------------------
    // C) STRING-ONLY trap : must NOT trigger SOQL_IN_LOOP
    // (Includes loop + SOQL text, multi-line, and bracket query text)
    // ------------------------------
    String fake =
        'for (HS_Test__c t : Trigger.new) {\n' +
        '    List<Account> accs = [\n' +
        '        SELECT Id\n' +
        '        FROM Account\n' +
        '        WHERE Name != null\n' +
        '    ];\n' +
        '}\n';
    if (fake.length() > 0) {
        // do nothing, just keep the string referenced
    }

    // ============================================================
    // D) BAD blocks (enable ONE at a time)
    // ============================================================

    // ------------------------------
    // D1) BAD: Inline bracket SOQL inside a foreach loop (classic)
    // Expected: MUST detect SOQL_IN_LOOP
    // ------------------------------
  /**HS  for (HS_Test__c t : Trigger.new) {
        List<Account> accs = [SELECT Id FROM Account LIMIT 1];
        if (!accs.isEmpty()) {
            t.Name = 'BAD1-' + accs[0].Id;
        }
    }
**/
    // ------------------------------
    // D2) BAD: Multi-line bracket SOQL inside loop
    // Expected: MUST detect SOQL_IN_LOOP
    // ------------------------------
    /*
    for (HS_Test__c t : Trigger.new) {
        List<Account> accs = [
            SELECT Id, Name
            FROM Account
            WHERE Name != null
            LIMIT 1
        ];
        if (!accs.isEmpty()) {
            t.Name = 'BAD2-' + accs[0].Name;
        }
    }
    */

    // ------------------------------
    // D3) BAD: Dynamic SOQL using Database.query inside loop
    // Expected: MUST detect SOQL_IN_LOOP
    // ------------------------------
    /*
    for (HS_Test__c t : Trigger.new) {
        String q = 'SELECT Id FROM Account LIMIT 1';
        List<SObject> rows = Database.query(q);
        if (!rows.isEmpty()) {
            t.Name = 'BAD3-' + (Id) rows[0].get('Id');
        }
    }
    */

    // ------------------------------
    // D4) BAD: Database.getQueryLocator inside loop (still SOQL in loop risk)
    // Expected: MUST detect SOQL_IN_LOOP
    // Note: This is only for detection testing, not a real-world trigger pattern.
    // ------------------------------
    /*
    for (HS_Test__c t : Trigger.new) {
        Database.QueryLocator ql = Database.getQueryLocator('SELECT Id FROM Account');
        if (ql != null) {
            t.Name = 'BAD4-QL';
        }
    }
    */

    // ------------------------------
    // D5) BAD: No-brace loop, single statement pattern
    // Expected: MUST detect SOQL_IN_LOOP
    // ------------------------------
    /*
    for (HS_Test__c t : Trigger.new)
        t.Name = [SELECT Name FROM Account LIMIT 1].Name;
    */

    // ------------------------------
    // D6) BAD: Nested loops (bulk scenario)
    // Expected: MUST detect SOQL_IN_LOOP
    // ------------------------------
    /*
    for (HS_Test__c outerRec : Trigger.new) {
        for (Integer i = 0; i < 2; i++) {
            List<Account> accs = [SELECT Id FROM Account LIMIT 1];
            if (!accs.isEmpty()) {
                outerRec.Name = 'BAD6-' + i;
            }
        }
    }
    */

}
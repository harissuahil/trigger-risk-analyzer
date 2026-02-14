trigger TRA_LargeTrigger_NoHandler_Test on HS_Test__c (before insert, before update, after update) {

    // Collect record Ids for after-update logic
    Set<Id> recordIds = new Set<Id>();
    for (HS_Test__c r : Trigger.new) {
        if (r.Id != null) {
            recordIds.add(r.Id);
        }
    }

    // BEFORE logic: normalize data and apply simple business rules
    if (Trigger.isBefore) {
        for (HS_Test__c r : Trigger.new) {

            // Normalize Name
            if (r.Name != null) {
                r.Name = r.Name.trim();
            }

            // Apply default name if missing
            if (Trigger.isInsert && String.isBlank(r.Name)) {
                r.Name = 'AUTO-' + String.valueOf(System.now().getTime());
            }

            // Simple validation-style logic
            if (r.Name != null && r.Name.length() > 80) {
                r.Name = r.Name.substring(0, 80);
            }
        }
    }

    // AFTER UPDATE logic: query children and touch them
    if (Trigger.isAfter && Trigger.isUpdate) {
        if (recordIds.isEmpty()) return;

        List<HS_Test_Child__c> children = [
            SELECT Id, Parent__c, Name
            FROM HS_Test_Child__c
            WHERE Parent__c IN :recordIds
            LIMIT 200
        ];

        if (!children.isEmpty()) {
            for (HS_Test_Child__c c : children) {
                // No-op update to simulate business processing
                c.Name = c.Name;
            }
            update children;
        }
    }
}
public with sharing class TRA_RecursionRisk_Good_Handler {
    private static Set<Id> processed = new Set<Id>();

    public static void runAfterUpdate(List<HS_Test__c> newList, Map<Id, HS_Test__c> newMap) {
        if (newList == null || newList.isEmpty()) return;

        List<HS_Test__c> toUpdate = new List<HS_Test__c>();

        for (HS_Test__c r : newList) {
            if (r == null || r.Id == null) continue;
            if (processed.contains(r.Id)) continue;

            // Only update if needed (prevents unnecessary DML + re-firing)
            if (r.TRA_Flag__c == true) continue;

            processed.add(r.Id);

            HS_Test__c upd = new HS_Test__c(
                Id = r.Id,
                TRA_Flag__c = true
            );
            toUpdate.add(upd);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
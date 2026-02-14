public class TRA_LargeTrigger_Handler_Good_Handler {

    //==========REGRESSION FIXED VERSION - Recursion guard using Set<Id>==========
    private static Set<Id> processedAfterUpdateIds = new Set<Id>();
    //==========END REGRESSION FIXED VERSION==========

    public static void handleBefore(List<HS_Test__c> records) {
        if (records == null || records.isEmpty()) return;

        //==========REGRESSION FIXED VERSION - BEFORE logic (field assignment only)==========
        for (HS_Test__c r : records) {

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
        //==========END REGRESSION FIXED VERSION==========
    }

    public static void handleAfterUpdate(List<HS_Test__c> records) {
        if (records == null || records.isEmpty()) return;

        //==========REGRESSION FIXED VERSION - Collect IDs in AFTER (no DML here)==========
        Set<Id> recordIds = new Set<Id>();
        for (HS_Test__c r : records) {
            if (r.Id != null) {
                recordIds.add(r.Id);
            }
        }
        if (recordIds.isEmpty()) return;

        // Recursion guard: only process Ids we haven’t processed in this transaction
        recordIds.removeAll(processedAfterUpdateIds);
        if (recordIds.isEmpty()) return;

        processedAfterUpdateIds.addAll(recordIds);

        System.enqueueJob(new TRA_LargeTrigger_Handler_Good_Queueable(recordIds));
        //==========END REGRESSION FIXED VERSION==========
    }
}
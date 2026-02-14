public class TRA_MixedDml_Good_Handler {

    public static void handleAfterInsert(List<HS_Test__c> records) {
        Set<Id> recordIds = new Set<Id>();
        for (HS_Test__c r : records) {
            recordIds.add(r.Id);
        }

        if (!recordIds.isEmpty()) {
            System.enqueueJob(new TRA_MixedDml_Good_Queueable(recordIds));
        }
    }
}
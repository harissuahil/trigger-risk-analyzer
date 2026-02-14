public with sharing class TRA_RecurGuardNotStaticTrapHandler {

    // This is intentionally NOT static.
    // It resets every trigger execution because a new handler instance is created each time.
    private Boolean hasRun = false;

    public void run(List<HS_Test_Child__c> newList) {
        if (hasRun) return;
        hasRun = true;

        List<HS_Test_Child__c> ups = new List<HS_Test_Child__c>();

        for (HS_Test_Child__c r : newList) {
            if (r.Name != null && !r.Name.contains('[R1]')) {
                HS_Test_Child__c u = new HS_Test_Child__c(
                    Id = r.Id,
                    Name = r.Name + ' [R1]'
                );
                ups.add(u);
            }
        }

        if (!ups.isEmpty()) {
            update ups;
        }
    }
}
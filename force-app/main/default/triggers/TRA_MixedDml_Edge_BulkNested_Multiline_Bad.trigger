trigger TRA_MixedDml_Edge_BulkNested_Multiline_Bad on HS_Test__c (after insert) {

    // Bulk-safe collections
    List<HS_Test__c> recordsToUpdate = new List<HS_Test__c>();
    List<PermissionSetAssignment> psasToInsert = new List<PermissionSetAssignment>();

    for (HS_Test__c rec : Trigger.new) {

        // Nested logic on purpose
        if (rec != null) {
            if (rec.Name != null) {

                // Non-setup object DML preparation
                HS_Test__c upd = new HS_Test__c(
                    Id = rec.Id,
                    Name = rec.Name + ' - updated'
                );
                recordsToUpdate.add(upd);

                // Setup object preparation (PermissionSetAssignment)
                PermissionSetAssignment psa = new PermissionSetAssignment();
                psa.AssigneeId =
                    UserInfo.getUserId();
                psa.PermissionSetId =
                    '0PS000000000000AAA'; // replace with valid PS Id if you want runtime success
                psasToInsert.add(psa);
            }
        }
    }

    // DML outside loop (bulk safe)
    if (!recordsToUpdate.isEmpty()) {
        update
            recordsToUpdate;
    }

    if (!psasToInsert.isEmpty()) {
        insert
            psasToInsert;
    }
}
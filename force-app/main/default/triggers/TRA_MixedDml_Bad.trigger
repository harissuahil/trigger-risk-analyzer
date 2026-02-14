trigger TRA_MixedDml_Bad on HS_Test__c (after insert) {
    update Trigger.new;

    PermissionSetAssignment psa = new PermissionSetAssignment();
    psa.AssigneeId = UserInfo.getUserId();
    psa.PermissionSetId = '0PS000000000000'; // dummy id; this trigger is for static analysis only
    insert psa;
}
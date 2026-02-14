trigger TRA_MixedDml_StringOnly_Trap on HS_Test__c (after insert) {

    // The lines below are ONLY strings.
    // They should NOT be detected if string masking is working.

    String s1 = 'insert User u;';
    String s2 = 'update User u;';
    String s3 = 'delete User u;';
    String s4 = 'insert PermissionSetAssignment psa;';
    String s5 = 'update PermissionSetAssignment psa;';
    String s6 = 'insert UserRole ur;';

    // Prevent unused-variable warnings
    Integer totalLen = (s1 + s2 + s3 + s4 + s5 + s6).length();
    if (totalLen < 0) {
        System.debug('Never executed');
    }
}
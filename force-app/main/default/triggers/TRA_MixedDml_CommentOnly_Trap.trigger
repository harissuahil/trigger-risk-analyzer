trigger TRA_MixedDml_CommentOnly_Trap on HS_Test__c (after insert) {

    // The lines below are ONLY comments.
    // They should NOT be detected if comment masking is working.

    // insert new User(
    //     LastName = 'Trap',
    //     Alias = 'trap',
    //     Email = 'trap@example.com',
    //     Username = 'trap' + DateTime.now().getTime() + '@example.com',
    //     TimeZoneSidKey = 'America/Chicago',
    //     LocaleSidKey = 'en_US',
    //     EmailEncodingKey = 'UTF-8',
    //     LanguageLocaleKey = 'en_US',
    //     ProfileId = '00e000000000000AAA'
    // );

    // List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
    // insert psas;

    // update new User(Id = '005000000000000AAA');

}
trigger TRA_DmlInBeforeTrigger_Bad on Account (before update) {
    // Intentionally bad for this rule: DML inside BEFORE trigger
    insert new Contact(LastName = 'Test');
}
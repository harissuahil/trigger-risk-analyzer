trigger TRA_DmlInBeforeTrigger_Good on Account (before update) {
    // Good: update fields directly on Trigger.new without running DML
    for (Account a : Trigger.new) {
        a.Description = 'Updated in before trigger without DML';
    }
}
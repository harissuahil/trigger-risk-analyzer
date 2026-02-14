trigger TRA_DmlInAfterTrigger_WithBeforeWord_Trap on Account (after update) {

    // The word "before" is intentionally in this comment to test false positives.
    // before before before

    // DML is also intentional, but this is AFTER trigger, not BEFORE.
    insert new Contact(LastName = 'Trap');
}
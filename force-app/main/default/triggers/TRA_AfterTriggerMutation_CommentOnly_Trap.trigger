// TRA_AfterTriggerMutation_CommentOnly_Trap.trigger
trigger TRA_AfterTriggerMutation_CommentOnly_Trap on HS_Test__c (after update) {

    // TRAP 1 (comment): looks like AFTER Trigger.new mutation, but it is ONLY a comment
    // Trigger.new[0].Name = 'SHOULD_NOT_BE_DETECTED';

    // TRAP 2 (string): looks like AFTER Trigger.new mutation, but it is ONLY a string
    String trap = 'Trigger.new[0].Name = \'SHOULD_NOT_BE_DETECTED\';';

    // Do nothing else on purpose.
}
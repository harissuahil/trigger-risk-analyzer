trigger TRA_RecursionRisk_CommentOnly_Trap on HS_Test__c (after update) {
    // update Trigger.new;  // comment-only trap, must NOT be detected as real DML
}
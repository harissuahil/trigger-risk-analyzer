trigger TRA_DmlInLoop_CommentOnly_Trap on HS_Test__c (after update) {
    for (HS_Test__c r : Trigger.new) {
        // update r; // comment-only, must NOT be detected
    }
}
trigger TRA_HardcodedId_CommentOnly_Trap on HS_Test__c (before insert) {
    // 001000000000000AAA  (comment only, should ideally NOT be flagged)
}
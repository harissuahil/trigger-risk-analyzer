trigger TRA_SoqlInLoop_CommentOnly_Trap on Account (before insert) {
    for (Account a : Trigger.new) {

        // Trap: SOQL text inside a comment (must NOT be detected)
        // [SELECT Id FROM Account]

        /* Trap: Database.query text inside a block comment (must NOT be detected)
           Database.query('SELECT Id FROM Account');
        */

        a.Description = 'comment trap';
    }
}
trigger TRA_UpdateTriggerNew_CommentOnly_Trap on HS_Test__c (after insert) { //HS
    for (HS_Test__c r : Trigger.new) { //HS
        // update Trigger.new; //HS
        System.debug('comment-only trap'); //HS
    } //HS
} //HS
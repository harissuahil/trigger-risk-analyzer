trigger TRA_HardcodedId_Good on HS_Test__c (before insert) {
    Id currentUserId = UserInfo.getUserId(); // not hardcoded
}
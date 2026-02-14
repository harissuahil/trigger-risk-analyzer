public with sharing class HS_CleanTriggerHandler {
    public static void run(
        List<Account> newList,
        Map<Id, Account> oldMap,
        Boolean isInsert,
        Boolean isUpdate
    ) {
        // Clean test: no business logic on purpose
        // (Keeps handler pattern without introducing risk)
    }
}
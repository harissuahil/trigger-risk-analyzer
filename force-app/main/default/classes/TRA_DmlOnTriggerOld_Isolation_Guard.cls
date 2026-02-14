public with sharing class TRA_DmlOnTriggerOld_Isolation_Guard {

    // Static variables reset each transaction, so this works as a per-transaction recursion guard.
    private static Boolean alreadyRan = false;

    public static Boolean hasAlreadyRun() {
        if (alreadyRan) {
            return true;
        }
        alreadyRan = true;
        return false;
    }
}
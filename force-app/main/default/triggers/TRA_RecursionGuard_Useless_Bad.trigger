trigger TRA_RecursionGuard_Useless_Bad on Account (after update) {
    Boolean hasRun = false;
    if (hasRun) return;
    hasRun = true;

    update Trigger.new;
}
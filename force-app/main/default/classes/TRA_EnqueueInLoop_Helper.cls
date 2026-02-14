public class TRA_EnqueueInLoop_Helper { //HS
    public static void enqueueOne(Id recordId) { //HS
        System.enqueueJob(new TRA_EnqueueLoopQueueable(new List<Id>{ recordId })); //HS
    } //HS
} //HS
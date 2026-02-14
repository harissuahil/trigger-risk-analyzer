public class TRA_EnqueueLoopQueueable implements Queueable { //HS
    private List<Id> ids; //HS

    public TRA_EnqueueLoopQueueable(List<Id> ids) { //HS
        this.ids = (ids == null) ? new List<Id>() : ids; //HS
    } //HS

    public void execute(QueueableContext qc) { //HS
        //HS No-op for TRA testing
        System.debug('TRA_EnqueueLoopQueueable ids=' + ids); //HS
    } //HS
} //HS
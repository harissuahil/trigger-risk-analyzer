public class TRA_MixedDml_Good_Queueable implements Queueable {

    private Set<Id> recordIds;

    public TRA_MixedDml_Good_Queueable(Set<Id> recordIds) {
        this.recordIds = recordIds;
    }

    public void execute(QueueableContext context) {

        // Example setup-object DML (safe here)
        List<User> usersToUpdate = [
            SELECT Id, IsActive
            FROM User
            WHERE IsActive = true
            LIMIT 1
        ];

        if (!usersToUpdate.isEmpty()) {
            usersToUpdate[0].IsActive = usersToUpdate[0].IsActive;
            update usersToUpdate;
        }
    }
}
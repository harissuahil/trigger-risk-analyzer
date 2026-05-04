public class TRA_LargeTrigger_Handler_Good_Queueable implements Queueable {
  private Set<Id> parentIds;

  public TRA_LargeTrigger_Handler_Good_Queueable(Set<Id> parentIds) {
    this.parentIds = parentIds;
  }

  public void execute(QueueableContext context) {
    if (parentIds == null || parentIds.isEmpty())
      return;

    List<HS_Test_Child__c> children = [
      SELECT Id, Parent__c, Name
      FROM HS_Test_Child__c
      WHERE Parent__c IN :parentIds
      LIMIT 200
    ];

    if (!children.isEmpty()) {
      for (HS_Test_Child__c c : children) {
        // No-op update to simulate business processing
        c.Name = c.Name;
      }
      update children;
    }
  }
}

// CLASS: DeploymentAnalysisService
public with sharing class DeploymentAnalysisService {
  // Existing: analyze ALL triggers
  public static Id startRun(String releaseLabel) {
    Deployment_Analysis_Run__c runRec = new Deployment_Analysis_Run__c();
    runRec.Status__c = 'Running';
    runRec.Release_Label__c = releaseLabel;
    runRec.Started_At__c = System.now();
    insert runRec;

    System.enqueueJob(new DeploymentAnalysisJob(runRec.Id, null));
    return runRec.Id;
  }

  // New: analyze ONLY selected triggers
  public static Id startRunForTriggers(
    String releaseLabel,
    List<String> triggerNames
  ) {
    Deployment_Analysis_Run__c runRec = new Deployment_Analysis_Run__c();
    runRec.Status__c = 'Running';
    runRec.Release_Label__c = releaseLabel;
    runRec.Started_At__c = System.now();
    insert runRec;

    System.enqueueJob(new DeploymentAnalysisJob(runRec.Id, triggerNames));
    return runRec.Id;
  }
}

/******************************************************************************************************
 * Release decision engine for Trigger Risk Analyzer.
 *
 * Responsibilities:
 * - Convert detected rule counts and severity counts into a release decision.
 * - Return manager-readable rationale, required fixes, top risks, and architect impacts.
 * - Keep release gate decisions deterministic and explainable.
 *
 * Keep this class focused on business release risk.
 * Detection logic belongs in TriggerRiskEngine, and run orchestration belongs in DeploymentAnalysisJob.
 *******************************************************************************************************/
public with sharing class ReleaseGateEngine {
  public class GateResult {
    public String decision; // APPROVED / APPROVED_WITH_CONDITIONS / BLOCKED
    public String recommendation; // PROCEED / PROCEED WITH CAUTION / NOT RECOMMENDED
    public List<String> rationale; // short bullets
    public List<String> requiredFixes; // only for BLOCKED
    public List<String> topRisks; // short bullets
    public List<String> architectImpacts; // labels
    public String policyProfile; // Standard
    public String gateVersion; // 7.0.1
  }

  // Public entry point
  public static GateResult evaluate(
    Map<String, Integer> ruleKeyCounts,
    Integer highCount,
    Integer mediumCount,
    Integer lowCount
  ) {
    GateResult out = new GateResult();
    out.policyProfile = 'Standard';
    out.gateVersion = '7.0.1';
    out.rationale = new List<String>();
    out.requiredFixes = new List<String>();
    out.topRisks = new List<String>();
    out.architectImpacts = new List<String>();

    Set<String> keys = (ruleKeyCounts == null)
      ? new Set<String>()
      : new Set<String>(ruleKeyCounts.keySet());

    // ---- Decision (deterministic, explainable) ----
    Boolean hasBlocked = hasAny(
      keys,
      new Set<String>{
        'SOQL_IN_LOOP',
        'DML_IN_LOOP',
        'MIXED_DML',
        'CALLOUT_IN_TRIGGER',
        'DML_IN_BEFORE_TRIGGER',
        'ENQUEUE_IN_LOOP',
        'DML_ON_TRIGGER_OLD'
      }
    );

    // Recursion blocks only when High-risk signals exist
    if (keys.contains('CROSS_TRIGGER_RECURSION_CYCLE'))
      hasBlocked = true;
    if (keys.contains('RECURSION_RISK') && (highCount != null && highCount > 0))
      hasBlocked = true;

    Boolean hasConditions = hasAny(
      keys,
      new Set<String>{
        'MULTIPLE_TRIGGERS_SAME_OBJECT',
        'AFTER_TRIGGER_MUTATION',
        'TRIGGER_HANDLER_MISSING',
        'EMAIL_IN_TRIGGER'
      }
    );

    // Volume-based condition (keeps it sensible)
    if (!hasBlocked && (mediumCount != null && mediumCount >= 3)) {
      hasConditions = true;
    }

    if (hasBlocked) {
      out.decision = 'BLOCKED';
      out.recommendation = 'NOT RECOMMENDED';
    } else if (hasConditions) {
      out.decision = 'APPROVED_WITH_CONDITIONS';
      out.recommendation = 'PROCEED WITH CAUTION';
    } else {
      out.decision = 'APPROVED';
      out.recommendation = 'PROCEED';
    }

    // ---- Architect Impacts ----
    if (
      keys.contains('MULTIPLE_TRIGGERS_SAME_OBJECT') ||
      keys.contains('AFTER_TRIGGER_MUTATION')
    ) {
      out.architectImpacts.add('Order-of-Execution Risk');
    }
    if (keys.contains('TRIGGER_HANDLER_MISSING')) {
      out.architectImpacts.add('Operational Maintainability Risk');
    }
    if (keys.contains('SOQL_IN_LOOP') || keys.contains('DML_IN_LOOP')) {
      out.architectImpacts.add('Bulk/Limit Risk');
    }
    if (
      keys.contains('RECURSION_RISK') ||
      keys.contains('CROSS_TRIGGER_RECURSION_CYCLE')
    ) {
      out.architectImpacts.add('Reliability/Recursion Risk');
    }
    if (keys.contains('MIXED_DML') || keys.contains('DML_ON_TRIGGER_OLD')) {
      out.architectImpacts.add('Transaction Safety Risk');
    }
    if (keys.contains('CALLOUT_IN_TRIGGER')) {
      out.architectImpacts.add('Integration Risk');
    }
    if (keys.contains('EMAIL_IN_TRIGGER')) {
      out.architectImpacts.add('Operational Reliability Risk');
    }
    if (keys.contains('ENQUEUE_IN_LOOP')) {
      out.architectImpacts.add('Async Limit Risk');
    }

    // Build key -> message map (include HARDCODED_ID, which was missing from rationale).
    Map<String, String> msgByKey = new Map<String, String>();
    if (keys.contains('SOQL_IN_LOOP'))
      msgByKey.put(
        'SOQL_IN_LOOP',
        'SOQL inside loops can exceed governor limits under bulk load.'
      );
    if (keys.contains('DML_IN_LOOP'))
      msgByKey.put(
        'DML_IN_LOOP',
        'DML inside loops can fail under bulk load due to governor limits.'
      );
    if (keys.contains('CROSS_TRIGGER_RECURSION_CYCLE'))
      msgByKey.put(
        'CROSS_TRIGGER_RECURSION_CYCLE',
        'Cross-trigger recursion risk can cause repeated execution and instability.'
      );
    if (keys.contains('RECURSION_RISK'))
      msgByKey.put(
        'RECURSION_RISK',
        'Recursion risk detected; triggers may re-run unexpectedly and create instability.'
      );
    if (keys.contains('DML_IN_BEFORE_TRIGGER'))
      msgByKey.put(
        'DML_IN_BEFORE_TRIGGER',
        'DML in BEFORE triggers increases recursion risk and makes execution behavior harder to predict.'
      );
    if (keys.contains('DML_ON_TRIGGER_OLD'))
      msgByKey.put(
        'DML_ON_TRIGGER_OLD',
        'DML on Trigger.old is not allowed and will fail at runtime. Use a separate list of records instead.'
      );
    if (keys.contains('MIXED_DML'))
      msgByKey.put(
        'MIXED_DML',
        'Mixed DML can cause runtime failures when setup and business objects are changed together.'
      );
    if (keys.contains('CALLOUT_IN_TRIGGER'))
      msgByKey.put(
        'CALLOUT_IN_TRIGGER',
        'Callouts in triggers create reliability risks and can block transactions.'
      );
    if (keys.contains('EMAIL_IN_TRIGGER'))
      msgByKey.put(
        'EMAIL_IN_TRIGGER',
        'Email send detected inside a trigger can hit limits and reduce reliability under bulk load.'
      );
    if (keys.contains('MULTIPLE_TRIGGERS_SAME_OBJECT'))
      msgByKey.put(
        'MULTIPLE_TRIGGERS_SAME_OBJECT',
        'Multiple triggers on the same object may cause unpredictable execution order.'
      );
    if (keys.contains('AFTER_TRIGGER_MUTATION'))
      msgByKey.put(
        'AFTER_TRIGGER_MUTATION',
        'Updating Trigger.new in AFTER triggers may cause inconsistent behavior.'
      );
    if (keys.contains('TRIGGER_HANDLER_MISSING'))
      msgByKey.put(
        'TRIGGER_HANDLER_MISSING',
        'Trigger logic is not centralized in a handler, increasing maintenance and change risk.'
      );
    if (keys.contains('HARDCODED_ID'))
      msgByKey.put(
        'HARDCODED_ID',
        'Hardcoded Ids increase environment migration risk and reduce reliability.'
      );
    if (keys.contains('ENQUEUE_IN_LOOP'))
      msgByKey.put(
        'ENQUEUE_IN_LOOP',
        'Queueable enqueued inside a loop is not allowed and will fail at runtime.'
      );

    // Pull severities from metadata when available.
    Map<String, Integer> sevRankByKey = new Map<String, Integer>();
    if (!msgByKey.isEmpty()) {
      for (Trigger_Risk_Rule__mdt r : [
        SELECT Rule_Key__c, Severity__c
        FROM Trigger_Risk_Rule__mdt
        WHERE Rule_Key__c IN :msgByKey.keySet()
      ]) {
        sevRankByKey.put(r.Rule_Key__c, severityRank(r.Severity__c));
      }
    }

    // Fallback severities for engine-only keys that might not exist in metadata.
    if (
      keys.contains('MULTIPLE_TRIGGERS_SAME_OBJECT') &&
      !sevRankByKey.containsKey('MULTIPLE_TRIGGERS_SAME_OBJECT')
    )
      sevRankByKey.put('MULTIPLE_TRIGGERS_SAME_OBJECT', 2);
    if (
      keys.contains('AFTER_TRIGGER_MUTATION') &&
      !sevRankByKey.containsKey('AFTER_TRIGGER_MUTATION')
    )
      sevRankByKey.put('AFTER_TRIGGER_MUTATION', 2);
    if (
      keys.contains('TRIGGER_HANDLER_MISSING') &&
      !sevRankByKey.containsKey('TRIGGER_HANDLER_MISSING')
    )
      sevRankByKey.put('TRIGGER_HANDLER_MISSING', 1);

    // Importance tie-breaker (lower number = more important).
    Map<String, Integer> importance = new Map<String, Integer>{
      'CROSS_TRIGGER_RECURSION_CYCLE' => 1,
      'RECURSION_RISK' => 2,
      'SOQL_IN_LOOP' => 3,
      'DML_IN_LOOP' => 4,
      'MIXED_DML' => 5,
      'DML_ON_TRIGGER_OLD' => 6,
      'CALLOUT_IN_TRIGGER' => 7,
      'ENQUEUE_IN_LOOP' => 8,
      'DML_IN_BEFORE_TRIGGER' => 9,
      'AFTER_TRIGGER_MUTATION' => 10,
      'MULTIPLE_TRIGGERS_SAME_OBJECT' => 11,
      'EMAIL_IN_TRIGGER' => 12,
      'HARDCODED_ID' => 20,
      'TRIGGER_HANDLER_MISSING' => 30
    };

    List<String> orderedKeys = new List<String>();
    orderedKeys.addAll(msgByKey.keySet());
    orderedKeys.sort(new RiskKeyComparator(sevRankByKey, importance));

    // Top Risks: always top 3 ranked.
    out.topRisks.clear();
    for (Integer i = 0; i < Math.min(3, orderedKeys.size()); i++) {
      out.topRisks.add(msgByKey.get(orderedKeys[i]));
    }

    // Rationale: decision-driven, not forced to 3.
    out.rationale.clear();
    Integer maxWhy = (out.decision == 'BLOCKED') ? 5 : 5;

    if (out.decision == 'BLOCKED') {
      // Show the most important High reasons.
      for (String k : orderedKeys) {
        Integer sr = sevRankByKey.containsKey(k) ? sevRankByKey.get(k) : 0;
        if (sr == 3)
          out.rationale.add(msgByKey.get(k));
        if (out.rationale.size() >= maxWhy)
          break;
      }
      // Safety fallback: if none were marked High, explain using top items.
      if (out.rationale.isEmpty()) {
        for (Integer i = 0; i < Math.min(3, orderedKeys.size()); i++)
          out.rationale.add(msgByKey.get(orderedKeys[i]));
      }
    } else if (out.decision == 'APPROVED_WITH_CONDITIONS') {
      // Show the most important Medium reasons.
      for (String k : orderedKeys) {
        Integer sr = sevRankByKey.containsKey(k) ? sevRankByKey.get(k) : 0;
        if (sr == 2)
          out.rationale.add(msgByKey.get(k));
        if (out.rationale.size() >= maxWhy)
          break;
      }
      // If no Medium exists, show up to 2 structural Low reasons (avoid noise).
      if (out.rationale.isEmpty()) {
        Integer addedLow = 0;
        for (String k : orderedKeys) {
          Integer sr = sevRankByKey.containsKey(k) ? sevRankByKey.get(k) : 0;
          if (sr == 1 && (k == 'TRIGGER_HANDLER_MISSING')) {
            out.rationale.add(msgByKey.get(k));
            addedLow++;
            if (addedLow >= 2)
              break;
          }
        }
      }
    } else {
      // Approved should feel clean and confident.
      if (orderedKeys.isEmpty()) {
        out.rationale.add(
          'No significant risks detected that would affect deployment.'
        );
      }
    }

    // clamp to max 3 for "required fixes" to stay executive-friendly
    // Apex does not support List.subList(), so trim manually

    if (out.requiredFixes.size() > 3) {
      List<String> trimmed = new List<String>();
      for (Integer i = 0; i < 3; i++) {
        trimmed.add(out.requiredFixes[i]);
      }
      out.requiredFixes = trimmed;
    }

    /* if (out.rationale.size() > 3) {
                List<String> trimmed = new List<String>();
                for (Integer i = 0; i < 3; i++) {
                    trimmed.add(out.rationale[i]);
                }
                out.rationale = trimmed;
            } */

    return out;
  }

  private static Boolean hasAny(Set<String> keys, Set<String> targets) {
    if (keys == null || keys.isEmpty())
      return false;
    for (String t : targets) {
      if (keys.contains(t))
        return true;
    }
    return false;
  }

  private static void addIfPresent(
    Set<String> keys,
    List<String> out,
    String key,
    String msg
  ) {
    if (keys != null && keys.contains(key) && out != null && out.size() < 10) {
      out.add(msg);
    }
  }

  private static Integer severityRank(String sev) {
    if (String.isBlank(sev))
      return 0;
    String s = sev.trim().toLowerCase();
    if (s == 'high')
      return 3;
    if (s == 'medium')
      return 2;
    if (s == 'low')
      return 1;
    return 0;
  }

  private class RiskKeyComparator implements Comparator<String> {
    private Map<String, Integer> sevRank;
    private Map<String, Integer> importance;

    public RiskKeyComparator(
      Map<String, Integer> sevRankByKey,
      Map<String, Integer> importanceByKey
    ) {
      this.sevRank = (sevRankByKey == null)
        ? new Map<String, Integer>()
        : sevRankByKey;
      this.importance = (importanceByKey == null)
        ? new Map<String, Integer>()
        : importanceByKey;
    }

    public Integer compare(String a, String b) {
      Integer sa = sevRank.containsKey(a) ? sevRank.get(a) : 0;
      Integer sb = sevRank.containsKey(b) ? sevRank.get(b) : 0;
      if (sa != sb)
        return (sb - sa); // higher severity first

      Integer ia = importance.containsKey(a) ? importance.get(a) : 999;
      Integer ib = importance.containsKey(b) ? importance.get(b) : 999;
      if (ia != ib)
        return (ia - ib); // lower importance number first

      return String.valueOf(a).compareTo(String.valueOf(b)); // stable tie-breaker
    }
  }
}

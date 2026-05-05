@isTest
private class ReleaseGateEngineTest {
  // ============================================================
  // BLOCKED decisions
  // ============================================================

  @isTest
  static void evaluate_soqlInLoop_shouldBeBlocked() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>{ 'SOQL_IN_LOOP' => 1 },
      1,
      0,
      0
    );

    System.assertEquals(
      'BLOCKED',
      r.decision,
      'SOQL_IN_LOOP should produce BLOCKED'
    );
    System.assertEquals(
      'NOT RECOMMENDED',
      r.recommendation,
      'BLOCKED should have NOT RECOMMENDED recommendation'
    );
  }

  @isTest
  static void evaluate_dmlInLoop_shouldBeBlocked() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>{ 'DML_IN_LOOP' => 1 },
      1,
      0,
      0
    );

    System.assertEquals(
      'BLOCKED',
      r.decision,
      'DML_IN_LOOP should produce BLOCKED'
    );
  }

  @isTest
  static void evaluate_calloutInTrigger_shouldBeBlocked() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>{ 'CALLOUT_IN_TRIGGER' => 1 },
      1,
      0,
      0
    );

    System.assertEquals(
      'BLOCKED',
      r.decision,
      'CALLOUT_IN_TRIGGER should produce BLOCKED'
    );
  }

  @isTest
  static void evaluate_mixedDml_shouldBeBlocked() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>{ 'MIXED_DML' => 1 },
      1,
      0,
      0
    );

    System.assertEquals(
      'BLOCKED',
      r.decision,
      'MIXED_DML should produce BLOCKED'
    );
  }

  @isTest
  static void evaluate_crossTriggerRecursion_shouldBeBlocked() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>{ 'CROSS_TRIGGER_RECURSION_CYCLE' => 1 },
      1,
      0,
      0
    );

    System.assertEquals(
      'BLOCKED',
      r.decision,
      'CROSS_TRIGGER_RECURSION_CYCLE should produce BLOCKED'
    );
  }

  // ============================================================
  // APPROVED_WITH_CONDITIONS decisions
  // ============================================================

  @isTest
  static void evaluate_emailInTrigger_shouldBeApprovedWithConditions() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>{ 'EMAIL_IN_TRIGGER' => 1 },
      0,
      1,
      0
    );

    System.assertEquals(
      'APPROVED_WITH_CONDITIONS',
      r.decision,
      'EMAIL_IN_TRIGGER should produce APPROVED_WITH_CONDITIONS'
    );
    System.assertEquals(
      'PROCEED WITH CAUTION',
      r.recommendation,
      'APPROVED_WITH_CONDITIONS should have PROCEED WITH CAUTION recommendation'
    );
  }

  @isTest
  static void evaluate_triggerHandlerMissing_shouldBeApprovedWithConditions() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>{ 'TRIGGER_HANDLER_MISSING' => 1 },
      0,
      1,
      0
    );

    System.assertEquals(
      'APPROVED_WITH_CONDITIONS',
      r.decision,
      'TRIGGER_HANDLER_MISSING should produce APPROVED_WITH_CONDITIONS'
    );
  }

  @isTest
  static void evaluate_threeMediumFindings_shouldBeApprovedWithConditions() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>(),
      0,
      3,
      0
    );

    System.assertEquals(
      'APPROVED_WITH_CONDITIONS',
      r.decision,
      'Three medium findings should produce APPROVED_WITH_CONDITIONS'
    );
  }

  // ============================================================
  // APPROVED decisions
  // ============================================================

  @isTest
  static void evaluate_noFindings_shouldBeApproved() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>(),
      0,
      0,
      0
    );

    System.assertEquals(
      'APPROVED',
      r.decision,
      'No findings should produce APPROVED'
    );
    System.assertEquals(
      'PROCEED',
      r.recommendation,
      'APPROVED should have PROCEED recommendation'
    );
  }

  @isTest
  static void evaluate_lowFindingsOnly_shouldBeApproved() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>{ 'HARDCODED_ID' => 1 },
      0,
      0,
      1
    );

    System.assertEquals(
      'APPROVED',
      r.decision,
      'Low severity findings only should produce APPROVED'
    );
  }

  // ============================================================
  // Gate metadata
  // ============================================================

  @isTest
  static void evaluate_policyAndVersion_shouldBePopulated() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>(),
      0,
      0,
      0
    );

    System.assertEquals(
      'Standard',
      r.policyProfile,
      'Policy profile should be Standard'
    );
    System.assertEquals('7.0.1', r.gateVersion, 'Gate version should be 7.0.1');
  }

  // ============================================================
  // architectImpacts population
  //
  // SOURCE — ReleaseGateEngine.evaluate() lines ~93–124:
  //   if (keys.contains('SOQL_IN_LOOP') || keys.contains('DML_IN_LOOP'))
  //       out.architectImpacts.add('Bulk/Limit Risk');
  //   if (keys.contains('CALLOUT_IN_TRIGGER'))
  //       out.architectImpacts.add('Integration Risk');
  //   ... (and several others)
  //
  // architectImpacts feeds the LWC impact chips. It's populated via
  // static keys.contains() checks, so this test does not depend on
  // CMDT severity data — making it robust across orgs.
  // ============================================================
  @isTest
  static void evaluate_blocked_architectImpacts_includesBulkAndIntegrationRisk() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>{
        'SOQL_IN_LOOP' => 1,
        'CALLOUT_IN_TRIGGER' => 1
      },
      2,
      0,
      0
    );

    System.assertEquals(
      'BLOCKED',
      r.decision,
      'SOQL+CALLOUT should produce BLOCKED'
    );
    System.assertNotEquals(
      null,
      r.architectImpacts,
      'architectImpacts must not be null'
    );

    Set<String> impacts = new Set<String>(r.architectImpacts);
    System.assert(
      impacts.contains('Bulk/Limit Risk'),
      'SOQL_IN_LOOP must produce Bulk/Limit Risk; actual: ' + r.architectImpacts
    );
    System.assert(
      impacts.contains('Integration Risk'),
      'CALLOUT_IN_TRIGGER must produce Integration Risk; actual: ' +
      r.architectImpacts
    );
  }

  // ============================================================
  // topRisks ordering
  //
  // SOURCE — ReleaseGateEngine.evaluate():
  //   orderedKeys.sort(new RiskKeyComparator(sevRankByKey, importance));
  //   for (Integer i = 0; i < Math.min(3, orderedKeys.size()); i++)
  //       out.topRisks.add(msgByKey.get(orderedKeys[i]));
  //
  // Comparator: higher severity first, then lower importance number,
  // then name as tie-breaker. SOQL_IN_LOOP is High in CMDT (relied on
  // by existing decision tests in this org). TRIGGER_HANDLER_MISSING
  // is Low (either from CMDT or from the engine-only-keys fallback at
  // line ~217). Either way, SOQL must rank first.
  // ============================================================
  @isTest
  static void evaluate_topRisks_orderedBySeverityDesc() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>{
        'TRIGGER_HANDLER_MISSING' => 1,
        'SOQL_IN_LOOP' => 1
      },
      1,
      0,
      1
    );

    System.assertNotEquals(null, r.topRisks, 'topRisks must not be null');
    System.assertEquals(
      2,
      r.topRisks.size(),
      'topRisks should have one entry per rule key'
    );
    System.assert(
      r.topRisks[0].contains('SOQL'),
      'High-severity SOQL_IN_LOOP must rank before Low-severity ' +
        'TRIGGER_HANDLER_MISSING; actual first item: ' +
        r.topRisks[0]
    );
  }

  // ============================================================
  // APPROVED_WITH_CONDITIONS rationale — Low fallback path
  //
  // SOURCE — ReleaseGateEngine.evaluate() rationale block:
  //   } else if (out.decision == 'APPROVED_WITH_CONDITIONS') {
  //     for (String k : orderedKeys) { if (sr == 2) add(...) }   ← no Medium present
  //     if (out.rationale.isEmpty()) {                           ← fallback fires
  //       for (String k : orderedKeys) {
  //         if (sr == 1 && (k == 'TRIGGER_HANDLER_MISSING'))
  //           out.rationale.add(...);
  //       }
  //     }
  //   }
  //
  // This unique fallback path is exercised only when TRIGGER_HANDLER_MISSING
  // is the sole reason. No existing test covers it. The engine-only-keys
  // fallback guarantees TRIGGER_HANDLER_MISSING gets sr=1 if CMDT lacks it,
  // so this test is robust across orgs.
  // ============================================================
  @isTest
  static void evaluate_conditions_handlerMissingOnly_rationaleUsesLowFallback() {
    ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
      new Map<String, Integer>{ 'TRIGGER_HANDLER_MISSING' => 1 },
      0,
      0,
      1
    );

    System.assertEquals(
      'APPROVED_WITH_CONDITIONS',
      r.decision,
      'TRIGGER_HANDLER_MISSING alone should produce APPROVED_WITH_CONDITIONS'
    );
    System.assertNotEquals(null, r.rationale, 'rationale must not be null');
    System.assertEquals(
      1,
      r.rationale.size(),
      'Low fallback should add exactly one entry'
    );
    System.assert(
      r.rationale[0].contains('not centralized'),
      'rationale should contain the TRIGGER_HANDLER_MISSING message ' +
        '("Trigger logic is not centralized..."); actual: ' +
        r.rationale[0]
    );
  }
}

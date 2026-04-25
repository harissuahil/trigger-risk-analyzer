@isTest
private class ReleaseGateEngineTest {

    // ============================================================
    // BLOCKED decisions
    // ============================================================

    @isTest
    static void evaluate_soqlInLoop_shouldBeBlocked() {
        ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
            new Map<String, Integer>{ 'SOQL_IN_LOOP' => 1 }, 1, 0, 0);

        System.assertEquals('BLOCKED', r.decision,
            'SOQL_IN_LOOP should produce BLOCKED');
        System.assertEquals('NOT RECOMMENDED', r.recommendation,
            'BLOCKED should have NOT RECOMMENDED recommendation');
    }

    @isTest
    static void evaluate_dmlInLoop_shouldBeBlocked() {
        ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
            new Map<String, Integer>{ 'DML_IN_LOOP' => 1 }, 1, 0, 0);

        System.assertEquals('BLOCKED', r.decision,
            'DML_IN_LOOP should produce BLOCKED');
    }

    @isTest
    static void evaluate_calloutInTrigger_shouldBeBlocked() {
        ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
            new Map<String, Integer>{ 'CALLOUT_IN_TRIGGER' => 1 }, 1, 0, 0);

        System.assertEquals('BLOCKED', r.decision,
            'CALLOUT_IN_TRIGGER should produce BLOCKED');
    }

    @isTest
    static void evaluate_mixedDml_shouldBeBlocked() {
        ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
            new Map<String, Integer>{ 'MIXED_DML' => 1 }, 1, 0, 0);

        System.assertEquals('BLOCKED', r.decision,
            'MIXED_DML should produce BLOCKED');
    }

    @isTest
    static void evaluate_crossTriggerRecursion_shouldBeBlocked() {
        ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
            new Map<String, Integer>{ 'CROSS_TRIGGER_RECURSION_CYCLE' => 1 }, 1, 0, 0);

        System.assertEquals('BLOCKED', r.decision,
            'CROSS_TRIGGER_RECURSION_CYCLE should produce BLOCKED');
    }

    // ============================================================
    // APPROVED_WITH_CONDITIONS decisions
    // ============================================================

    @isTest
    static void evaluate_emailInTrigger_shouldBeApprovedWithConditions() {
        ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
            new Map<String, Integer>{ 'EMAIL_IN_TRIGGER' => 1 }, 0, 1, 0);

        System.assertEquals('APPROVED_WITH_CONDITIONS', r.decision,
            'EMAIL_IN_TRIGGER should produce APPROVED_WITH_CONDITIONS');
        System.assertEquals('PROCEED WITH CAUTION', r.recommendation,
            'APPROVED_WITH_CONDITIONS should have PROCEED WITH CAUTION recommendation');
    }

    @isTest
    static void evaluate_triggerHandlerMissing_shouldBeApprovedWithConditions() {
        ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
            new Map<String, Integer>{ 'TRIGGER_HANDLER_MISSING' => 1 }, 0, 1, 0);

        System.assertEquals('APPROVED_WITH_CONDITIONS', r.decision,
            'TRIGGER_HANDLER_MISSING should produce APPROVED_WITH_CONDITIONS');
    }

    @isTest
    static void evaluate_threeMediumFindings_shouldBeApprovedWithConditions() {
        ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
            new Map<String, Integer>(), 0, 3, 0);

        System.assertEquals('APPROVED_WITH_CONDITIONS', r.decision,
            'Three medium findings should produce APPROVED_WITH_CONDITIONS');
    }

    // ============================================================
    // APPROVED decisions
    // ============================================================

    @isTest
    static void evaluate_noFindings_shouldBeApproved() {
        ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
            new Map<String, Integer>(), 0, 0, 0);

        System.assertEquals('APPROVED', r.decision,
            'No findings should produce APPROVED');
        System.assertEquals('PROCEED', r.recommendation,
            'APPROVED should have PROCEED recommendation');
    }

    @isTest
    static void evaluate_lowFindingsOnly_shouldBeApproved() {
        ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
            new Map<String, Integer>{ 'HARDCODED_ID' => 1 }, 0, 0, 1);

        System.assertEquals('APPROVED', r.decision,
            'Low severity findings only should produce APPROVED');
    }

    // ============================================================
    // Gate metadata
    // ============================================================

    @isTest
    static void evaluate_policyAndVersion_shouldBePopulated() {
        ReleaseGateEngine.GateResult r = ReleaseGateEngine.evaluate(
            new Map<String, Integer>(), 0, 0, 0);

        System.assertEquals('Standard', r.policyProfile,
            'Policy profile should be Standard');
        System.assertEquals('7.0.1', r.gateVersion,
            'Gate version should be 7.0.1');
    }
}
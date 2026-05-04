/******************************************************************************************************
 * Core detection engine for Trigger Risk Analyzer.
 *
 * Responsibilities:
 * - Analyze Apex trigger source for deployment risk patterns.
 * - Return Finding records with rule key, severity, category, message, and line number.
 * - Support both single-trigger analysis and context-aware multi-trigger analysis.
 * - Detect engine-driven risks that are difficult or unsafe to rely on with regex alone.
 * - Keep output deterministic so DeploymentAnalysisJob can build stable run records and summaries.
 *
 * Keep this class focused on detection.
 * Run orchestration belongs in DeploymentAnalysisJob, UI DTO mapping belongs in DeploymentAnalysisController,
 * and release decision logic belongs in ReleaseGateEngine.
 *******************************************************************************************************/
public with sharing class TriggerRiskEngine {
  // =====================
  // Inner Models
  // =====================
  public class Finding {
    public String ruleKey;
    public String ruleLabel;
    public String severity; // Low / Medium / High
    public String category;
    public String message;
    public Integer lineNumber; // best effort
    public Integer matchPos; // best effort
  }

  public class RiskResult {
    public String risk; // Low / Medium / High
    public List<String> reasons; // messages
    public List<String> matchedKeys; // rule keys
    public Integer lineNumber; // earliest matched line
  }

  // Context Models (multi-trigger awareness)
  public class TriggerUniverse {
    public Map<String, String> triggerNameToBody; // trigger name -> body
    public Map<String, String> triggerNameToObjectApi; // trigger name -> object api name
    public Map<String, Set<String>> objectToTriggers; // object api name -> trigger names
  }

  public class TriggerContext {
    public String triggerName;
    public String objectApiName;
    public String body;
    public TriggerUniverse universe;
  }

  // =====================
  // Main Analyzer (existing)
  // =====================
  public static List<Finding> analyzeFindings(String body) {
    List<Finding> findings = new List<Finding>();
    if (String.isBlank(body))
      return findings;

    // Load rules from custom metadata
    List<Trigger_Risk_Rule__mdt> rules = [
      SELECT
        DeveloperName,
        Label,
        Rule_Key__c,
        Severity__c,
        Pattern__c,
        Message__c,
        Category__c,
        Detection_Mode__c,
        Is_Enabled__c
      FROM Trigger_Risk_Rule__mdt
    ];

    // Map rules by key
    Map<String, Trigger_Risk_Rule__mdt> ruleByKey = new Map<String, Trigger_Risk_Rule__mdt>();
    for (Trigger_Risk_Rule__mdt r : rules) {
      String k = String.isBlank(r.Rule_Key__c)
        ? r.DeveloperName
        : r.Rule_Key__c;
      if (!String.isBlank(k) && !ruleByKey.containsKey(k)) {
        ruleByKey.put(k, r);
      }
    }

    Set<String> addedKeys = new Set<String>();

    // =====================
    // Engine-driven checks
    // =====================

    // SOQL in loop
    Integer soqlPos = findSoqlInLoopPosition(body);
    Trigger_Risk_Rule__mdt soqlRule = ruleByKey.get('SOQL_IN_LOOP');
    if (
      soqlPos != null &&
      soqlRule != null &&
      soqlRule.Is_Enabled__c &&
      soqlRule.Detection_Mode__c == 'ENGINE'
    ) {
      Trigger_Risk_Rule__mdt r = soqlRule;

      Finding f = new Finding();
      f.ruleKey = 'SOQL_IN_LOOP';
      f.ruleLabel = r != null ? r.Label : 'SOQL in Loop';
      f.severity = r != null ? r.Severity__c : 'High';
      f.category = r != null ? r.Category__c : 'BulkRisk';
      f.message = r != null
        ? r.Message__c
        : 'SOQL inside a loop can hit query limits in bulk.';
      f.matchPos = soqlPos;
      f.lineNumber = computeLineNumber(body, soqlPos);

      findings.add(f);
      addedKeys.add(f.ruleKey);
    }
    // Engine-driven DML in loop (avoid regex false positives)
    Integer dmlLoopPos = findDmlInLoopPosition(body);
    Trigger_Risk_Rule__mdt dmlLoopRule = ruleByKey.get('DML_IN_LOOP');
    if (
      dmlLoopPos != null &&
      dmlLoopRule != null &&
      dmlLoopRule.Is_Enabled__c &&
      dmlLoopRule.Detection_Mode__c == 'ENGINE'
    ) {
      Trigger_Risk_Rule__mdt r = dmlLoopRule;

      Finding f = new Finding();
      f.ruleKey = 'DML_IN_LOOP';
      f.ruleLabel = r != null ? r.Label : 'DML in Loop';
      f.severity = r != null ? r.Severity__c : 'High';
      f.category = r != null ? r.Category__c : 'BulkRisk';
      f.message = r != null
        ? r.Message__c
        : 'DML inside a loop can hit governor limits and fail in bulk.';
      f.matchPos = dmlLoopPos;
      f.lineNumber = computeLineNumber(body, dmlLoopPos);

      findings.add(f);
      addedKeys.add(f.ruleKey); // prevents regex rule from also firing
    }

    // Recursion risk
    Trigger_Risk_Rule__mdt recRule = ruleByKey.get('RECURSION_RISK');
    Finding rec = null;
    if (
      recRule != null &&
      recRule.Is_Enabled__c &&
      recRule.Detection_Mode__c == 'ENGINE'
    ) {
      rec = detectRecursionRisk(body, ruleByKey);
    }

    if (rec != null && !addedKeys.contains(rec.ruleKey)) {
      findings.add(rec);
      addedKeys.add(rec.ruleKey);
    }

    // Missing trigger handler
    Trigger_Risk_Rule__mdt mhRule = ruleByKey.get('TRIGGER_HANDLER_MISSING');
    Finding mh = null;
    if (
      mhRule != null &&
      mhRule.Is_Enabled__c &&
      mhRule.Detection_Mode__c == 'ENGINE'
    ) {
      mh = detectMissingHandlerPattern(body, ruleByKey);
    }

    if (mh != null && !addedKeys.contains(mh.ruleKey)) {
      findings.add(mh);
      addedKeys.add(mh.ruleKey);
    }
    // Engine-driven ENQUEUE_IN_LOOP
    Trigger_Risk_Rule__mdt enqRule = ruleByKey.get('ENQUEUE_IN_LOOP');
    Finding enq = null;
    if (
      enqRule != null &&
      enqRule.Is_Enabled__c &&
      enqRule.Detection_Mode__c == 'ENGINE'
    ) {
      enq = detectEnqueueInLoop(body, ruleByKey);
    }

    if (enq != null && !addedKeys.contains(enq.ruleKey)) {
      findings.add(enq);
      addedKeys.add(enq.ruleKey);
    }

    // EMAIL_IN_TRIGGER - Engine-driven detection (ignore comments/strings)
    Trigger_Risk_Rule__mdt emailRule = ruleByKey.get('EMAIL_IN_TRIGGER');
    Finding emailFinding = null;
    if (
      emailRule != null &&
      emailRule.Is_Enabled__c &&
      emailRule.Detection_Mode__c == 'ENGINE'
    ) {
      emailFinding = detectEmailInTrigger(body, ruleByKey);
    }
    if (emailFinding != null && !addedKeys.contains(emailFinding.ruleKey)) {
      findings.add(emailFinding);
      addedKeys.add(emailFinding.ruleKey);
    }
    //Engine-driven DML_ON_TRIGGER_OLD
    Trigger_Risk_Rule__mdt dmlOldRule = ruleByKey.get('DML_ON_TRIGGER_OLD');
    Finding dmlOld = null;
    if (
      dmlOldRule != null &&
      dmlOldRule.Is_Enabled__c &&
      dmlOldRule.Detection_Mode__c == 'ENGINE'
    ) {
      dmlOld = detectDmlOnTriggerOld(body, ruleByKey);
    }

    if (dmlOld != null && !addedKeys.contains(dmlOld.ruleKey)) {
      findings.add(dmlOld);
      addedKeys.add(dmlOld.ruleKey);
    }

    // =====================
    // Regex-driven checks
    // =====================

    for (Trigger_Risk_Rule__mdt r : rules) {
      String key = String.isBlank(r.Rule_Key__c)
        ? r.DeveloperName
        : r.Rule_Key__c;
      if (
        String.isBlank(key) ||
        addedKeys.contains(key) ||
        !r.Is_Enabled__c ||
        r.Detection_Mode__c == 'ENGINE' ||
        String.isBlank(r.Pattern__c)
      ) {
        continue;
      }

      Pattern p;
      try {
        p = Pattern.compile('(?i)' + r.Pattern__c);
      } catch (Exception e) {
        continue;
      }

      // Use masked text for a few regex rules to avoid matching comments/strings
      String scanText = maskCommentsAndStringsPreserveLength(body);
      if (key == 'HARDCODED_ID') {
        scanText = maskCommentsPreserveLength(body);
      }
      Matcher m = p.matcher(scanText);

      if (!m.find())
        continue;
      Integer firstPos = m.start();
      Integer matchPos = firstPos;
      // Special highlight logic for callouts
      if (key == 'CALLOUT_IN_TRIGGER') {
        // 1) Prefer the actual execution call (.send()
        Matcher sendM = Pattern.compile('\\.send\\s*\\(').matcher(scanText);
        if (sendM.find()) {
          matchPos = sendM.start();
        } else {
          // 2) Next, prefer PageReference.getContent / getContentAsPDF
          Matcher contentM = Pattern.compile(
              '\\bPageReference\\.getContent\\b|\\bgetContentAsPDF\\b'
            )
            .matcher(scanText);
          if (contentM.find()) {
            matchPos = contentM.start();
          }
        }
      }

      Finding f = new Finding();
      f.ruleKey = key;
      f.ruleLabel = r.Label;
      f.severity = String.isBlank(r.Severity__c) ? 'Low' : r.Severity__c;
      f.category = r.Category__c;
      f.message = r.Message__c;
      f.matchPos = matchPos;
      f.lineNumber = computeLineNumber(body, matchPos);
      findings.add(f);
      addedKeys.add(key);
    }

    findings.sort(new FindingSorter());
    return findings;
  }

  // Main Analyzer (context-aware overload)
  public static List<Finding> analyzeFindings(TriggerContext ctx) {
    if (ctx == null)
      return new List<Finding>();

    List<Finding> findings = analyzeFindings(ctx.body);

    // Dedupe keys already present (some callers may add their own)
    Set<String> existing = new Set<String>();
    if (findings != null) {
      for (Finding f : findings) {
        if (f != null && !String.isBlank(f.ruleKey)) {
          existing.add(f.ruleKey);
        }
      }
    }

    // Cross-trigger recursion cycle detection
    Finding cross = detectCrossTriggerRecursionCycle(ctx);
    if (cross != null && !existing.contains(cross.ruleKey)) {
      findings.add(cross);
      existing.add(cross.ruleKey);
    }

    // Trigger order-of-execution risks
    List<Finding> orderFindings = detectOrderOfExecutionRisks(ctx);
    if (orderFindings != null && !orderFindings.isEmpty()) {
      for (Finding ordFinding : orderFindings) {
        if (ordFinding != null && !existing.contains(ordFinding.ruleKey)) {
          findings.add(ordFinding);
          existing.add(ordFinding.ruleKey);
        }
      }
    }

    // Bulkification confidence scoring (one informational finding per trigger)
    Finding bulkScore = buildBulkConfidenceFinding(ctx, findings);
    if (bulkScore != null && !existing.contains(bulkScore.ruleKey)) {
      findings.add(bulkScore);
      existing.add(bulkScore.ruleKey);
    }

    findings.sort(new FindingSorter());
    return findings;
  }

  // =====================
  // Sorter
  // =====================
  private class FindingSorter implements Comparator<Finding> {
    public Integer compare(Finding a, Finding b) {
      Integer ra = rank(a.severity);
      Integer rb = rank(b.severity);
      if (ra != rb)
        return rb - ra;

      if (a.lineNumber == null)
        return 1;
      if (b.lineNumber == null)
        return -1;
      return a.lineNumber - b.lineNumber;
    }
  }

  // =====================
  // Summary API
  // =====================
  public static RiskResult analyze(String triggerBody) {
    List<Finding> findings = analyzeFindings(triggerBody);

    RiskResult out = new RiskResult();
    out.risk = 'Low';
    out.reasons = new List<String>();
    out.matchedKeys = new List<String>();

    Integer earliestPos;

    for (Finding f : findings) {
      out.matchedKeys.add(f.ruleKey);
      out.reasons.add(f.message);

      if (rank(f.severity) > rank(out.risk)) {
        out.risk = f.severity;
      }

      if (earliestPos == null || f.matchPos < earliestPos) {
        earliestPos = f.matchPos;
        out.lineNumber = f.lineNumber;
      }
    }
    return out;
  }

  // =====================
  // Utilities
  // =====================
  private static Integer computeLineNumber(String body, Integer pos) {
    Integer line = 1;
    for (Integer i = 0; i < pos && i < body.length(); i++) {
      if (body.substring(i, i + 1) == '\n')
        line++;
    }
    return line;
  }

  private static Integer rank(String risk) {
    if (risk == 'High')
      return 3;
    if (risk == 'Medium')
      return 2;
    return 1;
  }

  // =====================
  // SOQL-in-loop helpers
  // =====================
  private class BlockSpan {
    public Integer startPos;
    public Integer endPos;
  }

  private static Integer findSoqlInLoopPosition(String body) {
    if (String.isBlank(body))
      return null;

    String scan = maskCommentsAndStringsPreserveLength(body);

    for (BlockSpan b : findLoopBlocks(scan)) {
      Integer rel = findSoqlPosition(scan.substring(b.startPos, b.endPos));
      if (rel != null)
        return b.startPos + rel;
    }
    return null;
  }

  private static Integer findDmlInLoopPosition(String body) {
    if (String.isBlank(body))
      return null;

    // Use masked scan so loops in comments/strings do not interfere, but positions remain aligned
    String scan = maskCommentsAndStringsPreserveLength(body);

    // ---------- for/while loops ----------
    Matcher m = Pattern.compile('(?m)^\\s*(for|while)\\b').matcher(scan);
    while (m.find()) {
      Integer loopHeaderPos = m.start();
      Integer headerEnd = findLoopHeaderEndPos(scan, m.start(), m.group(0));
      if (headerEnd == null)
        continue;

      // Skip whitespace after the full header
      Integer j = headerEnd;
      while (j < scan.length()) {
        String ch = scan.substring(j, j + 1);
        if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n')
          break;
        j++;
      }

      // Braced loop
      if (j < scan.length() && scan.substring(j, j + 1) == '{') {
        Integer open = j;
        Integer close = findMatchingBrace(scan, open);
        if (close != null) {
          String loopSegment = scan.substring(open, close + 1);
          Integer rel = findDmlPosition(loopSegment);
          if (rel != null)
            return loopHeaderPos;
        }
        continue;
      }

      // No-brace loop
      Integer stmtEnd = findStatementEndPos(scan, headerEnd);
      if (stmtEnd == null)
        stmtEnd = Math.min(scan.length(), headerEnd + 400);

      String afterHeader = scan.substring(headerEnd, stmtEnd);
      Integer rel2 = findDmlPosition(afterHeader);
      if (rel2 != null)
        return loopHeaderPos;
    }
    // ---------- do { ... } while (...) ----------
    Matcher d = Pattern.compile('(?m)^\\s*do\\b').matcher(scan);
    while (d.find()) {
      Integer doPos = d.start();
      Integer doEnd = d.end();

      // Skip whitespace after "do"
      Integer j = doEnd;
      while (j < scan.length()) {
        String ch = scan.substring(j, j + 1);
        if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n')
          break;
        j++;
      }

      // Braced do
      if (j < scan.length() && scan.substring(j, j + 1) == '{') {
        Integer open = j;
        Integer close = findMatchingBrace(scan, open);
        if (close != null) {
          String loopSegment = scan.substring(open, close + 1);
          Integer rel = findDmlPosition(loopSegment);
          if (rel != null)
            return doPos;
        }
        continue;
      }

      // No-brace do
      Integer stmtEnd = findStatementEndPos(scan, doEnd);
      if (stmtEnd == null)
        stmtEnd = Math.min(scan.length(), doEnd + 400);

      String stmt = scan.substring(doEnd, stmtEnd);
      Integer rel2 = findDmlPosition(stmt);
      if (rel2 != null)
        return doPos;
    }

    return null;
  }

  //Returns relative position of DML keyword inside a string segment, ignoring comments and string literals
  private static Integer findDmlPosition(String segment) {
    if (String.isBlank(segment))
      return null;

    Integer n = segment.length();
    Boolean inLineComment = false;
    Boolean inBlockComment = false;
    Boolean inString = false;

    for (Integer i = 0; i < n; i++) {
      String ch = segment.substring(i, i + 1);

      if (inLineComment) {
        if (ch == '\n')
          inLineComment = false;
        continue;
      }
      if (inBlockComment) {
        if (i + 1 < n && segment.substring(i, i + 2) == '*/') {
          inBlockComment = false;
          i++;
        }
        continue;
      }
      if (inString) {
        if (ch == '\\') {
          if (i + 1 < n)
            i++;
          continue;
        }
        if (ch == '\'')
          inString = false;
        continue;
      }

      if (i + 1 < n) {
        String two = segment.substring(i, i + 2);
        if (two == '//') {
          inLineComment = true;
          i++;
          continue;
        }
        if (two == '/*') {
          inBlockComment = true;
          i++;
          continue;
        }
      }

      if (ch == '\'') {
        inString = true;
        continue;
      }
      //Left-boundary guard: prevent matching DML keywords inside identifiers like Trigger.isUpdate
      if (i > 0) {
        String prev = segment.substring(i - 1, i).toLowerCase();
        if (
          (prev >= 'a' &&
          prev <= 'z') ||
          (prev >= '0' &&
          prev <= '9') ||
          prev == '_'
        ) {
          continue;
        }
      }

      String tail = segment.substring(i).toLowerCase();

      if (
        startsWithWord(tail, 'database.insert') ||
        startsWithWord(tail, 'database.update') ||
        startsWithWord(tail, 'database.delete') ||
        startsWithWord(tail, 'database.upsert') ||
        startsWithWord(tail, 'database.undelete') ||
        startsWithWord(tail, 'database.merge') ||
        startsWithWord(tail, 'insert') ||
        startsWithWord(tail, 'update') ||
        startsWithWord(tail, 'delete') ||
        startsWithWord(tail, 'upsert') ||
        startsWithWord(tail, 'undelete') ||
        startsWithWord(tail, 'merge')
      ) {
        return i;
      }
    }

    return null;
  }

  private static Boolean startsWithWord(String tail, String word) {
    if (!tail.startsWith(word))
      return false;

    Integer len = word.length();
    if (tail.length() == len)
      return true;

    String next = tail.substring(len, len + 1);
    return !(next >= 'a' &&
      next <= 'z') &&
      !(next >= '0' &&
      next <= '9') &&
      next != '_';
  }

  private static List<BlockSpan> findLoopBlocks(String body) {
    List<BlockSpan> blocks = new List<BlockSpan>();
    Matcher m = Pattern.compile('(?m)^\\s*(for|while)\\b').matcher(body);

    while (m.find()) {
      Integer headerEnd = findLoopHeaderEndPos(body, m.start(), m.group(0));
      if (headerEnd == null)
        continue;

      // Find the next non-whitespace char after the loop header
      Integer j = headerEnd;
      while (j < body.length()) {
        String ch = body.substring(j, j + 1);
        if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n')
          break;
        j++;
      }

      // Case A: Braced loop: for/while(...) { ... }
      if (j < body.length() && body.substring(j, j + 1) == '{') {
        Integer open = j;
        Integer close = findMatchingBrace(body, open);
        if (close != null) {
          BlockSpan b = new BlockSpan();
          b.startPos = open;
          b.endPos = close + 1;
          blocks.add(b);
        }
        continue;
      }

      // Case B: Single-statement loop: for/while(...) doSomething();
      Integer stmtEnd = findStatementEndPos(body, headerEnd);
      if (stmtEnd != null && stmtEnd > headerEnd) {
        BlockSpan b2 = new BlockSpan();
        b2.startPos = headerEnd;
        b2.endPos = stmtEnd;
        blocks.add(b2);
      }
    }
    // Case C: do { ... } while (...);
    Matcher d = Pattern.compile('(?m)^\\s*do\\b').matcher(body);
    while (d.find()) {
      Integer doEnd = d.end();

      // Skip whitespace after "do"
      Integer j = doEnd;
      while (j < body.length()) {
        String ch = body.substring(j, j + 1);
        if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n')
          break;
        j++;
      }

      // Braced do: do { ... } while (...)
      if (j < body.length() && body.substring(j, j + 1) == '{') {
        Integer open = j;
        Integer close = findMatchingBrace(body, open);
        if (close != null) {
          BlockSpan b3 = new BlockSpan();
          b3.startPos = open;
          b3.endPos = close + 1;
          blocks.add(b3);
        }
        continue;
      }

      // No-brace do: do singleStatement; while (...);
      Integer stmtEnd = findStatementEndPos(body, doEnd);
      if (stmtEnd != null && stmtEnd > doEnd) {
        BlockSpan b4 = new BlockSpan();
        b4.startPos = doEnd;
        b4.endPos = stmtEnd;
        blocks.add(b4);
      }
    }
    return blocks;
  }

  private static Integer findMatchingBrace(String body, Integer start) {
    Integer depth = 0;
    for (Integer i = start; i < body.length(); i++) {
      if (body.substring(i, i + 1) == '{')
        depth++;
      if (body.substring(i, i + 1) == '}' && --depth == 0)
        return i;
    }
    return null;
  }
  //Finds best-effort end of the next Apex statement after a loop header (supports no-brace loops)
  private static Integer findStatementEndPos(String body, Integer startPos) {
    if (String.isBlank(body) || startPos == null)
      return null;

    Integer n = body.length();
    Boolean inLineComment = false;
    Boolean inBlockComment = false;
    Boolean inString = false;

    for (Integer i = startPos; i < n; i++) {
      if (i - startPos > 600)
        return i;
      String ch = body.substring(i, i + 1);

      if (inLineComment) {
        if (ch == '\n')
          inLineComment = false;
        continue;
      }
      if (inBlockComment) {
        if (i + 1 < n && body.substring(i, i + 2) == '*/') {
          inBlockComment = false;
          i++;
        }
        continue;
      }
      if (inString) {
        if (ch == '\\') {
          if (i + 1 < n)
            i++;
          continue;
        }
        if (ch == '\'')
          inString = false;
        continue;
      }

      if (i + 1 < n) {
        String two = body.substring(i, i + 2);
        if (two == '//') {
          inLineComment = true;
          i++;
          continue;
        }
        if (two == '/*') {
          inBlockComment = true;
          i++;
          continue;
        }
      }

      if (ch == '\'') {
        inString = true;
        continue;
      }

      // End of statement
      if (ch == ';')
        return i + 1;
      if (ch == '\n') {
        continue;
      }
    }

    return null;
  }
  // Engine-driven ENQUEUE_IN_LOOP finder
  private static Finding detectEnqueueInLoop(
    String body,
    Map<String, Trigger_Risk_Rule__mdt> ruleByKey
  ) {
    if (String.isBlank(body))
      return null;

    Trigger_Risk_Rule__mdt r = ruleByKey.get('ENQUEUE_IN_LOOP');
    if (r == null || !r.Is_Enabled__c)
      return null;

    Integer pos = findEnqueueInLoopPosition(body);
    if (pos == null)
      return null;

    Finding f = new Finding();
    f.ruleKey = String.isBlank(r.Rule_Key__c) ? r.DeveloperName : r.Rule_Key__c;
    f.ruleLabel = r.Label;
    f.severity = String.isBlank(r.Severity__c) ? 'Low' : r.Severity__c;
    f.category = r.Category__c;
    f.message = r.Message__c;
    f.matchPos = pos;
    f.lineNumber = computeLineNumber(body, pos);
    return f;
  }

  private static Integer findEnqueueInLoopPosition(String body) {
    if (String.isBlank(body))
      return null;

    // Scan on masked text so comment-only and string-only patterns do not false-positive
    String scan = maskCommentsAndStringsPreserveLength(body);

    // ---------- for/while loops ----------
    Matcher m = Pattern.compile('(?m)^\\s*(for|while)\\b').matcher(scan);
    while (m.find()) {
      Integer loopHeaderPos = m.start();
      Integer headerEnd = findLoopHeaderEndPos(scan, m.start(), m.group(0));
      if (headerEnd == null)
        continue;

      // Skip whitespace after the full header
      Integer j = headerEnd;
      while (j < scan.length()) {
        String ch = scan.substring(j, j + 1);
        if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n')
          break;
        j++;
      }

      // Braced loop: for/while (...) { ... }
      if (j < scan.length() && scan.substring(j, j + 1) == '{') {
        Integer open = j;
        Integer close = findMatchingBrace(scan, open);
        if (close != null) {
          String loopSegment = scan.substring(open, close + 1);
          if (containsEnqueue(loopSegment))
            return loopHeaderPos;
        }
        continue;
      }

      // No-brace loop: for/while (...) singleStatement;
      Integer stmtEnd = findStatementEndPos(scan, headerEnd);
      if (stmtEnd == null)
        stmtEnd = Math.min(scan.length(), headerEnd + 400);

      String afterHeader = scan.substring(headerEnd, stmtEnd);
      if (containsEnqueue(afterHeader))
        return loopHeaderPos;
    }

    // ---------- do { ... } while (...) ----------
    Matcher d = Pattern.compile('(?m)^\\s*do\\b').matcher(scan);
    while (d.find()) {
      Integer doPos = d.start();
      Integer j = d.end();

      // Skip whitespace after "do"
      while (j < scan.length()) {
        String ch = scan.substring(j, j + 1);
        if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n')
          break;
        j++;
      }

      // Braced do: do { ... } while (...);
      if (j < scan.length() && scan.substring(j, j + 1) == '{') {
        Integer open = j;
        Integer close = findMatchingBrace(scan, open);
        if (close != null) {
          String loopSegment = scan.substring(open, close + 1);
          if (containsEnqueue(loopSegment))
            return doPos;
        }
        continue;
      }

      // No-brace do: do singleStatement; while (...);
      Integer stmtEnd = findStatementEndPos(scan, d.end());
      if (stmtEnd == null)
        stmtEnd = Math.min(scan.length(), d.end() + 400);

      String loopStmt = scan.substring(d.end(), stmtEnd);
      if (containsEnqueue(loopStmt))
        return doPos;
    }

    return null;
  }

  private static Boolean containsEnqueue(String segment) {
    if (String.isBlank(segment))
      return false;
    Matcher q = Pattern.compile('(?i)\\bSystem\\s*\\.\\s*enqueueJob\\s*\\(')
      .matcher(segment);
    return q.find();
  }

  private static Integer findLoopHeaderEndPos(
    String scan,
    Integer keywordStart,
    String matchedPrefix
  ) {
    if (String.isBlank(scan) || keywordStart == null)
      return null;

    // Find the first '(' after the keyword (handles for/while with nested parentheses)
    Integer open = scan.indexOf('(', keywordStart);
    if (open == -1)
      return null;

    Integer depth = 0;
    for (Integer i = open; i < scan.length(); i++) {
      String ch = scan.substring(i, i + 1);
      if (ch == '(')
        depth++;
      if (ch == ')') {
        depth--;
        if (depth == 0)
          return i + 1;
      }
    }
    return null;
  }
  //==========EMAIL_IN_TRIGGER Helpers==========
  private static Finding detectEmailInTrigger(
    String body,
    Map<String, Trigger_Risk_Rule__mdt> ruleByKey
  ) {
    if (String.isBlank(body))
      return null;

    Integer pos = findEmailSendPosition(body);
    if (pos == null)
      return null;

    Trigger_Risk_Rule__mdt r = ruleByKey != null
      ? ruleByKey.get('EMAIL_IN_TRIGGER')
      : null;

    Finding f = new Finding();
    f.ruleKey = 'EMAIL_IN_TRIGGER';
    f.ruleLabel = r != null ? r.Label : 'Email in Trigger';
    f.severity = r != null ? r.Severity__c : 'Medium';
    f.category = r != null ? r.Category__c : 'Maintainability';
    f.message = r != null
      ? r.Message__c
      : 'Email send detected inside a trigger can hit limits and reduce reliability under bulk load.';
    f.matchPos = pos;
    f.lineNumber = computeLineNumber(body, pos);

    return f;
  }

  private static Integer findEmailSendPosition(String segment) {
    if (String.isBlank(segment))
      return null;

    Integer n = segment.length();
    Boolean inLineComment = false;
    Boolean inBlockComment = false;
    Boolean inString = false;

    for (Integer i = 0; i < n; i++) {
      String ch = segment.substring(i, i + 1);

      if (inLineComment) {
        if (ch == '\n')
          inLineComment = false;
        continue;
      }
      if (inBlockComment) {
        if (i + 1 < n && segment.substring(i, i + 2) == '*/') {
          inBlockComment = false;
          i++;
        }
        continue;
      }
      if (inString) {
        if (ch == '\\') {
          if (i + 1 < n)
            i++;
          continue;
        }
        if (ch == '\'')
          inString = false;
        continue;
      }

      if (i + 1 < n) {
        String two = segment.substring(i, i + 2);
        if (two == '//') {
          inLineComment = true;
          i++;
          continue;
        }
        if (two == '/*') {
          inBlockComment = true;
          i++;
          continue;
        }
      }

      if (ch == '\'') {
        inString = true;
        continue;
      }

      String tail = segment.substring(i).toLowerCase();

      if (startsWithWord(tail, 'messaging.sendemail')) {
        return i;
      }
    }

    return null;
  }
  // EMAIL_IN_TRIGGER Helpers END
  // Engine-driven DML_ON_TRIGGER_OLD finder
  private static Finding detectDmlOnTriggerOld(
    String body,
    Map<String, Trigger_Risk_Rule__mdt> ruleByKey
  ) {
    if (String.isBlank(body))
      return null;

    Trigger_Risk_Rule__mdt r = ruleByKey.get('DML_ON_TRIGGER_OLD');
    if (r == null || !r.Is_Enabled__c)
      return null;

    Integer pos = findDmlOnTriggerOldPosition(body);
    if (pos == null)
      return null;

    Finding f = new Finding();
    f.ruleKey = String.isBlank(r.Rule_Key__c) ? r.DeveloperName : r.Rule_Key__c;
    f.ruleLabel = r.Label;
    f.severity = String.isBlank(r.Severity__c) ? 'Low' : r.Severity__c;
    f.category = r.Category__c;
    f.message = r.Message__c;
    f.matchPos = pos;
    f.lineNumber = computeLineNumber(body, pos);
    return f;
  }

  private static Integer findDmlOnTriggerOldPosition(String segment) {
    if (String.isBlank(segment))
      return null;

    Integer n = segment.length();
    Boolean inLineComment = false;
    Boolean inBlockComment = false;
    Boolean inString = false;

    for (Integer i = 0; i < n; i++) {
      String ch = segment.substring(i, i + 1);

      if (inLineComment) {
        if (ch == '\n')
          inLineComment = false;
        continue;
      }
      if (inBlockComment) {
        if (i + 1 < n && segment.substring(i, i + 2) == '*/') {
          inBlockComment = false;
          i++;
        }
        continue;
      }
      if (inString) {
        if (ch == '\\') {
          if (i + 1 < n)
            i++;
          continue;
        }
        if (ch == '\'')
          inString = false;
        continue;
      }

      if (i + 1 < n) {
        String two = segment.substring(i, i + 2);
        if (two == '//') {
          inLineComment = true;
          i++;
          continue;
        }
        if (two == '/*') {
          inBlockComment = true;
          i++;
          continue;
        }
      }

      if (ch == '\'') {
        inString = true;
        continue;
      }

      String tail = segment.substring(i).toLowerCase();

      // Direct DML forms: update/delete/undelete <expr>
      if (
        startsWithWord(tail, 'update') ||
        startsWithWord(tail, 'delete') ||
        startsWithWord(tail, 'undelete')
      ) {
        Integer wordLen = startsWithWord(tail, 'update')
          ? 6
          : (startsWithWord(tail, 'delete') ? 6 : 8);
        Integer j = i + wordLen;

        while (j < n) {
          String cj = segment.substring(j, j + 1);
          if (cj != ' ' && cj != '\t' && cj != '\r' && cj != '\n')
            break;
          j++;
        }

        String after = segment.substring(j).toLowerCase();
        if (
          after.startsWith('trigger.old') || after.startsWith('trigger.oldmap')
        )
          return i;
      }

      // Database.* forms: Database.update(<expr>, ...)
      if (
        startsWithWord(tail, 'database.update') ||
        startsWithWord(tail, 'database.delete') ||
        startsWithWord(tail, 'database.undelete')
      ) {
        Integer j = i;
        while (j < n && segment.substring(j, j + 1) != '(')
          j++;
        if (j >= n)
          continue;
        j++;

        while (j < n) {
          String cj = segment.substring(j, j + 1);
          if (cj != ' ' && cj != '\t' && cj != '\r' && cj != '\n')
            break;
          j++;
        }

        String after = segment.substring(j).toLowerCase();
        if (
          after.startsWith('trigger.old') || after.startsWith('trigger.oldmap')
        )
          return i;
      }
    }

    return null;
  }

  private static Integer findSoqlPosition(String text) {
    Matcher m = Pattern.compile(
        // SOQL_IN_LOOP detects multi-line SOQL
        // '(?i)(\\[\\s*SELECT.*?FROM.*?\\])|(Database\\.(query|getQueryLocator))'
        '(?is)(\\[\\s*SELECT[\\s\\S]*?FROM[\\s\\S]*?\\])|(Database\\.(query|getQueryLocator))'
      )
      .matcher(text);
    return m.find() ? m.start() : null;
  }

  // =====================
  // Recursion detection
  // =====================
  private static Finding detectRecursionRisk(
    String body,
    Map<String, Trigger_Risk_Rule__mdt> ruleByKey
  ) {
    if (!containsActualDmlStatement(body)) {
      return null;
    }

    //return buildRecursionFinding(ruleByKey, body, 0, looksLikeRecursionGuard(body));
    Boolean hasGuard = looksLikeRecursionGuard(body);
    if (hasGuard) {
      return null;
    }
    return buildRecursionFinding(ruleByKey, body, 0, false);
  }

  private static Finding buildRecursionFinding(
    Map<String, Trigger_Risk_Rule__mdt> ruleByKey,
    String body,
    Integer pos,
    Boolean hasGuard
  ) {
    Trigger_Risk_Rule__mdt r = ruleByKey.get('RECURSION_RISK');

    Finding f = new Finding();
    f.ruleKey = 'RECURSION_RISK';
    f.ruleLabel = r != null ? r.Label : 'Recursion Risk';
    f.category = r != null ? r.Category__c : 'Reliability';
    f.severity = hasGuard ? 'Medium' : 'High';
    f.message = r != null
      ? r.Message__c
      : 'Possible recursion: DML on same object inside trigger.';
    f.matchPos = pos;
    f.lineNumber = computeLineNumber(body, pos);

    return f;
  }

  // =====================
  // Missing Handler
  // =====================
  private static Finding detectMissingHandlerPattern(
    String body,
    Map<String, Trigger_Risk_Rule__mdt> ruleByKey
  ) {
    if (!body.toLowerCase().contains('trigger'))
      return null;
    if (Pattern.compile('(?i)Handler\\.').matcher(body).find())
      return null;

    Trigger_Risk_Rule__mdt r = ruleByKey.get('TRIGGER_HANDLER_MISSING');

    Finding f = new Finding();
    f.ruleKey = 'TRIGGER_HANDLER_MISSING';
    f.ruleLabel = r != null ? r.Label : 'Missing Trigger Handler';
    f.severity = r != null ? r.Severity__c : 'Low';
    f.category = r != null ? r.Category__c : 'Maintainability';
    f.message = r != null
      ? r.Message__c
      : 'Trigger contains logic directly. Use a handler class.';
    f.matchPos = 0;
    f.lineNumber = 1;
    Integer lineCount = countEffectiveLines(body);

    // Downgrade severity for very small/simple triggers
    if (f.severity == 'Medium' && lineCount <= 12) {
      f.severity = 'Low';
    }

    return f;
  }

  // Cross-trigger recursion cycle detection (best-effort, explainable)
  private static Finding detectCrossTriggerRecursionCycle(TriggerContext ctx) {
    if (ctx == null || ctx.universe == null)
      return null;
    if (String.isBlank(ctx.objectApiName) || String.isBlank(ctx.triggerName))
      return null;

    // Only attempt this check if THIS trigger contains REAL DML statements
    if (!containsActualDmlStatement(ctx.body))
      return null;

    // Compute referenced objects from the body using simple, explainable heuristics.
    Set<String> referenced = extractReferencedObjectApiNames(ctx.body);
    referenced.remove(ctx.objectApiName);

    if (referenced.isEmpty())
      return null;

    // Find a 2-hop cycle: A -> B and B -> A
    for (String otherObj : referenced) {
      if (String.isBlank(otherObj))
        continue;

      // Do we have triggers on the other object?
      if (
        ctx.universe.objectToTriggers == null ||
        !ctx.universe.objectToTriggers.containsKey(otherObj)
      ) {
        continue;
      }

      Set<String> otherTriggers = ctx.universe.objectToTriggers.get(otherObj);
      if (otherTriggers == null || otherTriggers.isEmpty())
        continue;

      for (String otName : otherTriggers) {
        String otBody = (ctx.universe.triggerNameToBody != null)
          ? ctx.universe.triggerNameToBody.get(otName)
          : null;

        if (String.isBlank(otBody))
          continue;

        // Only proceed if OTHER trigger contains REAL DML statements
        if (!containsActualDmlStatement(otBody))
          continue;

        Set<String> otRefs = extractReferencedObjectApiNames(otBody);

        // If other trigger references back to this object, we have a cycle
        if (otRefs.contains(ctx.objectApiName)) {
          Boolean thisHasGuard = looksLikeRecursionGuard(ctx.body);
          Boolean otherHasGuard = looksLikeRecursionGuard(otBody);
          Boolean hasGuard = thisHasGuard || otherHasGuard;

          String confidence = 'Medium';
          try {
            // High confidence when both sides have DML + strong references to the other object
            Boolean thisStrong =
              hasStrongObjectReference(ctx.body, otherObj) &&
              containsActualDmlStatement(ctx.body);
            Boolean otherStrong =
              hasStrongObjectReference(otBody, ctx.objectApiName) &&
              containsActualDmlStatement(otBody);

            if (thisStrong && otherStrong)
              confidence = 'High';
            else if (
              containsActualDmlStatement(ctx.body) &&
              containsActualDmlStatement(otBody)
            )
              confidence = 'Medium';
            else
              confidence = 'Low';
          } catch (Exception ex) {
            // keep default
          }

          // Best highlight position (prefer FROM <Object>)
          Integer hlPos = findBestHighlightPos(ctx.body, otherObj);
          Integer posToUse = (hlPos == null) ? 0 : hlPos;
          Integer lineToUse = computeLineNumber(ctx.body, posToUse);

          Finding f = new Finding();
          f.ruleKey = 'CROSS_TRIGGER_RECURSION_CYCLE';
          f.ruleLabel = 'Cross-Trigger Recursion Cycle';
          f.category = 'Reliability';
          f.severity = hasGuard ? 'Medium' : 'High';
          f.matchPos = posToUse;
          f.lineNumber = (lineToUse == null || lineToUse <= 0) ? 1 : lineToUse;

          f.message =
            'Possible cross-trigger recursion cycle detected: ' +
            ctx.objectApiName +
            ' (' +
            ctx.triggerName +
            ')' +
            ' -> ' +
            otherObj +
            ' (' +
            otName +
            ')' +
            ' -> ' +
            ctx.objectApiName +
            '. ' +
            (hasGuard
              ? 'A recursion guard pattern may exist, but review carefully. '
              : 'No obvious recursion guard detected. Review carefully to avoid loops. ') +
            'Confidence: ' +
            confidence +
            '.';

          return f;
        }
      }
    }

    return null;
  }

  // New: only detect REAL DML statements (avoids matching trigger event keywords like "after update")
  private static Boolean containsActualDmlStatement(String body) {
    if (String.isBlank(body))
      return false;

    // Only scan inside the executable block (after the first '{') so we don't match header words.
    Integer brace = body.indexOf('{');
    String scan = (brace >= 0 &&
      brace + 1 < body.length())
      ? body.substring(brace + 1)
      : body;

    // Use the engine scanner that already ignores comments and strings.
    Integer pos = findDmlPosition(scan);
    return (pos != null);
  }

  //Helper: detect real Trigger.new mutation in AFTER context
  private static Integer findAfterTriggerNewMutationPos(
    String bodyRaw,
    String bodyLower,
    Boolean isBefore,
    Boolean isAfter
  ) {
    if (!isAfter)
      return -1;
    if (String.isBlank(bodyRaw))
      return -1;

    //Mask comments + strings so traps do not match.
    String maskedLower = maskCommentsAndStringsPreserveLength(bodyRaw)
      .toLowerCase();

    //If trigger supports BOTH before and after, only flag AFTER mutation when an explicit Trigger.isAfter guard exists.
    Boolean isAfterOnly = isAfter && !isBefore;
    Integer afterGuardPos = maskedLower.indexOf('trigger.isafter');
    if (!isAfterOnly && afterGuardPos < 0)
      return -1;

    Integer offset = 0;
    String scan = maskedLower;

    if (afterGuardPos >= 0) {
      offset = afterGuardPos;
      scan = maskedLower.substring(afterGuardPos);
    }

    // Direct DML on Trigger.new (true mutation pattern)
    Matcher dmlOnNew = Pattern.compile(
        '(?i)\\b(update|delete|undelete)\\s+trigger\\.new\\b'
      )
      .matcher(scan);
    if (dmlOnNew.find())
      return offset + dmlOnNew.start();

    // Indexed mutation: Trigger.new[i].Field = ... OR Trigger.new[i] = ...
    Matcher indexed = Pattern.compile(
        '(?i)trigger\\.new\\s*\\[[^\\]]*\\]\\s*(?:\\.[a-z0-9_]+\\s*=|=)'
      )
      .matcher(scan);
    if (indexed.find())
      return offset + indexed.start();

    // Loop variable mutation: for (Obj r : Trigger.new) { r.Field = ... }
    Matcher loopMatcher = Pattern.compile(
        '(?i)for\\s*\\(\\s*[a-z0-9_\\.]+\\s+([a-z0-9_]+)\\s*:\\s*trigger\\.new\\s*\\)'
      )
      .matcher(scan);

    while (loopMatcher.find()) {
      String varName = loopMatcher.group(1);
      Integer scanFrom = loopMatcher.end();
      String rest = scan.substring(scanFrom);

      Matcher assign = Pattern.compile(
          '(?i)\\b' + varName + '\\s*\\.[a-z0-9_]+\\s*='
        )
        .matcher(rest);
      if (assign.find())
        return offset + scanFrom + assign.start();
    }

    return -1;
  }

  private static Boolean looksLikeRecursionGuard(String body) {
    if (String.isBlank(body))
      return false;

    // Mask comments + strings so traps do not match.
    String scan = maskCommentsAndStringsPreserveLength(body);
    String lower = scan.toLowerCase();

    // 1) Strong detection: static Boolean guard that is BOTH checked and set
    //Example patterns:
    Matcher boolDecl = Pattern.compile(
        '(?i)\\bstatic\\s+Boolean\\s+([A-Za-z_][A-Za-z0-9_]*)\\b'
      )
      .matcher(scan);
    while (boolDecl.find()) {
      String varName = boolDecl.group(1);
      if (String.isBlank(varName))
        continue;

      String v = varName.toLowerCase();

      //Must see a conditional check using this variable
      Boolean hasCheck =
        Pattern.compile('(?i)\\bif\\s*\\(\\s*!?\\s*' + v + '\\s*\\)')
          .matcher(lower)
          .find() ||
        Pattern.compile(
            '(?i)\\bif\\s*\\(\\s*' + v + '\\s*==\\s*(true|false)\\s*\\)'
          )
          .matcher(lower)
          .find();

      //Must see the variable being set (true or false)
      Boolean hasSet = Pattern.compile(
          '(?i)\\b' + v + '\\s*=\\s*(true|false)\\b'
        )
        .matcher(lower)
        .find();

      if (hasCheck && hasSet)
        return true;
    }

    // 2) Strong detection: static Set<Id> guard (contains + add)
    Matcher setDecl = Pattern.compile(
        '(?i)\\bstatic\\s+Set\\s*<\\s*Id\\s*>\\s+([A-Za-z_][A-Za-z0-9_]*)\\b'
      )
      .matcher(scan);
    while (setDecl.find()) {
      String varName = setDecl.group(1);
      if (String.isBlank(varName))
        continue;
      String v = varName.toLowerCase();

      Boolean hasContains = Pattern.compile(
          '(?i)\\b' + v + '\\s*\\.\\s*contains\\s*\\('
        )
        .matcher(lower)
        .find();
      Boolean hasAdd = Pattern.compile('(?i)\\b' + v + '\\s*\\.\\s*add\\s*\\(')
        .matcher(lower)
        .find();

      if (hasContains && hasAdd)
        return true;
    }

    // 3) Strong detection: static Map<Id, ...> guard (containsKey/get + put)
    Matcher mapDecl = Pattern.compile(
        '(?i)\\bstatic\\s+Map\\s*<\\s*Id\\s*,\\s*[A-Za-z_][A-Za-z0-9_\\.]*\\s*>\\s+([A-Za-z_][A-Za-z0-9_]*)\\b'
      )
      .matcher(scan);
    while (mapDecl.find()) {
      String varName = mapDecl.group(1);
      if (String.isBlank(varName))
        continue;
      String v = varName.toLowerCase();

      Boolean hasKeyRead = Pattern.compile(
          '(?i)\\b' + v + '\\s*\\.\\s*(containskey|get)\\s*\\('
        )
        .matcher(lower)
        .find();
      Boolean hasPut = Pattern.compile('(?i)\\b' + v + '\\s*\\.\\s*put\\s*\\(')
        .matcher(lower)
        .find();

      if (hasKeyRead && hasPut)
        return true;
    }

    // 4) Guard helper utility calls (common patterns)
    //This catches patterns like RecursionGuard.runOnce(...), Guard.enter(...), etc.
    if (
      Pattern.compile(
          '(?i)\\b(recursionguard|guard)\\s*\\.\\s*(runonce|enter|check|checkandset|acquire|lock)\\s*\\('
        )
        .matcher(scan)
        .find()
    )
      return true;

    return false;
  }

  private static Set<String> extractReferencedObjectApiNames(String body) {
    Set<String> out = new Set<String>();
    if (String.isBlank(body))
      return out;

    // 1) SOQL FROM <Object>
    Matcher soqlFrom = Pattern.compile(
        '(?i)\\bFROM\\s+([A-Za-z_][A-Za-z0-9_]*)'
      )
      .matcher(body);
    while (soqlFrom.find()) {
      String obj = soqlFrom.group(1);
      if (isPlausibleSObjectName(obj))
        out.add(obj);
    }

    // 2) Type usage in generics: List<Object>, Map<Id, Object>, Set<Object>
    Matcher gen = Pattern.compile(
        '(?i)\\b(List|Set)\\s*<\\s*([A-Za-z_][A-Za-z0-9_]*)\\b'
      )
      .matcher(body);
    while (gen.find()) {
      String obj = gen.group(2);
      if (isPlausibleSObjectName(obj))
        out.add(obj);
    }

    Matcher mapVal = Pattern.compile(
        '(?i)\\bMap\\s*<\\s*Id\\s*,\\s*([A-Za-z_][A-Za-z0-9_]*)\\b'
      )
      .matcher(body);
    while (mapVal.find()) {
      String obj = mapVal.group(1);
      if (isPlausibleSObjectName(obj))
        out.add(obj);
    }

    // 3) "new Object(" usage
    Matcher ctor = Pattern.compile(
        '(?i)\\bnew\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\('
      )
      .matcher(body);
    while (ctor.find()) {
      String obj = ctor.group(1);
      if (isPlausibleSObjectName(obj))
        out.add(obj);
    }

    return out;
  }

  private static Boolean hasStrongObjectReference(
    String body,
    String objApiName
  ) {
    if (String.isBlank(body) || String.isBlank(objApiName))
      return false;

    String lowerBody = body.toLowerCase();
    String lowerObj = objApiName.toLowerCase();

    // SOQL reference: FROM Object__c
    if (lowerBody.contains('from ' + lowerObj))
      return true;

    // Object instantiation: new Object__c(
    if (lowerBody.contains('new ' + lowerObj + '('))
      return true;

    // Generic usage: List<Object__c>, Set<Object__c>
    if (lowerBody.contains('<' + lowerObj + '>'))
      return true;

    // Map usage: Map<Id, Object__c>
    if (lowerBody.contains(', ' + lowerObj + '>'))
      return true;

    return false;
  }

  private static Integer findBestHighlightPos(String body, String objApiName) {
    if (String.isBlank(body) || String.isBlank(objApiName))
      return null;

    String lowerBody = body.toLowerCase();
    String lowerObj = objApiName.toLowerCase();

    // 1) SOQL FROM <Object>
    Integer p = lowerBody.indexOf('from ' + lowerObj);
    if (p >= 0)
      return p;

    // 2) new <Object>(
    p = lowerBody.indexOf('new ' + lowerObj + '(');
    if (p >= 0)
      return p;

    // 3) Generic usage <Object>
    p = lowerBody.indexOf('<' + lowerObj + '>');
    if (p >= 0)
      return p;

    // 4) Fallback: any mention of object name
    p = lowerBody.indexOf(lowerObj);
    if (p >= 0)
      return p;

    return null;
  }

  private static Boolean isPlausibleSObjectName(String token) {
    if (String.isBlank(token))
      return false;

    // Avoid common non-sObject tokens
    Set<String> bad = new Set<String>{
      'String',
      'Integer',
      'Long',
      'Decimal',
      'Double',
      'Boolean',
      'Date',
      'Datetime',
      'Time',
      'List',
      'Set',
      'Map',
      'Object',
      'Exception',
      'System',
      'Math',
      'Pattern',
      'Matcher',
      'Database',
      'Schema',
      'Id',
      'Void'
    };
    if (bad.contains(token))
      return false;

    // Typical sObject patterns: Account, Contact, MyObject__c, Something__mdt
    if (
      token.endsWith('__c') ||
      token.endsWith('__mdt') ||
      token.endsWith('__e')
    )
      return true;

    // Standard objects are PascalCase words; allow them too
    if (Pattern.compile('^[A-Z][A-Za-z0-9_]*$').matcher(token).matches())
      return true;

    return false;
  }

  // Order-of-execution risk detection
  private static List<Finding> detectOrderOfExecutionRisks(TriggerContext ctx) {
    List<Finding> out = new List<Finding>();
    if (ctx == null || ctx.universe == null)
      return out;

    String body = ctx.body != null ? ctx.body.toLowerCase() : '';
    String obj = ctx.objectApiName;

    // 1) Multiple triggers on same object
    if (
      !String.isBlank(obj) &&
      ctx.universe.objectToTriggers != null &&
      ctx.universe.objectToTriggers.containsKey(obj) &&
      ctx.universe.objectToTriggers.get(obj).size() > 1
    ) {
      Finding f = new Finding();
      f.ruleKey = 'MULTIPLE_TRIGGERS_SAME_OBJECT';
      f.ruleLabel = 'Multiple Triggers on Same Object';
      f.category = 'OrderOfExecution';
      f.severity = 'Medium';
      f.matchPos = 0;
      f.lineNumber = 1;
      f.message =
        'Multiple triggers exist on object ' +
        obj +
        '. Salesforce does not guarantee execution order across triggers, ' +
        'which can cause unpredictable behavior.';
      out.add(f);
    }
    //Accurate BEFORE/AFTER detection (header only)
    // Detect trigger timing
    //Boolean isBefore = body.contains('before');
    //Boolean isAfter  = body.contains('after');
    String headerLower = ctx.body != null ? ctx.body.toLowerCase() : '';
    Integer bracePos = headerLower.indexOf('{');
    if (bracePos >= 0)
      headerLower = headerLower.substring(0, bracePos);

    Integer lp = headerLower.indexOf('(');
    Integer rp = headerLower.indexOf(')', lp + 1);
    String events = (lp >= 0 &&
      rp > lp)
      ? headerLower.substring(lp + 1, rp)
      : headerLower;

    Boolean isBefore = events.contains('before');
    Boolean isAfter = events.contains('after');

    // 2) DML inside BEFORE trigger
    if (isBefore && containsActualDmlStatement(ctx.body)) {
      Finding f = new Finding();
      f.ruleKey = 'DML_IN_BEFORE_TRIGGER';
      f.ruleLabel = 'DML in BEFORE Trigger';
      f.category = 'OrderOfExecution';
      f.severity = 'High';
      f.matchPos = 0;
      f.lineNumber = 1;
      f.message =
        'DML detected inside a BEFORE trigger. ' +
        'This can cause recursion and makes execution order hard to reason about.';
      out.add(f);
    }

    // 3) Modifying Trigger.new in AFTER trigger
    Integer afterMutPos = findAfterTriggerNewMutationPos(
      ctx.body,
      body,
      isBefore,
      isAfter
    );
    if (afterMutPos >= 0) {
      Finding f = new Finding();
      f.ruleKey = 'AFTER_TRIGGER_MUTATION';
      f.ruleLabel = 'Trigger.new Modified in AFTER Trigger';
      f.category = 'OrderOfExecution';
      f.severity = 'Medium';
      //f.matchPos = body.indexOf('trigger.new');
      f.matchPos = afterMutPos;
      f.lineNumber = computeLineNumber(ctx.body, f.matchPos);
      f.message =
        'Trigger.new appears to be modified in an AFTER trigger. ' +
        'Record field changes should usually occur in BEFORE triggers.';
      out.add(f);
    }

    return out;
  }

  private class BulkScoreResult {
    Integer score;
    String level; // High / Medium / Low
    String deductions; // human readable summary
  }

  private static Finding buildBulkConfidenceFinding(
    TriggerContext ctx,
    List<Finding> existingFindings
  ) {
    if (ctx == null)
      return null;

    BulkScoreResult r = computeBulkConfidenceScore(ctx, existingFindings);
    if (r == null)
      return null;

    Finding f = new Finding();
    f.ruleKey = 'BULK_CONFIDENCE_SCORE';
    f.ruleLabel = 'Bulkification Confidence Score';
    f.category = 'BulkScore';
    f.severity = 'Low'; // informational only
    f.matchPos = 0;
    f.lineNumber = 1;

    String tName = String.isBlank(ctx.triggerName)
      ? 'Trigger'
      : ctx.triggerName;

    String msg = (r.level == 'High')
      ? 'Bulk-safe patterns detected.'
      : 'Bulk safety concerns detected.';

    if (!String.isBlank(r.deductions)) {
      msg += '\n\nPrimary considerations:';

      for (String d : r.deductions.split(',\\s*')) {
        if (d.contains('DML_IN_LOOP')) {
          msg += '\n• DML is executed inside a loop, which can cause governor limit issues under bulk load.';
        } else if (d.contains('SOQL_IN_LOOP')) {
          msg += '\n• SOQL is executed inside a loop, which may exceed query limits when processing multiple records.';
        } else if (d.contains('CROSS_TRIGGER_RECURSION_CYCLE')) {
          msg += '\n• A cross-trigger recursion pattern was detected, increasing the risk of repeated execution.';
        } else if (d.contains('RECURSION_RISK')) {
          msg += '\n• Recursion risk is present but partially guarded.';
        } else {
          msg +=
            '\n• ' +
            d.replaceAll('\\(.*\\)', '').replace('_', ' ').toLowerCase();
        }
      }
    } else {
      msg += '\n\nNo high-impact bulk processing risks were identified.';
    }
    if (r.level != 'High' || !String.isBlank(r.deductions)) {
      msg += '\n\nThis trigger is functional but may require refactoring before deployment to high-volume environments.';
    } else {
      msg += '\n\nThis trigger looks ready for higher-volume environments based on detected patterns.';
    }
    f.message = msg;

    return f;
  }

  private static BulkScoreResult computeBulkConfidenceScore(
    TriggerContext ctx,
    List<Finding> findings
  ) {
    BulkScoreResult out = new BulkScoreResult();
    Integer score = 100;

    List<String> ded = new List<String>();
    // Build rule-key set so we can avoid double-penalizing similar risks
    Set<String> keysPresent = new Set<String>();
    if (findings != null) {
      for (Finding fx : findings) {
        if (fx != null && !String.isBlank(fx.ruleKey)) {
          keysPresent.add(fx.ruleKey);
        }
      }
    }

    // Scoring-only dedupe rules (do NOT remove findings from the UI)
    Set<String> skipForScoring = new Set<String>();
    if (keysPresent.contains('DML_IN_LOOP')) {
      skipForScoring.add('SINGLE_RECORD_DML');
    }
    if (keysPresent.contains('CROSS_TRIGGER_RECURSION_CYCLE')) {
      skipForScoring.add('RECURSION_RISK');
    }

    // Deduct based on existing findings (ruleKey-based)
    if (findings != null) {
      for (Finding f : findings) {
        if (f == null || String.isBlank(f.ruleKey))
          continue;

        // Skip self
        if (f.ruleKey == 'BULK_CONFIDENCE_SCORE')
          continue;

        // Skip redundant deductions (scoring only)
        if (skipForScoring.contains(f.ruleKey))
          continue;

        Integer d = bulkDeductionForRuleKey(f.ruleKey, f.severity);
        if (d > 0) {
          score -= d;
          ded.add(f.ruleKey + '(-' + String.valueOf(d) + ')');
        }
      }
    }

    // Small additional heuristic deductions based on body patterns (safe + explainable)
    String body = (ctx.body == null) ? '' : ctx.body;

    Boolean usesCollections = Pattern.compile('(?i)\\b(List|Set|Map)\\s*<')
      .matcher(body)
      .find();

    // Only apply the "no collections" deduction if the trigger body appears to do real work.
    // IMPORTANT: do NOT match trigger header words like "before insert, before update".
    Boolean hasRealDml = containsActualDmlStatement(body);
    Boolean hasRealSoql = Pattern.compile(
        '(?i)(\\[\\s*SELECT\\b|\\bDatabase\\.(query|getQueryLocator)\\s*\\()'
      )
      .matcher(body)
      .find();

    if (!usesCollections && (hasRealDml || hasRealSoql)) {
      score -= 5;
      ded.add('NO_COLLECTIONS_PATTERN(-5)');
    }
    // Clamp score
    if (score < 0)
      score = 0;
    if (score > 100)
      score = 100;

    out.score = score;
    out.level = (score >= 80) ? 'High' : (score >= 60) ? 'Medium' : 'Low';
    out.deductions = String.join(ded, ', ');

    return out;
  }

  private static Integer bulkDeductionForRuleKey(
    String ruleKey,
    String severity
  ) {
    // Soften penalties when guards exist
    // If severity is Medium (guard detected), reduce deduction
    Boolean guarded = (severity == 'Medium');

    // SOQL / DML risks
    if (ruleKey == 'SOQL_IN_LOOP')
      return 30;
    if (ruleKey == 'DML_IN_LOOP')
      return 25;
    if (ruleKey == 'MIXED_DML')
      return 25;
    if (ruleKey == 'CALLOUT_IN_TRIGGER')
      return 20;
    if (ruleKey == 'EMAIL_IN_TRIGGER')
      return 10;

    // Recursion risks
    if (ruleKey == 'RECURSION_RISK') {
      return guarded ? 5 : 15;
    }

    if (ruleKey == 'CROSS_TRIGGER_RECURSION_CYCLE') {
      return guarded ? 10 : 20;
    }

    // Order-of-execution risks
    if (ruleKey == 'MULTIPLE_TRIGGERS_SAME_OBJECT')
      return 5;
    if (ruleKey == 'AFTER_TRIGGER_MUTATION')
      return 5;
    if (ruleKey == 'DML_IN_BEFORE_TRIGGER')
      return 15;

    // Maintainability
    if (ruleKey == 'TRIGGER_HANDLER_MISSING')
      return 3;

    return 0;
  }
  /*** Counts non-empty, non-comment lines to estimate trigger complexity.*/
  private static Integer countEffectiveLines(String body) {
    if (String.isBlank(body))
      return 0;

    Integer count = 0;
    for (String line : body.split('\n')) {
      String l = line.trim();
      if (
        l == '' ||
        l.startsWith('//') ||
        l.startsWith('/*') ||
        l.startsWith('*')
      ) {
        continue;
      }
      count++;
    }
    return count;
  }

  private static String maskCommentsAndStringsPreserveLength(String input) {
    if (String.isBlank(input))
      return input;

    Integer n = input.length();
    List<String> out = new List<String>();

    Boolean inLineComment = false;
    Boolean inBlockComment = false;
    Boolean inString = false;

    for (Integer i = 0; i < n; i++) {
      String ch = input.substring(i, i + 1);

      if (inLineComment) {
        out.add(ch == '\n' ? '\n' : ' ');
        if (ch == '\n')
          inLineComment = false;
        continue;
      }

      if (inBlockComment) {
        if (i + 1 < n && input.substring(i, i + 2) == '*/') {
          out.add(' ');
          out.add(' ');
          i++;
          inBlockComment = false;
        } else {
          out.add(ch == '\n' ? '\n' : ' ');
        }
        continue;
      }

      if (inString) {
        out.add(ch == '\n' ? '\n' : ' ');
        if (ch == '\\') {
          if (i + 1 < n) {
            out.add(' ');
            i++;
          }
          continue;
        }
        if (ch == '\'')
          inString = false;
        continue;
      }

      if (i + 1 < n) {
        String two = input.substring(i, i + 2);
        if (two == '//') {
          out.add(' ');
          out.add(' ');
          i++;
          inLineComment = true;
          continue;
        }
        if (two == '/*') {
          out.add(' ');
          out.add(' ');
          i++;
          inBlockComment = true;
          continue;
        }
      }

      if (ch == '\'') {
        out.add(' ');
        inString = true;
        continue;
      }

      out.add(ch);
    }

    return String.join(out, '');
  }
  private static String maskCommentsPreserveLength(String input) {
    if (String.isBlank(input))
      return input;

    Integer n = input.length();
    List<String> out = new List<String>();

    Boolean inLine = false;
    Boolean inBlock = false;

    for (Integer i = 0; i < n; i++) {
      String ch = input.substring(i, i + 1);

      if (inLine) {
        out.add(ch == '\n' ? '\n' : ' ');
        if (ch == '\n')
          inLine = false;
        continue;
      }

      if (inBlock) {
        if (i + 1 < n && input.substring(i, i + 2) == '*/') {
          out.add(' ');
          out.add(' ');
          i++;
          inBlock = false;
        } else {
          out.add(ch == '\n' ? '\n' : ' ');
        }
        continue;
      }

      if (i + 1 < n) {
        String two = input.substring(i, i + 2);
        if (two == '//') {
          out.add(' ');
          out.add(' ');
          i++;
          inLine = true;
          continue;
        }
        if (two == '/*') {
          out.add(' ');
          out.add(' ');
          i++;
          inBlock = true;
          continue;
        }
      }

      out.add(ch);
    }

    return String.join(out, '');
  }
}

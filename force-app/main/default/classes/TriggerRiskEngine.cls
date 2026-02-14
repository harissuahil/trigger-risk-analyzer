// CLASS: TriggerRiskEngine
public with sharing class TriggerRiskEngine {

    // =====================
    // Inner Models
    // =====================
    public class Finding {
        public String ruleKey;
        public String ruleLabel;
        public String severity;     // Low / Medium / High
        public String category;
        public String message;
        public Integer lineNumber;  // best effort
        public Integer matchPos;    // best effort
    }

    public class RiskResult {
        public String risk;                 // Low / Medium / High
        public List<String> reasons;        // messages
        public List<String> matchedKeys;    // rule keys
        public Integer lineNumber;          // earliest matched line
    }

    // ====== PHASE3 ======
    // Context Models (multi-trigger awareness)
    public class TriggerUniverse {
        public Map<String, String> triggerNameToBody;      // trigger name -> body
        public Map<String, String> triggerNameToObjectApi; // trigger name -> object api name
        public Map<String, Set<String>> objectToTriggers;  // object api name -> trigger names
    }

    public class TriggerContext {
        public String triggerName;
        public String objectApiName;
        public String body;
        public TriggerUniverse universe;
    }
    // ====== PHASE3 ======

    // =====================
    // Main Analyzer (existing)
    // =====================
    public static List<Finding> analyzeFindings(String body) {
        List<Finding> findings = new List<Finding>();
        if (String.isBlank(body)) return findings;

        // Load rules from custom metadata
        List<Trigger_Risk_Rule__mdt> rules = [
            SELECT DeveloperName, Label, Rule_Key__c, Severity__c,
                   Pattern__c, Message__c, Category__c,
                   Detection_Mode__c, Is_Enabled__c 
            FROM Trigger_Risk_Rule__mdt
        ];


        // Map rules by key
        Map<String, Trigger_Risk_Rule__mdt> ruleByKey = new Map<String, Trigger_Risk_Rule__mdt>();
        for (Trigger_Risk_Rule__mdt r : rules) {
            String k = String.isBlank(r.Rule_Key__c) ? r.DeveloperName : r.Rule_Key__c;
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
        Trigger_Risk_Rule__mdt soqlRule = ruleByKey.get('SOQL_IN_LOOP'); //HS
        if (soqlPos != null && soqlRule != null && soqlRule.Is_Enabled__c && soqlRule.Detection_Mode__c == 'ENGINE') { //HS
            Trigger_Risk_Rule__mdt r = soqlRule; //HS

            Finding f = new Finding();
            f.ruleKey   = 'SOQL_IN_LOOP';
            f.ruleLabel = r != null ? r.Label : 'SOQL in Loop';
            f.severity  = r != null ? r.Severity__c : 'High';
            f.category  = r != null ? r.Category__c : 'BulkRisk';
            f.message   = r != null ? r.Message__c : 'SOQL inside a loop can hit query limits in bulk.';
            f.matchPos  = soqlPos;
            f.lineNumber = computeLineNumber(body, soqlPos);

            findings.add(f);
            addedKeys.add(f.ruleKey);
        }
        //==========BUG FIX #7 - Engine-driven DML in loop (avoid regex false positives)==========
            Integer dmlLoopPos = findDmlInLoopPosition(body);
            Trigger_Risk_Rule__mdt dmlLoopRule = ruleByKey.get('DML_IN_LOOP'); //HS
            if (dmlLoopPos != null && dmlLoopRule != null && dmlLoopRule.Is_Enabled__c && dmlLoopRule.Detection_Mode__c == 'ENGINE') { //HS
                Trigger_Risk_Rule__mdt r = dmlLoopRule; //HS

            
            Finding f = new Finding();
            f.ruleKey   = 'DML_IN_LOOP';
            f.ruleLabel = r != null ? r.Label : 'DML in Loop';
            f.severity  = r != null ? r.Severity__c : 'High';
            f.category  = r != null ? r.Category__c : 'BulkRisk';
            f.message   = r != null ? r.Message__c : 'DML inside a loop can hit governor limits and fail in bulk.';
            f.matchPos  = dmlLoopPos;
            f.lineNumber = computeLineNumber(body, dmlLoopPos);
            
            findings.add(f);
            addedKeys.add(f.ruleKey); // prevents regex rule from also firing
        }
        //==========BUG FIX #7 END==========


        // Recursion risk
        Trigger_Risk_Rule__mdt recRule = ruleByKey.get('RECURSION_RISK'); //HS
        Finding rec = null; //HS
        if (recRule != null && recRule.Is_Enabled__c && recRule.Detection_Mode__c == 'ENGINE') { //HS
            rec = detectRecursionRisk(body, ruleByKey); //HS
        } //HS
        
        if (rec != null && !addedKeys.contains(rec.ruleKey)) {
            findings.add(rec);
            addedKeys.add(rec.ruleKey);
        }

        // Missing trigger handler
        Trigger_Risk_Rule__mdt mhRule = ruleByKey.get('TRIGGER_HANDLER_MISSING'); //HS
        Finding mh = null; //HS
        if (mhRule != null && mhRule.Is_Enabled__c && mhRule.Detection_Mode__c == 'ENGINE') { //HS
            mh = detectMissingHandlerPattern(body, ruleByKey); //HS
        } //HS

        if (mh != null && !addedKeys.contains(mh.ruleKey)) {
            findings.add(mh);
            addedKeys.add(mh.ruleKey);
        }
        //==========BUG FIX #9 - Engine-driven ENQUEUE_IN_LOOP========== //HS
        Trigger_Risk_Rule__mdt enqRule = ruleByKey.get('ENQUEUE_IN_LOOP'); //HS
        Finding enq = null; //HS
        if (enqRule != null && enqRule.Is_Enabled__c && enqRule.Detection_Mode__c == 'ENGINE') { //HS
            enq = detectEnqueueInLoop(body, ruleByKey); //HS
        } //HS
        
        if (enq != null && !addedKeys.contains(enq.ruleKey)) { //HS
            findings.add(enq); //HS
            addedKeys.add(enq.ruleKey); //HS
        } //HS
        //==========BUG FIX #9 END========== //HS
        //==========HS EMAIL_IN_TRIGGER - Engine-driven detection (ignore comments/strings)========== //HS
        Trigger_Risk_Rule__mdt emailRule = ruleByKey.get('EMAIL_IN_TRIGGER'); //HS
        Finding emailFinding = null; //HS
        if (emailRule != null && emailRule.Is_Enabled__c && emailRule.Detection_Mode__c == 'ENGINE') { //HS
            emailFinding = detectEmailInTrigger(body, ruleByKey); //HS
        } //HS
        if (emailFinding != null && !addedKeys.contains(emailFinding.ruleKey)) { //HS
            findings.add(emailFinding); //HS
            addedKeys.add(emailFinding.ruleKey); //HS
        } //HS
        //==========HS EMAIL_IN_TRIGGER END========== //HS
        //==========BUG FIX #11 - Engine-driven DML_ON_TRIGGER_OLD========== //HS
        Trigger_Risk_Rule__mdt dmlOldRule = ruleByKey.get('DML_ON_TRIGGER_OLD'); 
        Finding dmlOld = null; 
        if (dmlOldRule != null && dmlOldRule.Is_Enabled__c && dmlOldRule.Detection_Mode__c == 'ENGINE') { 
            dmlOld = detectDmlOnTriggerOld(body, ruleByKey); //HS
        } 
        
        if (dmlOld != null && !addedKeys.contains(dmlOld.ruleKey)) { 
            findings.add(dmlOld); 
            addedKeys.add(dmlOld.ruleKey); 
        } //HS
        //==========BUG FIX #11 END========== //HS

        // =====================
        // Regex-driven checks
        // =====================

        for (Trigger_Risk_Rule__mdt r : rules) {
            String key = String.isBlank(r.Rule_Key__c) ? r.DeveloperName : r.Rule_Key__c;
            if (String.isBlank(key)
                || addedKeys.contains(key)
                || !r.Is_Enabled__c //HS
                || r.Detection_Mode__c == 'ENGINE' //HS
                || String.isBlank(r.Pattern__c)) {
                    continue;
                }

            Pattern p;
            try {
                p = Pattern.compile('(?i)' + r.Pattern__c);
            } catch (Exception e) {
                continue;
            }

           	// Matcher m = p.matcher(body);
            //HS Use masked text for a few regex rules to avoid matching comments/strings
          /**  String scanText = body;
            if (key == 'TRIGGER_NEW_INDEX'|| key == 'DYNAMIC_SOQL'|| key == 'HARDCODED_ID') { 
                scanText = maskCommentsAndStringsPreserveLength(body); 
            } ================================================================================***/
            /*===================================================================================
            String scanText = body;
            if (key == 'TRIGGER_NEW_INDEX' || key == 'DYNAMIC_SOQL') {
                scanText = maskCommentsAndStringsPreserveLength(body);
            } else if (key == 'HARDCODED_ID') { 
                scanText = maskCommentsPreserveLength(body); 
            }

            Matcher m = p.matcher(scanText); 
			====================================================================================***/
            String scanText = maskCommentsAndStringsPreserveLength(body);
            if (key == 'HARDCODED_ID') {
                scanText = maskCommentsPreserveLength(body);
            }
            Matcher m = p.matcher(scanText);

            if (!m.find()) continue;
            Integer firstPos = m.start(); //HS
            Integer matchPos = firstPos;  //HS
            //HS: Special highlight logic for callouts
            if (key == 'CALLOUT_IN_TRIGGER') { //HS
                //HS: 1) Prefer the actual execution call (.send()
                Matcher sendM = Pattern.compile('\\.send\\s*\\(').matcher(scanText); //HS
                if (sendM.find()) { //HS
                    matchPos = sendM.start(); //HS
                } else { //HS
                    //HS: 2) Next, prefer PageReference.getContent / getContentAsPDF
                    Matcher contentM = Pattern.compile('\\bPageReference\\.getContent\\b|\\bgetContentAsPDF\\b')
                        .matcher(scanText); //HS
                    if (contentM.find()) { //HS
                        matchPos = contentM.start(); //HS
                    } //HS
                } //HS
            } //HS
            
            Finding f = new Finding();
            f.ruleKey   = key;
            f.ruleLabel = r.Label;
            f.severity  = String.isBlank(r.Severity__c) ? 'Low' : r.Severity__c;
            f.category  = r.Category__c;
            f.message   = r.Message__c;
           /* f.matchPos  = m.start();
            f.lineNumber = computeLineNumber(body, m.start());*/
            f.matchPos  = matchPos; //HS
            f.lineNumber = computeLineNumber(body, matchPos); //HS
            findings.add(f);
            addedKeys.add(key);
        }
        
        findings.sort(new FindingSorter());
        return findings;
    }

    // ====== PHASE3 ======
    // Main Analyzer (context-aware overload)
    public static List<Finding> analyzeFindings(TriggerContext ctx) {
        if (ctx == null) return new List<Finding>();
    
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
    
        // Phase 3.1: Cross-trigger recursion cycle detection
        Finding cross = detectCrossTriggerRecursionCycle(ctx);
        if (cross != null && !existing.contains(cross.ruleKey)) {
            findings.add(cross);
            existing.add(cross.ruleKey);
        }
    
        // Phase 3.2: Trigger order-of-execution risks
        List<Finding> orderFindings = detectOrderOfExecutionRisks(ctx);
        if (orderFindings != null && !orderFindings.isEmpty()) {
            for (Finding ordFinding : orderFindings) {
                if (ordFinding != null && !existing.contains(ordFinding.ruleKey)) {
                    findings.add(ordFinding);
                    existing.add(ordFinding.ruleKey);
                }
            }
        }
    
        //==========Phase3.3 START code change=========
        // Phase 3.3: Bulkification confidence scoring (one informational finding per trigger)
        Finding bulkScore = buildBulkConfidenceFinding(ctx, findings);
        if (bulkScore != null && !existing.contains(bulkScore.ruleKey)) {
            findings.add(bulkScore);
            existing.add(bulkScore.ruleKey);
        }
        //==========Phase3.3 END code change=========
    
        findings.sort(new FindingSorter());
        return findings;
    }


    // ====== PHASE3 ======

    // =====================
    // Sorter
    // =====================
    private class FindingSorter implements Comparator<Finding> {
        public Integer compare(Finding a, Finding b) {
            Integer ra = rank(a.severity);
            Integer rb = rank(b.severity);
            if (ra != rb) return rb - ra;

            if (a.lineNumber == null) return 1;
            if (b.lineNumber == null) return -1;
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
            if (body.substring(i, i + 1) == '\n') line++;
        }
        return line;
    }

    private static Integer rank(String risk) {
        if (risk == 'High') return 3;
        if (risk == 'Medium') return 2;
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
        if (String.isBlank(body)) return null; //HS
        
        String scan = maskCommentsAndStringsPreserveLength(body); //HS
        
        for (BlockSpan b : findLoopBlocks(scan)) { //HS
            Integer rel = findSoqlPosition(scan.substring(b.startPos, b.endPos)); //HS
            if (rel != null) return b.startPos + rel; //HS
        }
        return null;
    }

    //==========BUG FIX #7 - Engine-driven DML in loop finder==========
  /***  private static Integer findDmlInLoopPosition(String body) {
        if (String.isBlank(body)) return null;
        
        for (BlockSpan b : findLoopBlocks(body)) {
            String segment = body.substring(b.startPos, b.endPos);
            
            Integer rel = findDmlPosition(segment);
            if (rel != null) return b.startPos + rel;
        }
        return null;
    } ***/
    //==========BUG FIX #8 - DML in loop supports no-brace loops==========
    private static Integer findDmlInLoopPosition(String body) { //HS
        if (String.isBlank(body)) return null; //HS
        
        // Use masked scan so loops in comments/strings do not interfere, but positions remain aligned
        String scan = maskCommentsAndStringsPreserveLength(body); //HS
        
        // ---------- for/while loops ----------
        Matcher m = Pattern.compile('(?m)^\\s*(for|while)\\b').matcher(scan); //HS
        while (m.find()) { //HS
            Integer loopHeaderPos = m.start(); //HS
            Integer headerEnd = findLoopHeaderEndPos(scan, m.start(), m.group(0)); //HS
            if (headerEnd == null) continue; //HS
            
            // Skip whitespace after the full header
            Integer j = headerEnd; //HS
            while (j < scan.length()) { //HS
                String ch = scan.substring(j, j + 1); //HS
                if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n') break; //HS
                j++; //HS
            } //HS
            
            // Braced loop
            if (j < scan.length() && scan.substring(j, j + 1) == '{') { //HS
                Integer open = j; //HS
                Integer close = findMatchingBrace(scan, open); //HS
                if (close != null) { //HS
                    String loopSegment = scan.substring(open, close + 1); //HS
                    Integer rel = findDmlPosition(loopSegment); //HS
                    if (rel != null) return loopHeaderPos; //HS
                } //HS
                continue; //HS
            } //HS
            
            // No-brace loop
            Integer stmtEnd = findStatementEndPos(scan, headerEnd); //HS
            if (stmtEnd == null) stmtEnd = Math.min(scan.length(), headerEnd + 400); //HS
            
            String afterHeader = scan.substring(headerEnd, stmtEnd); //HS
            Integer rel2 = findDmlPosition(afterHeader); //HS
            if (rel2 != null) return loopHeaderPos; //HS
        } //HS
        // ---------- do { ... } while (...) ----------
        Matcher d = Pattern.compile('(?m)^\\s*do\\b').matcher(scan); //HS
        while (d.find()) { //HS
            Integer doPos = d.start(); //HS
            Integer doEnd = d.end(); //HS
            
            // Skip whitespace after "do"
            Integer j = doEnd; //HS
            while (j < scan.length()) { //HS
                String ch = scan.substring(j, j + 1); //HS
                if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n') break; //HS
                j++; //HS
            } //HS
            
            // Braced do
            if (j < scan.length() && scan.substring(j, j + 1) == '{') { //HS
                Integer open = j; //HS
                Integer close = findMatchingBrace(scan, open); //HS
                if (close != null) { //HS
                    String loopSegment = scan.substring(open, close + 1); //HS
                    Integer rel = findDmlPosition(loopSegment); //HS
                    if (rel != null) return doPos; //HS
                } //HS
                continue; //HS
            } //HS
            
            // No-brace do
            Integer stmtEnd = findStatementEndPos(scan, doEnd); //HS
            if (stmtEnd == null) stmtEnd = Math.min(scan.length(), doEnd + 400); //HS
            
            String stmt = scan.substring(doEnd, stmtEnd); //HS
            Integer rel2 = findDmlPosition(stmt); //HS
            if (rel2 != null) return doPos; //HS
        } //HS
        
        return null; //HS
    } //HS
    //==========BUG FIX #8 END========== //HS

    //Returns relative position of DML keyword inside a string segment, ignoring comments and string literals
    private static Integer findDmlPosition(String segment) {
        if (String.isBlank(segment)) return null;
        
        Integer n = segment.length();
        Boolean inLineComment = false;
        Boolean inBlockComment = false;
        Boolean inString = false;
        
        for (Integer i = 0; i < n; i++) {
            String ch = segment.substring(i, i + 1);
            
            if (inLineComment) {
                if (ch == '\n') inLineComment = false;
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
                    if (i + 1 < n) i++;
                    continue;
                }
                if (ch == '\'') inString = false;
                continue;
            }
            
            if (i + 1 < n) {
                String two = segment.substring(i, i + 2);
                if (two == '//') { inLineComment = true; i++; continue; }
                if (two == '/*') { inBlockComment = true; i++; continue; }
            }
            
            if (ch == '\'') { inString = true; continue; }
            //HS Left-boundary guard: prevent matching DML keywords inside identifiers like Trigger.isUpdate
            if (i > 0) { 
                String prev = segment.substring(i - 1, i).toLowerCase(); 
                if ((prev >= 'a' && prev <= 'z') || (prev >= '0' && prev <= '9') || prev == '_') { 
                    continue; 
                } 
            } 

            
            String tail = segment.substring(i).toLowerCase();
            
            if (startsWithWord(tail, 'database.insert') ||
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
                startsWithWord(tail, 'merge')) {
                    return i;
                }
        }
        
        return null;
    }
    
    private static Boolean startsWithWord(String tail, String word) {
        if (!tail.startsWith(word)) return false;
        
        Integer len = word.length();
        if (tail.length() == len) return true;
        
        String next = tail.substring(len, len + 1);
        return !(next >= 'a' && next <= 'z') && !(next >= '0' && next <= '9') && next != '_';
    }
    //==========BUG FIX #7 END==========
    
    private static List<BlockSpan> findLoopBlocks(String body) {
        List<BlockSpan> blocks = new List<BlockSpan>();
        Matcher m = Pattern.compile('(?m)^\\s*(for|while)\\b').matcher(body); //HS
        
        while (m.find()) { //HS
            Integer headerEnd = findLoopHeaderEndPos(body, m.start(), m.group(0)); //HS
            if (headerEnd == null) continue; //HS
            
            // Find the next non-whitespace char after the loop header
            Integer j = headerEnd; //HS
            while (j < body.length()) { //HS
                String ch = body.substring(j, j + 1); //HS
                if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n') break; //HS
                j++; //HS
            } //HS
            
            // Case A: Braced loop: for/while(...) { ... }
            if (j < body.length() && body.substring(j, j + 1) == '{') { //HS
                Integer open = j; //HS
                Integer close = findMatchingBrace(body, open);
                if (close != null) {
                    BlockSpan b = new BlockSpan();
                    b.startPos = open;
                    b.endPos = close + 1;
                    blocks.add(b);
                }
                continue; //HS
            }
            
            // Case B: Single-statement loop: for/while(...) doSomething();
            Integer stmtEnd = findStatementEndPos(body, headerEnd); //HS
            if (stmtEnd != null && stmtEnd > headerEnd) { //HS
                BlockSpan b2 = new BlockSpan(); //HS
                b2.startPos = headerEnd; //HS
                b2.endPos   = stmtEnd;  //HS
                blocks.add(b2); //HS
            } //HS
        }
        // Case C: do { ... } while (...);
        Matcher d = Pattern.compile('(?m)^\\s*do\\b').matcher(body); //HS
        while (d.find()) { //HS
            Integer doEnd = d.end(); //HS
            
            // Skip whitespace after "do"
            Integer j = doEnd; //HS
            while (j < body.length()) { //HS
                String ch = body.substring(j, j + 1); //HS
                if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n') break; //HS
                j++; //HS
            } //HS
            
            // Braced do: do { ... } while (...)
            if (j < body.length() && body.substring(j, j + 1) == '{') { //HS
                Integer open = j; //HS
                Integer close = findMatchingBrace(body, open); //HS
                if (close != null) { //HS
                    BlockSpan b3 = new BlockSpan(); //HS
                    b3.startPos = open; //HS
                    b3.endPos   = close + 1; //HS
                    blocks.add(b3); //HS
                } //HS
                continue; //HS
            } //HS
            
            // No-brace do: do singleStatement; while (...);
            Integer stmtEnd = findStatementEndPos(body, doEnd); //HS
            if (stmtEnd != null && stmtEnd > doEnd) { //HS
                BlockSpan b4 = new BlockSpan(); //HS
                b4.startPos = doEnd; //HS
                b4.endPos   = stmtEnd; //HS
                blocks.add(b4); //HS
            } //HS
        } //HS
        return blocks;
    }

    private static Integer findMatchingBrace(String body, Integer start) {
        Integer depth = 0;
        for (Integer i = start; i < body.length(); i++) {
            if (body.substring(i, i + 1) == '{') depth++;
            if (body.substring(i, i + 1) == '}' && --depth == 0) return i;
        }
        return null;
    }
    //HS Finds best-effort end of the next Apex statement after a loop header (supports no-brace loops)
    private static Integer findStatementEndPos(String body, Integer startPos) { //HS
        if (String.isBlank(body) || startPos == null) return null; //HS
        
        Integer n = body.length(); //HS
        Boolean inLineComment = false; //HS
        Boolean inBlockComment = false; //HS
        Boolean inString = false; //HS
        
        for (Integer i = startPos; i < n; i++) { //HS
            if (i - startPos > 600) return i; //HS BUG FIX# 8
            String ch = body.substring(i, i + 1); //HS

            
            if (inLineComment) { //HS
                if (ch == '\n') inLineComment = false; //HS
                continue; //HS
            } //HS
            if (inBlockComment) { //HS
                if (i + 1 < n && body.substring(i, i + 2) == '*/') { //HS
                    inBlockComment = false; //HS
                    i++; //HS
                } //HS
                continue; //HS
            } //HS
            if (inString) { //HS
                if (ch == '\\') { //HS
                    if (i + 1 < n) i++; //HS
                    continue; //HS
                } //HS
                if (ch == '\'') inString = false; //HS
                continue; //HS
            } //HS
            
            if (i + 1 < n) { //HS
                String two = body.substring(i, i + 2); //HS
                if (two == '//') { inLineComment = true; i++; continue; } //HS
                if (two == '/*') { inBlockComment = true; i++; continue; } //HS
            } //HS
            
            if (ch == '\'') { inString = true; continue; } //HS
            
            // End of statement //HS
            if (ch == ';') return i + 1; //HS
            //===============================BUG FIX #8 START=========================
            // Safety: stop at newline if statement is split weirdly (still ok) //HS
         //   if (ch == '\n') return i; //HS BUG FIX #8
            //HS Do NOT stop at newline; allow multi-line statements. Hard stop handled by 600-char limit.
            if (ch == '\n') { continue; } //HS
            //===============================BUG FIX #8 END=========================
        } //HS
        
        return null; //HS
    } //HS
    //==========BUG FIX #9 - Engine-driven ENQUEUE_IN_LOOP finder========== //HS
    private static Finding detectEnqueueInLoop(String body, Map<String, Trigger_Risk_Rule__mdt> ruleByKey) { //HS
        if (String.isBlank(body)) return null; //HS
        
        Trigger_Risk_Rule__mdt r = ruleByKey.get('ENQUEUE_IN_LOOP'); //HS
        if (r == null || !r.Is_Enabled__c) return null; //HS
        
        Integer pos = findEnqueueInLoopPosition(body); //HS
        if (pos == null) return null; //HS
        
        Finding f = new Finding(); //HS
        f.ruleKey = String.isBlank(r.Rule_Key__c) ? r.DeveloperName : r.Rule_Key__c; //HS
        f.ruleLabel = r.Label; //HS
        f.severity = String.isBlank(r.Severity__c) ? 'Low' : r.Severity__c; //HS
        f.category = r.Category__c; //HS
        f.message = r.Message__c; //HS
        f.matchPos = pos; //HS
        f.lineNumber = computeLineNumber(body, pos); //HS
        return f; //HS
    } //HS
    
    private static Integer findEnqueueInLoopPosition(String body) { //HS
        if (String.isBlank(body)) return null; //HS
        
        // Scan on masked text so comment-only and string-only patterns do not false-positive //HS
        String scan = maskCommentsAndStringsPreserveLength(body); //HS
        
        // ---------- for/while loops ---------- //HS
        Matcher m = Pattern.compile('(?m)^\\s*(for|while)\\b').matcher(scan); //HS
        while (m.find()) { //HS
            Integer loopHeaderPos = m.start(); //HS
            Integer headerEnd = findLoopHeaderEndPos(scan, m.start(), m.group(0)); //HS
            if (headerEnd == null) continue; //HS
            
            // Skip whitespace after the full header //HS
            Integer j = headerEnd; //HS
            while (j < scan.length()) { //HS
                String ch = scan.substring(j, j + 1); //HS
                if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n') break; //HS
                j++; //HS
            } //HS
            
            // Braced loop: for/while (...) { ... } //HS
            if (j < scan.length() && scan.substring(j, j + 1) == '{') { //HS
                Integer open = j; //HS
                Integer close = findMatchingBrace(scan, open); //HS
                if (close != null) { //HS
                    String loopSegment = scan.substring(open, close + 1); //HS
                    if (containsEnqueue(loopSegment)) return loopHeaderPos; //HS
                } //HS
                continue; //HS
            } //HS
            
            // No-brace loop: for/while (...) singleStatement; //HS
            Integer stmtEnd = findStatementEndPos(scan, headerEnd); //HS
            if (stmtEnd == null) stmtEnd = Math.min(scan.length(), headerEnd + 400); //HS
            
            String afterHeader = scan.substring(headerEnd, stmtEnd); //HS
            if (containsEnqueue(afterHeader)) return loopHeaderPos; //HS
        } //HS
        
        // ---------- do { ... } while (...) ---------- //HS
        Matcher d = Pattern.compile('(?m)^\\s*do\\b').matcher(scan); //HS
        while (d.find()) { //HS
            Integer doPos = d.start(); //HS
            Integer j = d.end(); //HS
            
            // Skip whitespace after "do" //HS
            while (j < scan.length()) { //HS
                String ch = scan.substring(j, j + 1); //HS
                if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n') break; //HS
                j++; //HS
            } //HS
            
            // Braced do: do { ... } while (...); //HS
            if (j < scan.length() && scan.substring(j, j + 1) == '{') { //HS
                Integer open = j; //HS
                Integer close = findMatchingBrace(scan, open); //HS
                if (close != null) { //HS
                    String loopSegment = scan.substring(open, close + 1); //HS
                    if (containsEnqueue(loopSegment)) return doPos; //HS
                } //HS
                continue; //HS
            } //HS
            
            // No-brace do: do singleStatement; while (...); //HS
            Integer stmtEnd = findStatementEndPos(scan, d.end()); //HS
            if (stmtEnd == null) stmtEnd = Math.min(scan.length(), d.end() + 400); //HS
            
            String loopStmt = scan.substring(d.end(), stmtEnd); //HS
            if (containsEnqueue(loopStmt)) return doPos; //HS
        } //HS
        
        return null; //HS
    } //HS
    
    private static Boolean containsEnqueue(String segment) { //HS
        if (String.isBlank(segment)) return false; //HS
        Matcher q = Pattern.compile('(?i)\\bSystem\\s*\\.\\s*enqueueJob\\s*\\(').matcher(segment); //HS
        return q.find(); //HS
    } //HS
    
    private static Integer findLoopHeaderEndPos(String scan, Integer keywordStart, String matchedPrefix) { //HS
        if (String.isBlank(scan) || keywordStart == null) return null; //HS
        
        // Find the first '(' after the keyword (handles for/while with nested parentheses) //HS
        Integer open = scan.indexOf('(', keywordStart); //HS
        if (open == -1) return null; //HS
        
        Integer depth = 0; //HS
        for (Integer i = open; i < scan.length(); i++) { //HS
            String ch = scan.substring(i, i + 1); //HS
            if (ch == '(') depth++; //HS
            if (ch == ')') { //HS
                depth--; //HS
                if (depth == 0) return i + 1; //HS
            } //HS
        } //HS
        return null; //HS
    } //HS
    //==========BUG FIX #9 END========== //HS
    //==========HS EMAIL_IN_TRIGGER Helpers========== //HS
    private static Finding detectEmailInTrigger(String body, Map<String, Trigger_Risk_Rule__mdt> ruleByKey) { //HS
        if (String.isBlank(body)) return null; //HS
        
        Integer pos = findEmailSendPosition(body); //HS
        if (pos == null) return null; //HS
        
        Trigger_Risk_Rule__mdt r = ruleByKey != null ? ruleByKey.get('EMAIL_IN_TRIGGER') : null; //HS
        
        Finding f = new Finding(); //HS
        f.ruleKey    = 'EMAIL_IN_TRIGGER'; //HS
        f.ruleLabel  = r != null ? r.Label : 'Email in Trigger'; //HS
        f.severity   = r != null ? r.Severity__c : 'Medium'; //HS
        f.category   = r != null ? r.Category__c : 'Maintainability'; //HS
        f.message    = r != null ? r.Message__c : 'Email send detected inside a trigger can hit limits and reduce reliability under bulk load.'; //HS
        f.matchPos   = pos; //HS
        f.lineNumber = computeLineNumber(body, pos); //HS
        
        return f; //HS
    } //HS
    
    private static Integer findEmailSendPosition(String segment) { //HS
        if (String.isBlank(segment)) return null; //HS
        
        Integer n = segment.length(); //HS
        Boolean inLineComment = false; //HS
        Boolean inBlockComment = false; //HS
        Boolean inString = false; //HS
        
        for (Integer i = 0; i < n; i++) { //HS
            String ch = segment.substring(i, i + 1); //HS
            
            if (inLineComment) { //HS
                if (ch == '\n') inLineComment = false; //HS
                continue; //HS
            } //HS
            if (inBlockComment) { //HS
                if (i + 1 < n && segment.substring(i, i + 2) == '*/') { //HS
                    inBlockComment = false; //HS
                    i++; //HS
                } //HS
                continue; //HS
            } //HS
            if (inString) { //HS
                if (ch == '\\') { //HS
                    if (i + 1 < n) i++; //HS
                    continue; //HS
                } //HS
                if (ch == '\'') inString = false; //HS
                continue; //HS
            } //HS
            
            if (i + 1 < n) { //HS
                String two = segment.substring(i, i + 2); //HS
                if (two == '//') { inLineComment = true; i++; continue; } //HS
                if (two == '/*') { inBlockComment = true; i++; continue; } //HS
            } //HS
            
            if (ch == '\'') { inString = true; continue; } //HS
            
            String tail = segment.substring(i).toLowerCase(); //HS
            
            if (startsWithWord(tail, 'messaging.sendemail')) { //HS
                return i; //HS
            } //HS
        } //HS
        
        return null; //HS
    } //HS
    //==========HS EMAIL_IN_TRIGGER Helpers END========== //HS
    //==========BUG FIX #11 - Engine-driven DML_ON_TRIGGER_OLD finder========== //HS
    private static Finding detectDmlOnTriggerOld(String body, Map<String, Trigger_Risk_Rule__mdt> ruleByKey) { //HS
        if (String.isBlank(body)) return null; //HS
        
        Trigger_Risk_Rule__mdt r = ruleByKey.get('DML_ON_TRIGGER_OLD'); //HS
        if (r == null || !r.Is_Enabled__c) return null; //HS
        
        Integer pos = findDmlOnTriggerOldPosition(body); //HS
        if (pos == null) return null; //HS
        
        Finding f = new Finding(); //HS
        f.ruleKey = String.isBlank(r.Rule_Key__c) ? r.DeveloperName : r.Rule_Key__c; //HS
        f.ruleLabel = r.Label; //HS
        f.severity = String.isBlank(r.Severity__c) ? 'Low' : r.Severity__c; //HS
        f.category = r.Category__c; //HS
        f.message = r.Message__c; //HS
        f.matchPos = pos; //HS
        f.lineNumber = computeLineNumber(body, pos); //HS
        return f; //HS
    } //HS
    
    private static Integer findDmlOnTriggerOldPosition(String segment) { //HS
        if (String.isBlank(segment)) return null; //HS
        
        Integer n = segment.length(); //HS
        Boolean inLineComment = false; //HS
        Boolean inBlockComment = false; //HS
        Boolean inString = false; //HS
        
        for (Integer i = 0; i < n; i++) { //HS
            String ch = segment.substring(i, i + 1); //HS
            
            if (inLineComment) { //HS
                if (ch == '\n') inLineComment = false; //HS
                continue; //HS
            } //HS
            if (inBlockComment) { //HS
                if (i + 1 < n && segment.substring(i, i + 2) == '*/') { //HS
                    inBlockComment = false; //HS
                    i++; //HS
                } //HS
                continue; //HS
            } //HS
            if (inString) { //HS
                if (ch == '\\') { //HS
                    if (i + 1 < n) i++; //HS
                    continue; //HS
                } //HS
                if (ch == '\'') inString = false; //HS
                continue; //HS
            } //HS
            
            if (i + 1 < n) { //HS
                String two = segment.substring(i, i + 2); //HS
                if (two == '//') { inLineComment = true; i++; continue; } //HS
                if (two == '/*') { inBlockComment = true; i++; continue; } //HS
            } //HS
            
            if (ch == '\'') { inString = true; continue; } //HS
            
            String tail = segment.substring(i).toLowerCase(); //HS
            
            // Direct DML forms: update/delete/undelete <expr> //HS
            if (startsWithWord(tail, 'update') || startsWithWord(tail, 'delete') || startsWithWord(tail, 'undelete')) { //HS
                Integer wordLen = startsWithWord(tail, 'update') ? 6 : (startsWithWord(tail, 'delete') ? 6 : 8); //HS
                    Integer j = i + wordLen; //HS
                
                while (j < n) { //HS
                    String cj = segment.substring(j, j + 1); //HS
                    if (cj != ' ' && cj != '\t' && cj != '\r' && cj != '\n') break; //HS
                    j++; //HS
                } //HS
                
                String after = segment.substring(j).toLowerCase(); //HS
                if (after.startsWith('trigger.old') || after.startsWith('trigger.oldmap')) return i; //HS
            } //HS
            
            // Database.* forms: Database.update(<expr>, ...) //HS
            if (startsWithWord(tail, 'database.update') || startsWithWord(tail, 'database.delete') || startsWithWord(tail, 'database.undelete')) { //HS
                Integer j = i; //HS
                while (j < n && segment.substring(j, j + 1) != '(') j++; //HS
                if (j >= n) continue; //HS
                j++; //HS
                
                while (j < n) { //HS
                    String cj = segment.substring(j, j + 1); //HS
                    if (cj != ' ' && cj != '\t' && cj != '\r' && cj != '\n') break; //HS
                    j++; //HS
                } //HS
                
                String after = segment.substring(j).toLowerCase(); //HS
                if (after.startsWith('trigger.old') || after.startsWith('trigger.oldmap')) return i; //HS
            } //HS
        } //HS
        
        return null; //HS
    } //HS
    //==========BUG FIX #11 END========== //HS



    private static Integer findSoqlPosition(String text) {
        Matcher m = Pattern.compile(
            // BUG FIX START #5 - SOQL_IN_LOOP detects multi-line SOQL
            // '(?i)(\\[\\s*SELECT.*?FROM.*?\\])|(Database\\.(query|getQueryLocator))'
           '(?is)(\\[\\s*SELECT[\\s\\S]*?FROM[\\s\\S]*?\\])|(Database\\.(query|getQueryLocator))' 
            // BUG FIX END #5 - SOQL_IN_LOOP detects multi-line SOQL
        ).matcher(text);
        return m.find() ? m.start() : null;
    }

    // =====================
    // Recursion detection
    // =====================
    private static Finding detectRecursionRisk(
        String body,
        Map<String, Trigger_Risk_Rule__mdt> ruleByKey
    ) {
        if (!containsActualDmlStatement(body)) { //Phase3.2
            return null;
        }
        //==========Phase3.4 START code change=========
        /*
        return buildRecursionFinding(ruleByKey, body, 0, body.contains('static'));
        */
        //==========BUG FIX #7 - Fully suppress Recursion Risk when a recursion guard exists==========
        //return buildRecursionFinding(ruleByKey, body, 0, looksLikeRecursionGuard(body));
        Boolean hasGuard = looksLikeRecursionGuard(body);
        if (hasGuard) {
            return null;
        }
        return buildRecursionFinding(ruleByKey, body, 0, false);
        //==========BUG FIX #7 END==========

        //==========Phase3.4 END code change=========

    }

    private static Finding buildRecursionFinding(
        Map<String, Trigger_Risk_Rule__mdt> ruleByKey,
        String body,
        Integer pos,
        Boolean hasGuard
    ) {
        Trigger_Risk_Rule__mdt r = ruleByKey.get('RECURSION_RISK');

        Finding f = new Finding();
        f.ruleKey   = 'RECURSION_RISK';
        f.ruleLabel = r != null ? r.Label : 'Recursion Risk';
        f.category  = r != null ? r.Category__c : 'Reliability';
        f.severity  = hasGuard ? 'Medium' : 'High';
        f.message   = r != null ? r.Message__c :
            'Possible recursion: DML on same object inside trigger.';
        f.matchPos  = pos;
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
        if (!body.toLowerCase().contains('trigger')) return null;
        if (Pattern.compile('(?i)Handler\\.').matcher(body).find()) return null;

        Trigger_Risk_Rule__mdt r = ruleByKey.get('TRIGGER_HANDLER_MISSING');

        Finding f = new Finding();
        f.ruleKey   = 'TRIGGER_HANDLER_MISSING';
        f.ruleLabel = r != null ? r.Label : 'Missing Trigger Handler';
        f.severity  = r != null ? r.Severity__c : 'Low';
        f.category  = r != null ? r.Category__c : 'Maintainability';
        f.message   = r != null ? r.Message__c :
            'Trigger contains logic directly. Use a handler class.';
        f.matchPos  = 0;
        f.lineNumber = 1;
        //==========Phase3.4 START code change=========
            Integer lineCount = countEffectiveLines(body);
        
        // Downgrade severity for very small/simple triggers
        if (f.severity == 'Medium' && lineCount <= 12) {
            f.severity = 'Low';
        }
        //==========Phase3.4 END code change=========

        return f;
    }

    // ====== PHASE3 ======
    // Phase 3.1: cross-trigger recursion cycle detection (best-effort, explainable)
    private static Finding detectCrossTriggerRecursionCycle(TriggerContext ctx) {
        if (ctx == null || ctx.universe == null) return null;
        if (String.isBlank(ctx.objectApiName) || String.isBlank(ctx.triggerName)) return null;
        
        // Only attempt this check if THIS trigger contains REAL DML statements (Phase 3.2.1 noise reduction)
        if (!containsActualDmlStatement(ctx.body)) return null; //Phase3.2
        
        // Compute referenced objects from the body using simple, explainable heuristics.
        Set<String> referenced = extractReferencedObjectApiNames(ctx.body);
        referenced.remove(ctx.objectApiName);
        
        if (referenced.isEmpty()) return null;
        
        // Find a 2-hop cycle: A -> B and B -> A
        for (String otherObj : referenced) {
            if (String.isBlank(otherObj)) continue;
            
            // Do we have triggers on the other object?
            if (ctx.universe.objectToTriggers == null || !ctx.universe.objectToTriggers.containsKey(otherObj)) {
                continue;
            }
            
            Set<String> otherTriggers = ctx.universe.objectToTriggers.get(otherObj);
            if (otherTriggers == null || otherTriggers.isEmpty()) continue;
            
            for (String otName : otherTriggers) {
                String otBody = (ctx.universe.triggerNameToBody != null)
                    ? ctx.universe.triggerNameToBody.get(otName)
                    : null;
                
                if (String.isBlank(otBody)) continue;
                
                // Only proceed if OTHER trigger contains REAL DML statements (Phase 3.2.1 noise reduction)
                if (!containsActualDmlStatement(otBody)) continue; //Phase3.2
                
                Set<String> otRefs = extractReferencedObjectApiNames(otBody);
                
                // If other trigger references back to this object, we have a cycle
                if (otRefs.contains(ctx.objectApiName)) {
                    
                    Boolean thisHasGuard = looksLikeRecursionGuard(ctx.body);
                    Boolean otherHasGuard = looksLikeRecursionGuard(otBody);
                    Boolean hasGuard = thisHasGuard || otherHasGuard;
                    
                   //==========Phase3.2 START code change=========
                        String confidence = 'Medium';
                    try {
                        // High confidence when both sides have DML + strong references to the other object
                        Boolean thisStrong = hasStrongObjectReference(ctx.body, otherObj) && containsActualDmlStatement(ctx.body);
                        Boolean otherStrong = hasStrongObjectReference(otBody, ctx.objectApiName) && containsActualDmlStatement(otBody);
                        
                        if (thisStrong && otherStrong) confidence = 'High';
                        else if (containsActualDmlStatement(ctx.body) && containsActualDmlStatement(otBody)) confidence = 'Medium';
                        else confidence = 'Low';
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
                        ctx.objectApiName + ' (' + ctx.triggerName + ')' +
                        ' -> ' + otherObj + ' (' + otName + ')' +
                        ' -> ' + ctx.objectApiName + '. ' +
                        (hasGuard ? 'A recursion guard pattern may exist, but review carefully. '
                         : 'No obvious recursion guard detected. Review carefully to avoid loops. ') +
                        'Confidence: ' + confidence + '.';
                    
                    return f;
                    //==========Phase3.2 END code change=========
                        }
            }
        }
        
        return null;
    }


    //==========Phase3.2 START code change=========
    // Old method kept for reference (caused false positives because it matches "before update"/"after update")
    /*
private static Boolean containsDmlKeyword(String body) {
if (String.isBlank(body)) return false;
return Pattern.compile(
'(?i)\\b(insert|update|upsert|delete|undelete)\\b|\\bDatabase\\.(insert|update|upsert|delete|undelete)\\b'
).matcher(body).find();
}
*/
    
    // New: only detect REAL DML statements (avoids matching trigger event keywords like "after update")
    private static Boolean containsActualDmlStatement(String body) {
        if (String.isBlank(body)) return false;
        
        // Only scan inside the executable block (after the first '{') so we don't match header words.
        Integer brace = body.indexOf('{'); //HS
        String scan = (brace >= 0 && brace + 1 < body.length()) ? body.substring(brace + 1) : body; //HS
        
        // Use the engine scanner that already ignores comments and strings.
        Integer pos = findDmlPosition(scan); //HS
        return (pos != null); //HS
    }
    //==========Phase3.2 END code change=========
    //==========BUG FIX #7 - Helper: detect real Trigger.new mutation in AFTER context==========
    private static Integer findAfterTriggerNewMutationPos(String bodyRaw, String bodyLower, Boolean isBefore, Boolean isAfter) { //HS
        if (!isAfter) return -1; //HS
        if (String.isBlank(bodyRaw)) return -1; //HS
        
        //HS Mask comments + strings so traps do not match.
        String maskedLower = maskCommentsAndStringsPreserveLength(bodyRaw).toLowerCase(); //HS
        
        //HS If trigger supports BOTH before and after, only flag AFTER mutation when an explicit Trigger.isAfter guard exists.
        Boolean isAfterOnly = isAfter && !isBefore; //HS
        Integer afterGuardPos = maskedLower.indexOf('trigger.isafter'); //HS
        if (!isAfterOnly && afterGuardPos < 0) return -1; //HS
        
        Integer offset = 0; //HS
        String scan = maskedLower; //HS
        
        if (afterGuardPos >= 0) { //HS
            offset = afterGuardPos; //HS
            scan = maskedLower.substring(afterGuardPos); //HS
        } //HS
        
        // Direct DML on Trigger.new (true mutation pattern)
        Matcher dmlOnNew = Pattern.compile('(?i)\\b(update|delete|undelete)\\s+trigger\\.new\\b').matcher(scan); //HS
        if (dmlOnNew.find()) return offset + dmlOnNew.start(); //HS
        
        // Indexed mutation: Trigger.new[i].Field = ... OR Trigger.new[i] = ...
        Matcher indexed = Pattern.compile('(?i)trigger\\.new\\s*\\[[^\\]]*\\]\\s*(?:\\.[a-z0-9_]+\\s*=|=)').matcher(scan); //HS
        if (indexed.find()) return offset + indexed.start(); //HS
        
        // Loop variable mutation: for (Obj r : Trigger.new) { r.Field = ... }
        Matcher loopMatcher = Pattern.compile( //HS
            '(?i)for\\s*\\(\\s*[a-z0-9_\\.]+\\s+([a-z0-9_]+)\\s*:\\s*trigger\\.new\\s*\\)' //HS
        ).matcher(scan); //HS
        
        while (loopMatcher.find()) { //HS
            String varName = loopMatcher.group(1); //HS
            Integer scanFrom = loopMatcher.end(); //HS
            String rest = scan.substring(scanFrom); //HS
            
            Matcher assign = Pattern.compile('(?i)\\b' + varName + '\\s*\\.[a-z0-9_]+\\s*=').matcher(rest); //HS
            if (assign.find()) return offset + scanFrom + assign.start(); //HS
        } //HS
        
        return -1; //HS
    } //HS


    //==========BUG FIX #7 END==========

   /* private static Boolean looksLikeRecursionGuard(String body) {
        if (String.isBlank(body)) return false;
        
        //HS Mask comments + strings so traps do not match.
        String scan = maskCommentsAndStringsPreserveLength(body); //HS
        
        // Best-effort patterns: static boolean flag, static set/map used as guard, or common guard words
        if (Pattern.compile('(?i)\\bstatic\\s+Boolean\\b').matcher(scan).find()) return true;
        if (Pattern.compile('(?i)\\bstatic\\s+(Set|Map)\\s*<\\s*Id\\b').matcher(scan).find()) return true;
        
        //HS Support common guard naming patterns
        if (Pattern.compile('(?i)\\b(alreadyProcessed|isExecuting|hasRun|recursionGuard|inProgress|alreadyRan|alreadyRun|hasAlreadyRun)\\b').matcher(scan).find()) return true; //HS
        
        return false;
    }*/
    private static Boolean looksLikeRecursionGuard(String body) {
        if (String.isBlank(body)) return false;
        
        //HS Mask comments + strings so traps do not match.
        String scan = maskCommentsAndStringsPreserveLength(body); //HS
        String lower = scan.toLowerCase(); //HS
        
        //HS 1) Strong detection: static Boolean guard that is BOTH checked and set
        //HS Example patterns:
        //HS   if (hasRun) return;
        //HS   if (!hasRun) { hasRun = true; ... }
        Matcher boolDecl = Pattern.compile('(?i)\\bstatic\\s+Boolean\\s+([A-Za-z_][A-Za-z0-9_]*)\\b').matcher(scan); //HS
        while (boolDecl.find()) { //HS
            String varName = boolDecl.group(1); //HS
            if (String.isBlank(varName)) continue; //HS
            
            String v = varName.toLowerCase(); //HS
            
            //HS Must see a conditional check using this variable
            Boolean hasCheck =
                Pattern.compile('(?i)\\bif\\s*\\(\\s*!?\\s*' + v + '\\s*\\)')
                .matcher(lower).find() //HS
                || Pattern.compile('(?i)\\bif\\s*\\(\\s*' + v + '\\s*==\\s*(true|false)\\s*\\)')
                .matcher(lower).find(); //HS
            
            //HS Must see the variable being set (true or false)
            Boolean hasSet =
                Pattern.compile('(?i)\\b' + v + '\\s*=\\s*(true|false)\\b')
                .matcher(lower).find(); //HS
            
            if (hasCheck && hasSet) return true; //HS
        } //HS
        
        //HS 2) Strong detection: static Set<Id> guard (contains + add)
        Matcher setDecl = Pattern.compile('(?i)\\bstatic\\s+Set\\s*<\\s*Id\\s*>\\s+([A-Za-z_][A-Za-z0-9_]*)\\b').matcher(scan); //HS
        while (setDecl.find()) { //HS
            String varName = setDecl.group(1); //HS
            if (String.isBlank(varName)) continue; //HS
            String v = varName.toLowerCase(); //HS
            
            Boolean hasContains =
                Pattern.compile('(?i)\\b' + v + '\\s*\\.\\s*contains\\s*\\(').matcher(lower).find(); //HS
            Boolean hasAdd =
                Pattern.compile('(?i)\\b' + v + '\\s*\\.\\s*add\\s*\\(').matcher(lower).find(); //HS
            
            if (hasContains && hasAdd) return true; //HS
        } //HS
        
        //HS 3) Strong detection: static Map<Id, ...> guard (containsKey/get + put)
        Matcher mapDecl = Pattern.compile('(?i)\\bstatic\\s+Map\\s*<\\s*Id\\s*,\\s*[A-Za-z_][A-Za-z0-9_\\.]*\\s*>\\s+([A-Za-z_][A-Za-z0-9_]*)\\b').matcher(scan); //HS
        while (mapDecl.find()) { //HS
            String varName = mapDecl.group(1); //HS
            if (String.isBlank(varName)) continue; //HS
            String v = varName.toLowerCase(); //HS
            
            Boolean hasKeyRead =
                Pattern.compile('(?i)\\b' + v + '\\s*\\.\\s*(containskey|get)\\s*\\(').matcher(lower).find(); //HS
            Boolean hasPut =
                Pattern.compile('(?i)\\b' + v + '\\s*\\.\\s*put\\s*\\(').matcher(lower).find(); //HS
            
            if (hasKeyRead && hasPut) return true; //HS
        } //HS
        
        //HS 4) Guard helper utility calls (common patterns)
        //HS This catches patterns like RecursionGuard.runOnce(...), Guard.enter(...), etc.
        if (Pattern.compile('(?i)\\b(recursionguard|guard)\\s*\\.\\s*(runonce|enter|check|checkandset|acquire|lock)\\s*\\(')
            .matcher(scan).find()) return true; //HS
        
        return false;
    }

    private static Set<String> extractReferencedObjectApiNames(String body) {
        Set<String> out = new Set<String>();
        if (String.isBlank(body)) return out;

        // 1) SOQL FROM <Object>
        Matcher soqlFrom = Pattern.compile('(?i)\\bFROM\\s+([A-Za-z_][A-Za-z0-9_]*)').matcher(body);
        while (soqlFrom.find()) {
            String obj = soqlFrom.group(1);
            if (isPlausibleSObjectName(obj)) out.add(obj);
        }

        // 2) Type usage in generics: List<Object>, Map<Id, Object>, Set<Object>
        Matcher gen = Pattern.compile('(?i)\\b(List|Set)\\s*<\\s*([A-Za-z_][A-Za-z0-9_]*)\\b').matcher(body);
        while (gen.find()) {
            String obj = gen.group(2);
            if (isPlausibleSObjectName(obj)) out.add(obj);
        }

        Matcher mapVal = Pattern.compile('(?i)\\bMap\\s*<\\s*Id\\s*,\\s*([A-Za-z_][A-Za-z0-9_]*)\\b').matcher(body);
        while (mapVal.find()) {
            String obj = mapVal.group(1);
            if (isPlausibleSObjectName(obj)) out.add(obj);
        }

        // 3) "new Object(" usage
        Matcher ctor = Pattern.compile('(?i)\\bnew\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*\\(').matcher(body);
        while (ctor.find()) {
            String obj = ctor.group(1);
            if (isPlausibleSObjectName(obj)) out.add(obj);
        }

        return out;
    }

    //==========Phase3.2 START code change=========
    /**
* Returns true if the trigger body has a strong, explicit reference
* to the given sObject API name.
* Used to increase confidence for cross-trigger recursion detection.
*/
    private static Boolean hasStrongObjectReference(String body, String objApiName) {
        if (String.isBlank(body) || String.isBlank(objApiName)) return false;
        
        String lowerBody = body.toLowerCase();
        String lowerObj  = objApiName.toLowerCase();
        
        // SOQL reference: FROM Object__c
        if (lowerBody.contains('from ' + lowerObj)) return true;
        
        // Object instantiation: new Object__c(
        if (lowerBody.contains('new ' + lowerObj + '(')) return true;
        
        // Generic usage: List<Object__c>, Set<Object__c>
        if (lowerBody.contains('<' + lowerObj + '>')) return true;
        
        // Map usage: Map<Id, Object__c>
        if (lowerBody.contains(', ' + lowerObj + '>')) return true;
        
        return false;
    }
    //==========Phase3.2 END code change=========
 
    //==========Phase3.2 START code change=========
    /**
* Finds the best position in the trigger body to highlight for a
* cross-trigger recursion finding.
* Preference order:
*   1) SOQL: FROM <Object>
*   2) new <Object>(
*   3) Generic usage: <Object>
*   4) First occurrence of object name
*/
    private static Integer findBestHighlightPos(String body, String objApiName) {
        if (String.isBlank(body) || String.isBlank(objApiName)) return null;
        
        String lowerBody = body.toLowerCase();
        String lowerObj  = objApiName.toLowerCase();
        
        // 1) SOQL FROM <Object>
        Integer p = lowerBody.indexOf('from ' + lowerObj);
        if (p >= 0) return p;
        
        // 2) new <Object>(
        p = lowerBody.indexOf('new ' + lowerObj + '(');
        if (p >= 0) return p;
        
        // 3) Generic usage <Object>
        p = lowerBody.indexOf('<' + lowerObj + '>');
        if (p >= 0) return p;
        
        // 4) Fallback: any mention of object name
        p = lowerBody.indexOf(lowerObj);
        if (p >= 0) return p;
        
        return null;
    }
    //==========Phase3.2 END code change=========

    

    private static Boolean isPlausibleSObjectName(String token) {
        if (String.isBlank(token)) return false;

        // Avoid common non-sObject tokens
        Set<String> bad = new Set<String>{
            'String','Integer','Long','Decimal','Double','Boolean','Date','Datetime','Time',
            'List','Set','Map','Object','Exception','System','Math','Pattern','Matcher',
            'Database','Schema','Id','Void'
        };
        if (bad.contains(token)) return false;

        // Typical sObject patterns: Account, Contact, MyObject__c, Something__mdt
        if (token.endsWith('__c') || token.endsWith('__mdt') || token.endsWith('__e')) return true;

        // Standard objects are PascalCase words; allow them too
        if (Pattern.compile('^[A-Z][A-Za-z0-9_]*$').matcher(token).matches()) return true;

        return false;
    }
    // ====== PHASE3 ======
    // ==========Phase3.2 START code change=========
    // Phase 3.2: Order-of-execution risk detection
    private static List<Finding> detectOrderOfExecutionRisks(TriggerContext ctx) {
        List<Finding> out = new List<Finding>();
        if (ctx == null || ctx.universe == null) return out;
        
        String body = ctx.body != null ? ctx.body.toLowerCase() : '';
        String obj = ctx.objectApiName;
        
        // 1) Multiple triggers on same object
        if (!String.isBlank(obj)
            && ctx.universe.objectToTriggers != null
            && ctx.universe.objectToTriggers.containsKey(obj)
            && ctx.universe.objectToTriggers.get(obj).size() > 1) {
                
                Finding f = new Finding();
                f.ruleKey = 'MULTIPLE_TRIGGERS_SAME_OBJECT';
                f.ruleLabel = 'Multiple Triggers on Same Object';
                f.category = 'OrderOfExecution';
                f.severity = 'Medium';
                f.matchPos = 0;
                f.lineNumber = 1;
                f.message =
                    'Multiple triggers exist on object ' + obj +
                    '. Salesforce does not guarantee execution order across triggers, ' +
                    'which can cause unpredictable behavior.';
                out.add(f);
            }
        //==========BUG FIX #12 - Accurate BEFORE/AFTER detection (header only)========== //HS
        // Detect trigger timing
        //Boolean isBefore = body.contains('before');
        //Boolean isAfter  = body.contains('after');        
        String headerLower = ctx.body != null ? ctx.body.toLowerCase() : ''; 
        Integer bracePos = headerLower.indexOf('{'); 
        if (bracePos >= 0) headerLower = headerLower.substring(0, bracePos);

        Integer lp = headerLower.indexOf('('); 
        Integer rp = headerLower.indexOf(')', lp + 1); 
        String events = (lp >= 0 && rp > lp) ? headerLower.substring(lp + 1, rp) : headerLower; 

        Boolean isBefore = events.contains('before'); 
        Boolean isAfter  = events.contains('after'); 
        //==========BUG FIX #12 END========== //HS

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
        //==========BUG FIX #7 - Fix false positive: Trigger.new Modified in AFTER Trigger==========
        //if (isAfter && body.contains('trigger.new') && body.contains('=')) {
            Integer afterMutPos = findAfterTriggerNewMutationPos(ctx.body, body, isBefore, isAfter);
            if (afterMutPos >= 0) {
        //==========BUG FIX #7 END==========
            Finding f = new Finding();
            f.ruleKey = 'AFTER_TRIGGER_MUTATION';
            f.ruleLabel = 'Trigger.new Modified in AFTER Trigger';
            f.category = 'OrderOfExecution';
            f.severity = 'Medium';
            //f.matchPos = body.indexOf('trigger.new');
            f.matchPos = afterMutPos; //BUG FIX #7
            f.lineNumber = computeLineNumber(ctx.body, f.matchPos);
            f.message =
                'Trigger.new appears to be modified in an AFTER trigger. ' +
                'Record field changes should usually occur in BEFORE triggers.';
            out.add(f);
        }
        
        return out;
    }
    //==========Phase3.2 END code change=========
    //==========Phase3.3 START code change=========
    private class BulkScoreResult {
        Integer score;
        String level;        // High / Medium / Low
        String deductions;   // human readable summary
    }
    
    private static Finding buildBulkConfidenceFinding(TriggerContext ctx, List<Finding> existingFindings) {
        if (ctx == null) return null;
    
        BulkScoreResult r = computeBulkConfidenceScore(ctx, existingFindings);
        if (r == null) return null;
    
        Finding f = new Finding();
        f.ruleKey = 'BULK_CONFIDENCE_SCORE';
        f.ruleLabel = 'Bulkification Confidence Score';
        f.category = 'BulkScore';
        f.severity = 'Low'; // informational only
        f.matchPos = 0;
        f.lineNumber = 1;
    
        String tName = String.isBlank(ctx.triggerName) ? 'Trigger' : ctx.triggerName;
    
        //==========Phase4.0.1 START code change=========
        /*
        f.message =
            'Bulkification confidence for ' + tName + ': ' +
            String.valueOf(r.score) + '/100 (' + r.level + '). ' +
            (String.isBlank(r.deductions)
                ? 'No major bulk risks detected.'
                : ('Deductions: ' + r.deductions));
        */
        //==========BUG FIX START===============================>
        //String msg = 'Bulk safety concerns detected.';
        	String msg = (r.level == 'High')
                ? 'Bulk-safe patterns detected.'
                : 'Bulk safety concerns detected.';
    	//==========BUG FIX END===============================>
        
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
                    msg += '\n• ' + d.replaceAll('\\(.*\\)', '').replace('_', ' ').toLowerCase();
                }
            }
        } else {
            msg += '\n\nNo high-impact bulk processing risks were identified.';
        }
    	//==========BUG FIX START===============================>
        //msg += '\n\nThis trigger is functional but may require refactoring before deployment to high-volume environments.';
        if (r.level != 'High' || !String.isBlank(r.deductions)) {
            msg += '\n\nThis trigger is functional but may require refactoring before deployment to high-volume environments.';
        } else {
            msg += '\n\nThis trigger looks ready for higher-volume environments based on detected patterns.';
        }
		//==========BUG FIX END===============================>
        f.message = msg;
        //==========Phase4.0.1 END code change=========
    
        return f;
    }


    
    private static BulkScoreResult computeBulkConfidenceScore(TriggerContext ctx, List<Finding> findings) {
        BulkScoreResult out = new BulkScoreResult();
        Integer score = 100;
        
        List<String> ded = new List<String>();
        //==========Phase3.4.3 START code change=========
        // Phase 3.4.3: build rule-key set so we can avoid double-penalizing similar risks
        Set<String> keysPresent = new Set<String>();
        if (findings != null) {
            for (Finding fx : findings) {
                if (fx != null && !String.isBlank(fx.ruleKey)) {
                    keysPresent.add(fx.ruleKey);
                }
            }
        }
        
        // Phase 3.4.3: scoring-only dedupe rules (do NOT remove findings from the UI)
        Set<String> skipForScoring = new Set<String>();
        if (keysPresent.contains('DML_IN_LOOP')) {
            skipForScoring.add('SINGLE_RECORD_DML');
        }
        if (keysPresent.contains('CROSS_TRIGGER_RECURSION_CYCLE')) {
            skipForScoring.add('RECURSION_RISK');
        }
        //==========Phase3.4.3 END code change=========

        // Deduct based on existing findings (ruleKey-based)
        if (findings != null) {
                   //==========Phase3.4 START code change=========
                        /*
        for (Finding f : findings) {
        if (f == null || String.isBlank(f.ruleKey)) continue;
        
        // Skip self
        if (f.ruleKey == 'BULK_CONFIDENCE_SCORE') continue;
        
        Integer d = bulkDeductionForRuleKey(f.ruleKey, f.severity);
        if (d > 0) {
        score -= d;
        ded.add(f.ruleKey + '(-' + String.valueOf(d) + ')');
        }
        }
        */
                        
            for (Finding f : findings) {
                if (f == null || String.isBlank(f.ruleKey)) continue;
                
                // Skip self
                if (f.ruleKey == 'BULK_CONFIDENCE_SCORE') continue;
                
                // Phase 3.4.3: skip redundant deductions (scoring only)
                if (skipForScoring.contains(f.ruleKey)) continue;
                
                Integer d = bulkDeductionForRuleKey(f.ruleKey, f.severity);
                if (d > 0) {
                    score -= d;
                    ded.add(f.ruleKey + '(-' + String.valueOf(d) + ')');
                }
            }
            //==========Phase3.4 END code change=========

        }
        
        // Small additional heuristic deductions based on body patterns (safe + explainable)
        String body = (ctx.body == null) ? '' : ctx.body;
        
        // If no obvious bulk pattern (no lists/sets/maps) and trigger does work, small deduction
        // (kept small to avoid noise)
       //====================== BUG FIX START=============================>
        /*Boolean usesCollections =
            Pattern.compile('(?i)\\b(List|Set|Map)\\s*<').matcher(body).find();
        if (!usesCollections && Pattern.compile('(?i)\\b(SELECT\\b|update\\b|insert\\b|delete\\b|upsert\\b)').matcher(body).find()) {
            score -= 5;
            ded.add('NO_COLLECTIONS_PATTERN(-5)');
        }*/
        Boolean usesCollections =
            Pattern.compile('(?i)\\b(List|Set|Map)\\s*<').matcher(body).find();
        
        // Only apply the "no collections" deduction if the trigger body appears to do real work.
        // IMPORTANT: do NOT match trigger header words like "before insert, before update".
        Boolean hasRealDml = containsActualDmlStatement(body);
        Boolean hasRealSoql = Pattern.compile('(?i)(\\[\\s*SELECT\\b|\\bDatabase\\.(query|getQueryLocator)\\s*\\()').matcher(body).find();
        
        if (!usesCollections && (hasRealDml || hasRealSoql)) {
            score -= 5;
            ded.add('NO_COLLECTIONS_PATTERN(-5)');
        }
		//====================== BUG FIX END=============================>
        // Clamp score
        if (score < 0) score = 0;
        if (score > 100) score = 100;
        
        out.score = score;
        out.level = (score >= 80) ? 'High' : (score >= 60) ? 'Medium' : 'Low';
        out.deductions = String.join(ded, ', ');
        
        return out;
    }
    
    private static Integer bulkDeductionForRuleKey(String ruleKey, String severity) {
        
        //==========Phase3.4 START code change=========
            // Phase 3.4: soften penalties when guards exist
            // If severity is Medium (guard detected), reduce deduction
            Boolean guarded = (severity == 'Medium');
        //==========Phase3.4 END code change=========
            
            // SOQL / DML risks
            if (ruleKey == 'SOQL_IN_LOOP') return 30;
        if (ruleKey == 'DML_IN_LOOP') return 25;
        if (ruleKey == 'MIXED_DML') return 25;
        if (ruleKey == 'CALLOUT_IN_TRIGGER') return 20;
        if (ruleKey == 'EMAIL_IN_TRIGGER') return 10;
        
        // Recursion risks
        if (ruleKey == 'RECURSION_RISK') {
            //==========Phase3.4 START code change=========
                return guarded ? 5 : 15;
            //==========Phase3.4 END code change=========
                // return 15;
                }
        
        if (ruleKey == 'CROSS_TRIGGER_RECURSION_CYCLE') {
            //==========Phase3.4 START code change=========
                return guarded ? 10 : 20;
            //==========Phase3.4 END code change=========
                // return 20;
                }
        
        // Order-of-execution risks
        if (ruleKey == 'MULTIPLE_TRIGGERS_SAME_OBJECT') return 5;
        if (ruleKey == 'AFTER_TRIGGER_MUTATION') return 5;
        if (ruleKey == 'DML_IN_BEFORE_TRIGGER') return 15;
        
        // Maintainability
        if (ruleKey == 'TRIGGER_HANDLER_MISSING') return 3;
        
        return 0;
    }
   //==========Phase3.4 START code change=========
    	/*** Counts non-empty, non-comment lines to estimate trigger complexity.*/
        private static Integer countEffectiveLines(String body) {
            if (String.isBlank(body)) return 0;
            
            Integer count = 0;
            for (String line : body.split('\n')) {
                String l = line.trim();
                if (l == '' || l.startsWith('//') || l.startsWith('/*') || l.startsWith('*')) {
                    continue;
                }
                count++;
            }
            return count;
        }
    //==========Phase3.4 END code change=========

    //==========Phase3.3 END code change=========
    private static String maskCommentsAndStringsPreserveLength(String input) { //HS
        if (String.isBlank(input)) return input; //HS
        
        Integer n = input.length(); //HS
        List<String> out = new List<String>(); //HS
        
        Boolean inLineComment = false; //HS
        Boolean inBlockComment = false; //HS
        Boolean inString = false; //HS
        
        for (Integer i = 0; i < n; i++) { //HS
            String ch = input.substring(i, i + 1); //HS
            
            if (inLineComment) { //HS
                out.add(ch == '\n' ? '\n' : ' '); //HS
                if (ch == '\n') inLineComment = false; //HS
                continue; //HS
            } //HS
            
            if (inBlockComment) { //HS
                if (i + 1 < n && input.substring(i, i + 2) == '*/') { //HS
                    out.add(' '); //HS
                    out.add(' '); //HS
                    i++; //HS
                    inBlockComment = false; //HS
                } else { //HS
                    out.add(ch == '\n' ? '\n' : ' '); //HS
                } //HS
                continue; //HS
            } //HS
            
            if (inString) { 
                out.add(ch == '\n' ? '\n' : ' '); //HS
                if (ch == '\\') { //HS
                    if (i + 1 < n) { out.add(' '); i++; } //HS
                    continue; //HS
                } 
                if (ch == '\'') inString = false; //HS
                continue; //HS
            } 
            
            if (i + 1 < n) { //HS
                String two = input.substring(i, i + 2); //HS
                if (two == '//') { //HS
                    out.add(' '); //HS
                    out.add(' '); //HS
                    i++; //HS
                    inLineComment = true; //HS
                    continue; //HS
                } 
                if (two == '/*') { //HS
                    out.add(' '); //HS
                    out.add(' '); //HS
                    i++; //HS
                    inBlockComment = true; //HS
                    continue; //HS
                } 
            } 
            
            if (ch == '\'') { //HS
                out.add(' '); //HS
                inString = true; //HS
                continue; //HS
            } 
            
            out.add(ch); //HS
        } 
        
        return String.join(out, ''); //HS
    }
    private static String maskCommentsPreserveLength(String input) { 
        if (String.isBlank(input)) return input; 
        
        Integer n = input.length(); 
        List<String> out = new List<String>(); 
        
        Boolean inLine = false; 
        Boolean inBlock = false; 
        
        for (Integer i = 0; i < n; i++) { 
            String ch = input.substring(i, i + 1); //HS
            
            if (inLine) { //HS
                out.add(ch == '\n' ? '\n' : ' '); //HS
                if (ch == '\n') inLine = false; //HS
                continue; //HS
            } //HS
            
            if (inBlock) { //HS
                if (i + 1 < n && input.substring(i, i + 2) == '*/') { 
                    out.add(' '); 
                    out.add(' '); 
                    i++; 
                    inBlock = false; 
                } else { 
                    out.add(ch == '\n' ? '\n' : ' '); 
                } 
                continue; 
            } //HS
            
            if (i + 1 < n) { 
                String two = input.substring(i, i + 2); 
                if (two == '//') { 
                    out.add(' '); 
                    out.add(' '); 
                    i++; //HS
                    inLine = true; //HS
                    continue; //HS
                } 
                if (two == '/*') { //HS
                    out.add(' '); //HS
                    out.add(' '); //HS
                    i++; //HS
                    inBlock = true; //HS
                    continue; //HS
                } 
            } 
            
            out.add(ch); 
        } 
        
        return String.join(out, ''); 
    } 
    
}
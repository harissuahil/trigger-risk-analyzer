// CLASS: TriggerFetchService
public with sharing class TriggerFetchService {

    public class TriggerInfo {
        public String id;
        public String name;
        public String body;
        public String tableEnumOrId;
    }

    public static TriggerInfo fetchByName(String triggerName) {
        if (String.isBlank(triggerName)) {
            throw new IllegalArgumentException('Trigger name cannot be blank.');
        }

        // SOQL for Tooling API
        String soql = 'SELECT Id, Name, Body, TableEnumOrId FROM ApexTrigger WHERE Name = \'' +
            String.escapeSingleQuotes(triggerName) + '\' LIMIT 1';

        Map<String, Object> r = ToolingApiClient.queryUntyped(soql);
        List<Object> recs = (List<Object>) r.get('records');

        if (recs == null || recs.isEmpty()) return null;

        Map<String, Object> row = (Map<String, Object>) recs[0];

        TriggerInfo info = new TriggerInfo();
        info.id = (String) row.get('Id');
        info.name = (String) row.get('Name');
        info.body = (String) row.get('Body');
        info.tableEnumOrId = (String) row.get('TableEnumOrId');
        return info;
    }

    // ====== PHASE3 ======
    // Bulk fetch: reduces callouts and allows building a shared trigger universe
    public static List<TriggerInfo> fetchByNames(List<String> triggerNames) {
        List<TriggerInfo> out = new List<TriggerInfo>();
        if (triggerNames == null || triggerNames.isEmpty()) return out;

        // Filter blanks + dedupe
        Set<String> uniq = new Set<String>();
        for (String n : triggerNames) {
            if (!String.isBlank(n)) uniq.add(n.trim());
        }
        if (uniq.isEmpty()) return out;

        List<String> names = new List<String>();
        names.addAll(uniq);

        // Chunk to avoid overly long query strings
        Integer chunkSize = 50;
        for (Integer i = 0; i < names.size(); i += chunkSize) {

            Integer endIdx = Math.min(i + chunkSize, names.size());

            // Apex does NOT support subList(), so build chunk manually
            List<String> chunk = new List<String>();
            for (Integer j = i; j < endIdx; j++) {
                chunk.add(names[j]);
            }

            List<String> quoted = new List<String>();
            for (String c : chunk) {
                quoted.add('\'' + String.escapeSingleQuotes(c) + '\'');
            }

            String soql =
                'SELECT Id, Name, Body, TableEnumOrId ' +
                'FROM ApexTrigger ' +
                'WHERE Name IN (' + String.join(quoted, ',') + ')';

            Map<String, Object> r = ToolingApiClient.queryUntyped(soql);
            List<Object> recs = (List<Object>) r.get('records');
            if (recs == null) continue;

            for (Object o : recs) {
                Map<String, Object> row = (Map<String, Object>) o;
                TriggerInfo info = new TriggerInfo();
                info.id = (String) row.get('Id');
                info.name = (String) row.get('Name');
                info.body = (String) row.get('Body');
                info.tableEnumOrId = (String) row.get('TableEnumOrId');
                out.add(info);
            }
        }

        return out;
    }
    // ====== PHASE3 ======
}
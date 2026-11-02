/**
 * AA_ValAgentAdminController — @AuraEnabled CRUD for the aaValAgentAdmin
 * LWC. Backs the "AA Validation Agents" admin page (list rows from AA_Val_Agent__c,
 * add/rename/reweight/toggle-active/delete).
 *
 * Weights are stored as absolute Numbers (e.g. 30/30/40 — they do NOT need to
 * sum to 100). The trigger helper normalises with (weight / totalWeight) so
 * any positive-decimal set works.
 */
public with sharing class AA_ValAgentAdminController {

    public class AgentRow {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal weight;
        @AuraEnabled public Boolean active;
        @AuraEnabled public Integer assignedCount;
    }

    @AuraEnabled(cacheable=true)
    public static List<AgentRow> listAgents() {
        List<AA_Val_Agent__c> rows = [
            SELECT Id, Name, Weight__c, Active__c
            FROM AA_Val_Agent__c
            ORDER BY Active__c DESC, Weight__c DESC, Name ASC
        ];
        Map<String, Integer> counts = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Val_Agent__c a, COUNT(Id) c
            FROM AA_Application__c
            WHERE Val_Agent__c != null
            GROUP BY Val_Agent__c
        ]) {
            counts.put((String) ar.get('a'), Integer.valueOf(ar.get('c')));
        }
        List<AgentRow> out = new List<AgentRow>();
        for (AA_Val_Agent__c r : rows) {
            AgentRow a = new AgentRow();
            a.id = r.Id;
            a.name = r.Name;
            a.weight = r.Weight__c;
            a.active = r.Active__c;
            a.assignedCount = counts.containsKey(r.Name) ? counts.get(r.Name) : 0;
            out.add(a);
        }
        return out;
    }

    /** Authorization gate — only a full admin (ModifyAllData) may mutate the
     *  assignment pool. Blocks a general AA_Val_Agents_Access user from directly
     *  invoking these @AuraEnabled methods (audit 2026-08-28). A dedicated
     *  agent-admin permission set can be added later for delegated admins. */
    private static void assertAgentAdmin() {
        Integer n = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.PermissionsModifyAllData = true
        ];
        if (n == 0) {
            throw new AuraHandledException('Not authorized — admin permission required.');
        }
    }

    @AuraEnabled
    public static Id createAgent(String agentName, Decimal weight, Boolean active) {
        assertAgentAdmin();
        String trimmed = String.isBlank(agentName) ? '' : agentName.trim();
        if (String.isBlank(trimmed)) throw new AuraHandledException('Name is required.');
        if (weight == null || weight <= 0) throw new AuraHandledException('Weight must be greater than 0.');
        for (AA_Val_Agent__c ex : [SELECT Id FROM AA_Val_Agent__c WHERE Name = :trimmed LIMIT 1]) {
            throw new AuraHandledException('An agent named "' + trimmed + '" already exists.');
        }
        AA_Val_Agent__c a = new AA_Val_Agent__c(
            Name = trimmed,
            Weight__c = weight,
            Active__c = active == null ? true : active
        );
        insert a;
        return a.Id;
    }

    @AuraEnabled
    public static void updateAgent(Id agentId, String agentName, Decimal weight, Boolean active) {
        assertAgentAdmin();
        if (agentId == null) throw new AuraHandledException('Missing agent id.');
        AA_Val_Agent__c a = [SELECT Id, Name, Weight__c, Active__c FROM AA_Val_Agent__c WHERE Id = :agentId LIMIT 1];
        String oldName = a.Name;
        String newName = String.isBlank(agentName) ? oldName : agentName.trim();
        if (weight != null && weight <= 0) throw new AuraHandledException('Weight must be greater than 0.');
        a.Name = newName;
        if (weight != null) a.Weight__c = weight;
        if (active != null) a.Active__c = active;
        update a;

        // If the display name changed, fan the rename out to existing
        // Applications so history + reports stay consistent.
        if (newName != oldName) {
            List<AA_Application__c> rows = [
                SELECT Id, Val_Agent__c FROM AA_Application__c WHERE Val_Agent__c = :oldName
            ];
            for (AA_Application__c r : rows) r.Val_Agent__c = newName;
            if (!rows.isEmpty()) update rows;
        }
    }

    @AuraEnabled
    public static void deleteAgent(Id agentId) {
        assertAgentAdmin();
        if (agentId == null) throw new AuraHandledException('Missing agent id.');
        delete [SELECT Id FROM AA_Val_Agent__c WHERE Id = :agentId LIMIT 1];
        // Picklist value stays — legacy Applications keep referencing it.
        // Admin can prune it in Setup if truly unused.
    }

    // Note: Val_Agent__c is an UNRESTRICTED picklist, so the trigger can
    // write any name (e.g. a newly-added agent) without needing the value
    // pre-registered. If admin wants the new name to appear in the Details
    // dropdown, they add it via Setup → Object Manager → AA Application →
    // Val Agent. Auto-registration was intentionally left out to keep this
    // class free of Tooling API round-trips.
}
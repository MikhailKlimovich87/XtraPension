/**
 * AA_ValAgentAssignHelper — weighted auto-assignment for Val_Agent__c on
 * AA_Application__c inserts.
 *
 * Algorithm ("largest deficit"):
 *   Given active agents A₁..Aₙ with weights w₁..wₙ (sum W) and current
 *   assigned counts c₁..cₙ (total N), the "ideal" count for Aᵢ after the
 *   next insert is round((N+1) × wᵢ / W). The agent with the biggest gap
 *   between ideal-count and current-count wins the next assignment.
 *
 *   Tiebreaker: highest weight, then alphabetical.
 *
 * Reads active rows from AA_Val_Agent__c fresh each call — Fernando can
 * change weights in the admin LWC and the very next insert picks up the new
 * distribution.
 *
 * Skips (never overwrites): rows already inserted with Val_Agent__c set
 * (imports, manual creates, admin overrides).
 */
public class AA_ValAgentAssignHelper {

    public static void assign(List<AA_Application__c> newRows) {
        // Nothing to do if every row already has an agent set
        List<AA_Application__c> toAssign = new List<AA_Application__c>();
        for (AA_Application__c a : newRows) {
            if (String.isBlank(a.Val_Agent__c)) toAssign.add(a);
        }
        if (toAssign.isEmpty()) return;

        // Load active agents (name + weight). If none configured, silently
        // skip — leaving Val_Agent__c null; admin will populate later.
        List<AA_Val_Agent__c> agents = [
            SELECT Name, Weight__c FROM AA_Val_Agent__c
            WHERE Active__c = true AND Weight__c != null AND Weight__c > 0
            ORDER BY Weight__c DESC, Name ASC
        ];
        if (agents.isEmpty()) return;

        // Current counts per agent name (only active agents count in the
        // denominator — reassigning after a paused agent recovers is fine).
        Set<String> activeNames = new Set<String>();
        for (AA_Val_Agent__c ag : agents) activeNames.add(ag.Name);

        Map<String, Integer> counts = new Map<String, Integer>();
        for (String n : activeNames) counts.put(n, 0);

        for (AggregateResult ar : [
            SELECT Val_Agent__c agent, COUNT(Id) cnt FROM AA_Application__c
            WHERE Val_Agent__c IN :activeNames
            GROUP BY Val_Agent__c
        ]) {
            counts.put((String) ar.get('agent'), Integer.valueOf(ar.get('cnt')));
        }

        Decimal totalWeight = 0;
        for (AA_Val_Agent__c ag : agents) totalWeight += ag.Weight__c;

        Integer runningTotal = 0;
        for (Integer c : counts.values()) runningTotal += c;

        // Assign each row in order — after each, the local count bumps up so
        // subsequent rows in the SAME batch see the updated distribution.
        for (AA_Application__c app : toAssign) {
            runningTotal += 1;
            String winner = pickAgent(agents, counts, totalWeight, runningTotal);
            if (winner != null) {
                app.Val_Agent__c = winner;
                counts.put(winner, counts.get(winner) + 1);
            }
        }
    }

    /** Largest-deficit selection — see class-header algorithm note. */
    @TestVisible
    private static String pickAgent(List<AA_Val_Agent__c> agents, Map<String, Integer> counts, Decimal totalWeight, Integer runningTotal) {
        Decimal bestDeficit = null;
        String winner = null;
        Decimal winnerWeight = -1;
        for (AA_Val_Agent__c ag : agents) {
            Decimal ideal = ((Decimal) runningTotal) * ag.Weight__c / totalWeight;
            Decimal deficit = ideal - counts.get(ag.Name);
            if (bestDeficit == null
                || deficit > bestDeficit
                || (deficit == bestDeficit && ag.Weight__c > winnerWeight)) {
                bestDeficit = deficit;
                winner = ag.Name;
                winnerWeight = ag.Weight__c;
            }
        }
        return winner;
    }
}
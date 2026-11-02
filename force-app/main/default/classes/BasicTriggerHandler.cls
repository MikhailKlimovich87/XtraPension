public without sharing class BasicTriggerHandler {

    public Map<Id, Basic__c> newClaim;
    public Map<Id, Basic__c> oldClaim;
    public List<Basic__c> newClaimsList;

    // Statuses that participate in agent distribution.
    // NOTE: These must match the picklist values exactly (case, spacing).
    private static final List<String> DISTRIBUTION_STATUSES = new List<String>{
        'Form In Progress',
        'Validation Call',
        'Form completed',
        'Pending Client'
    };

    // Single source of truth for the distribution weights (30 / 30 / 40).
    // AGENTS is derived from this map so the two can never drift apart.
    private static final Map<String, Decimal> WEIGHTS = new Map<String, Decimal>{
        'Sean B' => 30,
        'Ciara'  => 30,
        'Becky'  => 40
    };

    // Preserve an explicit order for deterministic tie-breaking.
    private static final List<String> AGENTS = new List<String>{
        'Sean B', 'Ciara', 'Becky'
    };

    // Shared status strings (keep in sync with BP_DocuSignController / picklist values)
    private static final String STATUS_SIGNED_WAITING_DOCS = 'Signed - Waiting Docs at WDM';
    private static final String STATUS_SENT_FOR_ESIG = 'Sent for eSignature';
    private static final String STATUS_FORM_COMPLETED = 'Form completed';

    // One pack regeneration per claim and transaction
    private static Set<Id> packRegenerationQueued = new Set<Id>();

    public BasicTriggerHandler(
        List<Basic__c> newClaimsList,
        Map<Id, Basic__c> newClaim,
        Map<Id, Basic__c> oldClaim
    ) {
        this.newClaimsList = newClaimsList == null ? new List<Basic__c>() : newClaimsList;
        this.newClaim      = newClaim == null ? new Map<Id, Basic__c>() : newClaim;
        this.oldClaim      = oldClaim == null ? new Map<Id, Basic__c>() : oldClaim;
    }

    // The documents are already with the signer: changing the data now would make the pack
    // disagree with what is being signed. The envelope has to be voided first (the claim then
    // goes back to the agent as "Pending Client").
    public void blockEditsWhileOutForSignature() {
        for (Basic__c claim : newClaimsList) {
            Basic__c old = oldClaim.get(claim.Id);
            if (old == null || old.Status__c != STATUS_SENT_FOR_ESIG || claim.Status__c != STATUS_SENT_FOR_ESIG) {
                continue;
            }
            List<String> changed = BP_ClaimPackGuard.changedSourceFields(old, claim);
            if (!changed.isEmpty()) {
                claim.addError('This claim is out for eSignature. Void the DocuSign envelope before changing: '
                    + String.join(changed, ', '));
            }
        }
    }

    // Data changed after the pack was generated and before it was sent: regenerate every document
    // so BR1, IPC1394, Client Summary and DD mandate stay consistent with each other.
    public void regeneratePackOnSourceChange() {
        if (System.isBatch() || System.isFuture()) {
            return;
        }
        for (Basic__c claim : newClaimsList) {
            Basic__c old = oldClaim.get(claim.Id);
            if (old == null || claim.Status__c != STATUS_FORM_COMPLETED || old.Status__c != STATUS_FORM_COMPLETED
                || packRegenerationQueued.contains(claim.Id)
                || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
                continue;
            }
            if (!BP_ClaimPackGuard.changedSourceFields(old, claim).isEmpty()) {
                packRegenerationQueued.add(claim.Id);
                try {
                    System.enqueueJob(new BP_RegeneratePackQueueable(claim.Id));
                } catch (Exception ex) {
                    System.debug(LoggingLevel.ERROR, 'Pack regeneration was not queued: ' + ex.getMessage());
                }
            }
        }
    }

    public void generatePdfFiles() {
        for (Basic__c app : newClaim.values()) {
            Basic__c old = oldClaim.get(app.Id);

            if (app.Status__c == STATUS_SIGNED_WAITING_DOCS
                && old != null
                && app.Status__c != old.Status__c) {

                // The full-form ZIP is NOT built here: it must contain the BR1 regenerated after signing
                // (DocuSign date), so BP_GenerateApplication_BR1 builds it once that BR1 has been saved.
                if (app.GoCardless_Mandate_Id__c == null) {
                    createMandate(app.Id);
                }
            }
        }
    }

    public void distributeBetweenAgents() {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (String agent : AGENTS) {
            counts.put(agent, 0);
        }

        for (AggregateResult result : [
            SELECT Validation_Agent__c agent, COUNT(Id) recordCount
            FROM Basic__c
            WHERE Validation_Agent__c IN :AGENTS
              AND Status__c IN :DISTRIBUTION_STATUSES
            GROUP BY Validation_Agent__c
        ]) {
            String agentName = (String) result.get('agent');
            Object cntObj    = result.get('recordCount');

            // Defensive: alias lookup can return null in some API versions.
            if (agentName == null) agentName = (String) result.get('expr0');
            if (cntObj    == null) cntObj    = result.get('expr1');

            if (agentName == null || cntObj == null) {
                continue;
            }
            counts.put(agentName, (Integer) cntObj);
        }

        for (Basic__c claim : newClaimsList) {

            if (!DISTRIBUTION_STATUSES.contains(claim.Status__c)) {
                continue;
            }
            if (String.isNotBlank(claim.Validation_Agent__c)) {
                continue;
            }

            String selectedAgent;
            Decimal lowestRatio;

            for (String agent : AGENTS) {

                Integer c = counts.get(agent);
                if (c == null) c = 0;   // null-safe

                Decimal weight = WEIGHTS.get(agent);
                if (weight == null || weight == 0) {
                    continue;
                }

                Decimal ratio = Decimal.valueOf(c) / weight;

                if (selectedAgent == null || ratio < lowestRatio) {
                    selectedAgent = agent;
                    lowestRatio = ratio;
                }
            }

            if (selectedAgent == null) {
                selectedAgent = AGENTS[0];
            }

            claim.Validation_Agent__c = selectedAgent;

            Integer current = counts.get(selectedAgent);
            counts.put(selectedAgent, (current == null ? 0 : current) + 1);
        }
    }

    @future(callout=true)
    public static void createMandate(Id claimId) {
        if (claimId == null) return;

        List<Basic__c> claims = [
            SELECT
                Id,
                First_Name__c,
                Last_Name__c,
                Email__c,
                Contact__c,
                Claimant_address1__c,
                Claimant_address2__c,
                Claimant_City__c,
                Eircode__c,
                Current_Address_Abroad_Country_Name__c,
                Current_Address_Abroad__CountryCode__s,
                Current_Address_Abroad_Country__c,
                Current_Address_Abroad_State_Name__c,
                Bank_IBAN__c,
                Bank_BIC__c,
                BSB_Number__c,
                GoCardless_Customer_Id__c,
                GoCardless_Bank_Account_Id__c,
                GoCardless_Mandate_Id__c,
                Bank_Account__c,
                Bank_Sort_Code__c,
                CurrencyIsoCode,
                Name
            FROM Basic__c
            WHERE Id = :claimId
        ];
        if (claims.isEmpty()) return;

        GocardlessApiService service = new GocardlessApiService(claims[0]);
        if (!Test.isRunningTest()) {
            service.createMandateDirectly();
        }
    }
}
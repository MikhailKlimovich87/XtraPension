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

    // Every claim from Australia or New Zealand goes to Becky (Fernando, 10 Nov 2026): she takes the
    // AUS/NZ validation calls (book.xtrapension.com/go/claim-aus books the claim's own agent).
    private static final String AUS_NZ_AGENT = 'Becky';
    private static final List<String> AUS_NZ_CODES = new List<String>{ 'AU', 'NZ' };
    private static final List<String> AUS_NZ_NAMES = new List<String>{ 'Australia', 'New Zealand' };

    // Single source of truth for the split of every other claim (Fernando, 10 Nov 2026:
    // Becky 25%, Ciara 37.5%, Sean B 37.5%), counted over the open claims that are not AUS/NZ.
    private static final Map<String, Decimal> WEIGHTS = new Map<String, Decimal>{
        'Sean B' => 37.5,
        'Ciara'  => 37.5,
        'Becky'  => 25
    };

    // Preserve an explicit order for deterministic tie-breaking.
    private static final List<String> AGENTS = new List<String>{
        'Sean B', 'Ciara', 'Becky'
    };

    // Shared status strings (keep in sync with BP_DocuSignController / picklist values)
    private static final String STATUS_SIGNED_WAITING_DOCS = 'Signed - Waiting Docs at WDM';
    private static final String STATUS_SENT_FOR_ESIG = 'Sent for eSignature';
    private static final String STATUS_FORM_COMPLETED = 'Form completed';

    // The pack exists and has not gone out for signature yet: a data change regenerates it (also used by the editors).
    public static final Set<String> PACK_EDIT_STATUSES = new Set<String>{
        STATUS_FORM_COMPLETED, 'Pending Client', 'Agent Check', 'QC Approved'
    };

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
        // The client's own form (portal, Apex REST) autosaves every minute; it regenerates the pack on its last step.
        if (System.isBatch() || System.isFuture() || RestContext.request != null) {
            return;
        }
        for (Basic__c claim : newClaimsList) {
            Basic__c old = oldClaim.get(claim.Id);
            if (old == null || !PACK_EDIT_STATUSES.contains(claim.Status__c) || old.Status__c != claim.Status__c
                || packRegenerationQueued.contains(claim.Id)
                || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
                continue;
            }
            if (!BP_ClaimPackGuard.changedSourceFields(old, claim).isEmpty()) {
                queuePackRegeneration(claim.Id);
            }
        }
    }

    // One whole-pack regeneration per claim and transaction. Also used by the IPCBR1 / IPC1394 editors
    // (XpEditorDocsAfterSave), which save in the same transaction as this trigger. Returns true when a
    // regeneration is queued for the claim (now or earlier in the transaction).
    public static Boolean queuePackRegeneration(Id claimId) {
        if (packRegenerationQueued.contains(claimId)) {
            return true;
        }
        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
            return false;
        }
        packRegenerationQueued.add(claimId);
        // XpClaimDocs: an agent cannot add versions to the claim's files, so for them the job runs as XtraPension Admin
        try {
            if (!XpClaimDocs.request(claimId, XpClaimDocs.REGENERATE)) {
                packRegenerationQueued.remove(claimId);
                return false;
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Pack regeneration was not queued: ' + ex.getMessage());
            packRegenerationQueued.remove(claimId);
            return false;
        }
        return true;
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

    // A claim from Australia or New Zealand, by its country code or, when that is empty, its country name.
    public static Boolean isAusNz(Basic__c claim) {
        String code = claim.Current_Address_Abroad_Country__c == null ? '' : claim.Current_Address_Abroad_Country__c.trim().toUpperCase();
        if (String.isNotBlank(code)) {
            return AUS_NZ_CODES.contains(code);
        }
        String name = claim.Current_Address_Abroad_Country_Name__c == null ? '' : claim.Current_Address_Abroad_Country_Name__c.trim();
        for (String n : AUS_NZ_NAMES) {
            if (n.equalsIgnoreCase(name)) {
                return true;
            }
        }
        return false;
    }

    // Emails of our own and the devs' test claims: their Stage 1 pack is never queued for the printing house
    // (Is_Test_Claim__c, read by BP_PortalUtils.generateZipArchiveAfterCreatedClaim). Added 10/11/2026.
    private static final List<String> TEST_EMAIL_PARTS = new List<String>{
        '@xtrapension.com', '@tinderpoint.com', '@succraft.com', '@success-craft.com', 'mihail.klimovich@', '+test'
    };

    @TestVisible
    private static Boolean isTestEmail(String email) {
        if (String.isBlank(email)) {
            return false;
        }
        String e = email.trim().toLowerCase();
        for (String part : TEST_EMAIL_PARTS) {
            if (e.contains(part)) {
                return true;
            }
        }
        return false;
    }

    public void markTestClaims() {
        for (Basic__c claim : newClaimsList) {
            if (claim.Is_Test_Claim__c != true && isTestEmail(claim.Email__c)) {
                claim.Is_Test_Claim__c = true;
            }
        }
    }

    // "Ever Work in the UK" changed on the Claim page counts as answered: the long form shows Yes until
    // Ever_Work_UK_approved__c is set (BP_ResponseWrappers), and its next autosave would write Yes back (10/11/2026).
    public void markWorkedInUkAnswered() {
        if (RestContext.request != null) {
            return;
        }
        for (Basic__c claim : newClaimsList) {
            Basic__c old = oldClaim.get(claim.Id);
            if (old != null && claim.Claimant_Ever_Worked_UK__c != old.Claimant_Ever_Worked_UK__c && claim.Ever_Work_UK_approved__c != true) {
                claim.Ever_Work_UK_approved__c = true;
            }
        }
    }

    public void distributeBetweenAgents() {
        // Runs on before insert (BasicTrigger): also the place to mark test claims, without touching the trigger
        markTestClaims();
        Map<String, Integer> counts = new Map<String, Integer>();
        for (String agent : AGENTS) {
            counts.put(agent, 0);
        }

        // Only the open claims that are not AUS/NZ: Becky's AUS/NZ claims do not take from her 25% of the rest.
        for (AggregateResult result : [
            SELECT Validation_Agent__c agent, COUNT(Id) recordCount
            FROM Basic__c
            WHERE Validation_Agent__c IN :AGENTS
              AND Status__c IN :DISTRIBUTION_STATUSES
              AND (Current_Address_Abroad_Country__c = null OR Current_Address_Abroad_Country__c NOT IN :AUS_NZ_CODES)
              AND (Current_Address_Abroad_Country__c != null OR Current_Address_Abroad_Country_Name__c = null OR Current_Address_Abroad_Country_Name__c NOT IN :AUS_NZ_NAMES)
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
            if (isAusNz(claim)) {
                claim.Validation_Agent__c = AUS_NZ_AGENT;
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
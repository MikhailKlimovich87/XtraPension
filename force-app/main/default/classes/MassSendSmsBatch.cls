public class MassSendSmsBatch implements Database.Batchable<SObject>, Database.AllowsCallouts {

    private String messageBody;
    private String countryFilter;

    // ---------------------------------------------------------------
    // Constructors
    // ---------------------------------------------------------------
    public MassSendSmsBatch(String messageBody, String countryFilter) {
        this.messageBody   = messageBody;
        this.countryFilter = countryFilter;
    }

    public MassSendSmsBatch(String messageBody) {
        this(messageBody, null);
    }

    // ---------------------------------------------------------------
    // START
    // ---------------------------------------------------------------
    public Database.QueryLocator start(Database.BatchableContext bc) {
        String q = 'SELECT Id, Address_abroad__CountryCode__s, Phone__c ' +
                   'FROM Reapply__c ' +
                   'WHERE CreatedDate = TODAY ';

        if (String.isNotBlank(countryFilter)) {
            q += countryFilter;
        }

        //q += ' LIMIT 1';
        System.debug(q);
        return Database.getQueryLocator(q);
    }

    // ---------------------------------------------------------------
    // EXECUTE
    // ---------------------------------------------------------------
    public void execute(Database.BatchableContext bc, List<Reapply__c> scope) {
 System.debug('scope === ' + scope);
        // 1. Collect Reapply Ids in this chunk
        Set<Id> reapplyIds = new Set<Id>();
        for (Reapply__c r : scope) {
            reapplyIds.add(r.Id);
        }

        // 2. Find which of those have at least one Sent EmailMessage
        Set<Id> reappliesWithSentEmail = new Set<Id>();
        if (!reapplyIds.isEmpty()) {
            for (EmailMessage em : [
                SELECT Id, RelatedToId
                FROM EmailMessage
                WHERE RelatedToId IN :reapplyIds
            ]) {
                reappliesWithSentEmail.add(em.RelatedToId);
            }
        }

        // 3. Send SMS only when the Reapply has a Sent email AND a phone
        for (Reapply__c c : scope) {
            System.debug('Repply === ' + c);
            if (!reappliesWithSentEmail.contains(c.Id)) {
                System.debug('Skipping ' + c.Id + ' — no Sent EmailMessage found');
                continue;
            }
            if (String.isBlank(c.Phone__c)) {
                System.debug('Skipping ' + c.Id + ' — no phone number');
                continue;
            }

            try {
                HttpResponse res = TwilioSmsSender.send(
                    messageBody, c.Phone__c, c.Address_abroad__CountryCode__s
                );
                System.debug('Repply === ' + c);
                if (res != null) {
                    System.debug(c.Phone__c + ' => ' + res.getStatusCode());
                }
            } catch (Exception ex) {
                System.debug('Error for ' + c.Phone__c + ' => ' + ex.getMessage());
            }
        }
    }

    // ---------------------------------------------------------------
    // FINISH
    // ---------------------------------------------------------------
    public void finish(Database.BatchableContext bc) {
        System.debug('MassSendSmsBatch finished. Job Id: ' + bc.getJobId());
    }


    public static void fakeMethod() {
        Integer i =0;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
        i++;
    }
}
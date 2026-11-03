public class GocardlessPaymentBatch
    implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date today = Date.today();
        return Database.getQueryLocator([
            SELECT Id,
                   Name,
                   Amount__c,
                   CurrencyIsoCode,
                   Status__c,
                   Payment_Date__c,
                   Basic__c,
                   Basic__r.Id,
                   Basic__r.Name,
                   Basic__r.First_Name__c,
                   Basic__r.Last_Name__c,
                   Basic__r.CurrencyIsoCode,
                   Basic__r.Email__c,
                   Basic__r.GoCardless_Mandate_Id__c,
                   Basic__r.GoCardless_Customer_Id__c,
                   Basic__r.GoCardless_Bank_Account_Id__c
            FROM Basic_Payment__c
            WHERE Status__c = 'Schedule'
              AND Payment_Date__c = :today
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Basic_Payment__c> scope) {
        List<Basic_Payment__c> toUpdate = new List<Basic_Payment__c>();

        for (Basic_Payment__c pmt : scope) {

            // ---------- Validation ----------
            if (pmt.Basic__r == null
            || String.isEmpty(pmt.Basic__r.GoCardless_Mandate_Id__c)
            || pmt.Amount__c == null
            || pmt.Amount__c <= 0) {

            toUpdate.add(new Basic_Payment__c(
                Id              = pmt.Id,
                Status__c       = 'Fail',
                Error_Message__c = 'Missing claim / mandate / amount.'
            ));
            continue;
        }

        // ---------- Call GoCardless ----------
        try {
            GocardlessApiService svc = new GocardlessApiService(pmt.Basic__r);

            // pmt.Amount__c is already the PER-INSTALMENT slice
            // (in major units, e.g. 33.33). Pass it straight through —
            // the service converts to minor units internally.
            // The payment record Id is the idempotency key: a re-run of this batch can never charge twice.
            GocardlessApiService.PaymentResult result =
                svc.chargeDirectDebitPayment(pmt.Amount__c, 'sf-payment-' + pmt.Id);

            if (result.isSuccess) {
                // API accepted the request → payment is in flight, NOT paid
                toUpdate.add(new Basic_Payment__c(
                    Id                       = pmt.Id,
                    Status__c                = 'Submitted',
                    GoCardless_Payment_Id__c = result.paymentId,
                    Error_Message__c         = null
                ));
            } else {
                toUpdate.add(new Basic_Payment__c(
                    Id               = pmt.Id,
                    Status__c        = 'Fail',
                    Error_Message__c = truncate(result.errorMessage, 255)
                ));
            }

            } catch (Exception ex) {
                toUpdate.add(new Basic_Payment__c(
                    Id               = pmt.Id,
                    Status__c        = 'Fail',
                    Error_Message__c = truncate(ex.getMessage(), 255)
                ));
            }
        }

        if (!toUpdate.isEmpty()) {
            logSaveFailures(toUpdate, Database.update(toUpdate, false));
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO, 'GocardlessPaymentBatch finished.');
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------
    // A failed update must never be silent: the instalment would stay in 'Schedule' with a past date and never be retried.
    private static void logSaveFailures(List<Basic_Payment__c> updated, List<Database.SaveResult> results) {
        List<String> errors = new List<String>();
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                errors.add(updated[i].Id + ' (' + updated[i].Status__c + '): ' + results[i].getErrors()[0].getMessage());
            }
        }
        if (errors.isEmpty()) {
            return;
        }
        System.debug(LoggingLevel.ERROR, 'GocardlessPaymentBatch could not save: ' + errors);
        try {
            insert new Application_Form_Error__c(
                Error_Body__c = 'GoCardless charge result could not be saved on ' + errors.size() + ' instalment(s):\n' + String.join(errors, '\n'),
                Error_Date__c = Date.today()
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Could not log GoCardless save failures: ' + ex.getMessage());
        }
    }

    private static String truncate(String s, Integer maxLen) {
        if (String.isBlank(s)) return s;
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }
}
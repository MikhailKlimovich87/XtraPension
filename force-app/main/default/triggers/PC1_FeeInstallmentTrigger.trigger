/**
 * PC1_FeeInstallmentTrigger — pin GBP on fee installments.
 *
 * Amount__c is a currency-typed field, so it renders in the RECORD's currency.
 * PC1_FeeInstallmentScheduler already sets CurrencyIsoCode='GBP' when it
 * generates a plan, but a row created any other way (the UI, Data Loader, a
 * future code path) inherits the org's corporate EUR and shows the installment
 * in euros on the fee card. This makes GBP structural rather than remembered.
 */
trigger PC1_FeeInstallmentTrigger on PC1_Fee_Installment__c (before insert) {
    PC1_CurrencyGuard.forceGbp(Trigger.new);
}
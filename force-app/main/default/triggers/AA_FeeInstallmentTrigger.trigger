/**
 * AA_FeeInstallmentTrigger — pins CurrencyIsoCode='GBP' on every fee
 * instalment at insert.
 *
 * This trigger was removed on 2026-09-11 on the reasoning that
 * AA_Fee_Installment__c is a master-detail child of AA_Application__c and so
 * inherits the parent's currency, making the stamp redundant. The deploy then
 * failed AA_CurrencyGuardTest.feeInstallmentIsForcedToGbp with
 * "Expected: GBP, Actual: EUR" — the child does NOT inherit it here, it takes
 * the org's corporate currency, which is EUR. Restored, and the test is what
 * keeps it honest: delete this trigger again and that assertion fails again.
 *
 * Sibling of the same guard on AA_ApplicationTrigger and
 * AA_HandoffNotifyTrigger — the three money-bearing objects.
 */
trigger AA_FeeInstallmentTrigger on AA_Fee_Installment__c (before insert) {
    AA_CurrencyGuard.forceGbp(Trigger.new);
}
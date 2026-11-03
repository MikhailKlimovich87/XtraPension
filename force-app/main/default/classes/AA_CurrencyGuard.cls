/**
 * AA_CurrencyGuard — force CurrencyIsoCode = 'GBP' on AA money-bearing records.
 *
 * The org's CORPORATE currency is EUR and must stay EUR: it is shared with the
 * other XtraPension products and changing it would reprice every existing record
 * in the org. AA is a UK product, so every AA record has to pin GBP for itself.
 *
 * The Node webhooks already pass CurrencyIsoCode='GBP' at their insert sites,
 * but that is a convention, not a guarantee:
 *   • anything created in the Salesforce UI gets the running user's currency,
 *     which for the val team is EUR (locale en_IE) — that is how PC1 records
 *     PC00102 and HO-000335 ended up in euros before PC1 grew this guard;
 *   • any NEW insert path that forgets the field reintroduces the bug silently,
 *     because a EUR record looks completely normal until money is displayed —
 *     and Award_Amount__c / Fee_Amount__c drive a GBP GoCardless charge.
 *
 * A before-insert guard makes GBP structural instead of remembered, and covers
 * the UI, the API, Data Loader and future code paths in one place. Verbatim
 * port of PC1_CurrencyGuard (2026-09-09); wired from AA_ApplicationTrigger
 * AA_HandoffNotifyTrigger and AA_FeeInstallmentTrigger. The fee-instalment one
 * is NOT redundant despite that object being a master-detail child: it does not
 * inherit the parent currency here, it takes the org corporate currency (EUR).
 * AA_CurrencyGuardTest.feeInstallmentIsForcedToGbp proves it.
 *
 * All three are insert-only (PC1 parity). On AA_Application__c the update path
 * is closed by the Currency_Must_Be_GBP validation rule (2026-09-11), because
 * CurrencyIsoCode remains editable on the record layout.
 *
 * Deliberately generic (SObject + describe check) so it is safe to call on any
 * object, and so it no-ops rather than failing to compile if the org is ever
 * converted back to single-currency (where CurrencyIsoCode does not exist).
 */
public with sharing class AA_CurrencyGuard {

    private static final String ISO_FIELD = 'CurrencyIsoCode';
    private static final String GBP = 'GBP';

    /** Stamp GBP on every row that isn't already GBP. Safe on empty/null input. */
    public static void forceGbp(List<SObject> rows) {
        if (rows == null || rows.isEmpty()) return;
        // Multi-currency is an org-level toggle; in a single-currency org the
        // field simply is not there and there is nothing to pin.
        if (!rows[0].getSObjectType().getDescribe().fields.getMap().containsKey(ISO_FIELD)) return;
        for (SObject row : rows) {
            if (row.get(ISO_FIELD) != GBP) row.put(ISO_FIELD, GBP);
        }
    }
}
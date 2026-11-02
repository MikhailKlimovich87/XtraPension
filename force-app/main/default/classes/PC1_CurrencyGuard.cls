/**
 * PC1_CurrencyGuard — force CurrencyIsoCode = 'GBP' on PC1 money-bearing records.
 *
 * The org's CORPORATE currency is EUR and must stay EUR: it is shared with the
 * other XtraPension products and changing it would reprice every existing record
 * in the org. PC1 is a UK product, so every PC1 record has to pin GBP for itself.
 *
 * The Node webhooks already pass CurrencyIsoCode='GBP' at 7 separate insert
 * sites, but that is a convention, not a guarantee:
 *   • anything created in the Salesforce UI gets the running user's currency,
 *     which for the val team is EUR (locale en_IE) — that is how PC00102 and
 *     HO-000335 ended up in euros;
 *   • any NEW insert path that forgets the field reintroduces the bug silently,
 *     because a EUR record looks completely normal until money is displayed.
 *
 * A before-insert guard makes GBP structural instead of remembered, and covers
 * the UI, the API, Data Loader and future code paths in one place.
 *
 * Deliberately generic (SObject + describe check) so it is safe to call on any
 * object, and so it no-ops rather than failing to compile if the org is ever
 * converted back to single-currency (where CurrencyIsoCode does not exist).
 */
public with sharing class PC1_CurrencyGuard {

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
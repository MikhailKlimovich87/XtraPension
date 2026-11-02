/**
 * pc1DDStatusCard — Direct Debit agreement snapshot for a PC1 Application.
 *
 * Reads the DD agreement state via PC1_GoCardlessController.getDDStatus
 * (cacheable) and mirrors the same fields via getRecord so the card reacts
 * live when other LWCs (or Apex triggers) mutate DD_Mandate_Status__c.
 *
 * Four visible states:
 *   1. No DD agreement yet → grey banner + gating hint (or Create Direct
 *      Debit button when Bank_Verification_Status__c is a green outcome
 *      AND DD_Terms_Read_By_Sales__c is true)
 *   2. Waiting for the bank to confirm → amber banner
 *   3. Active → green banner + activated-at + masked reference
 *   4. Failed / cancelled / expired → red banner with reason + next action
 *
 * The DD reference (mandate id under the hood) is masked to the last 6
 * characters — the underlying GoCardless identifier is opaque but we keep
 * the tail so ops can cross-reference against the GC dashboard without
 * exposing the full id to the sales rep or the client.
 *
 * (2026-08-18 UX audit) — user-facing wording rewritten: "mandate" →
 * "Direct Debit agreement", "GoCardless" is never shown to end users, raw
 * state strings ("pending_submission" etc.) are translated by prettyStatus.
 */
import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDDStatus              from '@salesforce/apex/PC1_GoCardlessController.getDDStatus';
import createMandateForApplication from '@salesforce/apex/PC1_GoCardlessController.createMandateForApplication';

const FIELDS = [
    'PC1_Application__c.DD_Mandate_Id__c',
    'PC1_Application__c.DD_Mandate_Status__c',
    'PC1_Application__c.DD_Mandate_Created_At__c',
    'PC1_Application__c.DD_Mandate_Activated_At__c',
    'PC1_Application__c.DD_Mandate_Failure_Reason__c',
    'PC1_Application__c.Bank_Verification_Status__c',
    'PC1_Application__c.DD_Terms_Read_By_Sales__c',
];

// Statuses that mean "safe to charge" — anything else is either pending, no
// mandate at all, or a hard failure that requires operator attention.
const ACTIVE_STATUSES  = ['active'];
const PENDING_STATUSES = [
    'pending_customer_approval',
    'pending_submission',
    'submitted',
];
const FAILED_STATUSES  = [
    'failed',
    'cancelled',
    'expired',
    'consumed',
    'blocked',
    'suspended_by_payer',
];
// Bank_Verification_Status__c values that unlock "Create Direct Debit".
// Must stay in sync with:
//   - PC1_MandateEligibility.VERIFIED_STATUSES (Apex)
//   - PC1_GoCardlessController.BANK_VERIFIED_STATUSES (Apex)
//   - web/intake.html runBankVerify() green + amber cases
// Name Close Match is included because it's the amber "sales already
// confirmed the spelling with the client" path.
const BANK_GREEN = [
    'Modulus Passed', 'Name Verified', 'Bank Confirmed', 'Name Close Match',
];

export default class Pc1DDStatusCard extends LightningElement {
    @api recordId;

    wiredRecord;
    wiredStatus;

    // From getRecord (reactive)
    mandateId       = '';
    mandateStatus   = '';
    createdAt       = null;
    activatedAt     = null;
    failureReason   = '';
    bankStatus      = '';
    ddTermsRead     = false;

    creating = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredHandler(res) {
        this.wiredRecord = res;
        if (res.data) {
            const f = res.data.fields;
            this.mandateId     = f.DD_Mandate_Id__c?.value || '';
            this.mandateStatus = f.DD_Mandate_Status__c?.value || '';
            this.createdAt     = f.DD_Mandate_Created_At__c?.value || null;
            this.activatedAt   = f.DD_Mandate_Activated_At__c?.value || null;
            this.failureReason = f.DD_Mandate_Failure_Reason__c?.value || '';
            this.bankStatus    = f.Bank_Verification_Status__c?.value || '';
            this.ddTermsRead   = !!f.DD_Terms_Read_By_Sales__c?.value;
        }
    }

    // Cacheable getDDStatus — used for the "status snapshot" (mandate id,
    // latest known status directly from GoCardless via the controller). Kept
    // alongside getRecord so a refreshApex after Create Mandate updates
    // BOTH surfaces on the next tick.
    @wire(getDDStatus, { recordId: '$recordId' })
    wiredStatusHandler(res) {
        this.wiredStatus = res;
    }

    // ── computed: which of the four states are we in ─────────────────
    get isNoMandate()      { return !this.mandateId; }
    get isActive()         { return ACTIVE_STATUSES.includes(this.mandateStatus); }
    get isPending()        { return this.mandateId && PENDING_STATUSES.includes(this.mandateStatus); }
    get isFailed()         { return this.mandateId && FAILED_STATUSES.includes(this.mandateStatus); }

    // Create-Mandate gate — bank green + DD terms read + no mandate yet
    get canCreate() {
        return this.isNoMandate
            && BANK_GREEN.includes(this.bankStatus)
            && this.ddTermsRead;
    }

    // Replace gate — the current mandate is dead (failed / cancelled /
    // expired, or parked after a bank change) and the NEW details are green.
    // PC1_GoCardlessController creates a replacement and cancels the old one.
    get canReplace() {
        return this.isFailed
            && BANK_GREEN.includes(this.bankStatus)
            && this.ddTermsRead;
    }

    get gatingHint() {
        const missing = [];
        if (!BANK_GREEN.includes(this.bankStatus)) missing.push('confirmed bank details');
        if (!this.ddTermsRead) missing.push('Direct Debit terms read to the client');
        return missing.length ? `Needs: ${missing.join(' + ')}.` : '';
    }

    get maskedMandateId() {
        const id = this.mandateId || '';
        if (id.length <= 6) return id;
        return '…' + id.slice(-6);
    }

    get activatedAtDisplay() { return this.fmt(this.activatedAt); }
    get createdAtDisplay()   { return this.fmt(this.createdAt); }

    get prettyStatus() {
        // Explicit whitelist of every GC state → plain-English translation.
        // Anything unknown falls back to a spaced/capitalised rendering so
        // ops still sees something rather than nothing, but the sales rep
        // never sees raw snake_case (2026-08-18 UX audit).
        const s = (this.mandateStatus || '').toLowerCase();
        const MAP = {
            'pending_customer_approval': 'Waiting for the client to approve',
            'pending_submission':        'Waiting for your bank to confirm',
            'submitted':                 'Sent to the bank',
            'active':                    'Active',
            'failed':                    'Direct Debit failed at the bank',
            'cancelled':                 'Cancelled',
            'expired':                   'Expired — set up a new one',
            'consumed':                  'No longer active',
            'blocked':                   'Blocked — contact support',
            'suspended_by_payer':        'Paused by the client’s bank',
        };
        if (!s) return '';
        if (MAP[s]) return MAP[s];
        const spaced = s.replace(/_/g, ' ');
        return spaced.charAt(0).toUpperCase() + spaced.slice(1);
    }

    get failureSnippet() {
        const r = (this.failureReason || '').trim();
        if (!r) return '';
        return r.length > 140 ? r.slice(0, 140) + '…' : r;
    }

    // Banner classes — BEM modifier per state
    get bannerClass() {
        const base = 'pc1-ddstatus__banner';
        if (this.isActive)  return `${base} ${base}--ok`;
        if (this.isPending) return `${base} ${base}--warn`;
        if (this.isFailed)  return `${base} ${base}--err`;
        return `${base} ${base}--none`;
    }

    // ── actions ──────────────────────────────────────────────────────
    async handleCreateMandate() {
        this.creating = true;
        try {
            const r = await createMandateForApplication({ recordId: this.recordId });
            if (r && r.ok) {
                this.toast(
                    r.replaced ? 'New Direct Debit set up' : 'Direct Debit set up',
                    'success',
                    `Status: ${r.status || 'waiting for the bank'} · Ref …${(r.mandate_id || '').slice(-6)}`
                );
                await refreshApex(this.wiredRecord);
                await refreshApex(this.wiredStatus);
            } else {
                this.toast('Direct Debit setup failed', 'error', 'The Direct Debit could not be created — try again in a minute.');
            }
        } catch (err) {
            this.toast('Direct Debit setup failed', 'error', this.errMsg(err));
        } finally {
            this.creating = false;
        }
    }

    // ── util ─────────────────────────────────────────────────────────
    fmt(iso) {
        if (!iso) return '';
        try {
            return new Date(iso).toLocaleString('en-GB', {
                day: '2-digit', month: '2-digit', year: 'numeric',
                hour: '2-digit', minute: '2-digit',
                timeZone: 'Europe/London',
            });
        } catch (_) { return iso; }
    }
    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, variant, message: message || '' }));
    }
    errMsg(e) { return e?.body?.message || e?.message || 'Unknown error'; }
}
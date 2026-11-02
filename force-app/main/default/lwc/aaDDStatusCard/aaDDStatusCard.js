/**
 * aaDDStatusCard — Direct Debit agreement snapshot for a AA Application.
 *
 * Reads the DD agreement state via AA_GoCardlessController.getDDStatus
 * (cacheable) and mirrors the same fields via getRecord so the card reacts
 * live when other LWCs (or Apex triggers) mutate DD_Mandate_Status__c.
 *
 * Five visible states:
 *   1. No DD agreement yet → grey banner + gating hint (or Create Direct
 *      Debit button when Bank_Verification_Status__c is a green outcome
 *      AND DD_Terms_Read_By_Sales__c is true)
 *   1b. Created at GoCardless but the mandate PDF never landed (status set,
 *      DD_Mandate_Id__c still blank) → amber banner + "Retry mandate
 *      document" (audit 2026-10-02 F103: this state used to show BOTH the
 *      "Not set up" and the "Active" banners)
 *   2. Waiting for the bank to confirm → amber banner
 *   3. Active → green banner + activated-at + masked reference
 *   4. Failed / cancelled / expired → red banner with reason + next action
 *      + "Create a new Direct Debit" (audit 2026-10-02 F53/F100: the banner
 *      and the failure Task told the rep to click Create again, but the
 *      button only rendered in state 1, and a dead mandate keeps its
 *      DD_Mandate_Id__c, so the record was a dead end that also blocks the
 *      DWP fill).
 *   4b. Failed / cancelled BEFORE the mandate document landed (dead status,
 *      DD_Mandate_Id__c blank) → red banner + "Create a new Direct Debit"
 *      behind the same client-agreement confirm (wave-3 W3-2: this state used
 *      to fall into state 1 and offer a plain "Create Direct Debit" with no
 *      confirm, and Heroku quietly minted a new mandate for a payer who had
 *      cancelled).
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
import LightningConfirm from 'lightning/confirm';
import getDDStatus              from '@salesforce/apex/AA_GoCardlessController.getDDStatus';
import createMandateForApplication from '@salesforce/apex/AA_GoCardlessController.createMandateForApplication';
import recreateMandateForApplication from '@salesforce/apex/AA_GoCardlessController.recreateMandateForApplication';

const FIELDS = [
    'AA_Application__c.DD_Mandate_Id__c',
    'AA_Application__c.DD_Mandate_Status__c',
    'AA_Application__c.DD_Mandate_Created_At__c',
    'AA_Application__c.DD_Mandate_Activated_At__c',
    'AA_Application__c.DD_Mandate_Failure_Reason__c',
    'AA_Application__c.Bank_Verification_Status__c',
    'AA_Application__c.DD_Terms_Read_By_Sales__c',
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
// Dead statuses AA_GoCardlessController.createMandateForApplication accepts
// for a re-create. Keep in sync with its `deadMandate` set: for any other
// status (blocked, suspended_by_payer…) Apex short-circuits with existed:true,
// so offering the button there would do nothing.
const RECREATE_STATUSES = ['failed', 'cancelled', 'expired'];
// Bank_Verification_Status__c values that unlock "Create Direct Debit".
// Must stay in sync with:
//   - AA_MandateEligibility.VERIFIED_STATUSES (Apex)
//   - AA_GoCardlessController.BANK_VERIFIED_STATUSES (Apex)
//   - web/intake.html runBankVerify() green + amber cases
// Name Close Match is included because it's the amber "sales already
// confirmed the spelling with the client" path.
const BANK_GREEN = [
    'Modulus Passed', 'Name Verified', 'Bank Confirmed', 'Name Close Match',
];

export default class AaDDStatusCard extends LightningElement {
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

    // ── computed: which state are we in ──────────────────────────────
    // A status with no mandate id = created at GoCardless, PDF still missing.
    get isPdfPending()     { return !this.mandateId && !!this.mandateStatus && !FAILED_STATUSES.includes(this.mandateStatus); }
    get isDeadNoId()       { return !this.mandateId && FAILED_STATUSES.includes(this.mandateStatus); }
    get isNoMandate()      { return !this.mandateId && !this.isPdfPending && !this.isDeadNoId; }
    get isActive()         { return !!this.mandateId && ACTIVE_STATUSES.includes(this.mandateStatus); }
    get isPending()        { return !!this.mandateId && PENDING_STATUSES.includes(this.mandateStatus); }
    get isFailed()         { return !!this.mandateId && FAILED_STATUSES.includes(this.mandateStatus); }

    get gatesGreen()       { return BANK_GREEN.includes(this.bankStatus) && this.ddTermsRead; }

    // Create-Mandate gate — bank green + DD terms read + no mandate yet
    get canCreate() {
        return this.isNoMandate && this.gatesGreen;
    }
    // Re-create over a dead mandate (same Apex method; it falls through to a
    // fresh mandate for failed / cancelled / expired).
    get canRecreate() {
        return this.isFailed && RECREATE_STATUSES.includes(this.mandateStatus) && this.gatesGreen;
    }
    // State 4b: with no id Apex does not short-circuit any dead status, so the
    // confirmed re-create is offered for all of them (gates still apply).
    get canRecreateNoId() {
        return this.isDeadNoId && this.gatesGreen;
    }
    get recreateBlockedHint() {
        if (!this.isFailed) return '';
        if (!RECREATE_STATUSES.includes(this.mandateStatus)) {
            return 'This Direct Debit cannot be replaced from here. Check it in the GoCardless dashboard.';
        }
        return this.gatesGreen ? '' : this.gatingHint;
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

    get prettyStatus() { return this.prettyFor(this.mandateStatus); }

    prettyFor(status) {
        // Explicit whitelist of every GC state → plain-English translation.
        // Anything unknown falls back to a spaced/capitalised rendering so
        // ops still sees something rather than nothing, but the sales rep
        // never sees raw snake_case (2026-08-18 UX audit).
        const s = (status || '').toLowerCase();
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
        const base = 'aa-ddstatus__banner';
        if (this.isActive)  return `${base} ${base}--ok`;
        if (this.isPending) return `${base} ${base}--warn`;
        if (this.isFailed)  return `${base} ${base}--err`;
        return `${base} ${base}--none`;
    }

    // ── actions ──────────────────────────────────────────────────────
    async handleRecreateMandate() {
        // A new Direct Debit needs the client's fresh agreement: a payer who
        // cancelled their Direct Debit has withdrawn the old authority.
        const ok = await LightningConfirm.open({
            label: 'Create a new Direct Debit?',
            message: 'Only continue if the client has agreed, on this call, to a new Direct Debit and you have '
                + 'read them the Direct Debit terms again. Check the bank details above are the ones they gave you.',
            theme: 'warning',
        });
        if (!ok) return;
        // The confirmed path tells Apex (and Heroku) the client agreed again.
        await this.handleCreateMandate(true);
    }

    async handleCreateMandate(clientReconfirmed) {
        this.creating = true;
        try {
            // onclick passes the click event: only a literal true counts.
            const r = clientReconfirmed === true
                ? await recreateMandateForApplication({ recordId: this.recordId })
                : await createMandateForApplication({ recordId: this.recordId });
            const returnedStatus = String((r && r.status) || '').toLowerCase();
            if (r && r.ok && FAILED_STATUSES.includes(returnedStatus)) {
                // wave-2 W2: a replayed GoCardless key used to hand back the OLD
                // dead mandate and this showed "Direct Debit set up". Apex now
                // refuses that case; this is the belt-and-braces check.
                this.toast('Direct Debit not set up', 'error',
                    `The Direct Debit came back as "${this.prettyFor(returnedStatus)}", so no new Direct Debit exists. Ask the tech team to check it.`);
                await refreshApex(this.wiredRecord);
                await refreshApex(this.wiredStatus);
            } else if (r && r.ok && r.pdf_pending) {
                // audit 2026-10-02 F103: the Direct Debit exists at GoCardless but
                // its PDF did not land, so the welcome email is held and the fee
                // cannot be charged yet. Do not report plain success.
                this.toast(
                    'Direct Debit created, document pending',
                    'warning',
                    'The Direct Debit was created but its mandate document has not arrived yet. Click "Retry mandate document" in a few minutes.'
                );
                await refreshApex(this.wiredRecord);
                await refreshApex(this.wiredStatus);
            } else if (r && r.ok) {
                this.toast(
                    'Direct Debit set up',
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
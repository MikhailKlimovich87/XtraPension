/**
 * aaBankEditor — single-tier UK bank verify panel for a AA Application.
 *
 * Tier 1 only — Bank Verify (auto). Server-side bank check via
 * AA_BankLookup.verifyAccount() → Heroku endpoint. Talks to Data8's live
 * UK bank registry when a holder name is present; falls back to a free
 * offline check when it isn't. Result populates Bank_Verification_Status__c
 * (Bank Confirmed / Name Verified / Name Close Match / Name Mismatch /
 * Invalid Sort Code / Invalid Account Number / Bank Does Not Accept DD /
 * Bank Verification Unavailable) and Bank_Name__c.
 *
 * (2026-08-17 refactor) — the earlier "Tier 2 verbal confirm" flow was
 * removed. Name confirmation now happens on the sales-agent side via a
 * separate DD Terms LWC that reads the terms back to the client; those
 * fields (DD_Terms_Read_By_Sales__c / _At__c / _By__c) live outside this
 * bundle. This bundle stays lean: fields, one Verify button, one status
 * badge with colour coding.
 *
 * (2026-08-18 UX audit) — status→colour→message mapping kept in strict sync
 * with web/intake.html runBankVerify() so the sales rep sees identical
 * wording whether they came in via the intake form or the SF record page.
 */
import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import verifyAccount             from '@salesforce/apex/AA_BankLookup.verifyAccount';
import verifyAndPersistAccount   from '@salesforce/apex/AA_BankLookup.verifyAndPersistAccount';
import saveVerification          from '@salesforce/apex/AA_BankLookup.saveVerification';
// Child modal for the (currently retired) verbal read-back step — see the
// FLAG in handleVerify() and openVerbalConfirm() below.
import AaVerbalConfirmModal      from 'c/aaVerbalConfirmModal';

const FIELDS = [
    'AA_Application__c.Bank_Sort_Code__c',
    'AA_Application__c.Bank_Account_Number__c',
    'AA_Application__c.Bank_Account_Holder__c',
    'AA_Application__c.Bank_Roll_Number__c',
    'AA_Application__c.Bank_Name__c',
    'AA_Application__c.Bank_Verification_Status__c',
    'AA_Application__c.Bank_Verified_At__c',
    'AA_Application__c.DD_Mandate_Id__c',
    'AA_Application__c.DD_Mandate_Status__c',
];

// Mandate statuses after which the Direct Debit no longer collects.
const DEAD_MANDATE = ['failed', 'cancelled', 'expired'];
const digitsOf = (s) => String(s || '').replace(/\D/g, '');

export default class AaBankEditor extends LightningElement {
    @api recordId;

    draft = { sort:'', account:'', holder:'', roll:'', bankName:'', status:'Unverified' };
    editing = false;
    verifying = false;
    saving = false;
    verifyMsg = '';
    verifyClass = 'aa-be__status';

    wiredRecord;
    mandateId = '';
    mandateStatus = '';
    original = {
        sort:'', account:'', holder:'', roll:'', bankName:'',
        status:'Unverified', verifiedAt:null,
    };

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredHandler(res) {
        this.wiredRecord = res;
        if (res.data) {
            const f = res.data.fields;
            this.original = {
                sort:       f.Bank_Sort_Code__c?.value || '',
                account:    f.Bank_Account_Number__c?.value || '',
                holder:     f.Bank_Account_Holder__c?.value || '',
                roll:       f.Bank_Roll_Number__c?.value || '',
                bankName:   f.Bank_Name__c?.value || '',
                status:     f.Bank_Verification_Status__c?.value || 'Unverified',
                verifiedAt: f.Bank_Verified_At__c?.value || null,
            };
            this.mandateId     = f.DD_Mandate_Id__c?.value || '';
            this.mandateStatus = f.DD_Mandate_Status__c?.value || '';
            if (!this.editing) this.draft = {
                sort: this.original.sort, account: this.original.account, holder: this.original.holder,
                roll: this.original.roll, bankName: this.original.bankName, status: this.original.status,
            };
        }
    }

    // ── computed ────────────────────────────────────────────────────
    get hasAny() {
        return this.original.sort || this.original.account || this.original.holder;
    }
    /** Status badge — colour comes from the auto-verify outcome. Kept in
     *  strict sync with the intake page + paintVerifyMsg() below.
     *  'Verified' is a legacy value from before the CoP-shaped contract —
     *  1 live record still carries it (probe 2026-08-18) so we keep the
     *  green branch until schema cleanup deactivates the picklist value. */
    get statusBadgeClass() {
        const s = this.original.status || 'Unverified';
        // GREEN — safe to proceed to DD agreement creation.
        if (['Modulus Passed','Name Verified','Bank Confirmed','Verified'].includes(s)) {
            return 'slds-badge slds-theme_success';
        }
        // AMBER — soft warning; DD agreement path still open.
        //   Name Close Match           : bank confirmed, name may differ slightly.
        //   Bank Does Not Accept DD    : real account, can't take Direct Debit.
        //   Bank Verification Unavailable : Data8 down / rate-limited; retry.
        if (['Name Close Match','Bank Does Not Accept DD',
             'Bank Verification Unavailable'].includes(s)) {
            return 'slds-badge slds-theme_warning';
        }
        // RED — hard block; digits or name need rechecking with the client.
        if (['Name Mismatch','Invalid Sort Code','Invalid Account Number'].includes(s)) {
            return 'slds-badge slds-theme_error';
        }
        return 'slds-badge';
    }
    get verifiedAtDisplay() {
        if (!this.original.verifiedAt) return '';
        try { return new Date(this.original.verifiedAt).toLocaleString('en-GB'); }
        catch (e) { return ''; }
    }
    get saveDisabled() {
        if (this.saving) return true;
        return !this.draft.sort?.trim() || !this.draft.account?.trim() || !this.draft.holder?.trim();
    }
    /** A Direct Debit that still collects is set up on the stored account. */
    get hasLiveMandate() {
        return !!this.mandateId && !DEAD_MANDATE.includes(String(this.mandateStatus || '').toLowerCase());
    }
    get draftDigitsChanged() {
        return digitsOf(this.draft.sort) !== digitsOf(this.original.sort)
            || digitsOf(this.draft.account) !== digitsOf(this.original.account);
    }
    /** audit 2026-10-02 F61/F108: say it BEFORE Save, not after. */
    get showLiveMandateWarning() {
        return this.editing && this.hasLiveMandate && this.draftDigitsChanged;
    }
    get maskedAccount() {
        const a = this.original.account || '';
        if (a.length < 4) return a;
        return '••••' + a.slice(-4);
    }

    // ── read/edit toggle ────────────────────────────────────────────
    handleEdit() {
        this.draft = {
            sort: this.original.sort, account: this.original.account, holder: this.original.holder,
            roll: this.original.roll, bankName: this.original.bankName, status: this.original.status,
        };
        this.editing = true;
        this.verifyMsg = '';
    }
    handleCancel() {
        this.editing = false;
        this.draft = {
            sort: this.original.sort, account: this.original.account, holder: this.original.holder,
            roll: this.original.roll, bankName: this.original.bankName, status: this.original.status,
        };
        this.verifyMsg = '';
    }
    handleFieldChange(e) {
        const key = e.currentTarget.dataset.key;
        let val = e.currentTarget.value;
        // Auto-format sort code as XX-XX-XX. Strip non-digits, cap 6, re-insert
        // dashes — agent can type "070116" or "07 01 16" and land on 07-01-16
        // (matches endpoint + DWP fill expected format).
        if (key === 'sort') {
            const digits = String(val || '').replace(/\D/g, '').slice(0, 6);
            const parts = [];
            if (digits.length > 0) parts.push(digits.slice(0, 2));
            if (digits.length > 2) parts.push(digits.slice(2, 4));
            if (digits.length > 4) parts.push(digits.slice(4, 6));
            val = parts.join('-');
            if (val !== e.currentTarget.value) e.currentTarget.value = val;
        }
        this.draft = { ...this.draft, [key]: val };
        // A change to sort/account invalidates the last verification —
        // wipe the inline status so nobody trusts a stale green banner.
        if (['sort','account'].includes(key)) {
            this.verifyMsg = '';
            this.draft.status = 'Unverified';
            this.draft.bankName = '';
        }
    }

    // ── Bank Verify (auto) ──────────────────────────────────────────
    async handleVerify() {
        this.verifying = true;
        this.verifyMsg = 'Checking account with the UK banking database…';
        this.verifyClass = 'aa-be__status';
        try {
            const holder = (this.editing ? this.draft.holder : this.original.holder) || '';
            const sort   = (this.editing ? this.draft.sort   : this.original.sort)   || '';
            const acct   = (this.editing ? this.draft.account: this.original.account)|| '';
            let r;
            if (this.editing) {
                // Edit mode: don't persist — Save will do that. Draft state
                // holds the outcome until the agent chooses to commit.
                r = await verifyAccount({
                    sortCode: sort, accountNumber: acct,
                    name: holder.trim(), accountType: 'PERSONAL',
                });
                this.draft = {
                    ...this.draft,
                    bankName: r.bankName || this.draft.bankName || '',
                    status:   r.status,
                };
            } else {
                // Read mode: persist so the status badge reflects the latest
                // server-side truth without a manual Save round-trip.
                r = await verifyAndPersistAccount({
                    applicationId: this.recordId,
                    sortCode: sort, accountNumber: acct,
                    accountHolder: holder.trim(),
                });
                await refreshApex(this.wiredRecord);
            }
            this.paintVerifyMsg(r);

            // ─── FLAG: verbal read-back re-wire point ──────────────────────
            // This is where the verbal-confirm step belongs. When the auto
            // check comes back "real account, name not electronically
            // verified" — i.e. r.status === 'Name Close Match' (or a Data8
            // response with no name match) — the val agent reads the details
            // back to the client and the client confirms verbally, upgrading
            // the status to 'Name Verified'. To re-enable, uncomment:
            //
            //     if (r.status === 'Name Close Match') {
            //         await this.openVerbalConfirm();
            //     }
            //
            // and un-hide the "Confirm verbally" button in aaBankEditor.html
            // (see the matching FLAG there). Left OFF by default: verbal
            // confirm was retired 2026-08-18 (redundant with the sales-side
            // verbal + GoCardless mandate-rejection safety net), so the live
            // record page stays Tier-1-only with no orphan buttons. The modal
            // (c/aaVerbalConfirmModal) and openVerbalConfirm() below are kept
            // wired for clone-parity so re-enabling is a two-line change.
        } catch (err) {
            this.verifyMsg = '✗ ' + this.errMsg(err);
            this.verifyClass = 'aa-be__status aa-be__status--err';
        } finally {
            this.verifying = false;
        }
    }

    /** Map endpoint status values → friendly inline copy + colour. Wording
     *  kept in strict sync with web/intake.html runBankVerify() so sales
     *  reps see the same message on both surfaces. */
    paintVerifyMsg(r) {
        const bank = r.bankName || 'this bank';
        switch (r.status) {
            case 'Modulus Passed':
            case 'Bank Confirmed':
            case 'Name Verified':
            case 'Verified':
                this.verifyMsg = `✓ ${bank} — account confirmed. You can proceed to the Direct Debit agreement.`;
                this.verifyClass = 'aa-be__status aa-be__status--ok'; break;
            case 'Name Close Match':
                this.verifyMsg = `⚠ ${bank} — account confirmed, but the name we have may differ slightly. Check the spelling with the client.`;
                this.verifyClass = 'aa-be__status aa-be__status--warn'; break;
            case 'Bank Verification Unavailable':
                this.verifyMsg = '⚠ The bank check service is temporarily unavailable. Try again in a few minutes — you don\'t need to change any digits.';
                this.verifyClass = 'aa-be__status aa-be__status--warn'; break;
            case 'Bank Does Not Accept DD':
                this.verifyMsg = `⚠ ${bank} — the account is real but this account cannot receive Direct Debits. Ask the client if they have another account.`;
                this.verifyClass = 'aa-be__status aa-be__status--warn'; break;
            case 'Name Mismatch':
                this.verifyMsg = `✗ ${bank} — the name doesn't match the bank's record. Confirm the name spelling and account with the client.`;
                this.verifyClass = 'aa-be__status aa-be__status--err'; break;
            case 'Invalid Sort Code':
                this.verifyMsg = '✗ Sort code not recognised — please re-check the 6 digits.';
                this.verifyClass = 'aa-be__status aa-be__status--err'; break;
            case 'Invalid Account Number':
                this.verifyMsg = '✗ Account number doesn\'t match this sort code — please double-check.';
                this.verifyClass = 'aa-be__status aa-be__status--err'; break;
            default:
                this.verifyMsg = '✗ This sort code + account combination was not recognised.';
                this.verifyClass = 'aa-be__status aa-be__status--err';
        }
    }

    // ── Verbal read-back confirm (retired flow, kept for clone-parity) ──
    /**
     * Open the verbal-confirmation modal so the val agent can read the bank
     * details back to the client on the call. On a verbal "yes" we upgrade the
     * stored status to 'Name Verified' via the existing saveVerification Apex.
     * Not invoked by default — see the FLAG in handleVerify(). Provided so the
     * verbal-confirm step is a single call away if re-enabled.
     */
    async openVerbalConfirm() {
        const src = this.editing ? this.draft : this.original;
        const result = await AaVerbalConfirmModal.open({
            size:          'small',
            description:   'Verbal bank-detail confirmation',
            bankName:      src.bankName || '',
            sortCode:      src.sort || '',
            accountNumber: src.account || '',
            accountHolder: src.holder || '',
        });
        if (result !== 'confirm') return;
        try {
            await saveVerification({
                applicationId: this.recordId,
                sortCode:      (src.sort || '').trim(),
                accountNumber: (src.account || '').trim(),
                accountHolder: (src.holder || '').trim(),
                rollNumber:    (src.roll || '').trim(),
                bankName:      (src.bankName || '').trim(),
                status:        'Name Verified',
            });
            await refreshApex(this.wiredRecord);
            this.paintVerifyMsg({ status: 'Name Verified', bankName: src.bankName });
            this.toast('Name confirmed verbally', 'success');
        } catch (err) {
            this.toast('Could not save confirmation', 'error', this.errMsg(err));
        }
    }

    // ── Save edited fields ──────────────────────────────────────────
    async handleSave() {
        // audit 2026-10-02 F61/F108: new digits do NOT move a live Direct Debit;
        // GoCardless keeps collecting from the old account. Make the operator
        // acknowledge that (the server refuses the save without it).
        let acknowledge = false;
        const digitsChanged = this.draftDigitsChanged;
        if (this.hasLiveMandate && digitsChanged) {
            acknowledge = await LightningConfirm.open({
                label: 'A Direct Debit is set up on the old account',
                message: 'Saving these new bank details will NOT move the Direct Debit: any fee would still be '
                    + 'collected from the old account. A task will be created with the steps to replace the '
                    + 'Direct Debit. Save anyway?',
                theme: 'warning',
            });
            if (!acknowledge) return;
        }
        this.saving = true;
        try {
            await saveVerification({
                applicationId: this.recordId,
                sortCode:      this.draft.sort.trim(),
                accountNumber: this.draft.account.trim(),
                accountHolder: this.draft.holder.trim(),
                rollNumber:    (this.draft.roll || '').trim(),
                bankName:      (this.draft.bankName || '').trim(),
                status:        this.draft.status || 'Unverified',
                acknowledgeLiveMandate: acknowledge,
            });
            this.editing = false;
            await refreshApex(this.wiredRecord);
            // New digits are re-checked by the server; show what it stored.
            this.toast('Bank account saved', 'success',
                digitsChanged ? 'The new account was checked again on save.' : '');
        } catch (err) {
            this.toast('Save failed', 'error', this.errMsg(err).replace(/^LIVE_DD_MANDATE:\s*/, ''));
        } finally { this.saving = false; }
    }

    // ── util ────────────────────────────────────────────────────────
    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, variant, message: message || '' }));
    }
    errMsg(e) { return e?.body?.message || e?.message || 'Unknown error'; }
}
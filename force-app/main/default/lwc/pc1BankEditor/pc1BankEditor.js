/**
 * pc1BankEditor — single-tier UK bank verify panel for a PC1 Application.
 *
 * Tier 1 only — Bank Verify (auto). Server-side bank check via
 * PC1_BankLookup.verifyAccount() → Heroku endpoint. Talks to Data8's live
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
import verifyAccount             from '@salesforce/apex/PC1_BankLookup.verifyAccount';
import verifyAndPersistAccount   from '@salesforce/apex/PC1_BankLookup.verifyAndPersistAccount';
import saveVerification          from '@salesforce/apex/PC1_BankLookup.saveVerification';

const FIELDS = [
    'PC1_Application__c.Bank_Sort_Code__c',
    'PC1_Application__c.Bank_Account_Number__c',
    'PC1_Application__c.Bank_Account_Holder__c',
    'PC1_Application__c.Bank_Roll_Number__c',
    'PC1_Application__c.Bank_Name__c',
    'PC1_Application__c.Bank_Verification_Status__c',
    'PC1_Application__c.Bank_Verified_At__c',
];

export default class Pc1BankEditor extends LightningElement {
    @api recordId;

    draft = { sort:'', account:'', holder:'', roll:'', bankName:'', status:'Unverified' };
    editing = false;
    verifying = false;
    saving = false;
    verifyMsg = '';
    verifyClass = 'pc1-be__status';

    wiredRecord;
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
        this.verifyClass = 'pc1-be__status';
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
        } catch (err) {
            this.verifyMsg = '✗ ' + this.errMsg(err);
            this.verifyClass = 'pc1-be__status pc1-be__status--err';
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
                this.verifyClass = 'pc1-be__status pc1-be__status--ok'; break;
            case 'Name Close Match':
                this.verifyMsg = `⚠ ${bank} — account confirmed, but the name we have may differ slightly. Check the spelling with the client.`;
                this.verifyClass = 'pc1-be__status pc1-be__status--warn'; break;
            case 'Bank Verification Unavailable':
                this.verifyMsg = '⚠ The bank check service is temporarily unavailable. Try again in a few minutes — you don\'t need to change any digits.';
                this.verifyClass = 'pc1-be__status pc1-be__status--warn'; break;
            case 'Bank Does Not Accept DD':
                this.verifyMsg = `⚠ ${bank} — the account is real but this account cannot receive Direct Debits. Ask the client if they have another account.`;
                this.verifyClass = 'pc1-be__status pc1-be__status--warn'; break;
            case 'Name Mismatch':
                this.verifyMsg = `✗ ${bank} — the name doesn't match the bank's record. Confirm the name spelling and account with the client.`;
                this.verifyClass = 'pc1-be__status pc1-be__status--err'; break;
            case 'Invalid Sort Code':
                this.verifyMsg = '✗ Sort code not recognised — please re-check the 6 digits.';
                this.verifyClass = 'pc1-be__status pc1-be__status--err'; break;
            case 'Invalid Account Number':
                this.verifyMsg = '✗ Account number doesn\'t match this sort code — please double-check.';
                this.verifyClass = 'pc1-be__status pc1-be__status--err'; break;
            default:
                this.verifyMsg = '✗ This sort code + account combination was not recognised.';
                this.verifyClass = 'pc1-be__status pc1-be__status--err';
        }
    }

    // ── Save edited fields ──────────────────────────────────────────
    async handleSave() {
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
            });
            this.editing = false;
            await refreshApex(this.wiredRecord);
            this.toast('Bank account saved', 'success');
        } catch (err) {
            this.toast('Save failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    // ── util ────────────────────────────────────────────────────────
    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, variant, message: message || '' }));
    }
    errMsg(e) { return e?.body?.message || e?.message || 'Unknown error'; }
}
/**
 * aaVerbalConfirmModal — verbal read-back confirmation for the AA bank verify
 * flow (child modal of aaBankEditor).
 *
 * Purpose. When the automated bank check (Data8, via AA_BankLookup) confirms an
 * account is real but cannot electronically verify the account holder's NAME —
 * e.g. status 'Name Close Match', or a Data8 response that returns the bank but
 * no name match — the val agent reads the sort code, account number and holder
 * name back to the client on the call and the client confirms them verbally.
 * This modal is the UI for that read-back step: it presents the exact details to
 * read, gates the confirm button behind an "I read these back and the client
 * confirmed" tick, and returns the outcome to the caller. It performs NO Apex of
 * its own — the parent (aaBankEditor) persists the status upgrade.
 *
 * Calling convention (matches aaFeeChargeConfirmModal / aaFeeChargeCard):
 *
 *     import AaVerbalConfirmModal from 'c/aaVerbalConfirmModal';
 *     const result = await AaVerbalConfirmModal.open({
 *         size:       'small',
 *         description:'Verbal bank-detail confirmation',
 *         bankName:   this.original.bankName,   // may be ''
 *         sortCode:   this.original.sort,
 *         accountNumber: this.original.account,
 *         accountHolder: this.original.holder,
 *     });
 *     // result === 'confirm'  → client confirmed verbally; caller upgrades
 *     //                          Bank_Verification_Status__c → 'Name Verified'
 *     // result === 'cancel'   → dismissed / not confirmed; caller does nothing
 *
 * History. Verbal confirm was introduced 2026-08-17 as a free-tier substitute
 * for a paid Confirmation-of-Payee check, and retired again 2026-08-18 (redundant
 * with the sales-side verbal + the GoCardless mandate-rejection safety net). This
 * bundle is provided for clone-parity with the sandbox's original verbal-confirm
 * modal so the flow can be re-enabled without re-authoring; see the FLAG in
 * aaBankEditor.js for the exact re-wire point.
 */
import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class AaVerbalConfirmModal extends LightningModal {
    @api bankName;        // Bank identified by the automated check (may be blank)
    @api sortCode;        // XX-XX-XX
    @api accountNumber;   // full digits — read back in full, not masked
    @api accountHolder;   // name exactly as on the client's statement

    confirmed = false;    // "I read these back and the client confirmed" tick

    // ── computed ──────────────────────────────────────────────────────
    get hasBankName() {
        return !!(this.bankName && String(this.bankName).trim());
    }
    get holderDisplay() {
        return (this.accountHolder && String(this.accountHolder).trim())
            || '(no holder name on file)';
    }
    get canConfirm() {
        return this.confirmed;
    }
    get confirmDisabled() {
        return !this.confirmed;
    }

    // ── events ────────────────────────────────────────────────────────
    handleConfirmedChange(e) {
        this.confirmed = e.target.checked;
    }
    handleCancel() {
        this.close('cancel');
    }
    handleConfirm() {
        if (!this.canConfirm) return;
        this.close('confirm');
    }
}
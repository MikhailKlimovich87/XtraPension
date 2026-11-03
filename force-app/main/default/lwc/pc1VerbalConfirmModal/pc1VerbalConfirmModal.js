/**
 * pc1VerbalConfirmModal — lightning-modal child launched from pc1BankEditor
 * Tier 2 "Confirm Verbally with Client" button. Purely a UI shell: it shows
 * the current Bank_Account_Holder__c value in a big label, forces the agent
 * to tick a self-attestation checkbox ("I read the name back and the client
 * confirmed") before enabling the Confirm button, and returns a boolean up
 * to the parent LWC via close().
 *
 * The parent LWC does the Apex DML (saveVerbalConfirmation) — this modal
 * only collects the decision. Kept small so it can be reused if we ever
 * need a verbal-confirm step for another field (address, etc.).
 */
import LightningModal from 'lightning/modal';
import { api } from 'lwc';

export default class Pc1VerbalConfirmModal extends LightningModal {
    @api accountHolder = '';
    ticked = false;

    get confirmDisabled() { return !this.ticked; }

    handleTickChange(e) {
        this.ticked = !!e.target.checked;
    }

    handleCancel() { this.close(false); }
    handleConfirm() { if (this.ticked) this.close(true); }
}
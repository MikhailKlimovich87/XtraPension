import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getStages from '@salesforce/apex/PC1_RecordPageService.getStages';
import changeStage from '@salesforce/apex/PC1_RecordPageService.changeStage';
import STAGE_FIELD from '@salesforce/schema/PC1_Application__c.Stage__c';

// Stages after the DWP submission (plus every "Closed - ..." stage).
const POST_SUBMISSION_STAGES = new Set([
    'Submitted', 'Awaiting DWP Decision', 'Awarded', 'Fee Charged', 'DD Chargeback',
]);
const isPostSubmission = (s) => POST_SUBMISSION_STAGES.has(s) || /^Closed\b/.test(s || '');

/**
 * pc1StageCard — Hostinger-parity "Stage" card. Combobox listing every
 * PC1_Stage__mdt (ordered by Order__c) pre-selected to the record's current
 * Stage__c, plus a "Change Stage" button that calls
 * PC1_RecordPageService.changeStage. PC1_StageTransitionHelper (before-update
 * trigger) enforces legal transitions — an illegal one throws and is toasted.
 *
 * Audit 2026-11-11 PC-SFUI-7: PC1_Stage__mdt lists 11 of the 20 stages, so the
 * record's own stage is added to the list when it is not there (the box was
 * blank on an Awarded record), and a move from a post-submission stage back
 * to an earlier one asks for confirmation first.
 */
export default class Pc1StageCard extends LightningElement {
    @api recordId;
    stages = [];
    selected;
    currentStage;
    changing = false;

    @wire(getStages)
    wiredStages({ data }) {
        if (data) this.stages = data;
    }

    @wire(getRecord, { recordId: '$recordId', fields: [STAGE_FIELD] })
    wiredRecord({ data }) {
        if (data) {
            this.currentStage = getFieldValue(data, STAGE_FIELD);
            // Only follow the record while the user hasn't picked something else
            if (!this.selected || this.selected === this.currentStage) {
                this.selected = this.currentStage;
            }
        }
    }

    get options() {
        const opts = this.stages.map(s => ({ label: s.MasterLabel, value: s.MasterLabel }));
        if (this.currentStage && !opts.some(o => o.value === this.currentStage)) {
            opts.push({ label: this.currentStage, value: this.currentStage });
        }
        return opts;
    }
    get changeDisabled() {
        return this.changing || !this.selected || this.selected === this.currentStage;
    }

    handleSelect(e) {
        this.selected = e.detail.value;
    }

    async handleChangeStage() {
        if (this.changeDisabled) return;
        if (isPostSubmission(this.currentStage) && !isPostSubmission(this.selected)) {
            const confirmed = await LightningConfirm.open({
                message: `This application is at "${this.currentStage}". Moving it back to "${this.selected}" returns it to the stages before submission: the Award and Fee cards are hidden there and Mary can call the client again. Continue?`,
                variant: 'header',
                theme: 'warning',
                label: 'Move this application back?'
            });
            if (!confirmed) return;
        }
        this.changing = true;
        try {
            await changeStage({ applicationId: this.recordId, newStage: this.selected, note: 'Changed via Stage card' });
            this.toast('Stage changed', 'success', `${this.currentStage || '—'} → ${this.selected}`);
            this.currentStage = this.selected;
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.dispatchEvent(new CustomEvent('stagechange', { bubbles: true, composed: true }));
        } catch (e) {
            this.toast(this.errMsg(e), 'error');
            this.selected = this.currentStage; // snap back on illegal transition
        } finally {
            this.changing = false;
        }
    }

    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message: message || '', variant }));
    }
    errMsg(e) {
        return e?.body?.message
            || e?.body?.pageErrors?.[0]?.message
            || e?.body?.output?.errors?.[0]?.message
            || e?.message
            || 'Unknown error';
    }
}
import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStages from '@salesforce/apex/PC1_RecordPageService.getStages';
import changeStage from '@salesforce/apex/PC1_RecordPageService.changeStage';
import STAGE_FIELD from '@salesforce/schema/PC1_Application__c.Stage__c';

/**
 * pc1StageCard — Hostinger-parity "Stage" card. Combobox listing every
 * PC1_Stage__mdt (ordered by Order__c) pre-selected to the record's current
 * Stage__c, plus a "Change Stage" button that calls
 * PC1_RecordPageService.changeStage. PC1_StageTransitionHelper (before-update
 * trigger) enforces legal transitions — an illegal one throws and is toasted.
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
        return this.stages.map(s => ({ label: s.MasterLabel, value: s.MasterLabel }));
    }
    get changeDisabled() {
        return this.changing || !this.selected || this.selected === this.currentStage;
    }

    handleSelect(e) {
        this.selected = e.detail.value;
    }

    async handleChangeStage() {
        if (this.changeDisabled) return;
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
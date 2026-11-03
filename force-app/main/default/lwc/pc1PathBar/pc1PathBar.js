import { LightningElement, api, wire } from 'lwc';
import getApplication from '@salesforce/apex/PC1_RecordPageService.getApplication';
import getStages      from '@salesforce/apex/PC1_RecordPageService.getStages';
import changeStage    from '@salesforce/apex/PC1_RecordPageService.changeStage';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

/**
 * pc1PathBar — arrow-shaped stage path, driven by PC1_Stage__mdt so Setup
 * can reorder / rename stages without a code deploy. Clicking a step opens
 * a small confirmation to jump the Application to that stage (audit-trailed
 * via PC1_Stage_Log__c).
 *
 * Ignores "Needs Human" from the sequence — that stage sits off-pipeline;
 * when the record is on it we highlight a banner instead of a step.
 */
export default class Pc1PathBar extends LightningElement {
    @api recordId;
    stages = [];
    app;
    wiredApp;

    @wire(getStages) wireStages({ data }) { if (data) this.stages = data; }
    @wire(getApplication, { recordId: '$recordId' })
    wireApp(result) {
        this.wiredApp = result;
        if (result.data) this.app = result.data;
    }

    // Map "Awaiting First Call" (picklist label) ⇄ "Awaiting_First_Call" (MDT DeveloperName)
    stageMatches(mdt, stagePicklist) {
        if (!stagePicklist) return false;
        return mdt.DeveloperName === stagePicklist.replace(/\s+/g, '_')
            || mdt.MasterLabel === stagePicklist;
    }

    get pipeline() {
        // exclude Needs_Human — off-pipeline
        return (this.stages || []).filter(s => s.DeveloperName !== 'Needs_Human');
    }

    get isOffPipeline() {
        return this.app?.Stage__c === 'Needs Human';
    }

    get steps() {
        const cur = this.app?.Stage__c;
        const pipe = this.pipeline;
        const curIdx = pipe.findIndex(s => this.stageMatches(s, cur));
        return pipe.map((s, i) => {
            let cls = 'step';
            let mark = '';
            let currentAttr = 'false';
            if (!this.isOffPipeline && curIdx !== -1) {
                if (i < curIdx)  { cls += ' done';    mark = '✓ '; }
                if (i === curIdx) { cls += ' current'; currentAttr = 'step'; }
            }
            return {
                key: s.DeveloperName,
                label: s.MasterLabel.replace(/_/g, ' '),
                cls,
                mark,
                currentAttr,
                title: s.Description__c || s.MasterLabel
            };
        });
    }

    async handleStepClick(evt) {
        const dev = evt.currentTarget.dataset.dev;
        const label = evt.currentTarget.dataset.label;
        if (!dev || !label) return;
        if (!window.confirm(`Move Application to "${label}"?`)) return;
        try {
            // Send the picklist label (Stage__c is a Picklist, values use spaces)
            const picklistValue = label;
            await changeStage({ applicationId: this.recordId, newStage: picklistValue, note: `Path bar click → ${label}` });
            this.dispatchEvent(new ShowToastEvent({ title: 'Stage updated', variant: 'success' }));
            await refreshApex(this.wiredApp);
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Failed', message: e?.body?.message || e.message, variant: 'error' }));
        }
    }
}
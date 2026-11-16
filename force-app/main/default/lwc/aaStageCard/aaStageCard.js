import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getStages from '@salesforce/apex/AA_RecordPageService.getStages';
import changeStage from '@salesforce/apex/AA_RecordPageService.changeStage';
import STAGE_FIELD from '@salesforce/schema/AA_Application__c.Stage__c';
import AWARD_FIELD from '@salesforce/schema/AA_Application__c.Award_Amount__c';

/**
 * aaStageCard — Hostinger-parity "Stage" card. Combobox listing every
 * AA_Stage__mdt (ordered by Order__c) pre-selected to the record's current
 * Stage__c, plus a "Change Stage" button that calls
 * AA_RecordPageService.changeStage. No transition is refused by stage order
 * (the state machine of AA_StageTransitionHelper was removed 2026-07-30).
 * What can refuse a move is a validation rule (Submitted needs the DWP
 * reference) or the DWP decision guard below, and that error is toasted.
 *
 * Entering three stages sends the client an email (audit 2026-11-11
 * AA-SFUI-4): Submitted (AA_StageTransitionHelper), Awarded and
 * Closed - Refused (AA_MessageDispatcher.OUTCOME_EVENT_BY_STAGE). The two
 * decision emails go once per application, ever, so a wrong pick tells the
 * client the wrong decision and uses the email up. Those picks ask for a
 * confirmation that names the email before anything is saved.
 *
 * The server holds the two decision stages to more than a pick
 * (AA_StageTransitionHelper.decisionGuard), and this card follows it:
 *   - Awarded needs the award amount on the record. The Award card saves the
 *     amount and moves the case to Awarded, so with no amount this card says
 *     so instead of asking to send the email.
 *   - Closed - Refused needs the refusal written down. The note box appears
 *     for that stage, is required, and is sent as the stage note (kept on the
 *     stage log). The fixed note sent for other stages would be refused.
 */
const AWARDED = 'Awarded';
const REFUSED = 'Closed - Refused';
// AA_Stage_Log__c.Note__c is Text(255).
const NOTE_MAX = 255;
const CLIENT_EMAIL_BY_STAGE = {
    'Submitted': {
        what: 'the "application submitted to DWP" email',
        once: false
    },
    'Awarded': {
        what: 'the "DWP has approved your claim" email',
        once: true
    },
    'Closed - Refused': {
        what: 'the "DWP has refused your claim" email',
        once: true
    }
};

/** The confirmation shown before a stage pick that emails the client, or
 *  null when the stage sends nothing. */
function stageEmailConfirm(stage) {
    const mail = CLIENT_EMAIL_BY_STAGE[stage];
    if (!mail) return null;
    return {
        label: `Moving to "${stage}" emails the client`,
        message: `Changing the stage to "${stage}" sends the client ${mail.what} `
            + '(with the helper in copy, when the record has one). '
            + (mail.once
                ? 'It is sent once per application and cannot be recalled or sent again: if this stage is picked by mistake, the client is told the wrong decision and the real one is never emailed. '
                : 'It cannot be recalled. ')
            + `Change the stage to "${stage}" and send the email?`,
        theme: 'warning'
    };
}

export default class AaStageCard extends LightningElement {
    @api recordId;
    stages = [];
    selected;
    currentStage;
    changing = false;
    note = '';
    awardAmount;       // undefined until the record loads, or when the field cannot be read

    @wire(getStages)
    wiredStages({ data }) {
        if (data) this.stages = data;
    }

    @wire(getRecord, { recordId: '$recordId', fields: [STAGE_FIELD], optionalFields: [AWARD_FIELD] })
    wiredRecord({ data }) {
        if (data) {
            this.currentStage = getFieldValue(data, STAGE_FIELD);
            this.awardAmount = getFieldValue(data, AWARD_FIELD);
            // Only follow the record while the user hasn't picked something else
            if (!this.selected || this.selected === this.currentStage) {
                this.selected = this.currentStage;
            }
        }
    }

    get options() {
        return this.stages.map(s => ({ label: s.MasterLabel, value: s.MasterLabel }));
    }
    /** Closed - Refused is picked: the refusal must be written in the note. */
    get noteRequired() {
        return this.selected === REFUSED && this.selected !== this.currentStage;
    }
    get noteMax() { return NOTE_MAX; }
    get changeDisabled() {
        return this.changing || !this.selected || this.selected === this.currentStage
            || (this.noteRequired && !this.note.trim());
    }

    handleSelect(e) {
        this.selected = e.detail.value;
    }
    handleNote(e) {
        this.note = e.detail.value || '';
    }

    async handleChangeStage() {
        if (this.changeDisabled) return;
        // No award amount on the record (null or 0, not "could not be read"):
        // the server refuses Awarded. Say what to do, before any question
        // about sending the approval email.
        if (this.selected === AWARDED && this.awardAmount !== undefined && !(Number(this.awardAmount) > 0)) {
            this.toast('Record the DWP award first', 'error',
                'Use the Award card: it saves the amount and moves the case to Awarded. '
                + 'Moving a case to Awarded emails the client that the claim was approved, and that email is sent only once.');
            return;
        }
        const note = this.noteRequired ? this.note.trim() : 'Changed via Stage card';
        const ask = stageEmailConfirm(this.selected);
        if (ask) {
            // LightningConfirm resolves true only on OK (false on Cancel, Esc
            // or the close button).
            const ok = await LightningConfirm.open(ask);
            if (ok !== true) return;
            if (this.changeDisabled) return;
        }
        this.changing = true;
        try {
            await changeStage({ applicationId: this.recordId, newStage: this.selected, note });
            this.toast('Stage changed', 'success', `${this.currentStage || '—'} → ${this.selected}`);
            this.currentStage = this.selected;
            this.note = '';
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
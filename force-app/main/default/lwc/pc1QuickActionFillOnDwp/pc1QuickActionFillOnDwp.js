import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import startFillFromUi from '@salesforce/apex/PC1_HerokuBridge.startFillFromUi';

import STAGE_FIELD    from '@salesforce/schema/PC1_Application__c.Stage__c';
import DECL_FIELD     from '@salesforce/schema/PC1_Application__c.Declaration_Complete__c';
import MANDATE_FIELD  from '@salesforce/schema/PC1_Application__c.DD_Mandate_Status__c';
import DWPREF_FIELD   from '@salesforce/schema/PC1_Application__c.DWP_Reference__c';

/**
 * PC Quick Action — Fill on DWP.
 *
 * Gate matrix (client-side pre-flight; server enforces the same):
 *   Stage in FILL_READY_STAGES
 *   Declaration_Complete__c = true
 *   DD_Mandate_Status__c = 'active'
 *   DWP_Reference__c is null
 *
 * When ALL green → normal confirm → Start filling.
 * When ONE OF {DECL, MANDATE} blocks and the rest are green → offer a
 * Force option in the gate panel. The Force flag bypasses that specific
 * gate on the server; the hard idempotency gates (DWP_Reference,
 * fill_in_progress) are NEVER bypassed.
 * When STAGE is not ready OR DWP_Reference already exists → gate only,
 * no force button. Those are never worth overriding.
 *
 * testMode=true so the Heroku worker uses the sandbox DWP tenant. Flip
 * to false only after the org is signed off for production runs.
 */

const FILL_READY_STAGES = new Set([
    'Data Complete',
    'Reviewed',
    'Filling',
    'Ready for Submit',
    'Submitted'
]);

const FIELDS = [STAGE_FIELD, DECL_FIELD, MANDATE_FIELD, DWPREF_FIELD];

export default class Pc1QuickActionFillOnDwp extends LightningElement {
    @api recordId;
    working = false;
    _stage = null;
    _declarationComplete = false;
    _mandateStatus = null;
    _dwpRef = null;
    _loaded = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this._stage = getFieldValue(data, STAGE_FIELD);
            this._declarationComplete = getFieldValue(data, DECL_FIELD) === true;
            this._mandateStatus = getFieldValue(data, MANDATE_FIELD);
            this._dwpRef = getFieldValue(data, DWPREF_FIELD);
            this._loaded = true;
        } else if (error) {
            this._loaded = true;
        }
    }

    // ── Gate diagnosis ─────────────────────────────────────────────────
    get stageReady()     { return FILL_READY_STAGES.has(this._stage); }
    get declReady()      { return this._declarationComplete === true; }
    get mandateReady()   { return (this._mandateStatus || '').toLowerCase() === 'active'; }
    get notAlreadySubmitted() { return !this._dwpRef; }

    // A gate the user CANNOT override (stage too early, or already
    // submitted at DWP). Force button never shown for these.
    get hardBlock() {
        return !this.stageReady || !this.notAlreadySubmitted;
    }
    // A gate the user CAN choose to bypass (mandate not active,
    // declaration not yet signed). Force button offered.
    get softBlock() {
        return !this.hardBlock && (!this.declReady || !this.mandateReady);
    }

    get appReadyToFill()  { return this.stageReady && this.declReady && this.mandateReady && this.notAlreadySubmitted; }
    get isGated()         { return this._loaded && !this.appReadyToFill; }
    get isReadyToStart()  { return this._loaded && this.appReadyToFill; }
    get isLoading()       { return !this._loaded && !this.working; }
    get canForce()        { return this.softBlock; }

    // ── Gate messaging ─────────────────────────────────────────────────
    get gateHeadline() {
        if (!this.stageReady) return 'Fill on DWP not available yet';
        if (!this.notAlreadySubmitted) return 'Application already submitted';
        if (!this.mandateReady) return 'Direct Debit mandate not active yet';
        if (!this.declReady) return 'Waiting for signed declaration';
        return 'Not ready';
    }
    get gateMessage() {
        if (!this.stageReady) {
            return "The DWP fill can only run once Mary has finished collecting all the data (Stage: Data Complete or later).";
        }
        if (!this.notAlreadySubmitted) {
            return `This application already has a DWP reference (${this._dwpRef}). Refile only after deliberately clearing DWP_Reference__c.`;
        }
        if (!this.mandateReady) {
            return `Direct Debit mandate is not active yet — usual wait after signing is 2–3 business days for Bacs to confirm. Current mandate status: ${this._mandateStatus || 'null'}.`;
        }
        if (!this.declReady) {
            return 'All the data is collected — the declaration just needs to be signed before the fill can run.';
        }
        return '';
    }
    get forceButtonLabel() {
        if (!this.mandateReady && !this.declReady) return 'Run anyway (skip mandate + declaration)';
        if (!this.mandateReady) return 'Run anyway (skip mandate check)';
        if (!this.declReady)    return 'Run anyway (skip declaration check)';
        return 'Run anyway';
    }
    get forceWarning() {
        const bits = [];
        if (!this.mandateReady) bits.push('Direct Debit is not confirmed at Bacs — a DWP award could be paid to an account that later fails collection.');
        if (!this.declReady)    bits.push('The client has not signed the declaration — do NOT click Submit on DWP without their signature.');
        return bits.join(' ');
    }
    get currentStageLabel() { return this._stage || '—'; }

    // ── Fill run entry points ──────────────────────────────────────────
    async handleStart() {
        return this._runFill(false);
    }
    async handleForceStart() {
        if (!this.canForce) return;
        // eslint-disable-next-line no-alert
        if (!confirm('Force-run this fill? ' + this.forceWarning + '\n\nThe worker still stops at the declaration page and never auto-submits.')) return;
        return this._runFill(true);
    }
    async _runFill(force) {
        this.working = true;
        try {
            const result = await startFillFromUi({
                applicationId: this.recordId,
                testMode: true,
                force: force === true,
            });
            this.dispatchEvent(new ShowToastEvent({
                title: force ? 'Fill on DWP (forced)' : 'Fill on DWP',
                message: result || 'Fill run started.',
                variant: 'success',
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Fill on DWP failed',
                message: e?.body?.message ?? e?.message ?? 'Unknown error',
                variant: 'error',
            }));
        } finally {
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}
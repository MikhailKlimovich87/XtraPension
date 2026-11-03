import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import startFillFromUi from '@salesforce/apex/AA_HerokuBridge.startFillFromUi';

import STAGE_FIELD from '@salesforce/schema/AA_Application__c.Stage__c';
import DECL_FIELD  from '@salesforce/schema/AA_Application__c.Declaration_Complete__c';

/**
 * AA Quick Action: Fill on DWP.
 *
 * Two-gate flow:
 *   1. Load Stage + Declaration_Complete__c via getRecord.
 *   2. If stage < Data Complete OR declaration not signed → render a
 *      friendly "not available yet" panel (no Start button). This mirrors
 *      the gate the aaFillRunPanel already shows on the right sidebar,
 *      so ops sees the same message whether they open the sidebar card
 *      or the quick action modal.
 *   3. Otherwise → the normal confirm → start-fill flow.
 *
 * testMode is advisory and ignored server-side: the worker NEVER submits.
 * It fills the live DWP form in a hosted browser and stops at the
 * Declaration; a human reviews and submits in the live view.
 */

// Stages where Fill on DWP is a legitimate next step. Same list as
// AA_HerokuBridge.FILL_STAGES and src/webhooks/internal.js (audit 2026-10-02
// F56/F142): the server refuses every other stage anyway.
const FILL_READY_STAGES = new Set([
    'Data Complete',
    'Ready for Review',
    'Reviewed',
    'Awaiting Bank Details',
    'Filling',
    'Ready for Submit',
    'Special Rules Fast-Track'
]);

const FIELDS = [STAGE_FIELD, DECL_FIELD];

export default class AaQuickActionFillOnDwp extends LightningElement {
    @api recordId;
    working = false;
    _stage = null;
    _declarationComplete = false;
    _loaded = false;

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredRecord({ data, error }) {
        if (data) {
            this._stage = getFieldValue(data, STAGE_FIELD);
            this._declarationComplete = getFieldValue(data, DECL_FIELD) === true;
            this._loaded = true;
        } else if (error) {
            this._loaded = true; // fall through to gate so the modal still renders something
        }
    }

    // ── Gate logic (mirrors aaFillRunPanel) ────────────────────────────
    get stageReady()      { return FILL_READY_STAGES.has(this._stage); }
    get appReadyToFill()  { return this.stageReady && this._declarationComplete; }
    get isGated()         { return this._loaded && !this.appReadyToFill; }
    get isReadyToStart()  { return this._loaded && this.appReadyToFill; }
    get isLoading()       { return !this._loaded && !this.working; }

    // Gate messaging — two sub-cases mirror the sidebar panel.
    get gateHeadline() {
        if (!this.stageReady) return 'Fill on DWP not available yet';
        return 'Waiting for signed declaration';
    }
    get gateMessage() {
        if (!this.stageReady) {
            return "The DWP fill can only run once Mary has finished collecting all the data (Stage: Data Complete) and the declaration is signed.";
        }
        return 'All the data is collected. The declaration just needs to be signed before the fill can run.';
    }
    get currentStageLabel() { return this._stage || '—'; }

    async handleStart() {
        // Belt-and-braces: even if the button somehow becomes clickable while
        // the app isn't ready, refuse to fire the fill.
        if (!this.appReadyToFill) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Fill on DWP',
                message: 'The application is not ready to fill yet. Reach Data Complete and a signed declaration first.',
                variant: 'warning',
            }));
            this.dispatchEvent(new CloseActionScreenEvent());
            return;
        }
        this.working = true;
        try {
            await startFillFromUi({
                applicationId: this.recordId,
                testMode: true,
            });
            // The return value is the Fill Run Id: meaningless to an operator.
            this.dispatchEvent(new ShowToastEvent({
                title: 'Fill on DWP started',
                message: 'Watch the Latest Fill Run card. When it shows Ready for Review, open its live view to check and submit.',
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
import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import getApplication from '@salesforce/apex/PC1_RecordPageService.getApplication';
import changeStage    from '@salesforce/apex/PC1_RecordPageService.changeStage';
import callNow        from '@salesforce/apex/PC1_MaryBridge.callNow';
import startFillFromUi from '@salesforce/apex/PC1_HerokuBridge.startFillFromUi';

const CDC_APP_CHANNEL    = '/data/PC1_Application__ChangeEvent';
const CDC_ANSWER_CHANNEL = '/data/PC1_Answer__ChangeEvent';

const FILL_CONFIRM_MSG =
    'This will open the DWP form in a Playwright browser and fill it in test mode (will NOT submit). Continue?';

/**
 * pc1ApplicationHeader — big record header mimicking the Hostinger dashboard.
 *
 * Structure:
 *   [avatar]  Name (h1)                    [Call Now] [Edit] [Mark Reviewed] [Fill on DWP]
 *             Client · <stage badge> · created <date>
 *   ┌─────────────────────────────────────────────────────────────────────┐
 *   │ Phone │ Email │ Address │ DOB │ Next call │ Data collected (bar) │
 *   └─────────────────────────────────────────────────────────────────────┘
 */
export default class Pc1ApplicationHeader extends NavigationMixin(LightningElement) {
    @api recordId;
    app;
    wiredApp;
    calling = false; // re-entrancy guard for Call Now

    // CDC subscriptions — live-refresh header when Mary (or any external
    // process) writes to PC1_Application__c or PC1_Answer__c. Without this
    // the header stays stale during an in-progress call: an operator hits
    // Call Now, Mary saves the client's new phone number, but the header
    // keeps showing the old one until the operator manually reloads.
    _appSub;
    _ansSub;

    @wire(getApplication, { recordId: '$recordId' })
    wired(result) {
        this.wiredApp = result;
        if (result.data) this.app = result.data;
    }

    async connectedCallback() {
        // Best-effort CDC subscription. If CDC is not enabled on the object,
        // subscribe rejects — the LWC continues to work (just no live
        // refresh, same behaviour as before this was added).
        try {
            onError((err) => console.warn('[pc1ApplicationHeader] empApi error', err));
            this._appSub = await subscribe(CDC_APP_CHANNEL, -1, (msg) => {
                try {
                    const hdr = msg?.data?.payload?.ChangeEventHeader;
                    if (hdr?.recordIds?.includes(this.recordId)) {
                        refreshApex(this.wiredApp);
                    }
                } catch (e) { /* swallow — never break the page */ }
            });
            this._ansSub = await subscribe(CDC_ANSWER_CHANNEL, -1, () => {
                // Cheap: child-answer changes almost always affect Progress /
                // parent scalars via PC1_ApplicationFieldSync. Re-query the
                // parent — SOQL is fast enough not to bother filtering.
                try { refreshApex(this.wiredApp); } catch (_) {}
            });
        } catch (e) {
            // CDC not enabled at object level yet — expected on first deploy.
            // eslint-disable-next-line no-console
            console.warn('[pc1ApplicationHeader] CDC subscribe failed (will not live-refresh):', e?.message || e);
        }
    }

    async disconnectedCallback() {
        try { if (this._appSub) await unsubscribe(this._appSub); } catch (_) {}
        try { if (this._ansSub) await unsubscribe(this._ansSub); } catch (_) {}
        this._appSub = null;
        this._ansSub = null;
    }


    get initials() {
        const n = this.app?.Full_Name__c || '';
        return n.split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0].toUpperCase()).join('') || '?';
    }

    get stageBadgeClass() {
        const s = this.app?.Stage__c;
        if (s === 'Submitted' || s === 'Ready for Submit') return 'slds-badge slds-theme_success stage-badge';
        if (s === 'Data Complete' || s === 'Reviewed')     return 'slds-badge slds-theme_success stage-badge';
        if (s === 'Needs Human')                            return 'slds-badge slds-theme_error stage-badge';
        if (s === 'Filling' || s === 'Call In Progress')   return 'slds-badge slds-theme_info stage-badge';
        if (s === 'Partial Data' || s === 'Ready for Review') return 'slds-badge slds-theme_warning stage-badge';
        return 'slds-badge stage-badge';
    }

    get stageLabel() { return this.app?.Stage__c || '—'; }

    get createdLabel() {
        const d = this.app?.CreatedDate;
        if (!d) return '';
        return `Created ${new Date(d).toLocaleDateString('en-GB')}`;
    }

    get phone()   { return this.app?.Phone__c || '—'; }
    get email()   { return this.app?.Email__c || '—'; }
    get address() {
        const a = this.app;
        if (!a) return '—';
        return [a.Address_Line1__c, a.City__c, a.Postcode__c].filter(Boolean).join(', ') || '—';
    }
    get dob() {
        const d = this.app?.DOB__c;
        return d ? new Date(d).toLocaleDateString('en-GB') : '—';
    }
    get nextCall() {
        const d = this.app?.Next_Call_At__c;
        return d ? new Date(d).toLocaleString('en-GB') : '—';
    }

    get progressText() {
        const f = this.app?.Progress_Filled__c ?? 0;
        const t = this.app?.Progress_Total__c ?? 0;
        return `${f}/${t}`;
    }
    get progressPct() {
        const p = this.app?.Progress_Percent__c;
        return typeof p === 'number' ? Math.min(100, Math.round(p)) : 0;
    }
    get progressBarStyle() { return `width:${this.progressPct}%`; }

    // Fernando 2026-07-30: only show Mark Reviewed once the record is
    // actually at Ready for Review — otherwise ops has to manually move it
    // through the earlier stages first. Anything before that hides the
    // button entirely; clicking it advances Stage → Reviewed.
    get canMarkReviewed() {
        return this.app?.Stage__c === 'Ready for Review';
    }
    get canFill() {
        const s = this.app?.Stage__c;
        return s === 'Reviewed' || s === 'Ready for Submit';
    }

    handleEdit() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.recordId, objectApiName: 'PC1_Application__c', actionName: 'edit' }
        });
    }

    async handleMarkReviewed() {
        try {
            await changeStage({ applicationId: this.recordId, newStage: 'Reviewed', note: 'Marked reviewed from record page' });
            this.toast('Marked Reviewed', 'success');
            await refreshApex(this.wiredApp);
            this.dispatchEvent(new CustomEvent('stagechange', { bubbles: true, composed: true }));
        } catch (e) { this.toast(this.errMsg(e), 'error'); }
    }

    async handleCallNow() {
        if (this.calling) return;
        // A real phone call to the client starts immediately — confirm first.
        let ok;
        try {
            ok = await LightningConfirm.open({
                message: 'Mary will phone this client right now. Continue?',
                label: 'Call Now',
                theme: 'warning',
            });
        } catch (e) {
            ok = window.confirm('Mary will phone this client right now. Continue?');
        }
        if (!ok) return;
        this.calling = true;
        try {
            await callNow({ applicationId: this.recordId });
            this.toast('Call Now', 'success', 'Mary is dialling — the call will appear in Call History shortly.');
        } catch (e) {
            this.toast(this.errMsg(e), 'error');
        } finally {
            this.calling = false;
        }
    }

    async handleFill() {
        let ok;
        try {
            ok = await LightningConfirm.open({
                message: FILL_CONFIRM_MSG,
                label: 'Fill on DWP (Test — will not submit)',
                theme: 'warning'
            });
        } catch (_) {
            // lightning/confirm unavailable (older API context) — browser native
            // eslint-disable-next-line no-alert
            ok = window.confirm(FILL_CONFIRM_MSG);
        }
        if (!ok) return;
        try {
            const runId = await startFillFromUi({ applicationId: this.recordId, testMode: true });
            this.toast('Fill started', 'success',
                runId ? `Run ${runId} launched — watch progress in the Fill Run panel.`
                      : 'Launched — watch progress in the Fill Run panel.');
        } catch (e) {
            this.toast(this.errMsg(e), 'error');
        }
    }

    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message: message || '', variant }));
    }
    errMsg(e) { return e?.body?.message || e?.message || 'Unknown error'; }
}
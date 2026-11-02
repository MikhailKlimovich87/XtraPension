import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getLatestOpenHandoff from '@salesforce/apex/AA_HandoffService.getLatestOpenHandoff';
import markResolved from '@salesforce/apex/AA_HandoffService.markResolved';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import AA_LAYOUT_CSS from '@salesforce/resourceUrl/aaLayoutOverride';

const CDC_HANDOFF_CHANNEL = '/data/AA_Handoff__ChangeEvent';
const HANDOFF_POLL_MS = 30000;

// Module-level flag — inject the layout CSS once per page load, no matter
// how many aaHandoffCard instances Salesforce mounts.
let _layoutCssInjected = false;
async function injectLayoutCss() {
    if (_layoutCssInjected) return;
    _layoutCssInjected = true;
    try {
        // Since LWC API 54+ `loadStyle` from platformResourceLoader stamps
        // the <link> INTO THE LWC'S SHADOW ROOT, not document.head — so
        // rules never reach the outer FlexiPage region wrappers. Fetch the
        // CSS ourselves and append a <style> to <head> so it applies
        // globally, escaping shadow DOM as intended.
        const res = await fetch(AA_LAYOUT_CSS);
        const css = await res.text();
        const style = document.createElement('style');
        style.setAttribute('data-aa-layout-override', '1');
        style.textContent = css;
        document.head.appendChild(style);
    } catch (e) {
        _layoutCssInjected = false;
        // eslint-disable-next-line no-console
        console.error('[aaHandoffCard] injectLayoutCss failed', e);
    }
}

/**
 * AA Handoff Card — red banner shown only when the current Application has an
 * unresolved handoff. Displays escalation context and offers a "Mark Resolved"
 * button that flips AA_Handoff__c.Resolved__c.
 *
 * Hidden entirely when nothing is escalated — no visual noise on happy-path
 * records.
 */
export default class AaHandoffCard extends LightningElement {
    @api recordId;
    handoff;
    wired;
    _cdcSub;

    @wire(getLatestOpenHandoff, { applicationId: '$recordId' })
    wiredHandoff(result) {
        this.wired = result;
        if (result.data) this.handoff = result.data;
        else             this.handoff = null;
    }

    get hasHandoff() { return this.handoff != null; }

    async connectedCallback() {
        // aaHandoffCard renders on every PC Application page (invisible when
        // no active handoff) — inject the layout CSS globally so the middle
        // column of the 3-col template gets its widened proportions.
        injectLayoutCss();

        // Subscribe to AA_Handoff__c CDC so when Mary flags for human (or ops
        // resolves elsewhere) the banner appears/disappears without a manual
        // refresh. AA_Handoff__c has no channel member today (CDC slot
        // limit, see startPolling), so this subscribe fails and handoffs
        // arrive through the 30 s poll instead. Kept so that deploying a
        // member makes the card live again with no code change.
        try {
            onError((err) => {
                // eslint-disable-next-line no-console
                console.warn('[aaHandoffCard] empApi error', err);
                this.startPolling();
            });
            this._cdcSub = await subscribe(CDC_HANDOFF_CHANNEL, -1, (_msg) => {
                // Any change to a Handoff row — refresh the wire. Filtering
                // by Application__c would require decoding the CDC payload;
                // the query is cheap enough to just refresh unconditionally.
                try {
                    if (this.wired) refreshApex(this.wired);
                } catch (_) { /* noop */ }
            });
            if (!this._cdcSub) this.startPolling();
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[aaHandoffCard] CDC subscribe failed (polling instead):', e?.message || e);
            this.startPolling();
        }
    }

    async disconnectedCallback() {
        if (this._pollTimer) { clearInterval(this._pollTimer); this._pollTimer = null; }
        try { if (this._cdcSub) await unsubscribe(this._cdcSub); } catch (_) { /* noop */ }
        this._cdcSub = null;
    }

    // CDC fallback (audit 2026-10-02 F52). The org's CDC entity slots are
    // limited, so only the AA_Application__c change event is selected
    // (sf-src/platformEventChannelMembers, wave 3); AA_Handoff__c has no
    // member, the subscribe above fails and this 30 s poll is what runs.
    // A handoff Mary raises mid-call can take up to 30 s to show.
    _pollTimer = null;
    startPolling() {
        if (this._pollTimer) return;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollTimer = setInterval(() => {
            if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return;
            try { if (this.wired) refreshApex(this.wired); } catch (_) { /* noop */ }
        }, HANDOFF_POLL_MS);
    }

    async handleResolve() {
        try {
            await markResolved({ handoffId: this.handoff.Id });
            this.dispatchEvent(new ShowToastEvent({ title: 'Handoff resolved', variant: 'success' }));
            await refreshApex(this.wired);
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Failed', message: e.body?.message ?? e.message, variant: 'error' }));
        }
    }
}
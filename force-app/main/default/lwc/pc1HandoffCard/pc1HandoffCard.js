import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getLatestOpenHandoff from '@salesforce/apex/PC1_HandoffService.getLatestOpenHandoff';
import markResolved from '@salesforce/apex/PC1_HandoffService.markResolved';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import PC1_LAYOUT_CSS from '@salesforce/resourceUrl/pc1LayoutOverride';

const CDC_HANDOFF_CHANNEL = '/data/PC1_Handoff__ChangeEvent';

// Module-level flag — inject the layout CSS once per page load, no matter
// how many pc1HandoffCard instances Salesforce mounts.
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
        const res = await fetch(PC1_LAYOUT_CSS);
        const css = await res.text();
        const style = document.createElement('style');
        style.setAttribute('data-pc1-layout-override', '1');
        style.textContent = css;
        document.head.appendChild(style);
    } catch (e) {
        _layoutCssInjected = false;
        // eslint-disable-next-line no-console
        console.error('[pc1HandoffCard] injectLayoutCss failed', e);
    }
}

/**
 * PC Handoff Card — red banner shown only when the current Application has an
 * unresolved handoff. Displays escalation context and offers a "Mark Resolved"
 * button that flips PC1_Handoff__c.Resolved__c.
 *
 * Hidden entirely when nothing is escalated — no visual noise on happy-path
 * records.
 */
export default class Pc1HandoffCard extends LightningElement {
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
        // pc1HandoffCard renders on every PC Application page (invisible when
        // no active handoff) — inject the layout CSS globally so the middle
        // column of the 3-col template gets its widened proportions.
        injectLayoutCss();

        // Live push — subscribe to PC1_Handoff__c CDC so when Mary flags for
        // human (or ops resolves elsewhere) the banner appears/disappears
        // without a manual refresh. If CDC isn't enabled on the org, degrade
        // gracefully — the card still works via user-action refresh.
        try {
            onError((err) => {
                // eslint-disable-next-line no-console
                console.warn('[pc1HandoffCard] empApi error', err);
            });
            this._cdcSub = await subscribe(CDC_HANDOFF_CHANNEL, -1, (_msg) => {
                // Any change to a Handoff row — refresh the wire. Filtering
                // by Application__c would require decoding the CDC payload;
                // the query is cheap enough to just refresh unconditionally.
                try {
                    if (this.wired) refreshApex(this.wired);
                } catch (_) { /* noop */ }
            });
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[pc1HandoffCard] CDC subscribe failed (no live refresh):', e?.message || e);
        }
    }

    async disconnectedCallback() {
        try { if (this._cdcSub) await unsubscribe(this._cdcSub); } catch (_) { /* noop */ }
        this._cdcSub = null;
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
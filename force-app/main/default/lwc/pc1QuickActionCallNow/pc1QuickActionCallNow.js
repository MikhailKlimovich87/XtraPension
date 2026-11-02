import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import callNow from '@salesforce/apex/PC1_MaryBridge.callNow';
import LightningConfirm from 'lightning/confirm';

/**
 * PC Quick Action — Call Now.
 *
 * Thin ScreenAction wrapper around PC1_MaryBridge.callNow. Fires as soon as
 * the framework hands us `recordId`. connectedCallback runs BEFORE `@api
 * recordId` is populated in Screen Actions, so we hook the setter — the
 * action fires the moment the id lands.
 */
export default class Pc1QuickActionCallNow extends LightningElement {
    _recordId;
    _fired = false;

    @api
    get recordId() { return this._recordId; }
    set recordId(val) {
        this._recordId = val;
        if (val && !this._fired) {
            this._fired = true;
            this.fire();
        }
    }

    async fire() {
        try {
            // A real phone call starts immediately — confirm first.
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
            const result = await callNow({ applicationId: this._recordId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Call Now',
                message: result || 'Requested outbound call.',
                variant: 'success',
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Call Now failed',
                message: e?.body?.message ?? e?.message ?? 'Unknown error',
                variant: 'error',
            }));
        } finally {
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }
}
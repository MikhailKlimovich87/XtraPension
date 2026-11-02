import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import callNow from '@salesforce/apex/AA_MaryBridge.callNow';

/**
 * AA Quick Action — Call Now.
 *
 * Thin ScreenAction wrapper around AA_MaryBridge.callNow. It used to dial the
 * moment the framework handed us `recordId` (audit F50/F86): the action sits
 * first in the highlights panel, so one mis-click rang a client with no way
 * to back out. It now shows a confirmation screen first, with a warning when
 * it is outside Mary's usual calling hours, and dials only on "Call now".
 */
export default class AaQuickActionCallNow extends LightningElement {
    @api recordId;
    calling = false;

    /** Mon-Fri 07:00-17:30 UK, the window the scheduler dials in (lib/retry.js). Bank holidays are not checked here. */
    get offHoursWarning() {
        try {
            const parts = new Intl.DateTimeFormat('en-GB', {
                timeZone: 'Europe/London', weekday: 'short', hour: '2-digit', minute: '2-digit', hour12: false,
            }).formatToParts(new Date());
            const g = (t) => parts.find((p) => p.type === t)?.value || '';
            const mins = Number(g('hour')) * 60 + Number(g('minute'));
            const weekend = ['Sat', 'Sun'].includes(g('weekday'));
            if (weekend || mins < 7 * 60 || mins >= 17 * 60 + 30) {
                return 'It is outside Mary\'s usual calling hours (Monday to Friday, 07:00 to 17:30 UK time).';
            }
        } catch (_) { /* Intl unavailable: no warning */ }
        return '';
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    async handleConfirm() {
        if (this.calling || !this.recordId) return;
        this.calling = true;
        try {
            await callNow({ applicationId: this.recordId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Call Now',
                message: 'Mary is dialling. The call will appear in Call History shortly.',
                variant: 'success',
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Call Now failed',
                message: friendlyError(e),
                variant: 'error',
            }));
        } finally {
            this.dispatchEvent(new CloseActionScreenEvent());
        }
    }
}

/**
 * AA_MaryBridge wraps a Heroku refusal as 'Heroku returned HTTP 409: {json}'.
 * Show the handler's plain-English `message` (or `detail`) instead of raw JSON.
 */
function friendlyError(e) {
    const raw = e?.body?.message ?? e?.message ?? 'Unknown error';
    const m = String(raw).match(/HTTP \d+: (\{[\s\S]*\})\s*$/);
    if (m) {
        try {
            const j = JSON.parse(m[1]);
            return j.message || j.detail || j.error || raw;
        } catch (_) { /* not JSON: fall through */ }
    }
    return raw;
}
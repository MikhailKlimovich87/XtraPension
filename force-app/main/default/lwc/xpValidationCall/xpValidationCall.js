import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getCall from '@salesforce/apex/XpValidationCallController.getCall';

// Coming back to the Claim's tab (after booking in the other tab) reads the call again, at most this often.
const REFRESH_GAP_MS = 5000;

/**
 * The client's validation call on the Claim (Fernando, 10 Nov 2026): from XP Booking, by the client's
 * e-mail (XpValidationCallController). Not booked: a button opens the booking page in a new tab with the
 * client's details filled in, offering only the claim's validation agent's times. Booked: when, with whom,
 * and the links to change or cancel it (the client's own page) or open it in XP Booking.
 */
export default class XpValidationCall extends LightningElement {
    @api recordId;
    data;
    error;
    loading = true;
    showLink = false;
    lastLoad = 0;

    onFocus = () => this.maybeReload();
    onVisible = () => {
        if (document.visibilityState === 'visible') this.maybeReload();
    };

    connectedCallback() {
        this.load();
        window.addEventListener('focus', this.onFocus);
        document.addEventListener('visibilitychange', this.onVisible);
    }

    disconnectedCallback() {
        window.removeEventListener('focus', this.onFocus);
        document.removeEventListener('visibilitychange', this.onVisible);
    }

    maybeReload() {
        if (Date.now() - this.lastLoad > REFRESH_GAP_MS) this.load();
    }

    async load() {
        if (!this.recordId) return;
        this.lastLoad = Date.now();
        try {
            this.data = await getCall({ claimId: this.recordId });
            this.error = undefined;
        } catch (e) {
            this.error = (e && e.body && e.body.message) || 'Could not read the validation call.';
        } finally {
            this.loading = false;
        }
    }

    get status() { return this.data ? this.data.status : null; }
    get call() { return this.data && this.data.call ? this.data.call : null; }
    get ready() { return !!this.data && !this.error; }

    get isNoEmail() { return this.status === 'no_email'; }
    get isOffline() { return this.status === 'offline'; }
    get isNone() { return this.status === 'ok' && !this.call; }
    get isBooked() { return this.status === 'ok' && !!this.call && this.call.state === 'booked'; }
    get isPast() { return this.status === 'ok' && !!this.call && this.call.state === 'past'; }
    get hasMismatch() { return this.isBooked && !!this.call.mismatch; }
    get canBook() { return this.isNone || this.isOffline || this.isPast; }

    get badge() {
        if (this.hasMismatch) return { label: 'Check', cls: 'xp-vc__badge xp-vc__badge_warn' };
        if (this.isBooked) return { label: 'Booked', cls: 'xp-vc__badge xp-vc__badge_ok' };
        if (this.isPast) return { label: 'Past', cls: 'xp-vc__badge' };
        if (this.isNone) return { label: 'Not booked', cls: 'xp-vc__badge' };
        return { label: 'Unknown', cls: 'xp-vc__badge' };
    }

    get agentLine() {
        const a = this.data && this.data.agent;
        const offers = this.data && this.data.offers;
        const region = this.data && this.data.region;
        if (!a) return 'The claim has no validation agent yet, so any free validation agent takes the call.';
        // The claim's agent does not take this region's calls (an AUS/NZ claim given to someone else by hand).
        if (offers && !a.startsWith(offers) && !offers.startsWith(a.split(' ')[0])) {
            return `${a} is this claim's validation agent, but ${a} does not take ${region} calls, so the booking page offers ${offers}'s times.`;
        }
        return `${a} is this claim's validation agent.`;
    }

    get bookHint() {
        const offers = this.data && this.data.offers;
        const region = this.data && this.data.region;
        return offers
            ? `Opens ${offers}'s times (${region}) in a new tab, with the client's name, e-mail and phone filled in.`
            : `Opens the ${region} validation times in a new tab, with the client's name, e-mail and phone filled in.`;
    }

    get fallbackLine() {
        const f = this.data && this.data.fallback;
        return f ? `The claim says: ${f}.` : 'The claim has no validation call written on it.';
    }

    get clientUrl() { return this.data ? this.data.clientUrl : ''; }
    get bookVariant() { return this.isPast ? 'neutral' : 'brand'; }
    get bookLabel() { return this.isPast ? 'Book another' : 'Book the call'; }
    get changeVariant() { return this.hasMismatch ? 'brand' : 'neutral'; }

    open(url) {
        if (url) window.open(url, '_blank', 'noopener');
    }

    handleBook() { this.open(this.data && this.data.bookUrl); }
    handleChange() { this.open(this.call && this.call.manageUrl); }
    handleCancel() { this.open(this.call && this.call.cancelUrl); }
    handleHub() { this.open(this.call && this.call.hubUrl); }

    handleRefresh() {
        this.loading = true;
        this.load();
    }

    async handleCopy() {
        const url = this.clientUrl;
        try {
            await navigator.clipboard.writeText(url);
            this.dispatchEvent(new ShowToastEvent({ title: "Client's link copied", message: 'Paste it in an e-mail or WhatsApp to the client.', variant: 'success' }));
        } catch (e) {
            // The browser refused the clipboard: the link shows, to copy by hand.
            this.showLink = true;
        }
    }
}
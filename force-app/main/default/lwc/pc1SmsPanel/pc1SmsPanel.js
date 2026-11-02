import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getThread from '@salesforce/apex/PC1_TwilioController.getThread';
import sendSMS   from '@salesforce/apex/PC1_TwilioController.sendSMS';

/**
 * pc1SmsPanel — SMS chat embedded below pc1WhatsAppPanel in the record page
 * leftsidebar. Reads/writes TwilioSF__Message__c via PC1_TwilioController.
 *
 * Poll every 30 s while the panel is visible + tab is active. Optimistic
 * bubble on send, reconciled by the next refresh.
 */
export default class Pc1SmsPanel extends LightningElement {
    @api recordId;

    @track messages = [];
    @track appPhone = '';
    @track fullName = '';
    @track loading = true;
    @track loadError = '';
    @track sending = false;
    @track composerText = '';
    @track collapsed = false;

    _timer = null;
    _observer = null;
    _visHandler = null;
    _inView = true;
    _userScrolledUp = false;
    _lastMsgCount = 0;

    // ─── lifecycle ─────────────────────────────────────────────────────
    connectedCallback() {
        this._refresh(true);
        this._timer = setInterval(() => {
            if (document.visibilityState !== 'visible') return;
            if (!this._inView) return;
            this._refresh(false);
        }, 30000);
        this._visHandler = () => {
            if (document.visibilityState === 'visible') this._refresh(false);
        };
        document.addEventListener('visibilitychange', this._visHandler);
    }
    renderedCallback() {
        if (!this._observer && this.template.host) {
            this._observer = new IntersectionObserver((entries) => {
                this._inView = entries[0] && entries[0].isIntersecting;
            }, { threshold: 0.05 });
            this._observer.observe(this.template.host);
        }
    }
    disconnectedCallback() {
        if (this._timer) { clearInterval(this._timer); this._timer = null; }
        if (this._observer) { this._observer.disconnect(); this._observer = null; }
        if (this._visHandler) document.removeEventListener('visibilitychange', this._visHandler);
    }

    async _refresh(setLoading) {
        if (setLoading) this.loading = true;
        try {
            const r = await getThread({ recordId: this.recordId });
            this.appPhone = r.appPhone || '';
            this.fullName = r.fullName || '';
            const prev = this._lastMsgCount;
            this.messages = this._decorate(r.messages || []);
            this._lastMsgCount = this.messages.length;
            this.loadError = '';
            const forceScroll = setLoading || this.messages.length > prev;
            requestAnimationFrame(() => this._scrollToBottom(forceScroll));
        } catch (e) {
            this.loadError = e?.body?.message || e?.message || 'Load failed';
        } finally {
            this.loading = false;
        }
    }

    _decorate(raw) {
        const arr = [...raw].sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
        return arr.map((m, i) => {
            const prev = arr[i - 1];
            const showDay = !prev || this._dayOf(m.timestamp) !== this._dayOf(prev.timestamp);
            const bubbleClass = m.isOutbound ? 'pc1-sms__bubble is-out' : 'pc1-sms__bubble is-in';
            return {
                key: m.id || `${m.timestamp}-${i}`,
                body: m.body || '',
                bubbleClass,
                isOut: !!m.isOutbound,
                timeLabel: this._timeOf(m.timestamp),
                dayLabel: showDay ? this._dayLabelOf(m.timestamp) : null,
                showDay,
                statusLabel: this._statusLabel(m.status, m.isOutbound),
                statusClass: this._statusClass(m.status, m.isOutbound),
                senderName: m.senderName || '',
                showSender: !!m.isOutbound && !!m.senderName && (!prev || !prev.isOutbound || prev.senderName !== m.senderName),
                errorCode: m.errorCode || '',
                hasError: (m.status || '').toLowerCase() === 'failed' || !!m.errorCode,
            };
        });
    }
    _dayOf(ts) { try { return new Date(ts).toISOString().slice(0, 10); } catch (e) { return ''; } }
    _timeOf(ts) {
        try { return new Date(ts).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }); }
        catch (e) { return ''; }
    }
    _dayLabelOf(ts) {
        try {
            const d = new Date(ts);
            const today = new Date(); today.setHours(0, 0, 0, 0);
            const dOnly = new Date(d); dOnly.setHours(0, 0, 0, 0);
            const diff = Math.round((today - dOnly) / 86400000);
            if (diff === 0) return 'Today';
            if (diff === 1) return 'Yesterday';
            return d.toLocaleDateString('en-GB', { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric' });
        } catch (e) { return ts; }
    }
    // Twilio initial API response returns `queued` — but from the ops
    // perspective the message has already left our system. Collapse the
    // in-flight states (accepted / queued / sending / sent) to a single
    // "Sent ✓" label so the panel doesn't look stuck. Only surface
    // `Delivered` / `Failed` when Twilio confirms terminal state (needs
    // a StatusCallback webhook to update the row post-send).
    _statusLabel(status, isOut) {
        if (!isOut) return '';
        const s = String(status || '').toLowerCase();
        if (s === 'delivered')                     return 'delivered ✓✓';
        if (s === 'undelivered' || s === 'failed') return s;
        if (['accepted','queued','sending','sent'].includes(s)) return 'sent ✓';
        return s || '…';
    }
    _statusClass(status, isOut) {
        if (!isOut) return 'pc1-sms__status';
        const s = String(status || '').toLowerCase();
        if (s === 'failed' || s === 'undelivered') return 'pc1-sms__status is-bad';
        if (s === 'delivered')                     return 'pc1-sms__status is-good';
        if (['accepted','queued','sending','sent'].includes(s)) return 'pc1-sms__status is-good';
        return 'pc1-sms__status';
    }
    _scrollToBottom(force) {
        const box = this.template.querySelector('.pc1-sms__thread');
        if (!box) return;
        if (!force && this._userScrolledUp) return;
        box.scrollTop = box.scrollHeight;
    }
    handleThreadScroll() {
        const box = this.template.querySelector('.pc1-sms__thread');
        if (!box) return;
        const atBottom = box.scrollHeight - (box.scrollTop + box.clientHeight) < 60;
        this._userScrolledUp = !atBottom;
    }

    // ─── UI handlers ────────────────────────────────────────────────────
    handleComposeInput(e) { this.composerText = e.target.value; }
    handleKeydown(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            this.handleSend();
        }
    }
    async handleSend() {
        const body = (this.composerText || '').trim();
        if (this.sending || !body) return;
        if (!this.appPhone) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Cannot send', message: 'No phone on this application.', variant: 'warning' }));
            return;
        }
        this.sending = true;
        const tempKey = 'temp-' + Date.now();
        const optimistic = {
            key: tempKey,
            body,
            bubbleClass: 'pc1-sms__bubble is-out is-sending',
            isOut: true,
            timeLabel: this._timeOf(new Date().toISOString()),
            statusLabel: 'sending', statusClass: 'pc1-sms__status',
            showDay: false, senderName: '', showSender: false,
        };
        this.messages = [...this.messages, optimistic];
        this.composerText = '';
        const ta = this.template.querySelector('.pc1-sms__ta');
        if (ta) ta.value = '';
        requestAnimationFrame(() => this._scrollToBottom(true));
        try {
            await sendSMS({ recordId: this.recordId, body });
            await this._refresh(false);
        } catch (e) {
            this.messages = this.messages.map(m => m.key === tempKey
                ? { ...m, bubbleClass: 'pc1-sms__bubble is-out is-failed', statusLabel: 'failed', statusClass: 'pc1-sms__status is-bad', hasError: true }
                : m
            );
            this.dispatchEvent(new ShowToastEvent({ title: 'Send failed', message: e?.body?.message || e?.message || '', variant: 'error' }));
        } finally {
            this.sending = false;
        }
    }
    handleToggleCollapse() { this.collapsed = !this.collapsed; }

    // ─── computed getters ───────────────────────────────────────────────
    get headerSubtitle() {
        const bits = [];
        if (this.fullName) bits.push(this.fullName);
        if (this.appPhone) bits.push(this.appPhone);
        else bits.push('No phone on file');
        return bits.join(' · ');
    }
    get isEmpty()      { return !this.loading && !this.loadError && this.messages.length === 0; }
    get hasMessages()  { return !this.loading && !this.loadError && this.messages.length > 0; }
    get sendDisabled() { return this.sending || !(this.composerText || '').trim() || !this.appPhone; }
    get disableAll()   { return this.sending || !this.appPhone; }
    get composerPlaceholder() {
        if (!this.appPhone) return 'No phone number on this application.';
        return 'Type an SMS… (Enter to send, Shift+Enter for newline)';
    }
    get collapseIcon() { return this.collapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get bodyStyle()    { return this.collapsed ? 'display:none;' : ''; }
    get showNoPhoneBanner() { return !this.loading && !this.appPhone; }
}
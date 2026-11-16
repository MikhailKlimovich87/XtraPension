import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import USER_SHORT_NAME from '@salesforce/schema/User.Short_Name__c';
import USER_PHONE from '@salesforce/schema/User.Phone';
import CLAIM_FIRST_NAME from '@salesforce/schema/Basic__c.First_Name__c';
import CLAIM_HELPER_FIRST_NAME from '@salesforce/schema/Basic__c.Friend_First_Name__c';
import CLAIM_FORM_LINK from '@salesforce/schema/Basic__c.Personal_Details_Form_Link__c';
import getThread      from '@salesforce/apex/XpClaimsWhatsAppController.getThread';
import sendMessage    from '@salesforce/apex/XpClaimsWhatsAppController.sendMessage';
import sendFileMessage from '@salesforce/apex/XpClaimsWhatsAppController.sendFileMessage';
import sendFileFromBrowser from '@salesforce/apex/XpClaimsWhatsAppController.sendFileFromBrowser';
import listClaimFiles from '@salesforce/apex/XpClaimsWhatsAppController.listClaimFiles';
import startAiReply from '@salesforce/apex/XpClaimsWhatsAppController.startAiReply';
import startRewrite from '@salesforce/apex/XpClaimsWhatsAppController.startRewrite';
import getAiReply from '@salesforce/apex/XpClaimsWhatsAppController.getAiReply';

const MAX_COMPOSER_PX = 220;
// Polls hit the XP AI for Claims cache, not Timelines: the cache is refreshed by
// the Timelines webhook when a message arrives (and every 5 min as a safety net).
const POLL_MS = 15_000;
const ACCEPTED_TYPES = ['.jpg','.jpeg','.png','.webp','.gif','.pdf','.doc','.docx','.xls','.xlsx','.txt','.csv','.mp3','.m4a','.ogg','.mp4'];

/**
 * WhatsApp shows text exactly as sent, so HTML must never reach it. The template
 * buttons on the record (e.g. "Google Review Message") copy email templates with
 * <a href="..."> links. Links become the bare URL (or "text: URL"), line tags become
 * line breaks, bold/italic become WhatsApp *bold* / _italic_, other tags are dropped.
 * Text without HTML comes back unchanged. Same function on the server (claims-ai/whatsapp.ts).
 */
const HTML_TAG_RE = /<\/?[a-z][a-z0-9]*\b[^<>]*>|&(?:amp|lt|gt|quot|nbsp|#\d+|#x[0-9a-f]+);/i;
function htmlToWhatsApp(input) {
    const s = String(input || '');
    if (!HTML_TAG_RE.test(s)) return s;
    const bare = (u) => u.replace(/^https?:\/\//i, '').replace(/\/$/, '').toLowerCase();
    return s
        .replace(/<a\b[^>]*?href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi, (m, href, inner) => {
            const text = inner.replace(/<[^>]+>/g, '').trim();
            if (/^mailto:/i.test(href)) return text || href.replace(/^mailto:/i, '');
            return !text || bare(text) === bare(href) ? href : `${text}: ${href}`;
        })
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<\/(p|div|li|h[1-6]|tr)>/gi, '\n')
        .replace(/<li\b[^>]*>/gi, '• ')
        .replace(/<\/?(b|strong)\b[^>]*>/gi, '*')
        .replace(/<\/?(i|em)\b[^>]*>/gi, '_')
        .replace(/<\/?[a-z][a-z0-9]*\b[^<>]*>/gi, '')
        .replace(/&nbsp;/gi, ' ')
        .replace(/&lt;/gi, '<')
        .replace(/&gt;/gi, '>')
        .replace(/&quot;/gi, '"')
        .replace(/&#(\d+);/g, (m, n) => String.fromCodePoint(Number(n)))
        .replace(/&#x([0-9a-f]+);/gi, (m, n) => String.fromCodePoint(parseInt(n, 16)))
        .replace(/&amp;/gi, '&')
        .replace(/[ \t]+\n/g, '\n')
        .replace(/\n{3,}/g, '\n\n')
        .trim();
}

/**
 * Bubble text as the phone shows it. Messages sent before that fix still carry HTML
 * (e.g. the 2025 Google review link), so they go through htmlToWhatsApp first. Then
 * links become clickable and *bold* / _italic_ / ~strike~ get their style. Returns
 * pieces for the template (LWC has no innerHTML).
 */
const URL_RE = /\b(?:https?:\/\/|www\.)[^\s<>"]+/gi;
const STYLE_RE = /(^|[\s([{"'])([*_~])(?!\s)([^\n]*?\S)\2(?=$|[\s.,;:!?)\]}"'])/g;
const STYLE_CLASS = { '*': 'xp-wa__b', '_': 'xp-wa__i', '~': 'xp-wa__s' };
function waParts(input) {
    const parts = [];
    const push = (text, cls = '', href = '') => {
        if (text) parts.push({ key: String(parts.length), text, cls, href });
    };
    const styled = (seg) => {
        let last = 0;
        seg.replace(STYLE_RE, (m, pre, mark, inner, at) => {
            push(seg.slice(last, at) + pre);
            push(inner, STYLE_CLASS[mark]);
            last = at + m.length;
            return m;
        });
        push(seg.slice(last));
    };
    const s = htmlToWhatsApp(input);
    let last = 0;
    for (const m of s.matchAll(URL_RE)) {
        if (m.index < last) continue;
        const url = m[0].replace(/[.,;:!?'")\]}*_~]+$/, '');
        styled(s.slice(last, m.index));
        push(url, 'xp-wa__link', /^www\./i.test(url) ? `https://${url}` : url);
        last = m.index + url.length;
    }
    styled(s.slice(last));
    return parts;
}

/**
 * xpClaimsWhatsAppPanel: WhatsApp chat on the claim (Basic__c) record page.
 * Copy of the Sales panel (xpWhatsAppPanel). Apex (XpClaimsWhatsAppController)
 * -> XP AI for Claims service -> Timelines; messages go out from
 * +353 83 123 4000. The other end is the client (Phone__c) or, when the claim
 * has one, the helper (Friend_Phone__c): the switch at the top picks which, and
 * every call says it.
 *
 * Read: 15s poll (served from the XP AI cache) while the panel is visible in viewport + tab is active
 * (IntersectionObserver + document.visibilityState).
 *
 * Send: optimistic bubble immediately, then reconcile with server response.
 * Errors surface via a retry-able red bubble.
 *
 * AI Reply: drafts the next message into the box (never sends). Whatever is
 * already typed in the box is the instruction for the draft.
 */
export default class XpClaimsWhatsAppPanel extends LightningElement {
    @api recordId;

    @track messages   = [];
    @track chat       = null;      // { id, phone, isAllowedToMessage } or null
    @track fullName   = '';
    @track appPhone   = '';        // phone of whoever is selected (client or helper)
    @track contact    = 'client';  // 'client' | 'helper'
    @track contacts   = [];        // [{ key, label, name, phone }] from the server
    _refreshSeq = 0;
    @track loading    = true;
    @track loadError  = '';
    @track sending    = false;
    @track composerText = '';
    @track collapsed  = false;

    // Attachment + voice-note state
    @track pendingFile = null;      // { contentVersionId, name, sizeLabel }
    @track showEmojiPicker = false;
    @track showPlusMenu = false;
    @track showSfPicker = false;
    @track sfFiles = [];
    @track sfSearchQuery = '';
    @track loadingSfFiles = false;
    @track drafting = false;
    @track draftProgress = '';
    @track draftKind = '';
    @track canUndo = false;
    @track showTemplates = false;
    _beforeRewrite = null;
    _firstName = '';
    _userName = '';
    _userPhone = '';
    _helperFirstName = '';
    _formLink = '';

    // Dados das mensagens prontas: nome do cliente e do helper e o link do formulário do cliente
    // (Personal_Details_Form_Link__c; nunca os links de agente, Form_Agent_URL__c / Short_Agent_Link__c).
    @wire(getRecord, { recordId: '$recordId', fields: [CLAIM_FIRST_NAME, CLAIM_HELPER_FIRST_NAME, CLAIM_FORM_LINK] })
    wiredClaim({ data }) {
        if (data) {
            this._firstName = data.fields.First_Name__c.value || '';
            this._helperFirstName = data.fields.Friend_First_Name__c.value || '';
            this._formLink = data.fields.Personal_Details_Form_Link__c.value || '';
        }
    }
    @wire(getRecord, { recordId: USER_ID, fields: [USER_SHORT_NAME, USER_PHONE] })
    wiredUser({ data }) {
        if (data) {
            this._userName = data.fields.Short_Name__c.value || '';
            this._userPhone = data.fields.Phone.value || '';
        }
    }
    _timer = null;
    _observer = null;
    _inView = true;
    _lastMsgCount = 0;
    _userScrolledUp = false;

    // ─── lifecycle ─────────────────────────────────────────────────────
    connectedCallback() {
        this._refresh(true);
        this._startPolling();
        // Immediate refresh when the user re-focuses the tab
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
        this._draftCancelled = true;
        if (this._observer) { this._observer.disconnect(); this._observer = null; }
        if (this._visHandler) document.removeEventListener('visibilitychange', this._visHandler);
    }
    _startPolling() {
        this._timer = setInterval(() => {
            if (document.visibilityState !== 'visible') return;
            if (!this._inView) return;
            this._refresh(false);
        }, POLL_MS);
    }

    async _refresh(setLoading) {
        if (setLoading) this.loading = true;
        // A poll that started before a client/helper switch must not paint the other person's chat.
        const seq = ++this._refreshSeq;
        const contact = this.contact;
        try {
            const r = await getThread({ claimId: this.recordId, contact });
            if (seq !== this._refreshSeq || contact !== this.contact) return;
            this.chat     = r.chat || null;
            const prevCount = this._lastMsgCount;
            this.messages = this._decorate(r.messages || []);
            this._lastMsgCount = this.messages.length;
            this.appPhone = r.phone || '';
            this.fullName = r.name || '';
            this.contacts = r.contacts || [];
            this.loadError = '';
            // Force scroll on the FIRST load (setLoading=true) OR when the
            // message count grew AND user is already at the bottom.
            const forceScroll = setLoading || this.messages.length > prevCount;
            requestAnimationFrame(() => this._scrollToBottom(setLoading));
            // Second RAF for images/audio which change layout after decode
            setTimeout(() => this._scrollToBottom(setLoading), 300);
        } catch (e) {
            if (seq !== this._refreshSeq) return;
            this.loadError = e?.body?.message || e?.message || 'Load failed';
        } finally {
            if (seq === this._refreshSeq) this.loading = false;
        }
    }

    // ─── client / helper ────────────────────────────────────────────────
    handlePickContact(e) {
        const key = e.currentTarget.dataset.key;
        if (!key || key === this.contact || this.sending || this.drafting) return;
        this.contact = key;
        this.messages = [];
        this._lastMsgCount = 0;
        this.chat = null;
        this.pendingFile = null;
        this.canUndo = false;
        this._beforeRewrite = null;
        this.showTemplates = false;
        const picked = (this.contacts || []).find(c => c.key === key);
        this.appPhone = picked ? picked.phone : '';
        this.fullName = picked ? picked.name : '';
        this._refresh(true);
    }
    get hasHelper() { return (this.contacts || []).some(c => c.key === 'helper'); }
    get contactTabs() {
        return (this.contacts || []).map(c => ({
            ...c,
            className: c.key === this.contact ? 'xp-wa__who is-on' : 'xp-wa__who',
            pressed: c.key === this.contact ? 'true' : 'false',
        }));
    }
    get isHelper() { return this.contact === 'helper'; }

    _decorate(raw) {
        // Sort ASC by timestamp (Timelines returns however we asked, but be
        // defensive). Then decorate each msg with view-friendly fields.
        const arr = [...raw].sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
        return arr.map((m, i) => {
            const prev = arr[i-1];
            const isOut = !!m.from_me;
            const bubbleClass = isOut ? 'xp-wa__bubble is-out' : 'xp-wa__bubble is-in';
            const showDay = !prev || this._dayOf(m.timestamp) !== this._dayOf(prev.timestamp);
            // Sender label. For outbound: split the display into two parts —
            //   topLabel (goes above bubble): WA identity ('Xtrapension' or
            //     whatever Timelines calls the WA account we send from). Only
            //     shown on the first bubble of a run.
            //   metaSender (next to timestamp): 'Sent by <SF User>' when the
            //     mirror table knows which SF user clicked Send. Always shown.
            // For inbound: topLabel = the client's WA display name if
            //   different from their phone; metaSender empty.
            const rawTLName = (m.sender_name || '').trim();
            const sfUserName = (m.sf_sender_name || '').replace(/\s*<[^>]+>\s*$/, '').trim();
            let topLabel = '';
            let metaSender = '';
            if (isOut) {
                // Always brand outbound as "XtraPension" (Timelines returns
                // "Xtrapension" from the WA account — Fernando wants the
                // proper caps in every bubble regardless of what TL saved).
                topLabel = 'XtraPension';
                if (sfUserName) metaSender = `Sent by ${sfUserName}`;
            } else if (rawTLName && rawTLName !== m.sender_phone) {
                topLabel = rawTLName;
            }
            const showTopLabel = !!topLabel && (!prev || !!prev.from_me !== isOut);
            // Media / audio detection
            const attachUrl  = m.attachment_url || '';
            const attachName = m.attachment_filename || '';
            const isAudio = /\.(ogg|oga|mp3|m4a|opus|wav|webm)$/i.test(attachName) || /audio\//i.test(attachName || '') || /audio\//i.test(m.mime || '');
            const isImage = /\.(jpe?g|png|webp|gif)$/i.test(attachName);
            return {
                key:       m.uid || `${m.chat_id}-${m.timestamp}`,
                text:      m.text || '',
                parts:     waParts(m.text),
                timestamp: m.timestamp,
                bubbleClass,
                isOut,
                timeLabel: this._timeOf(m.timestamp),
                dayLabel:  showDay ? this._dayLabelOf(m.timestamp) : null,
                showDay,
                statusLabel: this._statusLabel(m.status, isOut),
                topLabel, showTopLabel, metaSender,
                hasAttachment: !!attachUrl,
                isAudio, isImage,
                attachmentUrl:      attachUrl,
                attachmentFilename: attachName || 'attachment',
            };
        });
    }
    _dayOf(ts) { try { return new Date(ts).toISOString().slice(0, 10); } catch { return ''; } }
    _timeOf(ts) {
        try { return new Date(ts).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }); } catch { return ''; }
    }
    _dayLabelOf(ts) {
        try {
            const d = new Date(ts);
            const today = new Date(); today.setHours(0,0,0,0);
            const dOnly = new Date(d); dOnly.setHours(0,0,0,0);
            const diff = Math.round((today - dOnly) / 86_400_000);
            if (diff === 0) return 'Today';
            if (diff === 1) return 'Yesterday';
            return d.toLocaleDateString('en-GB', { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric' });
        } catch { return ts; }
    }
    _statusLabel(status, isOut) {
        if (!isOut) return '';
        const s = String(status || '').toLowerCase();
        if (s === 'read')      return '✓✓';
        if (s === 'delivered') return '✓✓';
        if (s === 'sent')      return '✓';
        if (s === 'failed')    return '⚠';
        return '…';
    }
    _scrollToBottom(force) {
        const box = this.template.querySelector('.xp-wa__thread');
        if (!box) return;
        // Auto-scroll only when the user is already at the bottom (WhatsApp
        // behaviour) OR when we force it (initial load / after send).
        if (!force && this._userScrolledUp) return;
        box.scrollTop = box.scrollHeight;
    }
    handleThreadScroll() {
        const box = this.template.querySelector('.xp-wa__thread');
        if (!box) return;
        const atBottom = box.scrollHeight - (box.scrollTop + box.clientHeight) < 60;
        this._userScrolledUp = !atBottom;
    }

    // ─── UI handlers ────────────────────────────────────────────────────
    handleComposeInput(e) {
        this.composerText = e.target.value;
        this._fitComposer();
        // Typing after a rewrite makes the edit the agent's own; drop the undo.
        if (this.canUndo) { this.canUndo = false; this._beforeRewrite = null; }
    }
    /** Grow the box with the text, up to MAX_COMPOSER_PX; past that it scrolls. */
    _fitComposer() {
        const ta = this.template.querySelector('.xp-wa__ta');
        if (!ta) return;
        ta.style.height = 'auto';
        const h = Math.min(ta.scrollHeight + 2, MAX_COMPOSER_PX);
        ta.style.height = `${h}px`;
        ta.style.overflowY = ta.scrollHeight + 2 > MAX_COMPOSER_PX ? 'auto' : 'hidden';
    }
    /** Pasting a template with HTML (e.g. "Google Review Message"): put the clean text in the box instead. */
    handleComposePaste(e) {
        const pasted = (e.clipboardData && e.clipboardData.getData('text/plain')) || '';
        if (!HTML_TAG_RE.test(pasted)) return;
        e.preventDefault();
        const clean = htmlToWhatsApp(pasted);
        const ta = e.target;
        const start = ta.selectionStart ?? ta.value.length;
        const end = ta.selectionEnd ?? ta.value.length;
        ta.setRangeText(clean, start, end, 'end');
        this.composerText = ta.value;
        this._fitComposer();
        if (this.canUndo) { this.canUndo = false; this._beforeRewrite = null; }
        this.dispatchEvent(new ShowToastEvent({ title: 'Links tidied for WhatsApp', message: 'The pasted text had email formatting (HTML). It was turned into plain text before going in the box.', variant: 'info' }));
    }
    handleKeydown(e) {
        // Enter = send, Shift+Enter = newline
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            this.handleSend();
        }
    }
    async handleSend() {
        // Typed, pasted or rewritten: whatever goes out is plain WhatsApp text (the server checks again).
        const body = htmlToWhatsApp(this.composerText || '').trim();
        const file = this.pendingFile;
        if (this.sending) return;
        if (!body && !file) return;
        if (!this.appPhone) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Cannot send', message: this.noPhoneText, variant: 'warning' }));
            return;
        }
        this.sending = true;
        // Optimistic bubble
        const tempKey = 'temp-' + Date.now();
        const shown = body || (file ? `📎 ${file.name}` : '');
        const optimistic = {
            key: tempKey,
            text: shown,
            parts: waParts(shown),
            // audit #87: keep the REAL caption + file-ness separate from the display
            // text so a retry never resends the '📎 filename' placeholder as the body.
            retryBody: body || '',
            wasFile: !!file,
            timestamp: new Date().toISOString(),
            bubbleClass: 'xp-wa__bubble is-out is-sending', isOut: true,
            timeLabel: this._timeOf(new Date().toISOString()),
            statusLabel: '…', senderLabel: '', showSender: false, showDay: false,
        };
        this.messages = [...this.messages, optimistic];
        // Clear composer — both @track state AND DOM value directly (textareas
        // use value= as INITIAL binding only, not two-way).
        this.composerText = '';
        const ta = this.template.querySelector('.xp-wa__ta');
        if (ta) ta.value = '';
        this._fitComposer();
        requestAnimationFrame(() => this._scrollToBottom());
        try {
            if (file) {
                await sendFileMessage({
                    claimId:          this.recordId,
                    contact:          this.contact,
                    contentVersionId: file.contentVersionId,
                    caption:          body || null,
                });
                this.pendingFile = null;
            } else {
                await sendMessage({ claimId: this.recordId, contact: this.contact, messageBody: body });
            }
            await this._refresh(false);
        } catch (e) {
            this.messages = this.messages.map(m => m.key === tempKey
                ? { ...m, bubbleClass: 'xp-wa__bubble is-out is-failed', statusLabel: '⚠', failed: true, errorMsg: e?.body?.message || e?.message || 'Send failed' }
                : m
            );
            this.dispatchEvent(new ShowToastEvent({ title: 'Send failed', message: e?.body?.message || e?.message || '', variant: 'error' }));
        } finally {
            this.sending = false;
        }
    }
    handleToggleCollapse() { this.collapsed = !this.collapsed; }
    handleRetry(e) {
        const key = e.currentTarget.dataset.key;
        const msg = this.messages.find(m => m.key === key);
        if (!msg) return;
        this.messages = this.messages.filter(m => m.key !== key);
        // audit #87: restore the REAL caption, never the '📎 filename' display
        // placeholder. A failed FILE send can't be auto-replayed (the attachment
        // isn't retained), so ask the agent to re-attach instead of sending the
        // placeholder as a text message.
        this.composerText = msg.retryBody || '';
        if (msg.wasFile) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Re-attach the file',
                message: 'Re-select the file to resend it — the attachment isn\'t kept on a failed send. Your caption has been restored.',
                variant: 'info',
            }));
            return;
        }
        this.handleSend();
    }

    // ─── AI Reply / Rewrite ─────────────────────────────────────────────
    // Both write into the box and never send. AI Reply drafts the next message
    // (the box text is the instruction); Rewrite polishes the box text.
    handleAiReply() {
        const hint = (this.composerText || '').trim();
        this._runDraftJob('reply', () => startAiReply({ claimId: this.recordId, contact: this.contact, instruction: hint || null }));
    }
    handleRewrite() {
        const text = (this.composerText || '').trim();
        if (!text) return;
        this._runDraftJob('rewrite', () => startRewrite({ claimId: this.recordId, contact: this.contact, text }), text);
    }
    handleUndoRewrite() {
        const prev = this._beforeRewrite;
        if (prev == null) return;
        this._beforeRewrite = null;
        this.canUndo = false;
        this._setComposer(prev);
    }
    async _runDraftJob(kind, start, original) {
        if (this.drafting || this.sending) return;
        this.drafting = true;
        this.draftKind = kind;
        this._draftCancelled = false;
        this.draftProgress = kind === 'rewrite' ? 'Rewriting' : 'Reading the conversation';
        this.showEmojiPicker = false;
        this.showPlusMenu = false;
        try {
            const started = await start();
            const jobId = started && started.jobId;
            if (!jobId) throw new Error('Could not start.');
            const t0 = Date.now();
            for (;;) {
                await new Promise(r => setTimeout(r, kind === 'rewrite' ? 1200 : 2000));
                if (this._draftCancelled) return;
                const s = await getAiReply({ jobId });
                if (s.status === 'done') {
                    this._beforeRewrite = kind === 'rewrite' ? original : null;
                    this.canUndo = kind === 'rewrite';
                    this._setComposer(s.text || '');
                    this.dispatchEvent(new ShowToastEvent({
                        title: kind === 'rewrite' ? 'Rewritten' : 'Draft ready',
                        message: 'Check it and press Send. Nothing has been sent.',
                        variant: 'success',
                    }));
                    break;
                }
                if (s.status === 'error') throw new Error(s.error || 'Something went wrong.');
                this.draftProgress = s.progress || (kind === 'rewrite' ? 'Rewriting' : 'Writing the reply');
                if (Date.now() - t0 > 180000) throw new Error('This is taking too long. Try again.');
            }
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: kind === 'rewrite' ? 'Rewrite failed' : 'AI Reply failed', message: e?.body?.message || e?.message || '', variant: 'error' }));
        } finally {
            this.drafting = false;
            this.draftKind = '';
            this.draftProgress = '';
        }
    }
    _setComposer(text) {
        this.composerText = text;
        const ta = this.template.querySelector('.xp-wa__ta');
        if (ta) {
            ta.value = text;
            this._fitComposer();
            requestAnimationFrame(() => { ta.focus(); ta.setSelectionRange(text.length, text.length); ta.scrollTop = ta.scrollHeight; });
        }
    }

    // ─── emoji picker ───────────────────────────────────────────────────
    handleToggleEmoji() { this.showEmojiPicker = !this.showEmojiPicker; }
    handleEmojiClose()  { this.showEmojiPicker = false; }
    handleEmojiPick(e) {
        const emoji = e.detail && e.detail.char;
        if (!emoji) return;
        const ta = this.template.querySelector('.xp-wa__ta');
        if (ta) {
            const start = ta.selectionStart || (this.composerText || '').length;
            const end   = ta.selectionEnd   || start;
            const before = (this.composerText || '').slice(0, start);
            const after  = (this.composerText || '').slice(end);
            const next = before + emoji + after;
            this.composerText = next;
            ta.value = next;
            this._fitComposer();
            const cursor = start + emoji.length;
            requestAnimationFrame(() => { ta.focus(); ta.setSelectionRange(cursor, cursor); });
        } else {
            this.composerText = (this.composerText || '') + emoji;
        }
    }

    // ─── message templates ──────────────────────────────────────────────
    // Mensagens do Claims no tom das do Sales. Escolher uma só preenche a caixa; o que estava
    // digitado volta com Undo. Com o Helper selecionado, a saudação usa o nome do helper e o
    // "your" vira o nome do cliente ("Mary's UK State Pension claim").
    get templateItems() {
        return [
            { key: 'form', label: 'Form reminder' },
            { key: 'docusign', label: 'DocuSign reminder' },
            { key: 'posted', label: 'Claim posted' },
        ];
    }
    _templateText(key) {
        const client = this._firstName;
        const first = (this.isHelper ? this._helperFirstName : client) || 'there';
        const me = this._userName;
        const whose = this.isHelper ? (client ? client + "'s" : 'the') : 'your';
        const thanks = 'Thanks, ' + [me, this._userPhone].filter(Boolean).join(' ');
        if (key === 'form') {
            return 'Hi ' + first + ' - ' + (me ? me + ' here' : 'here') + ' from XtraPension. Just a quick reminder to finish ' +
                whose + ' UK State Pension claim form online' + (this._formLink ? ':\n' + this._formLink : '.') + '\n\n' +
                "If you need a hand, give me a call whenever suits & I'll come back to you if I miss you.\n\n" + thanks;
        }
        if (key === 'docusign') {
            const ask = !this.isHelper ? 'Could you sign them please whenever suits?'
                : client ? 'Could you help ' + client + ' sign them please whenever suits?'
                : 'Could you help get them signed please whenever suits?';
            return 'Hi ' + first + ' - ' + (me ? me + ' here' : 'here') + ' from XtraPension. We emailed the documents for ' +
                whose + ' UK State Pension claim through DocuSign.\n\n' +
                ask + ' Just look for the email from DocuSign.\n\n' + thanks;
        }
        if (key === 'posted') {
            return 'Hi ' + first + ' - Good news from XtraPension: ' + whose + ' UK State Pension claim has been posted to the DWP.\n\n' +
                "We'll be in touch as soon as we hear back from them.\n\n" + thanks;
        }
        return '';
    }
    handleToggleTemplates() {
        this.showTemplates = !this.showTemplates;
        this.showPlusMenu = false;
        this.showEmojiPicker = false;
    }
    handleTemplatePick(e) {
        const text = this._templateText(e.currentTarget.dataset.key);
        this.showTemplates = false;
        if (!text) return;
        const typed = this.composerText || '';
        this._beforeRewrite = typed.trim() ? typed : null;
        this.canUndo = !!typed.trim();
        this._setComposer(text);
    }

    // ─── attach menu (+) ────────────────────────────────────────────────
    handleTogglePlusMenu() {
        this.showPlusMenu = !this.showPlusMenu;
        this.showTemplates = false;
        this.showEmojiPicker = false;
        this.showSfPicker = false;
    }
    handleClickUploadFromDevice() {
        this.showPlusMenu = false;
        // Trigger the hidden native file input (avoids the fragile shadow-DOM
        // dig into lightning-file-upload, which SF changes across releases).
        const inp = this.template.querySelector('.xp-wa__native-file');
        if (inp) { inp.value = ''; inp.click(); }
    }
    async handleNativeFileChange(evt) {
        const file = evt.target.files && evt.target.files[0];
        if (!file) return;
        // Enforce a 10MB cap on this path — matches WhatsApp doc-attach ceiling
        // for practical UX. Larger files should go via SF Files (chunked upload).
        if (file.size > 10 * 1024 * 1024) {
            this.dispatchEvent(new ShowToastEvent({ title:'File too big', message:'Max 10 MB. Use "From Salesforce Files" for larger files.', variant:'warning' }));
            return;
        }
        this.sending = true;
        try {
            const base64 = await this._fileToBase64(file);
            await sendFileFromBrowser({
                claimId:       this.recordId,
                contact:       this.contact,
                filename:      file.name,
                mime:          file.type || 'application/octet-stream',
                base64Body:    base64,
                caption:       (this.composerText || '').trim() || null,
            });
            this.composerText = '';
            const ta = this.template.querySelector('.xp-wa__ta');
            if (ta) ta.value = '';
            this._fitComposer();
            await this._refresh(false);
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title:'Send failed', message: e?.body?.message || e?.message || '', variant:'error' }));
        } finally {
            this.sending = false;
            evt.target.value = '';
        }
    }
    _fileToBase64(file) {
        return new Promise((resolve, reject) => {
            const r = new FileReader();
            r.onload = () => resolve(String(r.result).split(',')[1] || '');
            r.onerror = reject;
            r.readAsDataURL(file);
        });
    }
    handleClickFromSf() {
        this.showPlusMenu = false;
        this.handleToggleSfPicker();
    }

    // ─── file attach ────────────────────────────────────────────────────
    handleFileUploaded(evt) {
        const files = (evt.detail && evt.detail.files) || [];
        if (!files.length) return;
        const f = files[0];
        this.pendingFile = {
            contentVersionId: f.contentVersionId,
            documentId:       f.documentId,
            name:             f.name,
            size:             f.size || 0,
            sizeLabel:        this._sizeLabel(f.size || 0),
        };
    }
    handleCancelFile() { this.pendingFile = null; }

    // SF Files picker — pick from files already on this claim
    async handleToggleSfPicker() {
        if (this.showSfPicker) { this.showSfPicker = false; return; }
        this.showSfPicker = true;
        this.sfSearchQuery = '';
        this.loadingSfFiles = true;
        try {
            const rows = await listClaimFiles({ claimId: this.recordId });
            this.sfFiles = (rows || []).map(r => ({
                ...r,
                sizeLabel: this._sizeLabel(r.size || 0),
                dateLabel: r.createdAt ? new Date(r.createdAt).toLocaleDateString('en-GB', { day:'2-digit', month:'short', year:'numeric' }) : '',
                icon: this._iconForFileType(r.fileType),
            }));
        } catch (e) {
            this.sfFiles = [];
            this.dispatchEvent(new ShowToastEvent({ title: 'Could not list files', message: e?.body?.message || e?.message || '', variant: 'error' }));
        } finally { this.loadingSfFiles = false; }
    }
    handleSfSearchInput(e) { this.sfSearchQuery = e.target.value; }
    handleSfModalOverlayClick() { this.showSfPicker = false; }
    handleStopPropagation(e) { e.stopPropagation(); }
    _iconForFileType(t) {
        const s = String(t || '').toUpperCase();
        if (s === 'PDF') return 'doctype:pdf';
        if (['PNG','JPG','JPEG','WEBP','GIF'].includes(s)) return 'doctype:image';
        if (['MP3','M4A','OGG','WAV'].includes(s)) return 'doctype:audio';
        if (['MP4','MOV'].includes(s)) return 'doctype:mp4';
        if (['DOC','DOCX'].includes(s)) return 'doctype:word';
        if (['XLS','XLSX'].includes(s)) return 'doctype:excel';
        if (s === 'ZIP') return 'doctype:zip';
        return 'doctype:unknown';
    }
    handleSfFilePick(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.sfFiles.find(f => f.contentVersionId === id);
        if (!row) return;
        // Same 10 MB cap as computer upload — WhatsApp itself caps documents
        // at 100 MB but our stack (Timelines quota, Apex heap on the SF side)
        // is safest under 10 MB, and Fernando standardised on this limit.
        if ((row.size || 0) > 10 * 1024 * 1024) {
            this.dispatchEvent(new ShowToastEvent({ title:'File too big', message:`"${row.title}" is ${row.sizeLabel} — max 10 MB.`, variant:'warning' }));
            return;
        }
        this.pendingFile = {
            contentVersionId: row.contentVersionId,
            name:             row.filename || row.title,
            size:             row.size || 0,
            sizeLabel:        row.sizeLabel,
        };
        this.showSfPicker = false;
    }
    _sizeLabel(n) {
        if (!n) return '';
        if (n < 1024) return `${n} B`;
        if (n < 1024*1024) return `${Math.round(n/1024)} KB`;
        return `${(n / (1024*1024)).toFixed(1)} MB`;
    }

    // Voice-note feature removed 2026-07-31 — Timelines/WA delivery
    // consistently failed at the client's phone (WhatsApp could not play the
    // audio even though Timelines and our panel could). Kept the file-attach
    // path for MP3/M4A that the rep chooses manually.

    // ─── computed getters ───────────────────────────────────────────────
    get headerSubtitle() {
        const bits = [];
        if (this.fullName) bits.push(this.fullName);
        if (this.appPhone) bits.push(this.appPhone);
        return bits.join(' · ');
    }
    get isEmpty()  { return !this.loading && !this.loadError && this.messages.length === 0; }
    get hasMessages() { return !this.loading && !this.loadError && this.messages.length > 0; }
    get sendDisabled() {
        // Enabled if either text OR a pending file exists AND there is a phone.
        return this.sending || this.drafting || (!(this.composerText || '').trim() && !this.pendingFile) || !this.appPhone;
    }
    get showNoPhoneBanner() { return !this.loading && !this.loadError && !this.appPhone; }
    get hasPhone() { return !!this.appPhone; }
    get showComposer()    { return true; }
    get disableAll()      { return this.sending || this.drafting || !this.appPhone; }
    get aiReplyLabel()    { return this.draftKind === 'reply' ? (this.draftProgress || 'Writing…') : 'AI Reply'; }
    get rewriteLabel()    { return this.draftKind === 'rewrite' ? (this.draftProgress || 'Rewriting…') : 'Rewrite'; }
    get draftingReply()   { return this.draftKind === 'reply'; }
    get draftingRewrite() { return this.draftKind === 'rewrite'; }
    get rewriteDisabled() { return this.disableAll || !(this.composerText || '').trim(); }
    get collapseIcon() { return this.collapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get bodyStyle() { return this.collapsed ? 'display:none;' : ''; }
    get acceptedTypes() { return ACCEPTED_TYPES; }
    get hasSfFiles() { return (this.sfFiles || []).length > 0; }
    get hasSfSearchQuery() { return !!(this.sfSearchQuery || '').trim(); }
    get filteredSfFiles() {
        const q = (this.sfSearchQuery || '').trim().toLowerCase();
        if (!q) return this.sfFiles;
        return this.sfFiles.filter(f =>
            (f.title || '').toLowerCase().includes(q) ||
            (f.filename || '').toLowerCase().includes(q) ||
            (f.fileType || '').toLowerCase().includes(q));
    }
    get hasFilteredSfFiles() { return this.filteredSfFiles.length > 0; }
    get filteredSfFilesCountLabel() {
        const total = this.sfFiles.length;
        const shown = this.filteredSfFiles.length;
        if (!total) return '';
        return this.sfSearchQuery ? `${shown} of ${total}` : `${total} file${total === 1 ? '' : 's'}`;
    }
    get composerPlaceholder() {
        if (!this.appPhone) return this.noPhoneText;
        if (this.chat && this.chat.isAllowedToMessage === false) return 'Chat exists but WhatsApp session blocked. First message may fail.';
        // With a helper on the claim, the box always says who the message goes to.
        if (this.hasHelper) return `Message to ${this.fullName || (this.isHelper ? 'the helper' : 'the client')} (${this.isHelper ? 'helper' : 'client'})… Enter to send`;
        return 'Type a message… (Enter to send, Shift+Enter for newline)';
    }
    get noPhoneText() {
        return this.isHelper ? 'No helper phone on this claim.' : 'No client phone on this claim. Add it in Details to use WhatsApp.';
    }
}
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getThread      from '@salesforce/apex/AA_WhatsAppController.getThread';
import sendMessage    from '@salesforce/apex/AA_WhatsAppController.sendMessage';
import setOptIn       from '@salesforce/apex/AA_WhatsAppController.setOptIn';
import sendFileMessage from '@salesforce/apex/AA_WhatsAppController.sendFileMessage';
import sendFileFromBrowser from '@salesforce/apex/AA_WhatsAppController.sendFileFromBrowser';
import listApplicationFiles from '@salesforce/apex/AA_WhatsAppController.listApplicationFiles';

const ACCEPTED_TYPES = ['.jpg','.jpeg','.png','.webp','.gif','.pdf','.doc','.docx','.xls','.xlsx','.txt','.csv','.mp3','.m4a','.ogg','.mp4'];

/**
 * aaWhatsAppPanel — WhatsApp chat embedded below the Data Collection panel.
 *
 * Read: Apex → Heroku → Timelines. 30s poll while the panel is visible in
 * viewport + tab is active (IntersectionObserver + document.visibilityState).
 *
 * Send: optimistic bubble immediately, then reconcile with server response.
 * Errors surface via a retry-able red bubble.
 *
 * Opt-in gate: Send composer is disabled if AA_Application.WhatsApp_OptIn__c
 * is false. Ops can click "Grant opt-in" (only appears when off) to flip it
 * after confirming by phone.
 */
export default class AaWhatsAppPanel extends LightningElement {
    @api recordId;

    @track messages   = [];
    @track chat       = null;      // { id, phone, isAllowedToMessage } or null
    @track optIn      = false;
    @track fullName   = '';
    @track appPhone   = '';
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
        if (this._observer) { this._observer.disconnect(); this._observer = null; }
        if (this._visHandler) document.removeEventListener('visibilitychange', this._visHandler);
    }
    _startPolling() {
        this._timer = setInterval(() => {
            if (document.visibilityState !== 'visible') return;
            if (!this._inView) return;
            this._refresh(false);
        }, 30_000);  // 30s: each poll can cost a Timelines API call (shared monthly quota)
    }

    async _refresh(setLoading) {
        if (setLoading) this.loading = true;
        try {
            const r = await getThread({ applicationId: this.recordId });
            this.chat     = r.chat || null;
            const prevCount = this._lastMsgCount;
            this.messages = this._decorate(r.messages || []);
            this._lastMsgCount = this.messages.length;
            this.optIn    = !!r.optIn;
            this.appPhone = r.appPhone || '';
            this.fullName = r.fullName || '';
            this.loadError = '';
            // Force scroll on the FIRST load (setLoading=true) OR when the
            // message count grew AND user is already at the bottom.
            const forceScroll = setLoading || this.messages.length > prevCount;
            requestAnimationFrame(() => this._scrollToBottom(setLoading));
            // Second RAF for images/audio which change layout after decode
            setTimeout(() => this._scrollToBottom(setLoading), 300);
        } catch (e) {
            this.loadError = e?.body?.message || e?.message || 'Load failed';
        } finally {
            this.loading = false;
        }
    }

    _decorate(raw) {
        // Sort ASC by timestamp (Timelines returns however we asked, but be
        // defensive). Then decorate each msg with view-friendly fields.
        const arr = [...raw].sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
        return arr.map((m, i) => {
            const prev = arr[i-1];
            const isOut = !!m.from_me;
            const bubbleClass = isOut ? 'aa-wa__bubble is-out' : 'aa-wa__bubble is-in';
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
        const box = this.template.querySelector('.aa-wa__thread');
        if (!box) return;
        // Auto-scroll only when the user is already at the bottom (WhatsApp
        // behaviour) OR when we force it (initial load / after send).
        if (!force && this._userScrolledUp) return;
        box.scrollTop = box.scrollHeight;
    }
    handleThreadScroll() {
        const box = this.template.querySelector('.aa-wa__thread');
        if (!box) return;
        const atBottom = box.scrollHeight - (box.scrollTop + box.clientHeight) < 60;
        this._userScrolledUp = !atBottom;
    }

    // ─── UI handlers ────────────────────────────────────────────────────
    handleComposeInput(e) { this.composerText = e.target.value; }
    handleKeydown(e) {
        // Enter = send, Shift+Enter = newline
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            this.handleSend();
        }
    }
    async handleSend() {
        const body = (this.composerText || '').trim();
        const file = this.pendingFile;
        if (this.sending) return;
        if (!body && !file) return;
        if (!this.optIn) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Cannot send', message: 'Client has not opted in to WhatsApp.', variant: 'warning' }));
            return;
        }
        this.sending = true;
        // Optimistic bubble
        const tempKey = 'temp-' + Date.now();
        const optimistic = {
            key: tempKey,
            text: body || (file ? `📎 ${file.name}` : ''),
            // audit #87: keep the REAL caption + file-ness separate from the display
            // text so a retry never resends the '📎 filename' placeholder as the body.
            retryBody: body || '',
            wasFile: !!file,
            timestamp: new Date().toISOString(),
            bubbleClass: 'aa-wa__bubble is-out is-sending', isOut: true,
            timeLabel: this._timeOf(new Date().toISOString()),
            statusLabel: '…', senderLabel: '', showSender: false, showDay: false,
        };
        this.messages = [...this.messages, optimistic];
        // Clear composer — both @track state AND DOM value directly (textareas
        // use value= as INITIAL binding only, not two-way).
        this.composerText = '';
        const ta = this.template.querySelector('.aa-wa__ta');
        if (ta) ta.value = '';
        requestAnimationFrame(() => this._scrollToBottom());
        try {
            if (file) {
                await sendFileMessage({
                    applicationId:    this.recordId,
                    contentVersionId: file.contentVersionId,
                    caption:          body || null,
                });
                this.pendingFile = null;
            } else {
                await sendMessage({ applicationId: this.recordId, messageBody: body });
            }
            await this._refresh(false);
        } catch (e) {
            this.messages = this.messages.map(m => m.key === tempKey
                ? { ...m, bubbleClass: 'aa-wa__bubble is-out is-failed', statusLabel: '⚠', failed: true, errorMsg: e?.body?.message || e?.message || 'Send failed' }
                : m
            );
            this.dispatchEvent(new ShowToastEvent({ title: 'Send failed', message: e?.body?.message || e?.message || '', variant: 'error' }));
        } finally {
            this.sending = false;
        }
    }
    async handleGrantOptIn() {
        try {
            await setOptIn({ applicationId: this.recordId, granted: true });
            this.optIn = true;
            this.dispatchEvent(new ShowToastEvent({ title: 'Opt-in granted', variant: 'success' }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Failed', message: e?.body?.message || e?.message || '', variant: 'error' }));
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

    // ─── emoji picker ───────────────────────────────────────────────────
    handleToggleEmoji() { this.showEmojiPicker = !this.showEmojiPicker; }
    handleEmojiClose()  { this.showEmojiPicker = false; }
    handleEmojiPick(e) {
        const emoji = e.detail && e.detail.char;
        if (!emoji) return;
        const ta = this.template.querySelector('.aa-wa__ta');
        if (ta) {
            const start = ta.selectionStart || (this.composerText || '').length;
            const end   = ta.selectionEnd   || start;
            const before = (this.composerText || '').slice(0, start);
            const after  = (this.composerText || '').slice(end);
            const next = before + emoji + after;
            this.composerText = next;
            ta.value = next;
            const cursor = start + emoji.length;
            requestAnimationFrame(() => { ta.focus(); ta.setSelectionRange(cursor, cursor); });
        } else {
            this.composerText = (this.composerText || '') + emoji;
        }
    }

    // ─── attach menu (+) ────────────────────────────────────────────────
    handleTogglePlusMenu() {
        this.showPlusMenu = !this.showPlusMenu;
        this.showEmojiPicker = false;
        this.showSfPicker = false;
    }
    handleClickUploadFromDevice() {
        this.showPlusMenu = false;
        // Trigger the hidden native file input (avoids the fragile shadow-DOM
        // dig into lightning-file-upload, which SF changes across releases).
        const inp = this.template.querySelector('.aa-wa__native-file');
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
                applicationId: this.recordId,
                filename:      file.name,
                mime:          file.type || 'application/octet-stream',
                base64Body:    base64,
                caption:       (this.composerText || '').trim() || null,
            });
            this.composerText = '';
            const ta = this.template.querySelector('.aa-wa__ta');
            if (ta) ta.value = '';
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

    // SF Files picker — pick from files already on this AA_Application
    async handleToggleSfPicker() {
        if (this.showSfPicker) { this.showSfPicker = false; return; }
        this.showSfPicker = true;
        this.sfSearchQuery = '';
        this.loadingSfFiles = true;
        try {
            const rows = await listApplicationFiles({ applicationId: this.recordId });
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
        // Enabled if either text OR a pending file exists AND opt-in granted.
        return this.sending || (!(this.composerText || '').trim() && !this.pendingFile) || !this.optIn;
    }
    get showOptInBanner() { return !this.loading && !this.optIn; }
    get showComposer()    { return true; }
    get disableAll()      { return this.sending || !this.optIn; }
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
        if (!this.optIn) return 'Client has not opted in to WhatsApp.';
        if (this.chat && this.chat.isAllowedToMessage === false) return 'Chat exists but WhatsApp session blocked. First message may fail.';
        return 'Type a message… (Enter to send, Shift+Enter for newline)';
    }
}
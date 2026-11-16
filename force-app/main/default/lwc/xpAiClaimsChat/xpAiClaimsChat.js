import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { RefreshEvent } from 'lightning/refresh';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import send from '@salesforce/apex/XpAiClaimsController.send';

const POLL_MS = 1200;
const MAX_FILE_BYTES = 3 * 1024 * 1024;
const FILE_TYPES = ['application/pdf', 'image/png', 'image/jpeg', 'image/webp', 'image/gif'];
// Fotos maiores sao reduzidas aqui no navegador (lado maior 2000 px, JPEG) antes de enviar:
// o Apex tem ~6 MB de memoria por chamada e a IA ve a imagem a ~1600 px de qualquer forma.
const MAX_FILES = 5;
const IMAGE_RAW_MAX_BYTES = 25 * 1024 * 1024;
const IMAGE_MAX_SIDE = 2000;
const IMAGE_TARGET_BYTES = 1200 * 1024;
const TOTAL_MAX_BASE64 = 4.5 * 1024 * 1024;

const readAsDataUrl = (file) =>
    new Promise((resolve, reject) => {
        const r = new FileReader();
        r.onload = () => resolve(String(r.result));
        r.onerror = () => reject(r.error);
        r.readAsDataURL(file);
    });
const loadImage = (src) =>
    new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => resolve(img);
        img.onerror = () => reject(new Error('not an image the browser can open'));
        img.src = src;
    });
const REFINE_LABEL = { shorter: 'Shorter', warmer: 'Warmer', redo: 'Redo' };

const escapeHtml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
/** O rascunho em texto simples, como HTML de e-mail: paragrafos e quebras de linha. */
const draftToHtml = (text) =>
    String(text || '')
        .trim()
        .split(/\n\s*\n/)
        .map((p) => `<p>${escapeHtml(p).replace(/\n/g, '<br>')}</p>`)
        .join('');
const same15 = (a, b) => !!a && !!b && a.slice(0, 15) === b.slice(0, 15);
const REFINE_PROGRESS = { shorter: 'Making it shorter', warmer: 'Making it warmer', redo: 'Writing it again' };

let seq = 0;
const nextKey = () => `k${++seq}`;

/**
 * XP AI for Claims side panel: a copy of xpAiChat that talks to XpAiClaimsController
 * (the Claims service), so the main panel is never touched. One conversation per record (plus a general one): opening a
 * record shows that record's chat, and "Recent" lists the others.
 */
export default class XpAiClaimsChat extends NavigationMixin(LightningElement) {
    /** Pedido feito sozinho ao abrir (ex.: o botao AI Reply do e-mail). */
    @api autoPrompt;
    /** Id do registo quando o componente vive dentro de uma accao do registo. */
    @api
    get recordIdOverride() {
        return this._override;
    }
    set recordIdOverride(v) {
        this._override = v;
        if (v && v !== this.recordId) {
            this.recordId = v;
            this.contextOff = false;
            this.loadContextLabel(v);
            this.switchChat();
        }
    }

    messages = [];
    draft = '';
    files = [];
    dragging = false;
    busy = false;
    progress = '';
    elapsed = 0;
    recordId;
    objectApiName;
    contextLabel;
    contextOff = false;
    loaded = false;
    showRecent = false;
    chats = [];
    chatsLoading = false;
    /** Which conversation is on screen: a 15-char record id, or 'general'. */
    chatId = null;

    _pollTimer;
    _alive = true;
    _busyChat = null;
    _override;
    _autoSent = false;
    _started = 0;

    // ------------------------------------------------------------ context

    @wire(CurrentPageReference)
    setPage(ref) {
        if (this._override) return;
        let id;
        let obj;
        if (ref && ref.type === 'standard__recordPage') {
            id = ref.attributes && ref.attributes.recordId;
            obj = ref.attributes && ref.attributes.objectApiName;
        } else if (ref && ref.type === 'standard__namedPage' && ref.attributes && ref.attributes.pageName === 'filePreview') {
            id = ref.state && (ref.state.selectedRecordId || ref.state.recordId);
            obj = 'ContentDocument';
        }
        if (id === this.recordId) return;
        this.recordId = id;
        this.objectApiName = obj;
        this.contextLabel = null;
        this.contextOff = false;
        this.showRecent = false;
        if (id) this.loadContextLabel(id);
        this.switchChat();
    }

    async loadContextLabel(id) {
        try {
            const res = await this.call('GET', `/context?recordId=${id}`);
            if (this.recordId === id) {
                this.contextLabel = res.label || (res.object ? `this ${res.object}` : 'this record');
            }
        } catch (e) {
            if (this.recordId === id) this.contextLabel = 'this record';
        }
    }

    get hasContext() {
        return !!this.recordId && !this.contextOff;
    }

    get showContextOff() {
        return !!this.recordId && this.contextOff;
    }

    get currentChatId() {
        return this.hasContext ? this.recordId.slice(0, 15) : 'general';
    }

    get chatTitle() {
        return this.hasContext ? this.contextLabel || 'this record' : 'General chat';
    }

    useContext() {
        this.contextOff = false;
        this.switchChat();
    }

    dropContext() {
        this.contextOff = true;
        this.switchChat();
    }

    switchChat() {
        const next = this.currentChatId;
        if (next === this.chatId && this.loaded) return;
        this.chatId = next;
        this.messages = [];
        this.loaded = false;
        // Um pedido a correr noutra conversa continua no servidor e fica guardado la.
        if (this.busy && this._busyChat !== next) {
            this.busy = false;
            this.progress = '';
        }
        this.loadHistory();
    }

    // ------------------------------------------------------------ lifecycle

    connectedCallback() {
        this._alive = true;
        if (!this.chatId) this.switchChat();
    }

    disconnectedCallback() {
        this._alive = false;
        clearTimeout(this._pollTimer);
    }

    /**
     * As respostas chegam como HTML ja escapado e com estilos embutidos pelo
     * servidor; aqui so se insere, uma vez por mensagem.
     */
    renderedCallback() {
        const byKey = new Map();
        for (const m of this.messages) {
            if (m.html) byKey.set(m.key, m.html);
            for (const c of m.cards) if (c.bodyHtml) byKey.set(c.key, c.bodyHtml);
        }
        this.template.querySelectorAll('[data-html], [data-note]').forEach((el) => {
            const key = el.dataset.html || el.dataset.note;
            const html = byKey.get(key);
            if (html !== undefined && el.dataset.rendered !== key) {
                // eslint-disable-next-line @lwc/lwc/no-inner-html
                el.innerHTML = html;
                el.dataset.rendered = key;
            }
        });
    }

    async loadHistory() {
        const chat = this.chatId;
        const path = chat === 'general' ? '/history' : `/history?recordId=${this.recordId}`;
        try {
            const res = await this.call('GET', path);
            if (chat !== this.chatId) return;
            this.messages = (res.messages || []).map((m) =>
                this.toMessage(m.role, m.text, m.html, {
                    turnId: m.turnId,
                    cards: m.cards,
                    reports: m.reports,
                    notes: m.notes,
                    isError: m.isError,
                }),
            );
        } catch (e) {
            // Sem historico o painel continua a funcionar.
        }
        if (chat === this.chatId) {
            this.loaded = true;
            this.scrollDown();
            if (this.autoPrompt && !this._autoSent && chat !== 'general' && !this.busy && this.messages.length === 0) {
                this._autoSent = true;
                this.setInput(this.autoPrompt);
                this.sendMessage();
            }
        }
    }

    // ------------------------------------------------------------ recent chats

    async toggleRecent() {
        this.showRecent = !this.showRecent;
        if (!this.showRecent) return;
        this.chatsLoading = true;
        try {
            const res = await this.call('GET', '/chats');
            this.chats = (res.chats || []).map((c) => {
                const id = c.recordId || 'general';
                const current = id === this.chatId;
                return {
                    rowKey: c.key,
                    recordId: c.recordId || '',
                    title: c.recordId ? c.label || 'A record' : 'General chat',
                    preview: c.preview,
                    when: this.ago(c.lastAt),
                    cls: current ? 'chat-row chat-row-current' : 'chat-row',
                };
            });
        } catch (e) {
            this.chats = [];
        }
        this.chatsLoading = false;
    }

    get hasChats() {
        return this.chats.length > 0;
    }

    openChat(event) {
        const recordId = event.currentTarget.dataset.record;
        this.showRecent = false;
        if (!recordId) {
            if (this.recordId && !this.contextOff) this.dropContext();
            else this.switchChat();
            return;
        }
        if (this.recordId && this.recordId.slice(0, 15) === recordId.slice(0, 15)) {
            if (this.contextOff) this.useContext();
            return;
        }
        // Abrir o registo muda a pagina, e a pagina muda a conversa.
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId, actionName: 'view' },
        });
    }

    ago(sqlDate) {
        if (!sqlDate) return '';
        const t = Date.parse(sqlDate.replace(' ', 'T') + 'Z');
        const mins = Math.max(0, Math.round((Date.now() - t) / 60000));
        if (mins < 1) return 'just now';
        if (mins < 60) return `${mins}m ago`;
        if (mins < 1440) return `${Math.round(mins / 60)}h ago`;
        const days = Math.round(mins / 1440);
        return days === 1 ? 'yesterday' : `${days} days ago`;
    }

    // ------------------------------------------------------------ transport

    async call(method, path, body) {
        const raw = await send({ method, path, body: body ? JSON.stringify(body) : null });
        let parsed;
        try {
            parsed = JSON.parse(raw || '{}');
        } catch (e) {
            throw new Error('XP AI for Claims sent an unreadable answer.');
        }
        if (parsed && parsed.error && !parsed.status) throw new Error(parsed.error);
        return parsed;
    }

    errorText(e) {
        return (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
    }

    contextPayload() {
        return this.hasContext
            ? { recordId: this.recordId, objectApiName: this.objectApiName, label: this.contextLabel }
            : null;
    }

    // ------------------------------------------------------------ messages

    toMessage(role, text, html, extra = {}) {
        const isUser = role === 'user';
        const reports = extra.reports || [];
        const notes = extra.notes || [];
        return {
            key: nextKey(),
            isUser,
            text: text || '',
            html: html || '',
            cls: isUser ? 'row row-user' : 'row row-bot',
            turnId: extra.turnId || null,
            reports: reports.map((r) => ({
                ...r,
                key: nextKey(),
                isAudio: r.kind === 'audio',
                isFile: r.kind === 'file',
                label: r.label || r.name,
            })),
            hasReports: reports.length > 0,
            notes: notes.map((n) => ({ key: nextKey(), text: n })),
            hasNotes: notes.length > 0,
            cards: (extra.cards || []).map((c) => this.toCard(c)),
            thanked: false,
            bubbleCls: extra.isError ? 'bubble bubble-bot bubble-error' : 'bubble bubble-bot',
            showBubble: isUser || !!(html || text) || !!extra.isError,
        };
    }

    toCard(c) {
        const isDraft = c.type === 'draft';
        // Onde o rascunho pode ir: Reply no e-mail aberto, e-mail da candidatura
        // aberta, ou ir ao e-mail do cliente para responder de la.
        const onEmail = isDraft && same15(this.recordId, c.replyEmailId);
        const onApp = isDraft && !onEmail && same15(this.recordId, c.applicationId);
        return {
            ...c,
            key: nextKey(),
            isDraft,
            showReply: onEmail,
            showOpenEmail: onApp,
            showGoToEmail: isDraft && !onEmail && !onApp && !!c.replyEmailId,
            isNote: c.type === 'note',
            isUpdate: c.type === 'update',
            heading: isDraft ? `Draft for ${c.application}` : c.title,
            confirmLabel: isDraft ? 'Save to Salesforce' : c.confirmLabel,
            lineItems: (c.lines || []).map((l) => ({ key: nextKey(), text: l })),
            status: c.status || '',
            statusUrl: c.statusUrl || null,
            done: !!c.done,
            notDone: !c.done,
            working: false,
            copied: false,
            statusCls: c.status ? (c.statusOk ? 'status status-ok' : 'status') : 'status',
        };
    }

    get isEmpty() {
        return this.loaded && this.messages.length === 0 && !this.busy;
    }

    get isLoading() {
        return !this.loaded;
    }

    get suggestions() {
        const list = this.hasContext
            ? [
                  'Summarise this and tell me what is pending',
                  'Write a reply to the latest email from this client',
                  'Explain the timeline of recent comms, outcomes and next steps',
                  'What does the latest HMRC check say?',
              ]
            : [
                  'Status of A13452',
                  'Find a client by name, email, phone or NI number',
                  'How many calls did each of us make this week?',
                  'What can you do?',
              ];
        return list.map((t) => ({ key: nextKey(), text: t }));
    }

    pickSuggestion(event) {
        const text = event.currentTarget.dataset.text;
        if (text === 'Find a client by name, email, phone or NI number') {
            this.setInput('Find ');
            this.focusInput();
            return;
        }
        this.setInput(text);
        this.sendMessage();
    }

    // ------------------------------------------------------------ input

    handleInput(event) {
        this.draft = event.target.value;
    }

    handleKey(event) {
        if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.sendMessage();
        }
    }

    /** O textarea nativo nao segue value={draft} depois de escrito; acerta-se a mao. */
    setInput(value) {
        this.draft = value;
        const el = this.template.querySelector('textarea.input');
        if (el) el.value = value;
    }

    focusInput() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const el = this.template.querySelector('textarea.input');
            if (el) el.focus();
        }, 0);
    }

    get sendDisabled() {
        return this.busy || (!this.draft.trim() && this.files.length === 0);
    }

    get hasFiles() {
        return this.files.length > 0;
    }

    openFilePicker() {
        const input = this.template.querySelector('input[type="file"]');
        if (input) input.click();
    }

    handleFiles(event) {
        const picked = Array.from(event.target.files || []);
        event.target.value = '';
        for (const f of picked) this.addFile(f);
    }

    /** Ctrl+V de um print ou imagem copiada: vira anexo; texto colado segue normal. */
    handlePaste(event) {
        const items = Array.from((event.clipboardData && event.clipboardData.items) || []);
        const files = items.filter((i) => i.kind === 'file').map((i) => i.getAsFile()).filter(Boolean);
        if (!files.length) return;
        event.preventDefault();
        files.forEach((f, i) => {
            const isImage = f.type.startsWith('image/');
            const stamp = new Date().toTimeString().slice(0, 8).replace(/:/g, '');
            const generic = !f.name || /^image\.(png|jpe?g|gif|webp)$/i.test(f.name);
            this.addFile(f, isImage && generic ? `screenshot-${stamp}${files.length > 1 ? `-${i + 1}` : ''}.png` : f.name);
        });
    }

    handleDragOver(event) {
        if (!Array.from((event.dataTransfer && event.dataTransfer.types) || []).includes('Files')) return;
        event.preventDefault();
        this.dragging = true;
    }

    handleDragLeave(event) {
        // So sai do estado quando o rato deixa o painel, nao ao passar entre elementos de dentro.
        if (event.currentTarget.contains(event.relatedTarget)) return;
        this.dragging = false;
    }

    handleDrop(event) {
        const files = Array.from((event.dataTransfer && event.dataTransfer.files) || []);
        this.dragging = false;
        if (!files.length) return;
        event.preventDefault();
        files.forEach((f) => this.addFile(f));
    }

    get rootClass() {
        return this.dragging ? 'xp dragging' : 'xp';
    }

    /** Valida, reduz fotos grandes e junta ao envio (botao, colar e arrastar passam por aqui). */
    async addFile(f, name = f.name) {
        const label = name || 'file';
        if (this.files.length >= MAX_FILES) {
            this.pushError(`Up to ${MAX_FILES} files per message. "${label}" was not added.`);
            return;
        }
        if (!FILE_TYPES.includes(f.type)) {
            this.pushError(`I can't read "${label}". Send it as a PDF, PNG or JPG.`);
            return;
        }
        let entry;
        try {
            if (f.type === 'application/pdf' || f.type === 'image/gif') {
                if (f.size > MAX_FILE_BYTES) {
                    this.pushError(`"${label}" is over 3 MB. Attach it on the record and ask me to read it from there.`);
                    return;
                }
                entry = { name: label, mime: f.type, base64: (await readAsDataUrl(f)).split(',')[1] || '', resized: false };
            } else {
                if (f.size > IMAGE_RAW_MAX_BYTES) {
                    this.pushError(`"${label}" is over 25 MB. Send a smaller photo or a screenshot.`);
                    return;
                }
                entry = await this.prepareImage(f, label);
            }
        } catch (e) {
            this.pushError(`Could not read "${label}": ${(e && e.message) || e}`);
            return;
        }
        const total = this.files.reduce((s, x) => s + x.base64.length, 0) + entry.base64.length;
        if (total > TOTAL_MAX_BASE64) {
            this.pushError(`"${label}" would make this message too big to send. Send it in the next message.`);
            return;
        }
        this.files = [...this.files, { key: nextKey(), ...entry, isImage: entry.mime.startsWith('image/') }];
    }

    /** Imagem pequena vai como esta; grande e reduzida para JPEG (lado maior 2000 px, ~1 MB). */
    async prepareImage(f, name) {
        const url = await readAsDataUrl(f);
        const img = await loadImage(url);
        const w0 = img.naturalWidth || img.width;
        const h0 = img.naturalHeight || img.height;
        const scale = Math.min(1, IMAGE_MAX_SIDE / Math.max(w0, h0));
        if (scale === 1 && f.size <= IMAGE_TARGET_BYTES) {
            return { name, mime: f.type, base64: url.split(',')[1] || '', resized: false };
        }
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(w0 * scale);
        canvas.height = Math.round(h0 * scale);
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#fff'; // fundo branco: o JPEG nao tem transparencia
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        let quality = 0.85;
        let out = canvas.toDataURL('image/jpeg', quality);
        while (out.length * 0.75 > IMAGE_TARGET_BYTES && quality > 0.5) {
            quality -= 0.15;
            out = canvas.toDataURL('image/jpeg', quality);
        }
        return { name: name.replace(/\.(png|jpe?g|webp)$/i, '') + '.jpg', mime: 'image/jpeg', base64: out.split(',')[1] || '', resized: true };
    }

    removeFile(event) {
        const key = event.currentTarget.dataset.key;
        this.files = this.files.filter((f) => f.key !== key);
    }

    // ------------------------------------------------------------ turns

    async sendMessage() {
        const text = this.draft.trim();
        if (this.busy || (!text && this.files.length === 0)) return;
        const files = this.files.map((f) => ({ name: f.name, mime: f.mime, base64: f.base64 }));
        const label = text || `(${files.map((f) => f.name).join(', ')})`;
        this.messages = [...this.messages, this.toMessage('user', label)];
        this.setInput('');
        this.files = [];
        this.showRecent = false;
        this.scrollDown();

        const chat = this.chatId;
        this.startBusy('Looking that up');
        try {
            const res = await this.call('POST', '/turn', { text, files, context: this.contextPayload() });
            if (res.status === 'done') {
                if (res.reset) {
                    this.stopBusy();
                    this.messages = [];
                    return;
                }
                this.finish(res.result, chat);
                return;
            }
            this.poll(res.jobId, chat);
        } catch (e) {
            this.stopBusy();
            this.pushError(this.errorText(e));
        }
    }

    startBusy(label) {
        this.busy = true;
        this._busyChat = this.chatId;
        this.progress = label;
        this.elapsed = 0;
        this._started = Date.now();
        this.scrollDown();
    }

    stopBusy() {
        this.busy = false;
        this.progress = '';
    }

    poll(jobId, chat) {
        clearTimeout(this._pollTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollTimer = setTimeout(async () => {
            if (!this._alive) return;
            try {
                const res = await this.call('GET', `/turn/${jobId}`);
                if (res.status === 'running') {
                    if (chat === this.chatId) {
                        this.progress = res.progress || this.progress;
                        this.elapsed = Math.round((Date.now() - this._started) / 1000);
                    }
                    this.poll(jobId, chat);
                    return;
                }
                if (chat !== this.chatId) return; // fica guardado na conversa dele
                if (res.status === 'error') {
                    this.stopBusy();
                    this.pushError(res.error || 'Something went wrong. Try again.');
                    return;
                }
                this.finish(res.result, chat);
            } catch (e) {
                if (chat !== this.chatId) return;
                this.stopBusy();
                this.pushError(this.errorText(e));
            }
        }, POLL_MS);
    }

    finish(result, chat) {
        if (chat && chat !== this.chatId) return;
        this.stopBusy();
        if (!result) return;
        this.messages = [
            ...this.messages,
            this.toMessage('assistant', result.text, result.html, {
                turnId: result.turnId,
                cards: result.cards,
                reports: result.reports,
                notes: result.notes,
            }),
        ];
        this.scrollDown();
    }

    pushError(text) {
        this.messages = [...this.messages, this.toMessage('assistant', text, null, { isError: true })];
        this.scrollDown();
    }

    async newChat() {
        if (this.busy) return;
        this.showRecent = false;
        try {
            await this.call('POST', '/reset', { recordId: this.hasContext ? this.recordId : null });
        } catch (e) {
            // mesmo que falhe, o ecra limpa
        }
        this.messages = [];
    }

    // ------------------------------------------------------------ cards

    findCard(key) {
        for (const m of this.messages) {
            const c = m.cards.find((x) => x.key === key);
            if (c) return c;
        }
        return null;
    }

    updateCard(key, patch) {
        this.messages = this.messages.map((m) => ({
            ...m,
            cards: m.cards.map((c) => {
                if (c.key !== key) return c;
                const merged = { ...c, ...patch };
                merged.notDone = !merged.done;
                return merged;
            }),
        }));
    }

    async confirmCard(event) {
        const key = event.currentTarget.dataset.key;
        const card = this.findCard(key);
        if (!card || card.working || card.done) return;
        this.updateCard(key, { working: true, status: card.isDraft ? 'Saving…' : 'Writing to Salesforce…', statusCls: 'status' });
        try {
            const path = card.isDraft ? `/draft/${card.id}/save` : `/action/${card.id}/confirm`;
            const res = await this.call('POST', path);
            const ok = res.status === 'done' || res.status === 'already';
            const final = ok || ['conflict', 'missing', 'cancelled'].includes(res.status);
            this.updateCard(key, {
                working: false,
                done: final,
                status: res.message,
                statusUrl: res.url || null,
                statusCls: ok ? 'status status-ok' : 'status status-warn',
            });
            if (res.status === 'done' && res.recordId) this.refreshRecord(res.recordId);
        } catch (e) {
            this.updateCard(key, { working: false, status: this.errorText(e), statusCls: 'status status-warn' });
        }
    }

    /**
     * Abre o Send Email do Salesforce preenchido como um Reply: To, Cc (Reply All),
     * "Re:" e a mensagem original citada por baixo do rascunho.
     * O Reply nativo do EmailMessage nao aceita texto por codigo (fica num spinner
     * sem fim), por isso usa-se o Send Email padrao, ligado a candidatura.
     */
    openComposer(event) {
        const key = event.currentTarget.dataset.key;
        const how = event.currentTarget.dataset.how;
        const card = this.findCard(key);
        if (!card) return;
        const fields = {
            // Mesmo remetente que o Simple_Email da equipa usa.
            ValidatedFromAddress: 'clients@xtrapension.com',
            HtmlBody: draftToHtml(card.body) + (card.quoteHtml || ''),
            Subject: card.replySubject || card.subject || '',
        };
        if (card.toAddress) fields.ToAddress = card.toAddress;
        if (how === 'replyall' && card.ccAddress) fields.CcAddress = card.ccAddress;
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: { apiName: 'Global.SendEmail' },
            state: { recordId: card.applicationId, defaultFieldValues: encodeDefaultFieldValues(fields) },
        });
        this.updateCard(key, { status: 'Opened in the email composer. Check it and press Send there.', statusCls: 'status status-ok' });
        // Dentro do AI Reply a janela fecha, mas so depois de o composer abrir.
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.dispatchEvent(new CustomEvent('composeropened', { bubbles: true, composed: true }));
        }, 1500);
    }

    goToEmail(event) {
        const card = this.findCard(event.currentTarget.dataset.key);
        if (!card || !card.replyEmailId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: card.replyEmailId, objectApiName: 'EmailMessage', actionName: 'view' },
        });
    }

    async discardCard(event) {
        const key = event.currentTarget.dataset.key;
        const card = this.findCard(key);
        if (!card || card.working || card.done) return;
        try {
            const res = await this.call('POST', `/action/${card.id}/cancel`);
            this.updateCard(key, { done: true, status: res.message, statusCls: 'status' });
        } catch (e) {
            this.updateCard(key, { status: this.errorText(e), statusCls: 'status status-warn' });
        }
    }

    async refineCard(event) {
        const key = event.currentTarget.dataset.key;
        const kind = event.currentTarget.dataset.kind;
        const card = this.findCard(key);
        if (!card || this.busy) return;
        this.updateCard(key, { done: true, status: `${REFINE_LABEL[kind]} version requested.`, statusCls: 'status' });
        this.messages = [...this.messages, this.toMessage('user', `${REFINE_LABEL[kind]} version, please.`)];
        const chat = this.chatId;
        this.startBusy(REFINE_PROGRESS[kind]);
        try {
            const res = await this.call('POST', `/draft/${card.id}/${kind}`, { context: this.contextPayload() });
            if (res.jobId) this.poll(res.jobId, chat);
            else {
                this.stopBusy();
                this.pushError(res.message || 'This draft is too old to act on.');
            }
        } catch (e) {
            this.stopBusy();
            this.pushError(this.errorText(e));
        }
    }

    async copyCard(event) {
        const key = event.currentTarget.dataset.key;
        const card = this.findCard(key);
        if (!card) return;
        const text = card.isDraft
            ? `${card.subject ? `Subject: ${card.subject}\n\n` : ''}${card.body}`
            : card.body || (card.lines || []).join('\n');
        let ok = false;
        try {
            await navigator.clipboard.writeText(card.isDraft ? card.body : text);
            ok = true;
        } catch (e) {
            const area = this.template.querySelector(`textarea[data-copy="${key}"]`);
            if (area) {
                area.value = card.isDraft ? card.body : text;
                area.select();
                // eslint-disable-next-line @lwc/lwc/no-document-query
                ok = !!(document.execCommand && document.execCommand('copy'));
            }
        }
        this.updateCard(key, { copied: ok });
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => this.updateCard(key, { copied: false }), 1800);
    }

    refreshRecord(recordId) {
        try {
            notifyRecordUpdateAvailable([{ recordId }]);
        } catch (e) {
            // sem refresh, o registo actualiza no proximo carregamento
        }
        try {
            this.dispatchEvent(new RefreshEvent());
        } catch (e) {
            // idem
        }
    }

    // ------------------------------------------------------------ feedback

    async rate(event) {
        const key = event.currentTarget.dataset.key;
        const value = event.currentTarget.dataset.value;
        const msg = this.messages.find((m) => m.key === key);
        if (!msg || !msg.turnId || msg.thanked) return;
        this.messages = this.messages.map((m) => (m.key === key ? { ...m, thanked: true } : m));
        try {
            await this.call('POST', '/feedback', { turnId: msg.turnId, value });
        } catch (e) {
            // feedback nunca atrapalha
        }
    }

    // ------------------------------------------------------------ ui

    scrollDown() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const el = this.template.querySelector('.msgs');
            if (el) el.scrollTop = el.scrollHeight;
        }, 30);
    }
}
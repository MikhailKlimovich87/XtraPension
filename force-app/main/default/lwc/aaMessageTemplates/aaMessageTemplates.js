import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listTemplates from '@salesforce/apex/AA_MessageTemplateController.listTemplates';
import getMergeSchema from '@salesforce/apex/AA_MessageTemplateController.getMergeSchema';
import getTriggerEvents from '@salesforce/apex/AA_MessageTemplateController.getTriggerEvents';
import getMolds from '@salesforce/apex/AA_MessageTemplateController.getMolds';
import saveTemplate from '@salesforce/apex/AA_MessageTemplateController.saveTemplate';
import deleteTemplate from '@salesforce/apex/AA_MessageTemplateController.deleteTemplate';
import duplicateTemplate from '@salesforce/apex/AA_MessageTemplateController.duplicateTemplate';
import renderPreview from '@salesforce/apex/AA_MessageTemplateController.renderPreview';
import listSendLogs from '@salesforce/apex/AA_MessageTemplateController.listSendLogs';

const TOKEN_RE = /\{\{\s*([^}\s]+)\s*\}\}/g;

export default class AaMessageTemplates extends LightningElement {
    // ── tab state ───────────────────────────────────────────────
    activeTab = 'templates';

    // ── list state ──────────────────────────────────────────────
    rows = [];
    loading = true;
    saving = false;
    wired;

    // ── filters ─────────────────────────────────────────────────
    filterChannel = 'All';
    filterTrigger = 'All';
    filterActive = false;      // "Active only" checkbox
    filterSearch = '';         // Name substring

    // ── merge schema (palette + validator) ──────────────────────
    schema = [];
    allowedTokens = new Set();
    chipGroups = [];

    // ── trigger events ──────────────────────────────────────────
    triggerEventOptions = [];   // for Add modal (API values)
    triggerFilterOptions = [{ label: 'All triggers', value: 'All' }];
    triggerLabelByValue = {};

    // ── molds ("Start from template" picker) ────────────────────
    molds = [];
    moldOptions = [];
    selectedMold = 'blank';

    // ── edit modal state ────────────────────────────────────────
    showEdit = false;
    editing = null;
    subjectErrors = [];
    bodyErrors = [];
    lastFocus = 'content';

    // ── preview modal state ─────────────────────────────────────
    showPreview = false;
    previewTemplateId = null;
    previewAppId = '';
    previewLoading = false;
    previewResult = null;

    // ── send-log state ──────────────────────────────────────────
    logRows = [];
    logTotal = 0;
    logPageIndex = 0;
    logPageSize = 50;
    logLoading = false;
    logFilterFrom = null;
    logFilterTo = null;
    logFilterTemplate = '';
    logFilterStatus = 'All';

    channelOptions = [
        { label: 'Email', value: 'Email' },
        { label: 'SMS',   value: 'SMS' }
    ];
    channelFilterOptions = [
        { label: 'All channels', value: 'All' },
        { label: 'Email',        value: 'Email' },
        { label: 'SMS',          value: 'SMS' }
    ];
    contentModeOptions = [
        { label: 'Simple (plain text, auto-wrapped)', value: 'Simple' },
        { label: 'Advanced (raw HTML)',                value: 'Advanced' }
    ];
    statusFilterOptions = [
        { label: 'All statuses', value: 'All' },
        { label: 'Sent',         value: 'Sent' },
        { label: 'Failed',       value: 'Failed' },
        { label: 'Skipped-Deduped', value: 'Skipped-Deduped' },
        // Every skip the dispatcher writes (AA_MessageDispatcher.skipStatus):
        // held for a missing PDF, Do Not Contact, SMS STOP, stage gate. Until a
        // value is active in the org the dispatcher logs 'Failed' + "Suppressed:".
        { label: 'Skipped-Missing-Attachment', value: 'Skipped-Missing-Attachment' },
        { label: 'Skipped-Do-Not-Contact',     value: 'Skipped-Do-Not-Contact' },
        { label: 'Skipped-SMS-Opt-Out',        value: 'Skipped-SMS-Opt-Out' },
        { label: 'Skipped-Stage-Gate',         value: 'Skipped-Stage-Gate' }
    ];

    // ═══════════════════════════ WIRES ═══════════════════════════

    @wire(listTemplates)
    handleList(res) {
        this.wired = res;
        if (res.data) {
            this.rows = this.decorate(res.data);
            this.loading = false;
        } else if (res.error) {
            this.loading = false;
            this.toast('Load failed', 'error', this.errMsg(res.error));
        }
    }

    @wire(getMergeSchema)
    handleSchema({ data, error }) {
        if (data) {
            this.schema = data;
            this.allowedTokens = new Set(
                data.map((m) => m.token.replace(/^\{\{|\}\}$/g, ''))
            );
            const groups = {};
            for (const m of data) {
                if (!groups[m.category]) groups[m.category] = [];
                groups[m.category].push(m);
            }
            this.chipGroups = Object.keys(groups).map((cat) => ({
                category: cat,
                chips: groups[cat]
            }));
        } else if (error) {
            this.toast('Merge palette failed', 'error', this.errMsg(error));
        }
    }

    @wire(getTriggerEvents)
    handleTriggers({ data, error }) {
        if (data) {
            this.triggerEventOptions = data.map((t) => ({
                label: t.label, value: t.value
            }));
            this.triggerFilterOptions = [
                { label: 'All triggers', value: 'All' },
                ...this.triggerEventOptions
            ];
            const map = {};
            for (const t of data) map[t.value] = t.label;
            this.triggerLabelByValue = map;
        } else if (error) {
            this.toast('Trigger list failed', 'error', this.errMsg(error));
        }
    }

    @wire(getMolds)
    handleMolds({ data, error }) {
        if (data) {
            this.molds = data;
            this.moldOptions = data.map((m) => ({ label: m.label, value: m.key }));
        } else if (error) {
            this.toast('Mold list failed', 'error', this.errMsg(error));
        }
    }

    // ═══════════════════════ DECORATION / FILTER ═════════════════

    decorate(rows) {
        return rows.map((r) => ({
            ...r,
            channelIcon: r.channel === 'Email' ? 'utility:email' : 'utility:sms',
            channelEmoji: r.channel === 'Email' ? '\u{1F4E7}' : '\u{1F4F1}',
            channelCls: r.channel === 'Email' ? 'aa-mt__chan aa-mt__chan--email'
                                              : 'aa-mt__chan aa-mt__chan--sms',
            activeBadgeCls: r.active
                ? 'slds-badge slds-theme_success'
                : 'slds-badge slds-theme_warning',
            activeLabel: r.active ? 'Active' : 'Inactive',
            triggerDisplay: r.triggerEventLabel || r.triggerEvent,
            lastModifiedDisplay: r.lastModifiedDate
                ? new Date(r.lastModifiedDate).toLocaleString('en-GB', {
                    year: 'numeric', month: 'short', day: '2-digit',
                    hour: '2-digit', minute: '2-digit'
                })
                : '-'
        }));
    }

    get filteredRows() {
        const q = this.filterSearch.trim().toLowerCase();
        return this.rows.filter((r) => {
            if (this.filterChannel !== 'All' && r.channel !== this.filterChannel) return false;
            if (this.filterTrigger !== 'All' && r.triggerEvent !== this.filterTrigger) return false;
            if (this.filterActive && !r.active) return false;
            if (q && !(r.name || '').toLowerCase().includes(q)) return false;
            return true;
        });
    }

    get isEmpty() { return !this.loading && this.filteredRows.length === 0; }
    get showTable() { return !this.loading && this.filteredRows.length > 0; }
    get filteredCountLabel() {
        return `${this.filteredRows.length} of ${this.rows.length}`;
    }

    // ═══════════════════════ TAB HANDLING ════════════════════════

    handleTabActive(e) {
        this.activeTab = e.target.value;
        if (this.activeTab === 'sendlog' && this.logRows.length === 0 && !this.logLoading) {
            this.refreshLogs();
        }
    }

    // ═══════════════════════ FILTER HANDLERS ═════════════════════

    handleFilterChannel(e) { this.filterChannel = e.detail.value; }
    handleFilterTrigger(e) { this.filterTrigger = e.detail.value; }
    handleFilterActive(e)  { this.filterActive = e.target.checked; }
    handleFilterSearch(e)  { this.filterSearch = e.target.value || ''; }
    handleClearFilters() {
        this.filterChannel = 'All';
        this.filterTrigger = 'All';
        this.filterActive = false;
        this.filterSearch = '';
        const s = this.template.querySelector('lightning-input[data-role="search"]');
        if (s) s.value = '';
    }

    // ═══════════════════════ ROW ACTIONS ═════════════════════════

    handleAdd() {
        this.selectedMold = 'blank';
        this.editing = this.editingFromMold('blank');
        this.subjectErrors = [];
        this.bodyErrors = [];
        this.lastFocus = 'content';
        this.showEdit = true;
    }

    editingFromMold(key) {
        const mold = this.molds.find((m) => m.key === key)
            || { channel: 'Email', triggerEvent: 'Custom_Manual', contentMode: 'Simple',
                 subjectTemplate: '', contentText: '', bodyTemplate: '' };
        return {
            id: null,
            name: '',
            channel: mold.channel || 'Email',
            triggerEvent: mold.triggerEvent || 'Custom_Manual',
            contentMode: mold.contentMode || 'Simple',
            subjectTemplate: mold.subjectTemplate || '',
            contentText: mold.contentText || '',
            bodyTemplate: mold.bodyTemplate || '',
            attachmentStaticResourceName: '',
            active: false,
            language: 'en-GB'
        };
    }

    handleMoldChange(e) {
        this.selectedMold = e.detail.value;
        // Preserve any Name the user typed
        const prevName = this.editing?.name || '';
        this.editing = { ...this.editingFromMold(this.selectedMold), name: prevName };
        this.revalidate();
    }

    handleEdit(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.id === id);
        if (!row) return;
        // Legacy Content_Text__c rows can be plain text with **markdown**.
        // The rich text editor shows that as literal `**bold**` — jarring.
        // Convert md→HTML on load so the widget renders the intended bold/italic/paragraphs.
        // On save, widget emits HTML which server accepts (looksLikeHtml branch).
        const rawContent = row.contentText || '';
        const contentForEditor = this.looksLikeHtml(rawContent) ? rawContent : this.mdToHtml(rawContent);
        this.editing = {
            id: row.id,
            name: row.name,
            channel: row.channel,
            triggerEvent: row.triggerEvent,
            contentMode: row.contentMode || 'Simple',
            subjectTemplate: row.subjectTemplate || '',
            contentText: contentForEditor,
            bodyTemplate: row.bodyTemplate || '',
            attachmentStaticResourceName: row.attachmentStaticResourceName || '',
            active: row.active,
            language: row.language || 'en-GB'
        };
        this.selectedMold = 'blank';
        this.revalidate();
        this.showEdit = true;
    }

    /** Mirror of AA_EmailShellRenderer.looksLikeHtml (JS side). */
    looksLikeHtml(s) {
        if (!s) return false;
        return /<[a-zA-Z][a-zA-Z0-9]*[\s/>]/.test(s);
    }

    /**
     * Mirror of AA_EmailShellRenderer.simpleToHtml minus the HTML-escape step
     * (rich text editor will re-escape on input). Converts **bold** / *italic*
     * + newlines to <p><br> so legacy templates open WYSIWYG-correct.
     */
    mdToHtml(src) {
        if (!src) return '';
        let s = src.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
        s = s.replace(/\*\*([^*\n]+)\*\*/g, '<strong>$1</strong>');
        s = s.replace(/(^|[^*])\*([^*\n]+)\*(?!\*)/g, '$1<em>$2</em>');
        const paras = s.split(/\n{2,}/).filter(p => p.trim());
        return paras.map(p => '<p>' + p.replace(/\n/g, '<br/>') + '</p>').join('');
    }

    async handleDuplicate(e) {
        const id = e.currentTarget.dataset.id;
        this.saving = true;
        try {
            await duplicateTemplate({ templateId: id });
            this.toast('Duplicated', 'success', 'Draft copy created (inactive).');
            await refreshApex(this.wired);
        } catch (err) {
            this.toast('Duplicate failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    async handleDelete(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.id === id);
        if (!row) return;
        // eslint-disable-next-line no-alert
        if (!confirm(`Delete template "${row.name}"? This can't be undone.`)) return;
        this.saving = true;
        try {
            await deleteTemplate({ templateId: id });
            this.toast('Deleted', 'success', `Removed ${row.name}.`);
            await refreshApex(this.wired);
        } catch (err) {
            this.toast('Delete failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    async handleToggleActive(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.id === id);
        if (!row) return;
        this.saving = true;
        try {
            await saveTemplate({
                template: {
                    id: row.id,
                    name: row.name,
                    channel: row.channel,
                    triggerEvent: row.triggerEvent,
                    contentMode: row.contentMode || 'Simple',
                    subjectTemplate: row.subjectTemplate,
                    contentText: row.contentText,
                    bodyTemplate: row.bodyTemplate,
                    attachmentStaticResourceName: row.attachmentStaticResourceName,
                    active: !row.active,
                    language: row.language
                }
            });
            await refreshApex(this.wired);
        } catch (err) {
            this.toast('Toggle failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    // ═══════════════════════ MODAL FIELDS ════════════════════════

    handleName(e)         { this.editing = { ...this.editing, name: e.target.value }; }
    handleChannel(e)      { this.editing = { ...this.editing, channel: e.detail.value };
                             // SMS forced to Simple + no HTML shell
                             if (e.detail.value === 'SMS') {
                                 this.editing.contentMode = 'Simple';
                             }
                             this.revalidate(); }
    handleTrigger(e)      { this.editing = { ...this.editing, triggerEvent: e.detail.value }; }
    handleContentMode(e)  { this.editing = { ...this.editing, contentMode: e.detail.value };
                             this.revalidate(); }
    handleActive(e)       { this.editing = { ...this.editing, active: e.target.checked }; }
    handleAttachment(e)   { this.editing = { ...this.editing, attachmentStaticResourceName: e.target.value }; }

    handleSubject(e) {
        this.editing = { ...this.editing, subjectTemplate: e.target.value };
        this.subjectErrors = this.badTokens(this.editing.subjectTemplate);
    }

    /**
     * Rich text handler — the `<lightning-input-rich-text>` widget emits
     * HTML on change. Store as-is; server-side EmailShellRenderer detects
     * HTML vs legacy markdown at render time (see AA_EmailShellRenderer.
     * simpleToHtml — 2026-08-25 rich text migration).
     */
    handleRichContent(e) {
        const html = e.detail && e.detail.value ? e.detail.value : (e.target && e.target.value) || '';
        this.editing = { ...this.editing, contentText: html };
        this.bodyErrors = this.badTokens(this.editing.contentText);
    }

    handleContentText(e) {
        this.editing = { ...this.editing, contentText: e.target.value };
        this.bodyErrors = this.badTokens(this.editing.contentText);
    }

    handleBodyHtml(e) {
        this.editing = { ...this.editing, bodyTemplate: e.target.value };
        this.bodyErrors = this.badTokens(this.editing.bodyTemplate);
    }

    handleFocusSubject() { this.lastFocus = 'subject'; }
    handleFocusContent() { this.lastFocus = 'content'; }
    handleFocusBodyHtml() { this.lastFocus = 'bodyhtml'; }

    // ═══════════════════════ VALIDATION ══════════════════════════

    badTokens(src) {
        if (!src) return [];
        const bad = new Set();
        const it = src.matchAll(TOKEN_RE);
        for (const m of it) {
            if (m[1] === '__CONTENT__') continue;
            if (!this.allowedTokens.has(m[1])) bad.add(m[1]);
        }
        return Array.from(bad);
    }

    revalidate() {
        this.subjectErrors = this.badTokens(this.editing?.subjectTemplate);
        this.bodyErrors = this.isSimpleMode
            ? this.badTokens(this.editing?.contentText)
            : this.badTokens(this.editing?.bodyTemplate);
    }

    get isEmail() { return this.editing?.channel === 'Email'; }
    get isSimpleMode() { return (this.editing?.contentMode || 'Simple') === 'Simple'; }
    get isAdvancedMode() { return !this.isSimpleMode; }

    /**
     * Toolbar palette for the Simple-mode `<lightning-input-rich-text>`.
     * Deliberately narrow: font/color/size/background are OFF so pasted
     * content stays clean and email clients render consistently. The
     * XtraPension email shell (AA_Email_Shell static resource) supplies
     * the base typography — templates only need semantic structure.
     */
    get richTextFormats() {
        return ['bold','italic','underline','strike','list','indent','align','link','header','clean','removeformat'];
    }
    get showModeToggle() { return this.isEmail; }  // SMS is always simple
    get subjectDisabled() { return !this.isEmail; }
    get bodyErrorLine() {
        if (!this.bodyErrors.length) return '';
        const label = this.isSimpleMode ? 'Content' : 'Body HTML';
        return `Unknown tokens in ${label}: ` + this.bodyErrors.map((t) => `{{${t}}}`).join(', ');
    }
    get subjectErrorLine() {
        if (!this.subjectErrors.length) return '';
        return 'Unknown tokens in Subject: ' + this.subjectErrors.map((t) => `{{${t}}}`).join(', ');
    }
    get saveDisabled() {
        if (this.saving) return true;
        if (!this.editing) return true;
        if (this.isEmail && (!this.editing.subjectTemplate || !this.editing.subjectTemplate.trim())) return true;
        if (this.isSimpleMode && (!this.editing.contentText || !this.editing.contentText.trim())) return true;
        if (this.isAdvancedMode && (!this.editing.bodyTemplate || !this.editing.bodyTemplate.trim())) return true;
        if (this.bodyErrors.length) return true;
        if (this.isEmail && this.subjectErrors.length) return true;
        return false;
    }
    get contentTextareaCls() {
        return this.bodyErrors.length
            ? 'aa-mt__body aa-mt__body--err'
            : 'aa-mt__body';
    }
    get subjectInputCls() {
        return this.subjectErrors.length
            ? 'slds-input aa-mt__subject aa-mt__subject--err'
            : 'slds-input aa-mt__subject';
    }

    // ═══════════════════════ TOKEN PALETTE ═══════════════════════

    handleInsertToken(e) {
        const token = e.currentTarget.dataset.token;
        // Which text area is the palette going to inject into?
        let target;
        if (this.lastFocus === 'subject' && this.isEmail) target = 'subject';
        else if (this.lastFocus === 'bodyhtml' && this.isAdvancedMode) target = 'bodyhtml';
        else target = 'content';

        const selector = target === 'subject'
            ? 'input[data-role="subject"]'
            : target === 'bodyhtml'
                ? 'textarea[data-role="bodyhtml"]'
                : 'textarea[data-role="content"]';
        const el = this.template.querySelector(selector);

        const applyToState = (nextVal) => {
            if (target === 'subject') {
                this.editing = { ...this.editing, subjectTemplate: nextVal };
                this.subjectErrors = this.badTokens(nextVal);
            } else if (target === 'bodyhtml') {
                this.editing = { ...this.editing, bodyTemplate: nextVal };
                this.bodyErrors = this.badTokens(nextVal);
            } else {
                this.editing = { ...this.editing, contentText: nextVal };
                this.bodyErrors = this.badTokens(nextVal);
            }
        };

        if (!el) {
            const current = target === 'subject' ? (this.editing.subjectTemplate || '')
                : target === 'bodyhtml' ? (this.editing.bodyTemplate || '')
                : (this.editing.contentText || '');
            applyToState(current + token);
            return;
        }
        const start = el.selectionStart ?? el.value.length;
        const end = el.selectionEnd ?? el.value.length;
        const val = el.value;
        const next = val.slice(0, start) + token + val.slice(end);
        el.value = next;
        applyToState(next);
        Promise.resolve().then(() => {
            el.focus();
            const pos = start + token.length;
            try { el.setSelectionRange(pos, pos); } catch (_) { /* input types w/o selection */ }
        });
    }

    // ═══════════════════════ KEYBOARD ════════════════════════════

    handleModalKeydown(e) {
        if (e.key === 'Escape') {
            e.stopPropagation();
            this.handleCloseEdit();
        } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') {
            e.preventDefault();
            if (!this.saveDisabled) this.handleSave();
        }
    }

    handlePreviewKeydown(e) {
        if (e.key === 'Escape') {
            e.stopPropagation();
            this.handleClosePreview();
        }
    }

    // ═══════════════════════ SAVE ════════════════════════════════

    handleCloseEdit() { this.showEdit = false; }

    async handleSave() {
        if (this.saveDisabled) return;
        this.saving = true;
        try {
            await saveTemplate({ template: this.editing });
            this.toast('Saved', 'success', 'Template saved.');
            this.showEdit = false;
            await refreshApex(this.wired);
        } catch (err) {
            this.toast('Save failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    // ═══════════════════════ PREVIEW ═════════════════════════════

    handleOpenPreview(e) {
        this.previewTemplateId = e.currentTarget.dataset.id;
        this.previewAppId = '';
        this.previewResult = null;
        this.showPreview = true;
    }

    handleClosePreview() {
        this.showPreview = false;
        this.previewResult = null;
    }

    handlePreviewApp(e) { this.previewAppId = e.detail?.recordId || e.target.value || ''; }
    handlePreviewAppInput(e) { this.previewAppId = e.target.value; }

    async handleRunPreview() {
        if (!this.previewAppId) {
            this.toast('Pick a sample', 'error', 'Enter a AA Application Id to preview against.');
            return;
        }
        this.previewLoading = true;
        try {
            this.previewResult = await renderPreview({
                templateId: this.previewTemplateId,
                appId: this.previewAppId
            });
        } catch (err) {
            this.toast('Preview failed', 'error', this.errMsg(err));
        } finally { this.previewLoading = false; }
    }

    get previewTemplate() {
        return this.rows.find((r) => r.id === this.previewTemplateId) || {};
    }
    get previewIsEmail() {
        return this.previewTemplate.channel === 'Email';
    }
    get hasPreviewResult() { return !!this.previewResult; }

    /**
     * 2026-08-25 preview fidelity (Fernando): render the FULL rendered
     * email body inside an iframe so it looks exactly like what the client
     * receives — inline styles, tables, XtraPension email shell colors,
     * everything. Data-URL avoids storing a temporary file. If body is
     * huge (>2MB after base64) the data-URL might exceed browser limits;
     * fall back to a plain text pre-block in that case.
     */
    get previewBodyDataUrl() {
        const html = this.previewResult && this.previewResult.body || '';
        if (!html) return '';
        // If it's not already a full document, wrap in a minimal HTML5
        // scaffold so email-client rendering (which does the same wrap)
        // is approximated. Set base target=_blank so links open in a new tab.
        const isFullDoc = /<html[\s>]/i.test(html);
        const wrapped = isFullDoc ? html : (
            '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
            '<meta name="viewport" content="width=device-width,initial-scale=1">' +
            '<base target="_blank">' +
            '<style>body{margin:0;padding:16px;font-family:Helvetica,Arial,sans-serif;font-size:14px;line-height:1.5;color:#222;background:#f6f7fb}p{margin:0 0 12px}</style>' +
            '</head><body>' + html + '</body></html>'
        );
        try {
            // Use unescape+encodeURIComponent trick to handle non-latin chars in Btoa
            const b64 = btoa(unescape(encodeURIComponent(wrapped)));
            return 'data:text/html;base64,' + b64;
        } catch (_) { return ''; }
    }

    /** Auto-fit iframe height to its content on load. */
    handleIframeLoad(e) {
        try {
            const iframe = e.target;
            const doc = iframe.contentDocument;
            if (!doc) return;
            const h = Math.min(Math.max(doc.body.scrollHeight + 40, 320), 900);
            iframe.style.height = h + 'px';
        } catch (_) { /* cross-origin protection may throw — leave default height */ }
    }

    /**
     * Best-effort "who is this going to" line. If we have the SAMPLE
     * application id + it resolved merges, show the client name.
     */
    get previewClientDisplay() {
        const r = this.previewResult || {};
        const merges = r.resolvedMerges || [];
        const first = (merges.find(m => m.token === '{{FirstName}}') || {}).example;
        const last  = (merges.find(m => m.token === '{{LastName}}')  || {}).example;
        if (first || last) return ((first || '') + ' ' + (last || '')).trim() + '  (from sample record)';
        return '(sample record ' + (this.previewAppId || '?') + ')';
    }

    /** Sender email — for the "From:" line in the envelope. */
    get previewFromEmail() {
        return 'noreply@xtrapension.com';
    }

    // ═══════════════════════ LIVE PREVIEW (in Edit modal) ═══════════════════════
    //
    // Renders the draft in a mini-envelope on the right of the Compose editor —
    // no server round-trip. Uses sample values from getMergeSchema chip.example
    // for token substitution so the user sees "Hi Margaret" not "Hi {{FirstName}}".
    //
    // The rendered body is wrapped in the same shell CSS the real server uses
    // for the shell (approximation — actual AA_Email_Shell static resource
    // is teal-header). Perfect fidelity requires clicking Preview + a real
    // Application Id (kept on the second modal). This is the WYSIWYG editor
    // pair — instant feedback on every keystroke.
    //

    get sampleValues() {
        const m = {};
        for (const chip of (this.schema || [])) {
            const bare = (chip.token || '').replace(/^\{\{|\}\}$/g, '');
            if (bare && chip.example) m[bare] = chip.example;
        }
        // Ensure a few load-bearing defaults exist even if the schema doesn't
        // ship them (some orgs have blank Example__c on custom merge fields).
        if (!m.FirstName)      m.FirstName = 'Margaret';
        if (!m.LastName)       m.LastName = "O'Connor";
        if (!m.FullName)       m.FullName = (m.FirstName + ' ' + m.LastName).trim();
        if (!m.ApplicationRef) m.ApplicationRef = 'AA-SAMPLE-042';
        if (!m.DWPReference)   m.DWPReference = 'DWP-000-000-000';
        if (!m.Stage)          m.Stage = 'Application Prep';
        // No "£" here: templates write "£{{FeeAmount}}", so a symbol in this
        // fallback renders "££520.00" the moment the schema example is blanked
        // (same rule as AA_MessageTemplateController.getMergeSchema).
        if (!m.FeeAmount)      m.FeeAmount = '520.00';
        if (!m.XPPhone)        m.XPPhone = '+353 1 234 5678';
        if (!m.XPEmail)        m.XPEmail = 'hello@xtrapension.com';
        if (!m.XPWhatsApp)     m.XPWhatsApp = '+353 87 654 3210';
        if (!m.MandateId)      m.MandateId = 'MD-Z1XXXXXXXX (sample)';
        return m;
    }

    /** Substitute known merge tokens with sample values; leave unknowns literal so warnings still surface. */
    resolveTokens(src) {
        if (!src) return '';
        const vals = this.sampleValues;
        return src.replace(TOKEN_RE, (_m, name) => (vals[name] != null ? String(vals[name]) : '{{' + name + '}}'));
    }

    get sampleClientDisplay() {
        const v = this.sampleValues;
        return `${v.FullName} <${(v.FirstName || 'sample').toLowerCase()}@example.com>  (sample)`;
    }

    get liveSubjectResolved() {
        if (!this.isEmail) return '';
        return this.resolveTokens(this.editing?.subjectTemplate || '(no subject)');
    }

    get liveBodyHtml() {
        if (!this.editing) return '';
        const raw = this.isSimpleMode
            ? (this.editing.contentText || '')
            : (this.editing.bodyTemplate || '');
        const html = this.isSimpleMode
            ? (this.looksLikeHtml(raw) ? raw : this.mdToHtml(raw))
            : raw;   // advanced mode: raw HTML flowed through verbatim (with shell IF simple)
        return this.resolveTokens(html);
    }

    get liveSmsBody() {
        if (this.isEmail) return '';
        // SMS mode: strip HTML if the widget somehow injected any, then resolve tokens.
        const raw = (this.editing?.contentText || '').replace(/<[^>]+>/g, '');
        return this.resolveTokens(raw);
    }

    get liveSmsLenDisplay() {
        const b = this.liveSmsBody;
        if (!b) return '';
        const isGsm = /^[ -~\r\n]*$/.test(b);
        const seg = isGsm
            ? (b.length <= 160 ? 1 : Math.ceil(b.length / 153))
            : (b.length <= 70  ? 1 : Math.ceil(b.length / 67));
        return b.length + ' char' + (b.length === 1 ? '' : 's') + ' · ' + seg + ' SMS segment' + (seg === 1 ? '' : 's') + (isGsm ? ' (GSM-7)' : ' (UCS-2)');
    }

    /**
     * Build the shell fragment (no <html>/<body>) for injection into a
     * `lwc:dom="manual"` div. LWC blocks BOTH iframe src="data:..." (silent
     * runtime block) AND iframe srcdoc="..." (compile-time LWC1048). The
     * remaining Salesforce-approved path for arbitrary HTML with styles is
     * manual DOM injection into a whitelisted div. Shadow DOM scopes the
     * <style> naturally so the shell CSS doesn't leak into surrounding SLDS.
     */
    buildShellFragment(body, showEmpty) {
        if (!body && showEmpty) {
            return '<div style="padding:40px;font:14px Helvetica,Arial,sans-serif;color:#8a8f99;text-align:center;background:#f6f7fb;border-radius:6px">Start typing on the left — this preview updates instantly.</div>';
        }
        return '<style>' +
              '.aa-shell{max-width:640px;margin:0 auto;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);font-family:Helvetica,Arial,sans-serif;color:#222;line-height:1.55;font-size:14px}' +
              '.aa-shell__hdr{background:#0d7377;color:#fff;padding:20px 24px;font-weight:600;font-size:18px}' +
              '.aa-shell__body{padding:20px 24px}' +
              '.aa-shell__body p{margin:0 0 12px}' +
              '.aa-shell__body ul,.aa-shell__body ol{margin:0 0 12px 20px}' +
              '.aa-shell__body a{color:#0d7377}' +
              '.aa-shell__ftr{background:#f0f2f5;color:#555;padding:12px 24px;font-size:12px;text-align:center;border-top:1px solid #e6e8ef}' +
              '.aa-shell__ftr a{color:#0d7377;text-decoration:none;margin:0 6px}' +
              '.aa-render-wrap{background:#f6f7fb;padding:16px;border-radius:6px}' +
            '</style>' +
            '<div class="aa-render-wrap">' +
              '<div class="aa-shell">' +
                '<div class="aa-shell__hdr">XtraPension</div>' +
                '<div class="aa-shell__body">' + body + '</div>' +
                '<div class="aa-shell__ftr">' +
                  'Need help? <a href="#">' + (this.sampleValues.XPEmail || 'hello@xtrapension.com') + '</a>' +
                  ' · <a href="#">' + (this.sampleValues.XPPhone || '') + '</a>' +
                '</div>' +
              '</div>' +
            '</div>';
    }

    /**
     * renderedCallback fires on every state change — inject the freshly-built
     * shell fragment into the live-render div. This is the only reliable way
     * to show arbitrary HTML in an LWC (iframes are blocked, and
     * `lightning-formatted-rich-text` strips styles/tables/most tags — see
     * the 2026-08-25 preview fidelity commit that moved us AWAY from it).
     */
    renderedCallback() {
        try {
            if (this.showEdit) {
                const live = this.template.querySelector('[data-role="live-render"]');
                if (live) live.innerHTML = this.buildShellFragment(this.liveBodyHtml, true);
            }
            if (this.showPreview && this.hasPreviewResult && this.previewBodyIsHtml) {
                const full = this.template.querySelector('[data-role="full-render"]');
                if (full) {
                    const body = (this.previewResult.body || '');
                    // Server body is usually a full HTML doc. Extract just the <body>
                    // contents so we don't try to nest <html><body> inside a div.
                    const bodyMatch = body.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
                    const inner = bodyMatch ? bodyMatch[1] : body;
                    full.innerHTML = inner;
                }
            }
        } catch (_) { /* leave whatever was there */ }
    }

    /** Legacy data URL — no longer used (iframes blocked); kept for reference. */
    get liveBodyDataUrl() {
        const body = this.liveBodyHtml;
        if (!body) {
            // Empty state — show placeholder inside the envelope
            const empty = '<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;padding:40px;font:14px Helvetica,Arial,sans-serif;color:#8a8f99;text-align:center;background:#f6f7fb}</style></head><body>Start typing on the left — this preview updates instantly.</body></html>';
            try { return 'data:text/html;base64,' + btoa(empty); } catch (_) { return ''; }
        }
        const wrapped =
            '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
            '<meta name="viewport" content="width=device-width,initial-scale=1">' +
            '<base target="_blank">' +
            '<style>' +
              'body{margin:0;padding:0;font-family:Helvetica,Arial,sans-serif;color:#222;background:#f6f7fb;line-height:1.55;font-size:14px}' +
              '.shell{max-width:640px;margin:24px auto;background:#fff;border-radius:8px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08)}' +
              '.shell__hdr{background:#0d7377;color:#fff;padding:20px 24px;font-weight:600;font-size:18px}' +
              '.shell__body{padding:20px 24px}' +
              '.shell__body p{margin:0 0 12px}' +
              '.shell__body a{color:#0d7377}' +
              '.shell__ftr{background:#f0f2f5;color:#555;padding:12px 24px;font-size:12px;text-align:center;border-top:1px solid #e6e8ef}' +
              '.shell__ftr a{color:#0d7377;text-decoration:none;margin:0 6px}' +
            '</style>' +
            '</head><body>' +
              '<div class="shell">' +
                '<div class="shell__hdr">XtraPension</div>' +
                '<div class="shell__body">' + body + '</div>' +
                '<div class="shell__ftr">' +
                  'Need help? <a href="#">' + (this.sampleValues.XPEmail || 'hello@xtrapension.com') + '</a>' +
                  ' · <a href="#">' + (this.sampleValues.XPPhone || '') + '</a>' +
                '</div>' +
              '</div>' +
            '</body></html>';
        try {
            return 'data:text/html;base64,' + btoa(unescape(encodeURIComponent(wrapped)));
        } catch (_) { return ''; }
    }

    handleLiveIframeLoad(e) {
        try {
            const iframe = e.target;
            const doc = iframe.contentDocument;
            if (!doc) return;
            const h = Math.min(Math.max(doc.body.scrollHeight + 20, 380), 720);
            iframe.style.height = h + 'px';
        } catch (_) { /* cross-origin — leave default */ }
    }

    /** For the "target: ___" label in the merge-field palette. */
    get lastFocusLabel() {
        if (this.lastFocus === 'subject') return 'Subject';
        if (this.lastFocus === 'bodyhtml') return 'Body HTML';
        return 'Content';
    }

    /** SMS character count display. Twilio segments at 160 GSM-7 / 70 UTF-16. */
    get previewSmsLenDisplay() {
        const b = (this.previewResult && this.previewResult.body) || '';
        if (!b) return '';
        // audit #86: old class matched control chars only, mis-classifying every
        // real message as UCS-2. Use the printable-ASCII approximation the live
        // counter uses (a genuine GSM-extended char just reads as UCS-2 — safe).
        const isGsm = /^[ -~\r\n]*$/.test(b);
        const seg = isGsm
            ? (b.length <= 160 ? 1 : Math.ceil(b.length / 153))
            : (b.length <= 70  ? 1 : Math.ceil(b.length / 67));
        return b.length + ' char' + (b.length === 1 ? '' : 's') + ' · ' + seg + ' SMS segment' + (seg === 1 ? '' : 's') + (isGsm ? ' (GSM-7)' : ' (UCS-2)');
    }
    get previewBodyIsHtml() {
        return this.hasPreviewResult && /<html|<body|<p[\s>]/i.test(this.previewResult.body || '');
    }

    // ═══════════════════════ SEND LOG ════════════════════════════

    handleLogFrom(e)     { this.logFilterFrom = e.target.value || null; }
    handleLogTo(e)       { this.logFilterTo = e.target.value || null; }
    handleLogTemplate(e) { this.logFilterTemplate = e.detail?.value || e.target?.value || ''; }
    handleLogStatus(e)   { this.logFilterStatus = e.detail?.value || 'All'; }

    get templateFilterOptions() {
        return [
            { label: 'All templates', value: '' },
            ...this.rows.map((r) => ({ label: r.name, value: r.id }))
        ];
    }

    async refreshLogs() {
        this.logLoading = true;
        try {
            const page = await listSendLogs({
                fromDate: this.logFilterFrom,
                toDate: this.logFilterTo,
                templateId: this.logFilterTemplate || null,
                status: this.logFilterStatus,
                pageIndex: this.logPageIndex,
                pageSize: this.logPageSize
            });
            this.logRows = (page.rows || []).map((r) => ({
                ...r,
                sentAtDisplay: r.sentAt
                    ? new Date(r.sentAt).toLocaleString('en-GB', {
                        timeZone: 'Europe/London', year: 'numeric', month: 'short',
                        day: '2-digit', hour: '2-digit', minute: '2-digit'
                    })
                    : '-',
                statusBadgeCls: this.statusBadgeCls(r.status),
                errorPreview: (r.errorMessage || '').slice(0, 120),
                appUrl: r.applicationId ? `/${r.applicationId}` : null,
                templateUrl: r.templateId ? `/${r.templateId}` : null
            }));
            this.logTotal = page.total || 0;
        } catch (err) {
            this.toast('Send log failed', 'error', this.errMsg(err));
        } finally { this.logLoading = false; }
    }

    handleApplyLogFilters() {
        this.logPageIndex = 0;
        this.refreshLogs();
    }

    handleClearLogFilters() {
        this.logFilterFrom = null;
        this.logFilterTo = null;
        this.logFilterTemplate = '';
        this.logFilterStatus = 'All';
        this.logPageIndex = 0;
        // Clear datepicker inputs in DOM
        this.template.querySelectorAll('lightning-input[data-role^="logfilter-"]').forEach((el) => {
            el.value = null;
        });
        this.refreshLogs();
    }

    handleLogPrev() {
        if (this.logPageIndex === 0) return;
        this.logPageIndex -= 1;
        this.refreshLogs();
    }

    handleLogNext() {
        if ((this.logPageIndex + 1) * this.logPageSize >= this.logTotal) return;
        this.logPageIndex += 1;
        this.refreshLogs();
    }

    get logHasPrev() { return this.logPageIndex > 0; }
    get logHasNext() { return (this.logPageIndex + 1) * this.logPageSize < this.logTotal; }
    get logHasPrevDisabled() { return !this.logHasPrev; }
    get logHasNextDisabled() { return !this.logHasNext; }
    get logPageLabel() {
        if (this.logTotal === 0) return '0';
        const from = this.logPageIndex * this.logPageSize + 1;
        const to = Math.min((this.logPageIndex + 1) * this.logPageSize, this.logTotal);
        return `${from}-${to} of ${this.logTotal}`;
    }

    statusBadgeCls(status) {
        if (status === 'Sent') return 'slds-badge slds-theme_success';
        if (status === 'Failed') return 'slds-badge slds-theme_error';
        return 'slds-badge slds-theme_warning';
    }

    // ═══════════════════════ UTIL ════════════════════════════════

    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, variant, message: message || '' }));
    }
    errMsg(e) { return e?.body?.message || e?.message || 'Unknown error'; }
}
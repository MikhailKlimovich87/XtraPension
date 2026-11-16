import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

import refresh from '@salesforce/apex/XpMissingInfoPanel.refresh';
// previewAsking / sendAsking: preview / sendEmail plus the agent's questions (claims only, call of 11/11/2026 17h13)
import preview from '@salesforce/apex/XpMissingInfoPanel.previewAsking';
import sendEmail from '@salesforce/apex/XpMissingInfoPanel.sendAsking';

const AGENT_GROUP = 'For you to check';
const CLAIM = 'Basic__c';

/**
 * Missing Information panel on the application and on the claim (Form In Progress to QC Approved). Lists
 * what is still missing, grouped and in plain words, with the checks only the agent can act on kept apart,
 * and sends the client a clear email (or gives the same text for WhatsApp) after a preview where the agent ticks
 * what to ask.
 * XpMissingInfoPanel picks the class by the record: XpMissingInfo (Sales) or BP_MissingInfo (Claims).
 */
export default class XpMissingInfo extends LightningElement {
    @api objectApiName;

    _recordId;

    groups = [];
    missing = 0;
    optional = 0;
    checks = 0;
    clientCount = 0;
    hasEmail = false;
    inStage = true;
    step;
    lastAsked;
    isLoading = false;

    showPreview = false;
    previewLoading = false;
    sending = false;
    note = '';
    // The validation agent's questions for the client, one per line (claims only)
    questions = '';
    mail = { to: '', cc: '', subject: '', html: '' };
    noteTimer;

    showWhatsApp = false;
    waLoading = false;
    waText = '';

    // What the email / WhatsApp asks: one tick per item for the client (call of 11/11/2026). Each opening starts
    // from the server's askByDefault (no helper given starts unticked on a claim; everything else ticked).
    picks = [];

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.load(false);
        }
    }

    // No Claim: grava Missing_Info__c no refresh, copia o helper e fala em claim/DWP.
    get isClaim() {
        return this.objectApiName === CLAIM;
    }

    get recordWord() {
        return this.isClaim ? 'claim' : 'application';
    }

    get hasItems() {
        return this.groups.length > 0;
    }

    get summary() {
        const parts = [];
        if (this.missing) parts.push(`${this.missing} missing`);
        if (this.optional) parts.push(`${this.optional} optional`);
        if (this.checks) parts.push(`${this.checks} to check`);
        return parts.join(' · ');
    }

    get stepText() {
        if (!this.step) return '';
        // O Claim já vem com a frase pronta (passo N de 9); o Sales manda o nome do passo.
        return this.isClaim ? this.step : `The client is on the "${this.step}" step of the form.`;
    }

    get emptyText() {
        return this.isClaim ? 'Nothing missing. The claim has what the DWP needs.' : 'Nothing missing. The application has what HMRC needs.';
    }

    get savedHint() {
        return `The email is saved on the ${this.recordWord}. Items under "For you to check" are never sent to the client.`;
    }

    get nothingToAsk() {
        return !this.clientCount;
    }

    // On a claim the email also opens with nothing missing: the agent can still send questions (11/11/2026 17h13)
    get emailDisabled() {
        return this.isLoading || (!this.clientCount && !this.isClaim) || !this.hasEmail || !this.inStage;
    }

    get emailTitle() {
        if (!this.inStage) return 'Only from Form In Progress to QC Approved';
        if (!this.hasEmail) return `The ${this.recordWord} has no client email`;
        if (!this.clientCount) return this.isClaim ? 'Nothing missing: you can still send the client your questions' : 'Nothing to ask the client';
        return 'Preview the email before it is sent';
    }

    get hasQuestions() {
        return this.isClaim && !!(this.questions || '').trim();
    }

    get whatsAppDisabled() {
        return this.isLoading || !this.clientCount || !this.inStage;
    }

    get whatsAppTitle() {
        if (!this.inStage) return 'Only from Form In Progress to QC Approved';
        if (!this.clientCount) return 'Nothing to ask the client';
        return 'The same request as a WhatsApp message, to copy';
    }

    get sendDisabled() {
        return this.sending || this.previewLoading || (this.nothingTicked && !this.hasQuestions);
    }

    get leaveOut() {
        return this.picks.filter((p) => !p.checked).map((p) => p.key);
    }

    get nothingTicked() {
        return !this.picks.some((p) => p.checked);
    }

    // the email's warning: questions alone are enough on a claim
    get emailNothingTicked() {
        return this.nothingTicked && !this.hasQuestions;
    }

    get copyDisabled() {
        return this.waLoading || this.nothingTicked;
    }

    resetPicks() {
        const seen = new Set();
        const picks = [];
        for (const g of this.groups) {
            if (g.agentOnly) continue;
            for (const i of g.items) {
                if (!i.clientText || seen.has(i.line)) continue;
                seen.add(i.line);
                picks.push({ key: i.line, label: i.agentText, checked: i.askByDefault });
            }
        }
        this.picks = picks;
    }

    togglePick(event) {
        const key = event.target.dataset.key;
        const checked = event.target.checked;
        this.picks = this.picks.map((p) => (p.key === key ? { ...p, checked } : p));
    }

    handlePick(event) {
        this.togglePick(event);
        this.loadPreview();
    }

    handleWaPick(event) {
        this.togglePick(event);
        this.loadWhatsApp();
    }

    get sendLabel() {
        return this.sending ? 'Sending…' : 'Send email';
    }

    async load(manual) {
        this.isLoading = true;
        try {
            // O refresh na mão é o antigo "Check Missing" do Claim (force); no Sales o force não muda nada.
            const res = await refresh({ recordId: this.recordId, force: !!manual });
            this.groups = (res.groups || []).map((g, gi) => ({
                key: `g${gi}`,
                label: g.label,
                agentOnly: g.label === AGENT_GROUP,
                className: g.label === AGENT_GROUP ? 'group group-agent' : 'group',
                items: g.items.map((i, ii) => ({
                    key: `g${gi}i${ii}`,
                    line: i.agentText,
                    agentText: i.agentText,
                    clientText: i.clientText,
                    askByDefault: i.askByDefault !== false,
                    tag: i.optional ? 'optional' : ''
                }))
            }));
            this.missing = res.missing || 0;
            this.optional = res.optional || 0;
            this.checks = res.checks || 0;
            this.clientCount = res.clientCount || 0;
            this.hasEmail = !!res.hasEmail;
            this.inStage = res.inStage !== false;
            this.step = res.step;
            this.lastAsked = res.lastAsked;
            if (manual) {
                if (this.isClaim) notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
                this.toast('Missing information refreshed', '', 'success');
            }
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleRefresh() {
        this.load(true);
    }

    async handleOpenPreview() {
        this.note = '';
        this.questions = '';
        this.resetPicks();
        this.showPreview = true;
        await this.loadPreview();
    }

    async loadPreview() {
        this.previewLoading = true;
        try {
            const res = await preview({ recordId: this.recordId, note: this.note, leaveOut: this.leaveOut, questions: this.isClaim ? this.questions : '' });
            this.mail = { to: res.to, cc: res.cc, subject: res.subject, html: res.html };
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.previewLoading = false;
        }
    }

    handleNote(event) {
        this.note = event.target.value;
        clearTimeout(this.noteTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.noteTimer = setTimeout(() => this.loadPreview(), 500);
    }

    handleQuestions(event) {
        this.questions = event.target.value;
        clearTimeout(this.noteTimer);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.noteTimer = setTimeout(() => this.loadPreview(), 500);
    }

    // The WhatsApp message: the same items as the email, ready to edit and copy into the client's chat.
    async handleOpenWhatsApp() {
        this.resetPicks();
        this.showWhatsApp = true;
        await this.loadWhatsApp();
    }

    async loadWhatsApp() {
        this.waLoading = true;
        try {
            const res = await preview({ recordId: this.recordId, note: '', leaveOut: this.leaveOut, questions: '' });
            this.waText = res.whatsapp;
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.waLoading = false;
        }
    }

    handleWaText(event) {
        this.waText = event.target.value;
    }

    async handleCopyWhatsApp() {
        try {
            await navigator.clipboard.writeText(this.waText);
            this.toast('Copied', 'Paste it in the WhatsApp chat with the client.', 'success');
        } catch (e) {
            this.toast('Copy by hand', 'The browser did not allow copying: click in the box, press Ctrl+A and then Ctrl+C.', 'info');
        }
    }

    handleCloseWhatsApp() {
        this.showWhatsApp = false;
    }

    handleClose() {
        this.showPreview = false;
    }

    async handleSend() {
        this.sending = true;
        try {
            const message = await sendEmail({ recordId: this.recordId, note: this.note, leaveOut: this.leaveOut, questions: this.isClaim ? this.questions : '' });
            this.showPreview = false;
            this.toast('Email sent', message, 'success');
            if (this.isClaim) notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.load(false);
        } catch (error) {
            this.toast('Not sent', this.reduceError(error), 'error');
        } finally {
            this.sending = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unknown error';
    }
}
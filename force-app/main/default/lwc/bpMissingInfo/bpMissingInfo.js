import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

import refresh from '@salesforce/apex/BP_MissingInfo.refresh';
import preview from '@salesforce/apex/BP_MissingInfo.preview';
import sendEmail from '@salesforce/apex/BP_MissingInfo.sendEmail';

/**
 * Missing Information panel on the claim. Lists what is still missing, grouped and in plain words
 * (BP_MissingInfo), keeps Missing_Info__c current while the claim is being completed, and sends
 * the client a clear email after the agent has seen the preview.
 */
export default class BpMissingInfo extends LightningElement {
    _recordId;

    groups = [];
    blocking = 0;
    clientCount = 0;
    hasEmail = false;
    isLoading = false;

    showPreview = false;
    previewLoading = false;
    sending = false;
    note = '';
    mail = { to: '', cc: '', subject: '', html: '' };
    noteTimer;

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

    get hasMissing() {
        return this.groups.length > 0;
    }

    get summary() {
        if (!this.hasMissing) return '';
        const optional = this.optionalCount;
        const parts = [];
        if (this.blocking) parts.push(`${this.blocking} missing`);
        if (optional) parts.push(`${optional} optional`);
        return parts.join(', ');
    }

    get optionalCount() {
        return this.groups.reduce((n, g) => n + g.items.filter((i) => i.optional).length, 0);
    }

    get emailDisabled() {
        return this.isLoading || !this.clientCount || !this.hasEmail;
    }

    get emailTitle() {
        if (!this.hasEmail) return 'The claim has no client email';
        if (!this.clientCount) return 'Nothing to ask the client';
        return 'Preview the email before it is sent';
    }

    get sendDisabled() {
        return this.sending || this.previewLoading;
    }

    get sendLabel() {
        return this.sending ? 'Sending…' : 'Send email';
    }

    async load(force) {
        this.isLoading = true;
        try {
            const res = await refresh({ basicId: this.recordId, force });
            this.groups = (res.groups || []).map((g, gi) => ({
                key: `g${gi}`,
                label: g.label,
                items: g.items.map((i, ii) => ({
                    key: `g${gi}i${ii}`,
                    agentText: i.agentText,
                    clientText: i.clientText,
                    optional: i.optional,
                    agentOnly: !i.clientText,
                    tag: i.optional ? 'optional' : !i.clientText ? 'for you' : ''
                }))
            }));
            this.blocking = res.blocking || 0;
            this.clientCount = res.clientCount || 0;
            this.hasEmail = !!res.hasEmail;
            if (force) {
                notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
                this.toast('Missing information refreshed', '', 'success');
            }
        } catch (error) {
            this.toast('Error', this.reduceError(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCheckMissing() {
        this.load(true);
    }

    async handleOpenPreview() {
        this.note = '';
        this.showPreview = true;
        await this.loadPreview();
    }

    async loadPreview() {
        this.previewLoading = true;
        try {
            const res = await preview({ basicId: this.recordId, note: this.note });
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

    handleClose() {
        this.showPreview = false;
    }

    async handleSend() {
        this.sending = true;
        try {
            const message = await sendEmail({ basicId: this.recordId, note: this.note });
            this.showPreview = false;
            this.toast('Email sent', message, 'success');
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
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
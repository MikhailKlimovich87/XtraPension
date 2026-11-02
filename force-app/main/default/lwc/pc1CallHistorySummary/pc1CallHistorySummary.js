import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getCallHistory from '@salesforce/apex/PC1_RecordPageService.getCallHistory';
import getCallHistoryCount from '@salesforce/apex/PC1_RecordPageService.getCallHistoryCount';
import getActivePending from '@salesforce/apex/PC1_CallScheduleService.getActivePending';

export default class Pc1CallHistorySummary extends NavigationMixin(LightningElement) {
    @api recordId;
    calls = [];
    total = null;
    errorText = '';
    pending = null;

    @wire(getCallHistory, { recordId: '$recordId' })
    wired({ data, error }) {
        if (data) { this.calls = data; this.errorText = ''; }
        else if (error) {
            this.calls = [];
            const body = error.body;
            const msg = (body && body.message) || error.message;
            this.errorText = `Could not load the call history${msg ? `: ${msg}` : '.'}`;
        }
    }

    @wire(getCallHistoryCount, { recordId: '$recordId' })
    wiredCount({ data }) {
        if (data !== undefined && data !== null) this.total = data;
    }

    // The real next call is the Pending PC1_Call_Schedule__c row (the same one
    // pc1CallSchedule shows) — Rescheduled_To__c on a past call is history.
    @wire(getActivePending, { applicationId: '$recordId' })
    wiredPending({ data }) {
        this.pending = data || null;
    }

    get hasError() { return !!this.errorText; }
    get hasCalls() { return this.calls.length > 0; }
    get callCount() { return this.total == null ? this.calls.length : Math.max(this.total, this.calls.length); }
    get callLabel() { return this.callCount === 1 ? 'call recorded' : 'calls recorded'; }

    get topThree() {
        return this.calls.slice(0, 3).map(c => this.decorate(c));
    }

    decorate(c) {
        const dir = String(c.Direction__c || '');
        const inbound = dir.startsWith('inbound');
        const dirIcon = dir === 'outbound' ? '📞→'
                      : dir === 'inbound_unknown' ? '←❓'
                      : inbound ? '←📞' : '📞';
        const dirLabel = dir === 'outbound' ? 'Outbound'
                       : dir === 'inbound_unknown' ? 'Inbound (unknown)'
                       : inbound ? 'Inbound' : 'Call';
        const status = (c.Status__c || '').replace(/_/g, ' ').toUpperCase();
        const badgeCls = this.statusCls(c.Status__c);
        const duration = c.Duration_Min__c
            ? (Number(c.Duration_Min__c) < 1
                ? `${Math.round(Number(c.Duration_Min__c) * 60)}s`
                : `${Number(c.Duration_Min__c).toFixed(1)} min`)
            : '';
        const parts = [];
        if (dirLabel) parts.push(dirLabel);
        if (c.Source__c) parts.push(c.Source__c);
        if (c.Rep_Name__c && c.Rep_Name__c !== c.Source__c) parts.push(c.Rep_Name__c);
        if (c.Voicemail_Left__c) parts.push('voicemail');
        if (duration) parts.push(duration);
        return {
            id: c.Id,
            dirIcon,
            startedFmt: this.fmt(c.Started_At__c),
            metaLine: parts.join(' · '),
            status,
            badgeCls,
            hasTranscript: !!c.Transcript_URL__c,
            transcriptUrl: c.Transcript_URL__c,
            hasRecording: !!c.Recording_URL__c,
            recordingUrl: c.Recording_URL__c
        };
    }

    statusCls(s) {
        if (s === 'completed')     return 'call-badge b-ok';
        if (s === 'no_answer' || s === 'failed') return 'call-badge b-bad';
        if (s === 'in_progress')   return 'call-badge b-info';
        if (s === 'rescheduled')   return 'call-badge b-warn';
        return 'call-badge';
    }

    get nextScheduled() {
        const t = this.pending && this.pending.Scheduled_At__c;
        return t && new Date(t).getTime() > Date.now() ? t : null;
    }
    get hasNextScheduled() { return !!this.nextScheduled; }
    get nextScheduledFmt() { return this.fmt(this.nextScheduled); }

    fmt(iso) {
        if (!iso) return '';
        try {
            return new Date(iso).toLocaleString('en-GB', {
                day: '2-digit', month: '2-digit', year: 'numeric',
                hour: '2-digit', minute: '2-digit',
                timeZone: 'Europe/London'
            });
        } catch (_) { return iso; }
    }

    openCall(evt) {
        const id = evt.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, objectApiName: 'PC1_Call_Log__c', actionName: 'view' }
        });
    }

    stopProp(evt) { evt.stopPropagation(); }

    openTab() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'PC1_Application__c',
                relationshipApiName: 'Call_Logs__r',
                actionName: 'view'
            }
        });
    }
}
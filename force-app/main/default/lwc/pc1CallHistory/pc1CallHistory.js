import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getCallHistory from '@salesforce/apex/PC1_RecordPageService.getCallHistory';
import getCallHistoryCount from '@salesforce/apex/PC1_RecordPageService.getCallHistoryCount';

/**
 * pc1CallHistory — vertical list of PC1_Call_Log__c cards for this Application,
 * newest first (the 50 most recent; the header says when there are more).
 * Each card:
 *   • Direction icon + label (outbound, or any inbound_* value)
 *   • Started_At__c as DD/MM/YYYY HH:MM, Europe/London
 *   • Duration + status badge (+ voicemail tag)
 *   • Who: Mary, or Human · <rep>
 *   • Summary (Mary's post-call summary) or Detail, with a "Show more" toggle
 *   • Transcript / Recording links (signed by Apex at read time)
 *   • Link to open the Call Log record
 */
export default class Pc1CallHistory extends NavigationMixin(LightningElement) {
    @api recordId;
    calls = [];
    total = null;
    errorText = '';
    @track expanded = new Set();

    @wire(getCallHistory, { recordId: '$recordId' })
    wired({ data, error }) {
        if (data) { this.calls = data; this.errorText = ''; }
        else if (error) { this.calls = []; this.errorText = Pc1CallHistory.errorMessage(error); }
    }

    @wire(getCallHistoryCount, { recordId: '$recordId' })
    wiredCount({ data }) {
        if (data !== undefined && data !== null) this.total = data;
    }

    static errorMessage(error) {
        const body = error && error.body;
        const msg = (body && (body.message || (Array.isArray(body) && body.map(b => b.message).join('; ')))) || (error && error.message);
        return `Could not load the call history${msg ? `: ${msg}` : '.'}`;
    }

    get hasError() { return !!this.errorText; }
    get hasCalls() { return this.calls.length > 0; }
    get emptyText() { return 'No calls yet — inbound and outbound calls appear here.'; }
    get headerSummary() {
        const shown = this.calls.length;
        const total = this.total == null ? shown : Math.max(this.total, shown);
        if (total > shown) return `Showing the ${shown} most recent of ${total} call records`;
        return `${total} call record${total === 1 ? '' : 's'}`;
    }

    get rows() {
        return this.calls.map(c => {
            const text = c.Summary__c || c.Detail__c || '';
            const extra = c.Summary__c && c.Detail__c && c.Detail__c !== c.Summary__c ? c.Detail__c : '';
            const isLong = text.length > 180;
            const isOpen = this.expanded.has(c.Id);
            const shown  = !isLong || isOpen ? text : (text.slice(0, 180) + '…');
            const status = (c.Status__c || '').replace(/_/g, ' ').toUpperCase();
            const dir = Pc1CallHistory.direction(c.Direction__c);
            const who = [c.Source__c, c.Rep_Name__c && c.Rep_Name__c !== c.Source__c ? c.Rep_Name__c : null].filter(Boolean).join(' · ');
            return {
                id: c.Id,
                name: c.Name,
                dirIcon: dir.icon,
                dirLabel: dir.label,
                who,
                startedFmt: this.fmt(c.Started_At__c),
                durationFmt: Pc1CallHistory.duration(c.Duration_Min__c),
                hasDuration: !!c.Duration_Min__c,
                status,
                badgeCls: this.statusCls(c.Status__c),
                isVoicemail: !!c.Voicemail_Left__c,
                task: c.Task_Instruction__c || '',
                hasTask: !!c.Task_Instruction__c,
                detail: shown,
                hasDetail: !!text,
                extraDetail: extra,
                hasExtraDetail: !!extra,
                isLong,
                isOpen,
                toggleLabel: isOpen ? 'Show less' : 'Show more',
                rescheduleFmt: c.Rescheduled_To__c ? `→ rescheduled to ${this.fmt(c.Rescheduled_To__c)}` : '',
                hasReschedule: !!c.Rescheduled_To__c,
                hasTranscript: !!c.Transcript_URL__c,
                transcriptUrl: c.Transcript_URL__c,
                hasRecording: !!c.Recording_URL__c,
                recordingUrl: c.Recording_URL__c
            };
        });
    }

    /** Any inbound_* value is inbound (Nuacom writes plain 'inbound'). */
    static direction(d) {
        const v = String(d || '');
        if (v === 'outbound') return { icon: '📞→', label: 'Outbound' };
        if (v === 'inbound_unknown') return { icon: '←❓', label: 'Inbound (unknown caller)' };
        if (v === 'inbound_dnc') return { icon: '←📞', label: 'Inbound (Do Not Contact)' };
        if (v === 'inbound_safeguarding_lock') return { icon: '←📞', label: 'Inbound (safeguarding lock)' };
        if (v.startsWith('inbound')) return { icon: '←📞', label: 'Inbound' };
        return { icon: '📞', label: 'Call' };
    }

    static duration(min) {
        if (!min) return '';
        const n = Number(min);
        return n < 1 ? `${Math.round(n * 60)}s` : `${n.toFixed(1)} min`;
    }

    statusCls(s) {
        if (s === 'completed')     return 'call-badge b-ok';
        if (s === 'no_answer' || s === 'failed') return 'call-badge b-bad';
        if (s === 'in_progress')   return 'call-badge b-info';
        if (s === 'rescheduled')   return 'call-badge b-warn';
        return 'call-badge';
    }

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

    toggleExpand(evt) {
        const id = evt.currentTarget.dataset.id;
        if (this.expanded.has(id)) this.expanded.delete(id);
        else                        this.expanded.add(id);
        this.expanded = new Set(this.expanded); // trigger reactivity
    }

    openCall(evt) {
        const id = evt.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, objectApiName: 'PC1_Call_Log__c', actionName: 'view' }
        });
    }
}
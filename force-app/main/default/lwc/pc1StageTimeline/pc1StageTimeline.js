import { LightningElement, api, wire } from 'lwc';
import getStageHistory from '@salesforce/apex/PC1_RecordPageService.getStageHistory';

/**
 * pc1StageTimeline — vertical list of stage transitions for this Application,
 * newest first. Actor icons: human (👤 blue), mary (🤖 purple), system (⚙ grey).
 * Each item shows: from → to, timestamp, actor, optional note.
 */
export default class Pc1StageTimeline extends LightningElement {
    @api recordId;
    logs = [];

    @wire(getStageHistory, { recordId: '$recordId' })
    wired({ data }) { if (data) this.logs = data; }

    get hasLogs() { return this.logs.length > 0; }
    get headerSummary() {
        const n = this.logs.length;
        return `${n} transition${n === 1 ? '' : 's'}`;
    }

    get rows() {
        return this.logs.map(l => {
            const actor = l.Actor__c || 'system';
            const iconInfo =
                actor === 'human' ? { glyph: '👤', cls: 'actor human' }
              : actor === 'mary'  ? { glyph: '🤖', cls: 'actor mary'  }
              :                     { glyph: '⚙',  cls: 'actor system'};
            const title = l.From_Stage__c
                ? `${l.From_Stage__c} → ${l.To_Stage__c}`
                : l.To_Stage__c;
            const whenFmt = this.fmt(l.Changed_At__c);
            return {
                id: l.Id,
                title,
                whenFmt,
                actor,
                actorGlyph: iconInfo.glyph,
                actorCls: iconInfo.cls,
                changedBy: l.Changed_By__r ? l.Changed_By__r.Name : '',
                hasChangedBy: !!(l.Changed_By__r && l.Changed_By__r.Name),
                note: l.Note__c || '',
                hasNote: !!l.Note__c
            };
        });
    }

    fmt(iso) {
        if (!iso) return '';
        try { return new Date(iso).toLocaleString('en-GB', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }); }
        catch (_) { return iso; }
    }
}
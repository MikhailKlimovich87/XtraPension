import { LightningElement, api, wire } from 'lwc';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';

// Application History as a timeline by day: the day once as a heading, then the time, what changed (old → new) and who.
// Replaces the standard related list, which spent five lines on each change (Fernando, 03/11/2026). No Apex.

const SHOWN = 3; // as many as the standard list showed (Fernando, 03/11/2026)
// label do objeto no título; Basic__c tem o label "Claim"
const LABELS = { Application__c: 'Application', Basic__c: 'Claim' };
// Field history writes two rows when a lookup changes (record ids and names); the id row is dropped.
const ID = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;

function formatter(options) {
    try {
        return new Intl.DateTimeFormat(LOCALE, { ...options, timeZone: TIME_ZONE });
    } catch (e) {
        return new Intl.DateTimeFormat(undefined, options);
    }
}
// Days as "06 Oct 2026", the same on History, Checks and Work (Fernando, 03/11/2026); month names fixed in English
// because Intl writes "Sept" and the Work card's Apex writes "Sep".
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DAY_PARTS = formatter({ year: 'numeric', month: 'numeric', day: 'numeric' });
function dayLabel(date) {
    const p = {};
    for (const x of DAY_PARTS.formatToParts(date)) p[x.type] = x.value;
    return `${String(p.day).padStart(2, '0')} ${MONTHS[Number(p.month) - 1]} ${p.year}`;
}
const TIME = formatter({ hour: '2-digit', minute: '2-digit' });
const DAY_KEY = formatter({ year: 'numeric', month: '2-digit', day: '2-digit' });

const shown = (fv) => {
    if (!fv || fv.value === null || fv.value === undefined || fv.value === '') return null;
    return fv.displayValue !== null && fv.displayValue !== undefined ? fv.displayValue : String(fv.value);
};
const isIdOrEmpty = (v) => v === null || v === undefined || v === '' || ID.test(String(v));

// Changes saved in the same second come back in any order (e.g. Sent for eSignature -> Signed -> Printing House by
// automation). Newest first, chained by value: the next older change of a field is the one whose new value is the
// old value just shown; `anchor` holds that old value per field from the rows above the tie.
function orderTies(group, anchor) {
    const left = [...group];
    const out = [];
    while (left.length) {
        const prev = out[out.length - 1];
        const pick =
            (prev && left.find((o) => o.fieldApi === prev.fieldApi && o.newRaw === prev.oldRaw)) ||
            left.find((o) => o.fieldApi in anchor && o.newRaw === anchor[o.fieldApi]) ||
            left.find((o) => !left.some((x) => x !== o && x.fieldApi === o.fieldApi && x.oldRaw === o.newRaw)) ||
            left[0];
        out.push(pick);
        left.splice(left.indexOf(pick), 1);
    }
    return out;
}

function chainSameSecond(rows) {
    const out = [];
    const anchor = {};
    for (let i = 0; i < rows.length; ) {
        let j = i + 1;
        while (j < rows.length && rows[j].createdRaw === rows[i].createdRaw) j++;
        const group = j - i > 1 ? orderTies(rows.slice(i, j), anchor) : rows.slice(i, j);
        for (const r of group) {
            out.push(r);
            anchor[r.fieldApi] = r.oldRaw;
        }
        i = j;
    }
    return out;
}

export default class XpHistoryTimeline extends LightningElement {
    @api recordId;
    @api objectApiName;

    rows = [];
    more = false;
    loaded = false;
    error;
    wired;
    stamp;
    refreshId;

    // Mesmo card no Claim (04/11/2026): X__c -> X__History. Sem objectApiName fica como antes (Application__c).
    get object() {
        return this.objectApiName || 'Application__c';
    }

    get historyObject() {
        return this.object.replace(/__c$/, '__History');
    }

    get historyFields() {
        const h = this.historyObject;
        return [`${h}.Field`, `${h}.OldValue`, `${h}.NewValue`, `${h}.CreatedDate`];
    }

    get historyOptionalFields() {
        const h = this.historyObject;
        return [`${h}.CreatedBy.Name`, `${h}.CreatedById`];
    }

    get historySortBy() {
        return [`-${this.historyObject}.CreatedDate`];
    }

    get stampFields() {
        return [`${this.object}.LastModifiedDate`];
    }

    // "Application History" / "Claim History" (o label do Basic__c é Claim)
    get heading() {
        return `${LABELS[this.object] || this.object.replace(/__c$/, '').replace(/_/g, ' ')} History`;
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Histories',
        fields: '$historyFields',
        optionalFields: '$historyOptionalFields',
        sortBy: '$historySortBy',
        pageSize: 15
    })
    handleHistory(result) {
        this.wired = result;
        const { data, error } = result;
        if (error) {
            this.error = (error.body && error.body.message) || error.message || 'Unknown error';
            return;
        }
        if (!data) return;
        this.error = undefined;
        const all = data.records.map((r) => {
            const f = r.fields;
            const created = new Date(f.CreatedDate.value);
            const by = f.CreatedBy && f.CreatedBy.value && f.CreatedBy.value.fields ? f.CreatedBy.value.fields.Name.value : '';
            const byId = f.CreatedById ? f.CreatedById.value : null;
            const fieldApi = f.Field.value;
            const old = shown(f.OldValue);
            const neu = shown(f.NewValue);
            return {
                id: r.id,
                createdRaw: f.CreatedDate.value,
                fieldApi,
                oldRaw: f.OldValue ? f.OldValue.value : null,
                newRaw: f.NewValue ? f.NewValue.value : null,
                dayKey: DAY_KEY.format(created),
                dayLabel: dayLabel(created),
                time: TIME.format(created),
                field: fieldApi === 'created' ? 'Created' : f.Field.displayValue || fieldApi,
                plain: !old && !neu,
                old,
                neu,
                hasOld: !!old,
                hasNew: !!neu,
                user: by,
                userUrl: byId ? `/lightning/r/User/${byId}/view` : null
            };
        });
        const twin = (x) => `${x.createdRaw}|${x.fieldApi}`;
        const named = new Set(all.filter((x) => !(isIdOrEmpty(x.oldRaw) && isIdOrEmpty(x.newRaw))).map(twin));
        const rows = chainSameSecond(all.filter((x) => !(isIdOrEmpty(x.oldRaw) && isIdOrEmpty(x.newRaw) && (x.oldRaw || x.newRaw) && named.has(twin(x)))));
        this.rows = rows.slice(0, SHOWN);
        this.more = rows.length > SHOWN || !!data.nextPageToken;
        this.loaded = true;
    }

    // A new history row only exists after the record is saved: refresh when its LastModifiedDate changes.
    @wire(getRecord, { recordId: '$recordId', fields: '$stampFields' })
    handleRecord({ data }) {
        if (!data) return;
        const stamp = data.fields.LastModifiedDate.value;
        if (this.stamp && stamp !== this.stamp) this.refresh();
        this.stamp = stamp;
    }

    connectedCallback() {
        this.refreshId = registerRefreshHandler(this, this.refresh.bind(this));
    }

    disconnectedCallback() {
        if (this.refreshId) unregisterRefreshHandler(this.refreshId);
    }

    refresh() {
        return this.wired ? refreshApex(this.wired).then(() => true) : Promise.resolve(true);
    }

    get days() {
        const out = [];
        for (const r of this.rows) {
            let day = out[out.length - 1];
            if (!day || day.key !== r.dayKey) {
                day = { key: r.dayKey, label: r.dayLabel, items: [] };
                out.push(day);
            }
            day.items.push(r);
        }
        return out;
    }

    get title() {
        return this.loaded ? `${this.heading} (${this.rows.length}${this.more ? '+' : ''})` : this.heading;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get isEmpty() {
        return this.loaded && !this.error && this.rows.length === 0;
    }

    get isLoading() {
        return !this.loaded && !this.error;
    }

    get viewAllUrl() {
        return `/lightning/r/${this.object}/${this.recordId}/related/Histories/view`;
    }
}
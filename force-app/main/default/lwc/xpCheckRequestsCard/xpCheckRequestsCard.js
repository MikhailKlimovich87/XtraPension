import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';

// HMRC checks of the Application with the latest one first: number, date, who checked, the result and HMRC's answer
// (Notes, up to four lines); the earlier ones one line each. Replaces the standard "HMRC Check Requests" related
// list, whose "Has the request been processed?" was Not Done on 48,361 of 48,362 checks (Fernando, 03/11/2026).
// LWC + GraphQL only, no Apex.
// The same card on the Claim (05/11/2026): on a Basic__c it shows the Claim's DWP checks (Claim_Check__c).

const SHOWN = 3;

const CHECKS = gql`
    query applicationChecks($appId: ID) {
        uiapi {
            query {
                HMRC_Check__c(first: 3, where: { Application__c: { eq: $appId } }, orderBy: { CreatedDate: { order: DESC } }) {
                    edges {
                        node {
                            Id
                            Name { value }
                            CreatedDate { value }
                            Check_Date__c { value }
                            Check_Agents__c { value }
                            Priority_Request__c { value }
                            Notes__c { value }
                            CreatedBy { Name { value } }
                        }
                    }
                    pageInfo { hasNextPage }
                }
            }
        }
    }
`;

const CLAIM_CHECKS = gql`
    query claimChecks($claimId: ID) {
        uiapi {
            query {
                Claim_Check__c(first: 3, where: { Basic__c: { eq: $claimId } }, orderBy: { CreatedDate: { order: DESC } }) {
                    edges {
                        node {
                            Id
                            Name { value }
                            CreatedDate { value }
                            Check_Date__c { value }
                            Check_Agents__c { value }
                            Priority_Request__c { value }
                            Notes__c { value }
                            CreatedBy { Name { value } }
                        }
                    }
                    pageInfo { hasNextPage }
                }
            }
        }
    }
`;

// Priority Request values (a formula over the result boxes) and their colour.
const TONES = {
    'C2/C3/Received': 'info',
    DWP: 'info',
    'Payment Received': 'ok',
    '64-8': 'warn',
    'Not Received': 'warn',
    'Payment Not Received': 'warn',
    BadInfo: 'bad',
    BadNINO: 'bad',
    Reject: 'bad'
};
// Claim Check: the same colours as its Colour Label (red Not Received / Rejected, yellow more info, the rest green).
const CLAIM_TONES = {
    'Not Received': 'bad',
    Rejected: 'bad',
    'More Info': 'warn',
    'Payment Started': 'ok',
    'Lump Sum Letter': 'ok',
    Approved: 'ok',
    Processing: 'ok',
    Received: 'ok'
};

// Which checks each record page shows
const KINDS = {
    Application__c: { object: 'HMRC_Check__c', parentField: 'Application__c', list: 'HMRC_Check_Requests__r', title: 'HMRC Check Requests', tones: TONES },
    Basic__c: { object: 'Claim_Check__c', parentField: 'Basic__c', list: 'Claim_Checks__r', title: 'Claim Checks', tones: CLAIM_TONES }
};

// GraphQL returns text with HTML entities ("It&#39;s").
const ENTITIES = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&#x27;': "'" };
const decode = (s) => (typeof s === 'string' ? s.replace(/&(amp|lt|gt|quot|#39|#x27);/g, (m) => ENTITIES[m]) : s);
const v = (f) => (f ? decode(f.value) : null);

function formatter(options, timeZone) {
    try {
        return new Intl.DateTimeFormat(LOCALE, { ...options, timeZone });
    } catch (e) {
        return new Intl.DateTimeFormat(undefined, options);
    }
}
// Days as "24 Jun 2026", the same as Application History (Fernando, 03/11/2026).
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const dayLabel = (y, m, d) => `${String(d).padStart(2, '0')} ${MONTHS[Number(m) - 1]} ${y}`;
const LOCAL_PARTS = formatter({ year: 'numeric', month: 'numeric', day: 'numeric' }, TIME_ZONE);
function localDay(date) {
    const p = {};
    for (const x of LOCAL_PARTS.formatToParts(date)) p[x.type] = x.value;
    return dayLabel(p.year, p.month, p.day);
}
const LOCAL_DATE_TIME = formatter({ day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' }, TIME_ZONE);

export default class XpCheckRequestsCard extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    checks = [];
    more = false;
    loaded = false;
    error;
    wired;
    refreshId;

    // Without objectApiName it stays as before (Application__c)
    get kind() {
        return KINDS[this.objectApiName] || KINDS.Application__c;
    }

    get variables() {
        return this.recordId && this.kind === KINDS.Application__c ? { appId: this.recordId } : undefined;
    }

    get claimVariables() {
        return this.recordId && this.kind === KINDS.Basic__c ? { claimId: this.recordId } : undefined;
    }

    @wire(graphql, { query: CHECKS, variables: '$variables' })
    handleChecks(result) {
        if (this.kind === KINDS.Application__c) this.show(result);
    }

    @wire(graphql, { query: CLAIM_CHECKS, variables: '$claimVariables' })
    handleClaimChecks(result) {
        if (this.kind === KINDS.Basic__c) this.show(result);
    }

    show(result) {
        const kind = this.kind;
        this.wired = result;
        const { data, errors } = result;
        if (errors && errors.length) {
            this.error = errors.map((e) => e.message).join('; ');
            return;
        }
        if (!data) return;
        const conn = data.uiapi.query[kind.object];
        this.error = undefined;
        this.more = !!(conn.pageInfo && conn.pageInfo.hasNextPage);
        this.checks = conn.edges.map(({ node }) => {
            const created = new Date(v(node.CreatedDate));
            const checkDate = v(node.Check_Date__c);
            const createdBy = (node.CreatedBy && v(node.CreatedBy.Name)) || '';
            const result = v(node.Priority_Request__c);
            return {
                id: node.Id,
                name: v(node.Name),
                url: `/lightning/r/${kind.object}/${node.Id}/view`,
                date: checkDate ? dayLabel(...checkDate.split('-')) : localDay(created),
                who: v(node.Check_Agents__c) || createdBy.split(' ')[0],
                result,
                chipClass: `chip ${kind.tones[result] || 'info'}`,
                note: (v(node.Notes__c) || '').replace(/\s+/g, ' ').trim(),
                title: `Created ${LOCAL_DATE_TIME.format(created)}${createdBy ? ` by ${createdBy}` : ''}`
            };
        });
        this.loaded = true;
    }

    connectedCallback() {
        this.refreshId = registerRefreshHandler(this, this.refresh.bind(this));
    }

    disconnectedCallback() {
        if (this.refreshId) unregisterRefreshHandler(this.refreshId);
    }

    refresh() {
        return this.wired ? refreshGraphQL(this.wired).then(() => true) : Promise.resolve(true);
    }

    get latest() {
        return this.checks.length ? this.checks[0] : null;
    }

    get older() {
        return this.checks.slice(1, SHOWN);
    }

    get hasOlder() {
        return this.older.length > 0;
    }

    get heading() {
        return this.kind.title;
    }

    get title() {
        return this.loaded ? `${this.heading} (${this.checks.length}${this.more ? '+' : ''})` : this.heading;
    }

    get isEmpty() {
        return this.loaded && !this.error && this.checks.length === 0;
    }

    get isLoading() {
        return !this.loaded && !this.error;
    }

    get viewAllUrl() {
        return `/lightning/r/${this.objectApiName || 'Application__c'}/${this.recordId}/related/${this.kind.list}/view`;
    }

    handleMenu(event) {
        if (event.detail.value !== 'new') return;
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: this.kind.object, actionName: 'new' },
            state: {
                defaultFieldValues: encodeDefaultFieldValues({ [this.kind.parentField]: this.recordId }),
                navigationLocation: 'RELATED_LIST'
            }
        });
    }
}
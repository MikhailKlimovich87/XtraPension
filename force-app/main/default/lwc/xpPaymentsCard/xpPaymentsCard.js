import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LOCALE from '@salesforce/i18n/locale';

// Payments of the Application, one line per payment: product, PF number, amount and a coloured status.
// Replaces the standard related list, which spent four lines on each payment (Fernando, 03/11/2026).
// LWC + GraphQL only, no Apex.
// Mesmo card no Claim (Basic__c -> Basic_Payment__c), 04/11/2026: uma query fixa por objeto, só a do objeto da página
// roda. ID! de propósito: sem a variável o GraphQL ignora o filtro e traz os 200 primeiros pagamentos do org.

const PAYMENTS = gql`
    query applicationPayments($appId: ID!) {
        uiapi {
            query {
                Payment__c(first: 200, where: { Application__c: { eq: $appId } }, orderBy: { Name: { order: ASC } }) {
                    edges {
                        node {
                            Id
                            Name { value }
                            Product__r { Name { value } }
                            Amount__c { value }
                            CurrencyIsoCode { value }
                            Status__c { value }
                            Payment_Date__c { value }
                            Error_Message__c { value }
                        }
                    }
                    pageInfo { hasNextPage }
                }
            }
        }
    }
`;

const CLAIM_PAYMENTS = gql`
    query claimPayments($claimId: ID!) {
        uiapi {
            query {
                Basic_Payment__c(first: 200, where: { Basic__c: { eq: $claimId } }, orderBy: { Name: { order: ASC } }) {
                    edges {
                        node {
                            Id
                            Name { value }
                            Product__r { Name { value } }
                            Amount__c { value }
                            CurrencyIsoCode { value }
                            Status__c { value }
                            Payment_Date__c { value }
                            Error_Message__c { value }
                        }
                    }
                    pageInfo { hasNextPage }
                }
            }
        }
    }
`;

// objeto da página -> objeto do pagamento, lookup e related list
const BY_OBJECT = {
    Application__c: { child: 'Payment__c', parent: 'Application__c', rel: 'Payments__r' },
    Basic__c: { child: 'Basic_Payment__c', parent: 'Basic__c', rel: 'Basic_Payments__r' }
};

// Status__c values and their colour (CSS class). Submitted e Confirmed (GoCardless, só no Claim) = azul, como Schedule.
const TONES = { Paid: 'paid', Fail: 'fail', Refund: 'refund', Submitted: 'schedule', Confirmed: 'schedule', Schedule: 'schedule', Draft: 'draft', Cancel: 'cancel' };
// Footer totals, in this order; Cancel is left out.
const TOTALS = ['Paid', 'Fail', 'Refund', 'Confirmed', 'Submitted', 'Schedule', 'Draft'];

// GraphQL returns text with HTML entities ("Pension &amp; Tax Advice").
const ENTITIES = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&#x27;': "'" };
const decode = (s) => (typeof s === 'string' ? s.replace(/&(amp|lt|gt|quot|#39|#x27);/g, (m) => ENTITIES[m]) : s);
const v = (f) => (f ? decode(f.value) : null);

function money(amount, currency) {
    if (amount === null || amount === undefined) return '';
    try {
        return new Intl.NumberFormat(LOCALE, { style: 'currency', currency: currency || 'EUR' }).format(amount);
    } catch (e) {
        return `${currency || ''} ${Number(amount).toFixed(2)}`.trim();
    }
}

function day(isoDate) {
    if (!isoDate) return '';
    try {
        return new Intl.DateTimeFormat(LOCALE, { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(new Date(`${isoDate}T00:00:00Z`));
    } catch (e) {
        return isoDate;
    }
}

export default class XpPaymentsCard extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    payments = [];
    more = false;
    loaded = false;
    error;
    wired;
    refreshId;

    // Sem objectApiName fica como antes (Application__c).
    get object() {
        return BY_OBJECT[this.objectApiName] ? this.objectApiName : 'Application__c';
    }

    get cfg() {
        return BY_OBJECT[this.object];
    }

    get variables() {
        return this.recordId && this.object === 'Application__c' ? { appId: this.recordId } : undefined;
    }

    get claimVariables() {
        return this.recordId && this.object === 'Basic__c' ? { claimId: this.recordId } : undefined;
    }

    @wire(graphql, { query: PAYMENTS, variables: '$variables' })
    handleApplicationPayments(result) {
        if (this.object === 'Application__c') this.handlePayments(result);
    }

    @wire(graphql, { query: CLAIM_PAYMENTS, variables: '$claimVariables' })
    handleClaimPayments(result) {
        if (this.object === 'Basic__c') this.handlePayments(result);
    }

    handlePayments(result) {
        this.wired = result;
        const { data, errors } = result;
        if (errors && errors.length) {
            this.error = errors.map((e) => e.message).join('; ');
            return;
        }
        if (!data) return;
        const { child } = this.cfg;
        const conn = data.uiapi.query[child];
        this.error = undefined;
        this.more = !!(conn.pageInfo && conn.pageInfo.hasNextPage);
        this.payments = conn.edges.map(({ node }) => {
            const status = v(node.Status__c);
            const currency = v(node.CurrencyIsoCode);
            const amount = v(node.Amount__c);
            const name = v(node.Name);
            const date = day(v(node.Payment_Date__c));
            const tone = TONES[status] || 'draft';
            // Erro do Stripe/GoCardless no tooltip; num Paid é de uma tentativa antiga (249 Paid no Sales têm um), fica de fora.
            const failure = status === 'Paid' ? null : v(node.Error_Message__c);
            return {
                id: node.Id,
                name,
                product: (node.Product__r && v(node.Product__r.Name)) || 'No product',
                url: `/lightning/r/${child}/${node.Id}/view`,
                status: status || 'No status',
                currency,
                raw: amount,
                amount: money(amount, currency),
                rowClass: status === 'Cancel' ? 'row muted' : 'row',
                pillClass: `pill ${tone}`,
                title: [name, status, date, failure].filter(Boolean).join(' · ')
            };
        });
        this.loaded = true;
    }

    connectedCallback() {
        // Refreshes with the page (e.g. after a payment is created or edited from it).
        this.refreshId = registerRefreshHandler(this, this.refresh.bind(this));
    }

    disconnectedCallback() {
        if (this.refreshId) unregisterRefreshHandler(this.refreshId);
    }

    refresh() {
        return this.wired ? refreshGraphQL(this.wired).then(() => true) : Promise.resolve(true);
    }

    get title() {
        return this.loaded ? `Payments (${this.payments.length}${this.more ? '+' : ''})` : 'Payments';
    }

    get hasPayments() {
        return this.payments.length > 0;
    }

    get isEmpty() {
        return this.loaded && !this.error && this.payments.length === 0;
    }

    get isLoading() {
        return !this.loaded && !this.error;
    }

    get viewAllUrl() {
        return `/lightning/r/${this.object}/${this.recordId}/related/${this.cfg.rel}/view`;
    }

    // Sum per status (and per currency, in the rare app with more than one).
    get totals() {
        const sums = new Map();
        for (const p of this.payments) {
            if (!TOTALS.includes(p.status) || p.raw === null || p.raw === undefined) continue;
            const key = `${p.status}|${p.currency}`;
            sums.set(key, (sums.get(key) || 0) + p.raw);
        }
        return [...sums.entries()]
            .map(([key, sum]) => {
                const [status, currency] = key.split('|');
                return { key, status, value: money(sum, currency), cls: `total ${TONES[status]}` };
            })
            .sort((a, b) => TOTALS.indexOf(a.status) - TOTALS.indexOf(b.status));
    }

    handleMenu(event) {
        if (event.detail.value !== 'new') return;
        const { child, parent } = this.cfg;
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: { objectApiName: child, actionName: 'new' },
            state: {
                defaultFieldValues: encodeDefaultFieldValues({ [parent]: this.recordId }),
                navigationLocation: 'RELATED_LIST'
            }
        });
    }
}
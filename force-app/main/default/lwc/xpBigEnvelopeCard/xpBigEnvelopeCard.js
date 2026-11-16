import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { getRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import { buildRows } from './bigEnvelope';

// Card "Big Envelope & DWP" do Claim (Basic__c), gêmeo do xpKeyDocsCard do Sales: Big Envelope (Stage 1) enviado à
// gráfica e postado ao cliente, assinatura, mandato, documentos de volta na gráfica, Full forms (Stage 2), postado ao
// DWP e a checagem dos 45 dias. LWC + GraphQL, sem Apex. As regras das linhas estão em bigEnvelope.js.

// Campos do claim + arquivos (os títulos são classificados como no BP_DocumentsContentController, em bigEnvelope.js).
const CLAIM = gql`
    query claimBigEnvelope($id: ID) {
        uiapi {
            query {
                Basic__c(where: { Id: { eq: $id } }) {
                    edges {
                        node {
                            Status__c { value }
                            FTP_Claim_Created_Send_Date__c { value }
                            Claim_Created_ZIP_for_UPLOAD__c { value }
                            FTP_Claim_Created_Error__c { value }
                            FTP_Claim_Created_ZIP_Error__c { value }
                            Is_envelope_created__c { value }
                            Big_Envelop_Posted_Date__c { value }
                            Big_Envelop_Tracking_Number__c { value }
                            DocuSign_Date__c { value }
                            Bank_Account_Owner_Name__c { value }
                            Bank_Account_Owner_Email__c { value }
                            Owns_This_Account__c { value }
                            GoCardless_Mandate_Id__c { value }
                            Claim_Full_Form_ZIP_for_UPLOAD__c { value }
                            FTP_Claim_Full_Form_Created_Send_Date__c { value }
                            FTP_Claim_Full_Form_Error__c { value }
                            FTP_Claim_Full_Form_ZIP_Error__c { value }
                            Tracking_Number__c { value }
                            Process_Claim_Email_Date__c { value }
                        }
                    }
                }
                ContentDocumentLink(
                    first: 200
                    where: {
                        and: [
                            { LinkedEntityId: { eq: $id } }
                            { ContentDocument: { FileType: { ne: "SNOTE" } } }
                            {
                                or: [
                                    { ContentDocument: { Title: { like: "%Stage 1%" } } }
                                    { ContentDocument: { Title: { like: "%Stage 2%" } } }
                                    { ContentDocument: { Title: { like: "%Client Summary%" } } }
                                ]
                            }
                        ]
                    }
                ) {
                    edges {
                        node {
                            ContentDocumentId { value }
                            ContentDocument {
                                Title { value }
                                LatestPublishedVersion { CreatedDate { value } }
                            }
                        }
                    }
                }
            }
        }
    }
`;

// Envelopes do DocuSign do claim (dfsle__SourceId__c = Id de 18). Query separada: se o usuário não ler o objeto do
// DocuSign, o card continua e mostra só o plano de envelopes.
const ENVELOPES = gql`
    query claimEnvelopes($sourceId: String) {
        uiapi {
            query {
                dfsle__EnvelopeStatus__c(
                    first: 20
                    where: { dfsle__SourceId__c: { eq: $sourceId } }
                    orderBy: { CreatedDate: { order: DESC } }
                ) {
                    edges {
                        node {
                            dfsle__Status__c { value }
                            dfsle__EmailSubject__c { value }
                            dfsle__Sent__c { value }
                            CreatedDate { value }
                        }
                    }
                }
            }
        }
    }
`;

// A data do Posted to DWP não fica em campo nenhum: vem da mudança de Status__c no histórico, pela mesma related list
// do xpHistoryTimeline (no GraphQL o NewValue é um union e o wire do LDS não foi provado com ele). Sem filtro no
// wire: filtra Status__c aqui; 200 linhas cobrem a vida de um claim.
const HISTORY_FIELDS = ['Basic__History.Field', 'Basic__History.NewValue', 'Basic__History.CreatedDate'];
const HISTORY_SORT = ['-Basic__History.CreatedDate'];
const STAMP = ['Basic__c.LastModifiedDate'];

// GraphQL devolve texto com entidades HTML ("O&#39;Shea").
const ENTITIES = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&#39;': "'", '&#x27;': "'" };
const decode = (s) => (typeof s === 'string' ? s.replace(/&(amp|lt|gt|quot|#39|#x27);/g, (m) => ENTITIES[m]) : s);
const v = (f) => (f ? decode(f.value) : null);

// ISO -> 'YYYY-MM-DD' no fuso do usuário (o dia que ele vê nos outros cards).
function localYmd(iso) {
    if (!iso) return '';
    let parts;
    try {
        parts = new Intl.DateTimeFormat(LOCALE, { year: 'numeric', month: 'numeric', day: 'numeric', timeZone: TIME_ZONE }).formatToParts(new Date(iso));
    } catch (e) {
        parts = new Intl.DateTimeFormat(undefined, { year: 'numeric', month: 'numeric', day: 'numeric' }).formatToParts(new Date(iso));
    }
    const p = {};
    for (const x of parts) p[x.type] = x.value;
    return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
}

export default class XpBigEnvelopeCard extends NavigationMixin(LightningElement) {
    @api recordId;

    rows = [];
    loaded = false;
    error;
    claim;
    files = [];
    history = [];
    envelopes = null; // null = ainda não lidos (ou sem acesso): o card mostra o plano
    wiredClaim;
    wiredEnvelopes;
    wiredHistory;
    stamp;
    refreshId;

    get claimVars() {
        return this.recordId ? { id: this.recordId } : undefined;
    }

    get envelopeVars() {
        return this.recordId ? { sourceId: this.recordId } : undefined;
    }

    @wire(graphql, { query: CLAIM, variables: '$claimVars' })
    handleClaim(result) {
        this.wiredClaim = result;
        const { data, errors } = result;
        if (errors && errors.length) {
            this.error = errors.map((e) => e.message).join('; ');
            return;
        }
        if (!data) return;
        this.error = undefined;
        const q = data.uiapi.query;
        const edge = q.Basic__c.edges[0];
        const claim = {};
        if (edge) for (const k of Object.keys(edge.node)) claim[k] = v(edge.node[k]);
        this.claim = claim;
        this.files = q.ContentDocumentLink.edges.map(({ node }) => ({
            id: v(node.ContentDocumentId),
            title: v(node.ContentDocument.Title),
            created: node.ContentDocument.LatestPublishedVersion ? v(node.ContentDocument.LatestPublishedVersion.CreatedDate) : null
        }));
        this.compute();
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Histories',
        fields: HISTORY_FIELDS,
        sortBy: HISTORY_SORT,
        pageSize: 200
    })
    handleHistory(result) {
        this.wiredHistory = result;
        const { data, error } = result;
        // Sem histórico o card segue: a data do Posted to DWP cai para a data do e-mail ao cliente.
        if (error) this.history = [];
        else if (data) {
            this.history = data.records
                .filter((r) => r.fields.Field.value === 'Status__c')
                .map((r) => ({ newValue: r.fields.NewValue ? r.fields.NewValue.value : null, created: r.fields.CreatedDate.value }));
        } else return;
        this.compute();
    }

    // Linha nova no histórico só existe depois de salvar o claim (ex.: status mudado no path): atualiza quando o
    // LastModifiedDate muda, como o xpHistoryTimeline.
    @wire(getRecord, { recordId: '$recordId', fields: STAMP })
    handleStamp({ data }) {
        if (!data) return;
        const stamp = data.fields.LastModifiedDate.value;
        if (this.stamp && stamp !== this.stamp) this.refresh();
        this.stamp = stamp;
    }

    @wire(graphql, { query: ENVELOPES, variables: '$envelopeVars' })
    handleEnvelopes(result) {
        this.wiredEnvelopes = result;
        const { data, errors } = result;
        if (errors && errors.length) {
            this.envelopes = null;
        } else if (data) {
            this.envelopes = data.uiapi.query.dfsle__EnvelopeStatus__c.edges.map(({ node }) => ({
                status: v(node.dfsle__Status__c),
                subject: v(node.dfsle__EmailSubject__c),
                sent: v(node.dfsle__Sent__c),
                created: v(node.CreatedDate)
            }));
        } else return;
        this.compute();
    }

    compute() {
        if (!this.claim) return;
        this.rows = buildRows(this.claim, {
            files: this.files,
            history: this.history,
            envelopes: this.envelopes,
            today: localYmd(new Date().toISOString()),
            toDay: localYmd
        });
        this.loaded = true;
    }

    connectedCallback() {
        // Atualiza com a página (ex.: depois do Resend Big Envelope ou de um e-mail da gráfica).
        this.refreshId = registerRefreshHandler(this, this.refresh.bind(this));
    }

    disconnectedCallback() {
        if (this.refreshId) unregisterRefreshHandler(this.refreshId);
    }

    refresh() {
        const wires = [this.wiredClaim, this.wiredEnvelopes].filter(Boolean).map((w) => refreshGraphQL(w));
        if (this.wiredHistory) wires.push(refreshApex(this.wiredHistory));
        return Promise.all(wires).then(() => true);
    }

    get isLoading() {
        return !this.loaded && !this.error;
    }

    openFile(event) {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { recordIds: event.currentTarget.dataset.id }
        });
    }
}
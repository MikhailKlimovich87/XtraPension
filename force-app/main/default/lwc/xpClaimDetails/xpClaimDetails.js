import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import BASIC from '@salesforce/schema/Basic__c';
import { TABS, LOCATION } from './layoutSpec';
import { ALIASES, PREFER } from './searchAliases';

/**
 * O meio da página do Claim em abas (Client, Partner, UK & Abroad, DWP, Pension, Bank, Sale & Payment,
 * IPCBR1 & IPC1394, System). Gêmeo do xpApplicationDetails (salesforce/application-tabs): mesmo HTML, CSS, busca
 * "Find a field" e edição por aba; muda o objeto, as regras de "só aparece quando" e a aba dos editores (os dois
 * screen flows do Claim). Abas e seções vêm de layoutSpec.js (gerado de salesforce/claim-tabs/spec.cjs). Sem Apex.
 */

const filled = (v) => v !== null && v !== undefined && v !== '' && v !== false;
const FEE_STAGES = ['Awaiting DWP Payment', 'Charge DD', 'Closed Won'];
const isAU = (r) => r.CurrencyIsoCode === 'AUD' || r.Bank_Country_Code__c === 'AU' || r.Current_Address_Abroad_Country_Name__c === 'Australia';
const isIE = (r) => r.Current_Address_Abroad_Country_Name__c === 'Ireland' || r.Bank_Country_Code__c === 'IE';
const marital = (r, ...values) => values.includes(r.Claimant_marital_Status__c);

// "Só aparece quando" (fora da edição). Na edição aparece tudo, para dar para preencher.
const FIELD_RULES = {
    Claimant_nino__c: (r) => r.Has_Nino__c === 'Yes' || filled(r.Claimant_nino__c),
    PPS__c: (r) => isIE(r) || filled(r.PPS__c),
    Eircode__c: (r) => isIE(r) || filled(r.Eircode__c),
    Eircode_Verified__c: (r) => isIE(r) || filled(r.Eircode_Verified__c),
    Claimant_date_Of_Marriage__c: (r) => marital(r, 'Married', 'Civil Partner', 'Widowed', 'Divorced', 'Separated', 'Remarried') || filled(r.Claimant_date_Of_Marriage__c),
    // Remarried (11/11/2026 17h13): the first marriage ended in divorce or a death; a divorced client's former spouse may have died since.
    Claimant_date_Of_Divorce__c: (r) => marital(r, 'Divorced', 'Separated') || (marital(r, 'Remarried') && r.Previous_Marriage_Ended__c !== 'Widowed') || filled(r.Claimant_date_Of_Divorce__c),
    Claimant_date_Of_Bereavement__c: (r) => marital(r, 'Widowed', 'Divorced') || (marital(r, 'Remarried') && r.Previous_Marriage_Ended__c !== 'Divorced') || filled(r.Claimant_date_Of_Bereavement__c),
    Previous_Marriage_Ended__c: (r) => marital(r, 'Remarried') || filled(r.Previous_Marriage_Ended__c),
    Date_Of_Remarriage__c: (r) => marital(r, 'Remarried') || filled(r.Date_Of_Remarriage__c),
    // NINO do cônjuge: obrigatório quando ele já recebe pensão do UK (deck do John), mesmo com "Has Nino?" vazio.
    Partner_Nino__c: (r) => r.Partner_Has_Nino_values__c === 'Yes' || r.Partner_Claiming_UK_Pension__c === true || filled(r.Partner_Nino__c),
    Partner_Ever_Lived_UK_Notes__c: (r) => r.Partner_Ever_Lived_UK__c === true || filled(r.Partner_Ever_Lived_UK_Notes__c),
    Partner_is_Waiting_Uk_Benefits_text__c: (r) => r.Partner_is_Waiting_Uk_Benefits__c === true || filled(r.Partner_is_Waiting_Uk_Benefits_text__c),
    Claimant_lived_UK_From__c: (r) => r.Claimant_ever_Lived_UK__c === true || filled(r.Claimant_lived_UK_From__c),
    Claimant_lived_UK_to__c: (r) => r.Claimant_ever_Lived_UK__c === true || filled(r.Claimant_lived_UK_to__c),
    Claimant_Ever_Lived_UK_Notes__c: (r) => r.Claimant_ever_Lived_UK__c === true || filled(r.Claimant_Ever_Lived_UK_Notes__c),
    Claimant_worked_UK_From__c: (r) => r.Claimant_Ever_Worked_UK__c === true || filled(r.Claimant_worked_UK_From__c),
    Claimant_worked_UK_To__c: (r) => r.Claimant_Ever_Worked_UK__c === true || filled(r.Claimant_worked_UK_To__c),
    isYourPartnerCurrentlyGetPensionText__c: (r) => r.Is_Your_Partner_Currently_Get_Pension__c === true || filled(r.isYourPartnerCurrentlyGetPensionText__c),
    Claimant_is_Waiting_Uk_Benefits_text__c: (r) => r.Claimant_is_Waiting_Uk_Benefits__c === true || filled(r.Claimant_is_Waiting_Uk_Benefits_text__c),
    Pension_Start_Date__c: (r) => r.Pension_Claiming_from_Today__c !== true || filled(r.Pension_Start_Date__c),
    // HM Forces (BR1 Q17, 10/11/2026): os detalhes só quando serviu.
    ...Object.fromEntries(['Service', 'Enlisted', 'Discharged', 'Discharged_Where', 'Regiment', 'Service_No', 'Rank'].map((p) => {
        const api = `Claimant_HM_Forces_${p}__c`;
        return [api, (r) => r.Claimant_HM_Forces__c === true || filled(r[api])];
    })),
    // E-mail do dono da conta: só quando a conta não é do cliente (com nome e e-mail o DocuSign manda 2 envelopes).
    Bank_Account_Owner_Email__c: (r) => (filled(r.Owns_This_Account__c) && r.Owns_This_Account__c !== 'Claimant') || filled(r.Bank_Account_Owner_Email__c),
    // IBAN/BIC nos países com IBAN; conta + BSB (no campo Sort Code) na Austrália e onde não há IBAN.
    Bank_IBAN__c: (r) => filled(r.Bank_IBAN__c) || (!isAU(r) && !filled(r.Bank_Account__c)),
    Bank_BIC__c: (r) => filled(r.Bank_BIC__c) || (!isAU(r) && !filled(r.Bank_Account__c)),
    Bank_Account__c: (r) => filled(r.Bank_Account__c) || isAU(r) || !filled(r.Bank_IBAN__c),
    Bank_Sort_Code__c: (r) => filled(r.Bank_Sort_Code__c) || isAU(r) || !filled(r.Bank_IBAN__c),
    Partner_Address1__c: (r) => (r.Partner_same_as_claimant__c !== true && r.Partner_Address_Unknown__c !== true) || filled(r.Partner_Address1__c),
    Partner_Address2__c: (r) => (r.Partner_same_as_claimant__c !== true && r.Partner_Address_Unknown__c !== true) || filled(r.Partner_Address2__c),
    Partner_City__c: (r) => (r.Partner_same_as_claimant__c !== true && r.Partner_Address_Unknown__c !== true) || filled(r.Partner_City__c),
    Partner_State_Name__c: (r) => (r.Partner_same_as_claimant__c !== true && r.Partner_Address_Unknown__c !== true) || filled(r.Partner_State_Name__c),
    Partner_Postcode__c: (r) => (r.Partner_same_as_claimant__c !== true && r.Partner_Address_Unknown__c !== true) || filled(r.Partner_Postcode__c),
    Partner_Country__c: (r) => (r.Partner_same_as_claimant__c !== true && r.Partner_Address_Unknown__c !== true) || filled(r.Partner_Country__c),
};
const SECTION_RULES = {
    // Also once "Wants a helper?" is answered (11/11/2026), so a No shows on the page.
    helper: (r) => filled(r.Friend_First_Name__c) || filled(r.Friend_Last_Name__c) || filled(r.Friend_Phone__c) || filled(r.Friend_Email__c) || filled(r.Wants_Helper__c),
    award: (r) => filled(r.Award_Amount_GBP__c) || filled(r.DWP_Payment_Date__c) || FEE_STAGES.includes(r.Status__c),
    au: (r) => isAU(r) || filled(r.Age_Pension_now_or_next_year__c),
    accountant: (r) => r.Do_you_have_an_accountant__c === true || filled(r.Accountant_Name__c),
    remarried: (r) => marital(r, 'Remarried') || filled(r.Current_Spouse_First_Name__c) || filled(r.Current_Spouse_Last_Name__c),
};
// Aba Partner: só com cônjuge (estado civil, track B/C ou dado do parceiro já preenchido).
const TAB_RULES = {
    partner: (r) =>
        (filled(r.Claimant_marital_Status__c) && r.Claimant_marital_Status__c !== 'Single') ||
        r.Track__c === 'B' ||
        r.Track__c === 'C' ||
        filled(r.Partner_First_Name__c) ||
        filled(r.Partner_Surname__c),
};

// Listas dentro de uma seção (só leitura). Os imóveis no UK vão para o passo Summary do portal ("imposto de 20%").
const PROPERTY_FIELDS = ['Name', 'Address__c', 'Address_2__c', 'City__c', 'PostCode__c'].map((f) => `Claimant_UK_Property__c.${f}`);

// Editores do IPCBR1 e do IPC1394 (screen flows dos devs), como as abas da página antiga.
const EDITORS = [
    { flow: 'IPCBR1_Editor', label: 'IPCBR1 Editor' },
    { flow: 'IPC1394_Editor', label: 'IPC1394 Editor' },
];

// Endereço (campo composto): o lightning-output-field deixa endereço customizado em branco, então a tela
// monta o texto pelas partes e, na edição, mostra uma caixa por parte.
const ADDRESS_PARTS = ['Street__s', 'City__s', 'StateCode__s', 'PostalCode__s', 'CountryCode__s'];

const ALL_FIELDS = Object.keys(LOCATION);
const MAX_RESULTS = 10;
const norm = (s) => String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
// Para a busca: sem acento e pontuação vira espaço ("Nat Ins No:" -> "nat ins no", "e-mail" -> "e mail").
const clean = (s) => norm(s).replace(/[^a-z0-9]+/g, ' ').trim();
const STOP = new Set(['of', 'the', 'and', 'or', 'in', 'to', 'by', 'at', 'a', 'an', 'for']);
const apiWords = (name) => clean(name.replace(/__c$/, '').replace(/^X(?=\d)/, '').replace(/([a-z])([A-Z])/g, '$1 $2'));
const initials = (s, skipStop) => s.split(' ').filter((w) => w && !(skipStop && STOP.has(w))).map((w) => w[0]).join('');

// Erro de digitação: uma letra trocada, faltando, sobrando ou duas vizinhas invertidas (duas em palavra
// longa). Ex.: "insurence", "birht", "outstnding".
function closeEnough(a, b) {
    if (a.length < 4 || b.length < 4) return false;
    const max = a.length >= 8 ? 2 : 1;
    if (Math.abs(a.length - b.length) > max) return false;
    let prev2 = null;
    let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
    for (let i = 1; i <= a.length; i++) {
        const cur = [i];
        for (let j = 1; j <= b.length; j++) {
            let d = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
            if (prev2 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d = Math.min(d, prev2[j - 2] + 1);
            cur[j] = d;
        }
        prev2 = prev;
        prev = cur;
    }
    return prev[b.length] <= max;
}

// O que a busca compara em cada campo: rótulo, nome técnico, apelidos do time (searchAliases.js),
// siglas (Date of Birth -> "dob") e onde o campo fica (aba › seção).
function buildIndex(info) {
    const out = [];
    for (const name of ALL_FIELDS) {
        const f = info.fields[name];
        if (!f) continue;
        const label = clean(f.label);
        const api = apiWords(name);
        const aliases = (ALIASES[name] || []).map(clean);
        const acronyms = new Set([initials(label), initials(label, true), initials(api), initials(api, true)].filter((a) => a.length >= 2));
        const labelWords = [...new Set(`${label} ${api}`.split(' ').filter(Boolean))];
        const words = [...new Set([label, api, ...aliases].join(' ').split(' ').filter(Boolean))];
        out.push({ name, f, label, api, aliases, acronyms, labelWords, words, where: clean(LOCATION[name].label) });
    }
    return out;
}

// Menor = melhor; -1 = não bate.
function scoreOf(e, q, tokens) {
    if (e.label === q || e.aliases.includes(q)) return 0;
    if (e.label.startsWith(q) || e.acronyms.has(q.replace(/ /g, ''))) return 1;
    if (e.label.includes(q) || e.aliases.some((a) => a.startsWith(q))) return 2;
    if (e.api.includes(q) || e.aliases.some((a) => a.includes(q))) return 3;
    // palavra a palavra: primeiro no rótulo, depois nos apelidos; com erro de digitação vale menos
    const prefix = (ws) => (t) => ws.some((w) => w.startsWith(t));
    const typo = (ws) => (t) => ws.some((w) => closeEnough(t, w) || (w.length > t.length && closeEnough(t, w.slice(0, t.length))));
    const loose = (ws) => (t) => prefix(ws)(t) || typo(ws)(t);
    if (tokens.every(prefix(e.labelWords))) return 4;
    if (tokens.every(prefix(e.words))) return 4.5;
    if (tokens.every(loose(e.labelWords))) return 5;
    if (tokens.every(loose(e.words))) return 5.5;
    const whereWords = e.where.split(' ');
    if (tokens.every((t) => prefix(e.words)(t) || whereWords.some((w) => w.startsWith(t)))) return 6;
    return -1;
}

export default class XpClaimDetails extends NavigationMixin(LightningElement) {
    @api recordId;
    activeTab = TABS[0].id;
    editingTab = null;
    saving = false;
    toggled = {}; // seções abertas/fechadas pelo usuário
    query = '';
    flashApi = null;
    pendingScroll = null;
    info;
    index; // busca do Find a field, montada quando o objectInfo chega
    record;
    properties = [];
    flowRun = 0; // remonta o editor depois que ele termina, para dar para abrir de novo
    revealed = {}; // aba escondida pela regra (ex.: Partner) que o Find a field abriu

    @wire(getObjectInfo, { objectApiName: BASIC })
    wiredInfo({ data }) {
        if (data) {
            this.info = data;
            this.index = buildIndex(data);
        }
    }

    // Todos os campos da página que o usuário pode ver; endereço vem pelas partes e lookup pelo nome.
    get optionalFields() {
        if (!this.info) return undefined;
        const out = [];
        for (const name of ALL_FIELDS) {
            const f = this.info.fields[name];
            if (!f) continue;
            if (f.compound) for (const p of this.addressParts(name)) out.push(`Basic__c.${p.apiName}`);
            else out.push(`Basic__c.${name}`);
            if (f.reference && f.relationshipName) out.push(`Basic__c.${f.relationshipName}.Name`);
        }
        return out;
    }

    @wire(getRecord, { recordId: '$recordId', optionalFields: '$optionalFields' })
    wiredRecord({ data }) {
        if (data) this.record = data;
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Claimant_UK_Properties__r',
        fields: PROPERTY_FIELDS,
        pageSize: 50,
    })
    wiredProperties({ data }) {
        if (!data) return;
        const v = (r, f) => (r.fields[f] ? r.fields[f].value : null);
        this.properties = data.records.map((r) => ({
            id: r.id,
            url: `/lightning/r/Claimant_UK_Property__c/${r.id}/view`,
            line1: [v(r, 'Address__c'), v(r, 'Address_2__c')].filter(Boolean).join(', ') || v(r, 'Name') || 'Property',
            line2: [v(r, 'City__c'), v(r, 'PostCode__c')].filter(Boolean).join(' · '),
        }));
    }

    addressParts(name) {
        return Object.values(this.info.fields).filter((p) => p.compoundFieldName === name && p.apiName !== name);
    }

    get values() {
        const out = {};
        if (!this.record) return out;
        for (const [k, v] of Object.entries(this.record.fields)) out[k] = v && typeof v.value !== 'object' ? v.value : v && v.value;
        return out;
    }

    get ready() {
        return !!this.info && !!this.recordId;
    }

    get flowInputs() {
        return [{ name: 'recordId', type: 'String', value: this.recordId }];
    }

    get editors() {
        return EDITORS.map((e) => ({ ...e, key: `${e.flow}-${this.flowRun}` }));
    }

    get tabs() {
        const vals = this.values;
        const known = !!this.record;
        const out = [];
        for (const t of TABS) {
            const editing = this.editingTab === t.id;
            if (!editing && !this.revealed[t.id] && known && t.cond && !TAB_RULES[t.cond](vals)) continue;
            const sections = [];
            for (const s of t.sections) {
                if (!editing && known && s.cond && !SECTION_RULES[s.cond](vals)) continue;
                const open = this.toggled[s.key] !== undefined ? this.toggled[s.key] : !s.collapsed;
                const cols = s.cols.map((col, ci) => ({
                    key: `${s.key}-${ci}`,
                    fields: col
                        .filter((f) => this.info.fields[f.api])
                        .filter((f) => editing || !known || !FIELD_RULES[f.api] || FIELD_RULES[f.api](vals))
                        .map((f) => this.fieldView(f, editing)),
                }));
                const list = s.list === 'ukProperties' ? this.propertyList(vals) : null;
                sections.push({
                    key: s.key,
                    name: s.name,
                    sectionClass: open ? 'slds-section slds-is-open' : 'slds-section',
                    ariaExpanded: open ? 'true' : 'false',
                    open,
                    cols,
                    list,
                });
            }
            out.push({ id: t.id, title: t.title, isForms: t.forms, editing, sections });
        }
        return out;
    }

    // Imóveis no UK: só aparece quando a pergunta foi marcada ou já há imóvel na lista.
    propertyList(vals) {
        if (!this.properties.length && vals.Do_you_own_rent_any_UK_property__c !== true) return null;
        return { title: 'UK properties', rows: this.properties, empty: this.properties.length === 0 };
    }

    fieldView(f, editing) {
        const info = this.info.fields[f.api];
        const updateable = info.compound ? this.addressParts(f.api).some((p) => p.updateable) : info.updateable && !info.calculated;
        const canEdit = updateable && f.behavior !== 'Readonly';
        const view = {
            api: f.api,
            input: editing && canEdit,
            required: f.behavior === 'Required',
            pencil: !editing && canEdit,
            cls: `fld${this.flashApi === f.api ? ' flash' : ''}`,
        };
        if (info.compound) {
            view.address = true;
            view.addressInput = view.input;
            view.input = false;
            view.label = info.label;
            view.text = this.addressLines(f.api).join('\n');
            view.parts = ADDRESS_PARTS.map((s) => f.api.replace(/__c$/, `__${s}`)).filter((p) => this.info.fields[p]);
        } else if (info.dataType === 'Email') {
            // O lightning-output-field desenha um mailto: e o clique abria o Outlook (Grace, 03/11)
            const v = this.record ? this.record.fields[f.api] : null;
            view.email = true;
            view.label = info.label;
            view.text = v && v.value ? v.value : '';
            view.mailto = `mailto:${view.text}`;
        }
        return view;
    }

    // Abre o Send Email do Salesforce (o mesmo da página padrão) com o e-mail clicado no To e o helper em cópia:
    // todo e-mail ao cliente do Claim leva o helper em CC (Fernando, 04/11/2026).
    openEmail(event) {
        event.preventDefault();
        const to = event.currentTarget.dataset.email;
        const helper = (this.values.Friend_Email__c || '').trim();
        const defaults = { ToAddress: to };
        if (helper && helper.toLowerCase() !== String(to || '').trim().toLowerCase()) defaults.CcAddress = helper;
        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: { apiName: 'Global.SendEmail' },
            state: { recordId: this.recordId, defaultFieldValues: encodeDefaultFieldValues(defaults) },
        });
    }

    // Rua / "cidade, condado código" / país, como o Salesforce mostra.
    addressLines(name) {
        const fields = this.record ? this.record.fields : {};
        const part = (...suffixes) => {
            for (const s of suffixes) {
                const v = fields[name.replace(/__c$/, `__${s}`)];
                const text = v ? v.displayValue ?? v.value : null;
                if (text) return text;
            }
            return null;
        };
        const cityLine = [[part('City__s'), part('StateCode__s', 'State__s')].filter(Boolean).join(', '), part('PostalCode__s')].filter(Boolean).join(' ');
        return [part('Street__s'), cityLine, part('CountryCode__s', 'Country__s')].filter(Boolean);
    }

    handleTabActive(event) {
        const id = event.target.value;
        if (id !== this.activeTab && this.editingTab) this.editingTab = null;
        this.activeTab = id;
    }

    toggleSection(event) {
        const key = event.currentTarget.dataset.key;
        const s = TABS.flatMap((t) => t.sections).find((x) => x.key === key);
        const open = this.toggled[key] !== undefined ? this.toggled[key] : !s.collapsed;
        this.toggled = { ...this.toggled, [key]: !open };
    }

    startEdit() {
        this.editingTab = this.activeTab;
    }

    cancelEdit() {
        this.editingTab = null;
    }

    handleSubmit() {
        this.saving = true;
    }

    handleSaved() {
        this.saving = false;
        this.editingTab = null;
        // Os editores (IPCBR1 / IPC1394) guardam o registro de quando abriram e regravam tudo no Save deles:
        // recarrega para não desfazer o que acabou de ser salvo aqui.
        this.flowRun += 1;
        this.dispatchEvent(new ShowToastEvent({ title: 'Saved', variant: 'success' }));
    }

    handleError() {
        this.saving = false;
    }

    // O editor terminou (Save do flow): volta para a primeira tela, como a aba da página antiga fazia ao recarregar.
    handleFlowStatus(event) {
        if (event.detail.status === 'FINISHED' || event.detail.status === 'FINISHED_SCREEN') {
            this.flowRun += 1;
            this.dispatchEvent(new ShowToastEvent({ title: 'Saved', variant: 'success' }));
        }
    }

    // ---------- Find a field ----------
    get hasResults() {
        return this.results.length > 0;
    }

    get noResults() {
        return clean(this.query).length > 0 && !!this.record && this.results.length === 0;
    }

    get results() {
        const q = clean(this.query);
        if (!q || !this.index || !this.record) return [];
        const tokens = q.split(' ');
        const hits = [];
        for (const e of this.index) {
            let score = scoreOf(e, q, tokens);
            // Também pelo conteúdo: um e-mail, tracking, ano ou cidade digitado mostra em qual campo está.
            if (score < 0 && q.length >= 3 && e.f.dataType !== 'Boolean') {
                const s = this.shown(e.name, e.f);
                if (!s.empty && clean(s.text).includes(q)) score = 7;
            }
            if (score >= 0) hits.push({ score, e });
        }
        hits.sort((a, b) => a.score - b.score || PREFER.has(b.e.name) - PREFER.has(a.e.name));
        return hits.slice(0, MAX_RESULTS).map(({ e }) => ({ name: e.name, label: e.f.label, where: LOCATION[e.name].label, ...this.shown(e.name, e.f) }));
    }

    shown(name, f) {
        const values = this.record.fields;
        const val = (v) => (v ? v.displayValue ?? v.value : null);
        let text = null;
        if (f.compound) {
            text = this.addressLines(name).join(', ');
        } else if (f.reference && f.relationshipName) {
            const rel = values[f.relationshipName];
            text = rel && rel.value && rel.value.fields && rel.value.fields.Name ? rel.value.fields.Name.value : val(values[name]);
        } else {
            const v = values[name];
            if (v && f.dataType === 'Boolean') text = v.value ? 'Checked' : 'Not checked';
            else if (v && f.htmlFormatted && typeof v.value === 'string') {
                // fórmula HYPERLINK chega como &lt;a href=&quot;...&quot;&gt;texto&lt;/a&gt;
                const html = v.value.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');
                text = html.replace(/<[^>]*>/g, '');
            } else text = val(v);
        }
        const empty = text === null || text === undefined || text === '';
        return { text: empty ? '' : String(text), empty };
    }

    handleQuery(event) {
        this.query = event.detail.value;
    }

    handleKey(event) {
        if (event.key === 'Escape') this.query = '';
        // Enter abre o primeiro resultado
        if (event.key === 'Enter' && this.results.length) {
            event.preventDefault();
            this.openField(this.results[0].name);
        }
    }

    goToField(event) {
        this.openField(event.currentTarget.dataset.name);
    }

    // Abre a aba e a seção do campo, rola até ele e destaca por um instante.
    openField(name) {
        const loc = LOCATION[name];
        if (this.editingTab && this.editingTab !== loc.tab) this.editingTab = null;
        this.revealed = { ...this.revealed, [loc.tab]: true };
        this.activeTab = loc.tab;
        this.toggled = { ...this.toggled, [loc.section]: true };
        this.query = '';
        this.flashApi = name;
        this.pendingScroll = name;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.flashApi = null;
        }, 2000);
    }

    renderedCallback() {
        if (!this.pendingScroll) return;
        const el = this.template.querySelector(`[data-api="${this.pendingScroll}"]`);
        if (el) {
            this.pendingScroll = null;
            el.scrollIntoView({ block: 'center', behavior: 'smooth' });
        }
    }
}
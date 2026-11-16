// O que o quadro Lived & Worked mostra, a partir do que o XpLivedWorkedController.getData devolve. Separado do
// componente para testar fora do Salesforce com dados inventados (scratchpad/claims-page/build/lived-harness.ts).
// Regras: scratchpad/claims-page/research/01-forms-life-history.md §4.3 a §4.6 e §4.8.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
// Janela do HRP (Home Responsibilities Protection): anos fiscais de 6 Apr 1978 a 5 Apr 2010.
const HRP_FROM = '1978-04-06';
const HRP_TO = '2010-04-05';
// Step__c guarda a página em que o cliente ESTÁ: nestas duas o passo 2 ainda não foi gravado.
const BEFORE_STEP_2 = new Set(['', 'Friend / Family for Communication', 'About the Claimant']);
// Endereço no UK: o país só aparece quando não é o Reino Unido (ex.: Isle of Man).
const UK_NAMES = new Set(['', 'united kingdom', 'uk', 'gb', 'gbr', 'great britain', 'england', 'scotland', 'wales', 'northern ireland']);
export const UK_PLACES = ['United Kingdom', 'Isle of Man', 'Jersey', 'Guernsey'];
const ON_FORM = 2;

const CLIENT_FORM_NOTE = "The client's form rewrites countries and children when they press Next on step 2.";
const EMPTY_CARD = "Nothing yet: the short form and step 2 'About the claimant' are not done.";

/** "2026-10-06" -> "06 Oct 2026", como os outros quadros. */
export function day(iso) {
    if (!iso) return '';
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso);
    return m ? `${m[3]} ${MONTHS[Number(m[2]) - 1]} ${m[1]}` : String(iso);
}

/** Anos inteiros, com o último dia incluído: 01 Sep 1974 – 31 Aug 1977 = 3. */
export function wholeYears(from, to) {
    if (!from || !to) return null;
    const f = from.split('-').map(Number);
    const t = to.split('-').map(Number);
    const end = new Date(Date.UTC(t[0], t[1] - 1, t[2]) + 86400000);
    const ey = end.getUTCFullYear();
    const em = end.getUTCMonth() + 1;
    const ed = end.getUTCDate();
    return ey - f[0] - (em < f[1] || (em === f[1] && ed < f[2]) ? 1 : 0);
}

/** "6 y" (ou "<1 y"); vazio sem as duas datas ou com datas trocadas. */
export function duration(from, to) {
    const y = wholeYears(from, to);
    if (y === null || y < 0 || (to && from && to < from)) return '';
    return y < 1 ? '<1 y' : `${y} y`;
}

function range(from, to, now) {
    if (!from && !to && !now) return '';
    return `${day(from) || '?'} – ${now ? 'now' : day(to) || '?'}`;
}

/** Nome curto do número de previdência pelo país (o BP_MissingInfo usa os mesmos). */
export function numberLabel(code) {
    switch ((code || '').trim().toUpperCase()) {
        case 'IE': return 'PPS';
        case 'AU': return 'TFN';
        case 'NZ': return 'IRD';
        case 'CA': return 'SIN';
        case 'US': return 'SSN';
        default: return 'Social security no.';
    }
}

function hrpWindow(from, to) {
    if (!from && !to) return '';
    const f = from || to;
    const t = to || from;
    if (t < HRP_FROM || f > HRP_TO) return 'outside 1978–2010 window';
    if (f >= HRP_FROM && t <= HRP_TO) return 'in 1978–2010 window';
    return 'partly in 1978–2010 window';
}

function capitalise(s) {
    return s ? s.charAt(0).toUpperCase() + s.slice(1) : s;
}

function normTitle(t) {
    return (t || '').toLowerCase().replace(/\./g, '').trim();
}

/** Palavras do cônjuge, como o spouseNoun do BP_MissingInfo. Track B = marido, C = esposa. */
export function spouseWords(c) {
    let sex = c.Track__c === 'B' ? 'm' : c.Track__c === 'C' ? 'f' : null;
    if (!sex) {
        const partner = normTitle(c.Partner_Title__c);
        const own = normTitle(c.Claimant_title__c);
        if (partner === 'mr') sex = 'm';
        else if (['mrs', 'ms', 'miss'].includes(partner)) sex = 'f';
        else if (['mrs', 'ms', 'miss'].includes(own)) sex = 'm';
        else if (own === 'mr') sex = 'f';
        else sex = 'n';
    }
    const status = c.Claimant_marital_Status__c;
    const base = status === 'Civil Partner' && !c.Track__c ? 'civil partner' : sex === 'm' ? 'husband' : sex === 'f' ? 'wife' : 'spouse';
    const noun = status === 'Widowed' ? `late ${base}` : status === 'Divorced' || status === 'Separated' ? `former ${base}` : base;
    const his = sex === 'm' ? 'his' : sex === 'f' ? 'her' : 'their';
    const he = sex === 'm' ? 'he' : sex === 'f' ? 'she' : 'they';
    return { noun, Noun: capitalise(noun), his, His: capitalise(his), he };
}

/** known | never | forgot | null, pelo número ou pela resposta do formulário curto. */
function ninoState(answer, nino, hasFlag) {
    if (nino) return 'known';
    if (answer === 'Yes') return 'known';
    if (answer === 'Never Had') return 'never';
    if (answer === 'Forgot') return 'forgot';
    return hasFlag ? 'known' : null;
}

function step2Saved(c, ownCountries, children) {
    const status = c.Status__c || 'Form In Progress';
    if (status !== 'Form In Progress' && status !== 'Validation Call') return true;
    if (!BEFORE_STEP_2.has(c.Step__c || '') || !BEFORE_STEP_2.has(c.Agent_Form_Step__c || '')) return true;
    return ownCountries.length > 0 || children.length > 0;
}

function overflowChip(total) {
    return total > ON_FORM ? `${ON_FORM} on the form + ${total - ON_FORM} in Other information` : '';
}

function part(key, text, extra) {
    return text ? { key, text, href: (extra && extra.href) || null, cls: extra && extra.amber ? 'part amber' : 'part' } : null;
}

function googleLink(postcode, name) {
    if (!postcode) return null;
    return 'https://www.google.com/search?q=' + encodeURIComponent(`${postcode} ${name || ''}`.trim()).replace(/%20/g, '+');
}

function empty(text, tone) {
    return text ? { text, cls: `empty ${tone || 'grey'}` } : null;
}

// ------------------------------------------------------------------ linhas

function addressRow(r, kind, ctx) {
    const country = UK_NAMES.has((r.Country__c || '').trim().toLowerCase()) ? '' : r.Country__c;
    const line1 = [r.Address1__c, r.City__c, country].filter(Boolean).join(', ') || r.Postcode__c || 'UK address';
    const invalid = r.Verification_Status__c === 'Invalid';
    return row(r, kind, ctx, line1, null, [
        part('pc', r.Postcode__c),
        part('range', range(r.From_Date__c, r.To_Date__c)),
        part('dur', duration(r.From_Date__c, r.To_Date__c))
    ], invalid ? 'Address check: Invalid' : null);
}

function employerRow(r, kind, ctx) {
    return row(r, kind, ctx, r.Name || 'Employer (no name)', null, [
        part('city', r.City__c),
        part('pc', r.Postcode__c ? `${r.Postcode__c} ↗` : '', { href: googleLink(r.Postcode__c, r.Name) }),
        part('range', range(r.From_Date__c, r.To_Date__c)),
        part('dur', duration(r.From_Date__c, r.To_Date__c))
    ]);
}

function countryRow(r, kind, ctx) {
    const now = !!r.Is_Live_Here_Now__c;
    const label = numberLabel(r.Country_Type__c);
    const number = r.Social_Security_Number__c;
    return row(r, kind, ctx, r.Name || r.Country_Type__c || 'Country', now ? 'now' : null, [
        part('range', range(r.From_date__c, r.To_Date__c, now) || 'no dates', { amber: !r.From_date__c }),
        part('dur', duration(r.From_date__c, now ? ctx.today : r.To_Date__c)),
        number ? part('no', `${label} ${number}`) : part('no', `${label} missing`, { amber: true })
    ]);
}

function childRow(r, kind, ctx) {
    const minded = range(r.Minded_From__c, r.Minded_To__c);
    return row(r, kind, ctx, `${r.Name || 'Child'}${r.Dob__c ? ` · born ${day(r.Dob__c)}` : ''}`, null, [
        minded ? part('minded', `minded ${minded}`) : part('minded', 'minded dates missing', { amber: true }),
        part('hrp', hrpWindow(r.Minded_From__c, r.Minded_To__c)),
        part('nino', r.Nino__c ? `NINO ${r.Nino__c}` : '')
    ]);
}

function row(r, kind, ctx, line1, badge, parts, ownProblem) {
    const check = ctx.flagged.get(r.Id);
    return {
        key: r.Id,
        id: r.Id,
        kind,
        line1,
        badge,
        parts: parts.filter(Boolean),
        dot: !!(check || ownProblem),
        dotTitle: [check, ownProblem].filter(Boolean).join('; '),
        canEdit: ctx.editable
    };
}

function section(key, title, rows, chip, addKind, ctx, emptyLine, notes) {
    return {
        key,
        title: `${title} (${rows.length})`,
        chip: chip || '',
        addKind,
        canAdd: !!(ctx.editable && addKind),
        rows,
        empty: rows.length ? null : emptyLine || null,
        notes: (notes || []).filter(Boolean).map((text, i) => ({ key: `${key}-n${i}`, text }))
    };
}

// ------------------------------------------------------------------ quadro

/**
 * data = CardData do Apex (claim, companies, countries, children, checks, moreChecks, editable, lockReason,
 * clientCanEdit, ipcbr1Id, today). Devolve o que o template desenha.
 */
export function buildView(data) {
    const c = data.claim || {};
    const companies = data.companies || [];
    const countries = data.countries || [];
    const children = data.children || [];
    const today = data.today || new Date().toISOString().slice(0, 10);
    const editable = !!data.editable;
    const words = spouseWords(c);
    const track = c.Track__c || '';
    const onSpouse = track === 'B' || track === 'C';

    const flagged = new Map();
    const checks = (data.checks || []).map((k, i) => {
        for (const id of k.rowIds || []) if (!flagged.has(id)) flagged.set(id, k.text);
        return { key: `c${i}`, text: k.text };
    });
    const ctx = { flagged, editable, today };

    const ownAddr = companies.filter((r) => r.Is_Addresses__c && !r.Is_Partner__c);
    const ownEmp = companies.filter((r) => !r.Is_Addresses__c && !r.Is_Partner__c);
    const spAddr = companies.filter((r) => r.Is_Addresses__c && r.Is_Partner__c);
    const spEmp = companies.filter((r) => !r.Is_Addresses__c && r.Is_Partner__c);
    const ownCountries = countries.filter((r) => !r.Is_Partner__c);
    const spCountries = countries.filter((r) => r.Is_Partner__c);

    const saved = step2Saved(c, ownCountries, children);
    const view = { words, checks, editable, ipcbr1Id: data.ipcbr1Id || null };
    view.notes = [];
    if (!editable && data.lockReason) view.notes.push({ key: 'lock', text: data.lockReason });
    if (editable && data.clientCanEdit) view.notes.push({ key: 'client', text: CLIENT_FORM_NOTE });

    if (!c.Is_envelope_created__c && !saved && !companies.length && !countries.length && !children.length) {
        return { ...view, empty: EMPTY_CARD, header: [], blocks: [], hasChecks: false, more: '', extraAdds: [], hasExtraAdds: false, hasFoot: view.notes.length > 0 };
    }

    // NINO do registro que conta: o próprio (A) ou o do cônjuge (B/C).
    const ownNino = ninoState(c.Has_Nino__c, c.Claimant_nino__c, c.Claimant_hasNino__c);
    const spouseNino = ninoState(c.Partner_Has_Nino_values__c, c.Partner_Nino__c, c.Partner_Has_Nino__c);
    const nino = onSpouse ? spouseNino : ownNino;
    const widow = track === 'B' && (c.Is_Partner_alive__c === false || c.Claimant_marital_Status__c === 'Widowed');

    view.header = header(c, { track, words, nino, widow, onSpouse, saved, today });

    const q15 = ownAddr.length + spAddr.length;
    const q55 = ownCountries.length + spCountries.length;
    const livedNever = c.Claimant_ever_Lived_UK__c === false && saved;
    const workedNo = c.Claimant_Ever_Worked_UK__c === false && saved;
    const extraAdds = [];

    // Blocos do próprio cliente (endereços e empregadores no UK).
    const ownAddrSection = (title) =>
        section('ownAddr', title, ownAddr.map((r) => addressRow(r, 'ownAddress', ctx)), overflowChip(q15), 'ownAddress', ctx, null,
            [!onSpouse && ownNino === 'forgot' && ownAddr.length ? coverage(ownAddr, c) : '']);
    const ownEmpSection = (title) =>
        section('ownEmp', title, ownEmp.map((r) => employerRow(r, 'ownEmployer', ctx)), overflowChip(ownEmp.length), 'ownEmployer', ctx);

    const blocks = [];
    if (onSpouse) {
        blocks.push(spouseGroup(c, { words, spouseNino, widow, spAddr, spEmp, spCountries, q15, q55, ctx }));
        // Endereços e empregadores do próprio cliente: em geral nenhum (o pedido é pelo registro do cônjuge).
        const group = { key: 'own', heading: 'Your UK addresses and employers', actions: [], lines: [], sections: [], empty: null };
        if (ownAddr.length || ownEmp.length) {
            group.sections.push(ownAddrSection('Your UK addresses · Q15'), ownEmpSection('Your UK employers · Q18'));
        } else {
            group.empty = empty(`None (claiming on ${words.his} record).`);
            if (editable) group.actions = [{ kind: 'ownAddress', label: 'Address' }, { kind: 'ownEmployer', label: 'Employer' }];
        }
        blocks.push(group);
    } else {
        // Track A (ou ainda sem track).
        if (ownAddr.length || (!livedNever && ownNino === 'forgot')) {
            const s = ownAddrSection('UK addresses · Q15');
            if (!ownAddr.length) s.empty = empty('None. The NINO is unknown, so DWP needs UK addresses to trace it.', 'amber');
            blocks.push(single(s));
        } else extraAdds.push({ kind: 'ownAddress', label: 'UK address' });

        if (ownEmp.length || (!workedNo && (ownNino === 'forgot' || c.Claimant_Ever_Worked_UK__c === true))) {
            const s = ownEmpSection('UK employers · Q18');
            if (!ownEmp.length) {
                s.empty = ownNino === 'forgot'
                    ? empty('None. Needed to trace the NINO.', 'amber')
                    : empty('None listed (Q18 will say Yes with no employer).');
            }
            blocks.push(single(s));
        } else extraAdds.push({ kind: 'ownEmployer', label: 'UK employer' });
    }

    // Países depois do UK (Q55-63): os do cônjuge, se um dia existirem, ficam no bloco dele.
    const countryEmpty = saved
        ? empty('No country listed. The IPCBR1 needs every country since the UK (Q55).', 'red')
        : empty('None yet: the client adds them on step 2 of the form.');
    blocks.push(single(section('countries', 'Since the UK · Q55–63', ownCountries.map((r) => countryRow(r, 'country', ctx)), overflowChip(q55), 'country', ctx, countryEmpty)));

    // Filhos (HRP, Q53): todos vão para Other information.
    if (children.length || c.Claimant_Minded_Kids__c) {
        blocks.push(single(section('children', 'Children · HRP · Q53', children.map((r) => childRow(r, 'child', ctx)),
            children.length ? 'in Other information' : '', 'child', ctx, empty('Q53 says Yes but no child is listed.', 'amber'))));
    } else extraAdds.push({ kind: 'child', label: 'Child' });

    // Track A com linhas do cônjuge: o bloco dele só aparece quando existe algo.
    if (!onSpouse && (spAddr.length || spEmp.length || spCountries.length)) {
        blocks.push(spouseGroup(c, { words, spouseNino, widow: false, spAddr, spEmp, spCountries, q15, q55, ctx }));
    }

    view.blocks = blocks;
    view.hasChecks = checks.length > 0;
    view.more = data.moreChecks > 0 ? `and ${data.moreChecks} more` : '';
    view.extraAdds = editable ? extraAdds : [];
    view.hasExtraAdds = view.extraAdds.length > 0;
    view.hasFoot = view.hasExtraAdds || view.notes.length > 0;
    view.empty = null;
    return view;
}

function single(s) {
    return { key: `b-${s.key}`, heading: null, actions: [], lines: [], sections: [s], empty: null };
}

function header(c, o) {
    const rows = [];
    const add = (key, label, value, extra) => rows.push({ key, labelKey: `${key}-l`, label, value, valueClass: extra && extra.aqua ? 'aqua' : extra && extra.amber ? 'amber' : '', sub: (extra && extra.sub) || '' });

    let record;
    if (o.track === 'A') record = 'Own record (A)';
    else if (o.track === 'B') record = `Husband's record (B)${o.widow ? ' · widow' : ''}`;
    else if (o.track === 'C') record = "Wife's record (C)";
    else record = c.Is_envelope_created__c ? 'Not set' : 'Not chosen yet';
    add('record', 'Record', record);

    const whose = o.onSpouse ? `${o.words.his} ` : '';
    const ninoText = { known: 'Known', never: 'Never had', forgot: `Forgot → trace by ${whose}employers + addresses` }[o.nino] || 'Not answered yet';
    add('nino', 'NINO', ninoText, { amber: o.nino === 'forgot' });

    const from = c.Claimant_lived_UK_From__c;
    const to = c.Claimant_lived_UK_to__c;
    const approx = c.Approx_Years_in_UK__c ? `~${c.Approx_Years_in_UK__c} y (approx.)` : '';
    let inUk;
    if (from && to) inUk = [range(from, to), duration(from, to)].filter(Boolean).join(' · ');
    else if (to) inUk = [`until ${day(to)}`, approx].filter(Boolean).join(' · ');
    else if (from) inUk = `from ${day(from)}`;
    else if (approx) inUk = approx;
    else inUk = c.Claimant_ever_Lived_UK__c === false && o.saved ? 'Never' : 'Not given yet';
    add('inuk', 'In UK', inUk);

    const wf = c.Claimant_worked_UK_From__c;
    const wt = c.Claimant_worked_UK_To__c;
    add('worked', 'Worked', wf || wt ? range(wf, wt) : c.Claimant_Ever_Worked_UK__c === false && o.saved ? 'No' : 'Not given yet');

    const never = inUk === 'Never';
    if (!never || o.onSpouse) {
        const sub = o.onSpouse ? `${o.words.His} Left UK ${day(c.Partner_Left_UK__c) || 'not given'}` : '';
        if (to) add('left', 'Left UK', day(to), { aqua: true, sub });
        else add('left', 'Left UK', never ? 'Never lived there' : 'Not given', { sub });
    }
    return rows;
}

// "covers 1962–1979 of 1955–1979 in the UK": quanto dos anos no UK os endereços cobrem (informação, não alerta).
function coverage(rows, c) {
    const froms = rows.map((r) => r.From_Date__c).filter(Boolean).sort();
    const tos = rows.map((r) => r.To_Date__c).filter(Boolean).sort();
    if (!froms.length) return '';
    const a = froms[0].slice(0, 4);
    const z = (tos.length ? tos[tos.length - 1] : froms[froms.length - 1]).slice(0, 4);
    const lf = c.Claimant_lived_UK_From__c;
    const lt = c.Claimant_lived_UK_to__c;
    return lf && lt ? `covers ${a}–${z} of ${lf.slice(0, 4)}–${lt.slice(0, 4)} in the UK` : `covers ${a}–${z}`;
}

function spouseGroup(c, o) {
    const w = o.words;
    const towns = c.Partner_Towns_Lived__c;
    const lines = [];
    // O formulário curto grava o código do país no lugar das cidades (erro conhecido): só texto de verdade aparece.
    if (towns && !/^[A-Z]{2,3}$/.test(towns.trim())) lines.push({ key: 'towns', label: 'Towns', value: towns });
    const group = { key: 'spouse', heading: `${w.Noun}'s UK record`, actions: [], lines, sections: [], empty: null };
    const total = o.spAddr.length + o.spEmp.length + o.spCountries.length;
    if (!total) {
        group.empty = o.spouseNino === 'known'
            ? empty(`${w.His} NINO is known, so no employers or addresses are needed.`)
            : o.spouseNino === 'forgot' || o.widow
                ? empty(`None. Needed to trace ${w.his} NINO.`, 'amber')
                : empty('None listed.');
        if (o.ctx.editable) group.actions = [{ kind: 'spouseAddress', label: 'Address' }, { kind: 'spouseEmployer', label: 'Employer' }];
        return group;
    }
    const none = empty('None listed.');
    group.sections.push(
        section('spAddr', `${w.His} UK addresses · printed in Q15`, o.spAddr.map((r) => addressRow(r, 'spouseAddress', o.ctx)), overflowChip(o.q15), 'spouseAddress', o.ctx, none),
        section('spEmp', `${w.His} UK employers · printed in Q50`, o.spEmp.map((r) => employerRow(r, 'spouseEmployer', o.ctx)), overflowChip(o.spEmp.length), 'spouseEmployer', o.ctx, none)
    );
    if (o.spCountries.length) {
        group.sections.push(section('spCountries', `${w.His} countries · printed in Q55–63`, o.spCountries.map((r) => countryRow(r, 'spouseCountry', o.ctx)), overflowChip(o.q55), null, o.ctx));
    }
    return group;
}

// ------------------------------------------------------------------ formulário do modal

const ADDRESS_FIELDS = ['Address1__c', 'Address2__c', 'City__c', 'Postcode__c', 'Country__c', 'From_Date__c', 'To_Date__c'];
const EMPLOYER_FIELDS = ['Name', 'Address1__c', 'Address2__c', 'City__c', 'Postcode__c', 'From_Date__c', 'To_Date__c'];
const COUNTRY_FIELDS = ['Country_Type__c', 'Social_Security_Number__c', 'From_date__c', 'To_Date__c', 'Is_Live_Here_Now__c'];
const CHILD_FIELDS = ['Name', 'Nino__c', 'Dob__c', 'Minded_From__c', 'Minded_To__c'];

export const FORM_FIELDS = {
    ownAddress: ADDRESS_FIELDS,
    spouseAddress: ADDRESS_FIELDS,
    ownEmployer: EMPLOYER_FIELDS,
    spouseEmployer: EMPLOYER_FIELDS,
    country: COUNTRY_FIELDS,
    spouseCountry: COUNTRY_FIELDS,
    child: CHILD_FIELDS
};

const LABELS = {
    Name: 'Name',
    Address1__c: 'Address line 1',
    Address2__c: 'Address line 2',
    City__c: 'Town or city',
    Postcode__c: 'Postcode',
    Country__c: 'Country',
    From_Date__c: 'From',
    To_Date__c: 'To',
    Country_Type__c: 'Country',
    From_date__c: 'From',
    Is_Live_Here_Now__c: 'Lives there now',
    Social_Security_Number__c: 'Social security no.',
    Dob__c: 'Date of birth',
    Minded_From__c: 'Minded from',
    Minded_To__c: 'Minded to',
    Nino__c: 'NINO'
};
const DATES = new Set(['From_Date__c', 'To_Date__c', 'From_date__c', 'Dob__c', 'Minded_From__c', 'Minded_To__c']);
const WIDE = new Set(['Name', 'Address1__c', 'Address2__c', 'Country_Type__c', 'Is_Live_Here_Now__c']);

function thing(kind, words) {
    const own = { ownAddress: 'UK address', ownEmployer: 'UK employer', country: 'country', child: 'child' }[kind];
    if (own) return own;
    return `${words.his} ${{ spouseAddress: 'UK address', spouseEmployer: 'UK employer', spouseCountry: 'country' }[kind]}`;
}

/** Título e valores iniciais do modal (linha nova ou a linha clicada). */
export function formFor(kind, row, words) {
    const values = {};
    for (const f of FORM_FIELDS[kind]) values[f] = row && row[f] !== undefined ? row[f] : f === 'Is_Live_Here_Now__c' ? false : null;
    if (kind.endsWith('Address') && !UK_PLACES.includes(values.Country__c)) values.Country__c = 'United Kingdom';
    return { title: `${row ? 'Edit' : 'Add'} ${thing(kind, words)}`, values };
}

/** Campos do modal com os valores atuais (o "To" some quando o país é o atual). */
export function fieldsFor(kind, values, countryOptions) {
    return FORM_FIELDS[kind].map((name) => {
        let label = LABELS[name];
        if (name === 'Name') label = kind === 'child' ? "Child's name" : 'Employer';
        if (name === 'Social_Security_Number__c') label = numberLabel(values.Country_Type__c) === 'Social security no.' ? label : `${numberLabel(values.Country_Type__c)} number`;
        const isCombo = name === 'Country__c' || name === 'Country_Type__c';
        const options = name === 'Country__c' ? UK_PLACES.map((p) => ({ label: p, value: p })) : name === 'Country_Type__c' ? countryOptions || [] : null;
        const isCheckbox = name === 'Is_Live_Here_Now__c';
        const required = (name === 'Name' && kind !== 'country') || name === 'Country_Type__c';
        return {
            name,
            label,
            value: values[name] === null || values[name] === undefined ? '' : values[name],
            checked: !!values[name],
            type: DATES.has(name) ? 'date' : 'text',
            isCombo,
            isCheckbox,
            options,
            required,
            disabled: name === 'To_Date__c' && kind.endsWith('ountry') && !!values.Is_Live_Here_Now__c,
            max: name === 'Name' ? 80 : 255,
            cls: WIDE.has(name) ? 'field wide' : 'field'
        };
    });
}

/** Conferência antes de mandar: obrigatórios e datas na ordem. Texto do erro ou null. */
export function checkForm(kind, values) {
    if (kind.endsWith('Employer') && !(values.Name || '').trim()) return 'Add the employer name.';
    if (kind === 'child' && !(values.Name || '').trim()) return "Add the child's name.";
    if (kind.endsWith('ountry') && !values.Country_Type__c) return 'Pick the country.';
    if (kind.endsWith('Address') && !(values.Address1__c || '').trim() && !(values.Postcode__c || '').trim()) return 'Add the street or the postcode.';
    const from = values.From_Date__c || values.From_date__c || values.Minded_From__c;
    const to = kind.endsWith('ountry') && values.Is_Live_Here_Now__c ? null : values.To_Date__c || values.Minded_To__c;
    if (from && to && to < from) return 'The end date is before the start date.';
    return null;
}
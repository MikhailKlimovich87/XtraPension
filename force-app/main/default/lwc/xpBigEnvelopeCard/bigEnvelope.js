// Quais linhas o card "Big Envelope & DWP" mostra, a partir dos dados do claim. Separado do componente para testar
// fora do Salesforce (scratchpad/claims-page/build/bigenv-harness.ts e bigenv-gql-test.ts).
// Datas entram como 'YYYY-MM-DD' (campos Date) ou ISO (DateTime, convertidas por toDay no fuso do usuário).

// Os 19 valores de Status__c, na ordem do path.
export const STAGES = [
    'Form In Progress', 'Validation Call', 'Form completed', 'Pending Client', 'Agent Check', 'QC Approved',
    'Sent for eSignature', 'Signed - Waiting Docs at WDM', 'Posted to DWP', '45D Check', 'Awaiting Lump Sum Letter',
    'Agent Call', 'Decision Posted to DWP', 'Awaiting DWP Payment', 'Charge DD', 'Closed Won', 'On Hold',
    'Deposit Refund', 'Closed'
];
const SIGNED = 8;
const POSTED = 9;
const PAST_45D = 11;
const LAST_ACTIVE = 16; // Closed Won; depois vêm On Hold, Deposit Refund, Closed (fora da ordem)

/** 1..19 pela ordem do path, 0 quando desconhecido. */
export const stageNo = (status) => STAGES.indexOf(status) + 1;
const between = (n, a, b) => n >= a && n <= b;

/** Mesma classificação do BP_DocumentsContentController (contains, maiúsculas importam, a ordem importa). */
export function docType(t) {
    if (!t) return '';
    if (t.includes('IPCBR1') && !t.includes('Wet_Signature')) return 'IPCBR1 Full Form';
    if (t.includes('IPC1394') && !t.includes('Wet_Signature') && !t.includes('Payment_Notes')) return 'IPC1394 Full Form';
    if (t.includes('IPCBR1_Wet_Signature')) return 'IPCBR1 Wet';
    if (t.includes('IPC1394_Wet_Signature')) return 'IPC1394 Wet';
    if (t.includes('Client Summary')) return 'Client Summary';
    if (t.includes('_Pink')) return 'Pink Page';
    if (t.includes('_Yellow')) return 'Yellow Page';
    if (t.includes('_DWP')) return 'DWP Authority';
    if (t.includes('_Stage 1')) return 'Stage 1 ZIP';
    if (t.includes('_Stage 2')) return 'Stage 2 ZIP';
    if (t.includes('ENVELOPE_ZIP')) return 'ENVELOPE_ZIP';
    if (t.includes('_FULL_FORM_ZIP')) return 'FULL_FORM_ZIP';
    if (t.includes('IPC1394_Payment_Notes')) return 'Payment Notes';
    if (t.includes('Mandate')) return 'DD Mandate';
    return '';
}

const newestFirst = (a, b) => (b.created || '').localeCompare(a.created || '');

/** files: [{ id, title, created (ISO) }] -> o mais novo de cada: Stage 1 ZIP, Stage 2 ZIP, Client Summary. */
export function pickFiles(files) {
    const sorted = [...(files || [])].sort(newestFirst);
    const newest = (type) => sorted.find((f) => docType(f.title) === type) || null;
    return { stage1: newest('Stage 1 ZIP'), stage2: newest('Stage 2 ZIP'), summary: newest('Client Summary') };
}

/** history: [{ newValue, created (ISO) }] de Status__c -> ISO da mudança mais nova para Posted to DWP, ou null. */
export function postedAt(history) {
    const rows = (history || []).filter((h) => h.newValue === 'Posted to DWP').sort(newestFirst);
    return rows.length ? rows[0].created : null;
}

// Assuntos do BP_DocuSignController: 'UK State Pension - Claim (Summary)', '... (Direct Debit Mandate)' e o envelope
// único 'UK State Pension - Claim'. Qualquer outro assunto conta como envelope único.
export function envelopeKind(subject) {
    if (/\(Summary\)/i.test(subject || '')) return 'summary';
    if (/\(Direct Debit Mandate\)/i.test(subject || '')) return 'mandate';
    return 'both';
}

/** envelopes: [{ status, subject, sent, created }] -> a última rodada: o envelope único, ou Summary + mandate. */
export function latestRound(envelopes) {
    const sorted = [...(envelopes || [])].sort(newestFirst);
    if (!sorted.length) return [];
    if (envelopeKind(sorted[0].subject) === 'both') return [sorted[0]];
    const cut = sorted.findIndex((e) => envelopeKind(e.subject) === 'both');
    const recent = cut < 0 ? sorted : sorted.slice(0, cut);
    return [
        recent.find((e) => envelopeKind(e.subject) === 'summary'),
        recent.find((e) => envelopeKind(e.subject) === 'mandate')
    ].filter(Boolean);
}

const WORDS = { Sent: 'sent', Delivered: 'opened, waiting', Completed: 'signed', Declined: 'declined', Voided: 'voided' };
const word = (status) => WORDS[status] || String(status || 'unknown').toLowerCase();
const failed = (e) => e.status === 'Declined' || e.status === 'Voided';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** 'YYYY-MM-DD' -> '06 Oct 2026' (igual aos outros cards). */
export function fmtDay(ymd) {
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(ymd || '');
    return m ? `${m[3]} ${MONTHS[Number(m[2]) - 1]} ${m[1]}` : '';
}

/** 'YYYY-MM-DD' + n dias, em UTC (sem fuso). */
export function addDays(ymd, n) {
    const [y, m, d] = ymd.split('-').map(Number);
    return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/** Erro do Apex citado curto: espaços juntos, até max caracteres, entre aspas. */
export function brief(text, max = 120) {
    const t = String(text || '').replace(/\s+/g, ' ').trim();
    return `"${t.length > max ? t.slice(0, max - 1).trimEnd() + '…' : t}"`;
}

const blank = (s) => !s || !String(s).trim();

/**
 * c: o claim com os valores dos campos pelo nome da API. ctx: { files, history, envelopes (null = não lido),
 * today ('YYYY-MM-DD'), toDay (ISO -> 'YYYY-MM-DD') }. Devolve as linhas na ordem do card.
 */
export function buildRows(c, ctx) {
    const { files, history, envelopes, today } = ctx;
    const toDay = ctx.toDay || ((iso) => (iso ? String(iso).slice(0, 10) : ''));
    const n = stageNo(c.Status__c);
    const { stage1, stage2, summary } = pickFiles(files);
    const s1Sent = c.FTP_Claim_Created_Send_Date__c;
    const s2Sent = c.FTP_Claim_Full_Form_Created_Send_Date__c;
    const signed = c.DocuSign_Date__c;
    const rows = [];

    // Linha no molde do Key Docs. state: done (nome em negrito), wait (cinza), warn (âmbar), err (vermelho), act
    // (destacada: alguém precisa agir).
    const add = (key, label, o) => {
        const state = o.state || 'wait';
        const details = (o.details || []).filter((d) => d && d.text).map((d, i) => ({ key: `${key}-${i}`, text: d.text, cls: `detail ${d.cls || ''}`.trim() }));
        const hintCls = o.hintCls || (state === 'warn' || state === 'act' ? 'warn' : state === 'err' ? 'err' : '');
        rows.push({
            key,
            label,
            state,
            id: o.file ? o.file.id : null,
            nameClass: state === 'done' ? 'name' : 'name missing',
            hint: o.hint || '',
            hintClass: `hint ${hintCls}`.trim(),
            date: fmtDay(o.date),
            dateClass: o.dateWarn ? 'date warn' : 'date',
            details,
            rowClass: state === 'act' ? 'row act' : 'row',
            // texto completo ao passar o mouse (a dica corta com reticências)
            title: [o.hint, ...details.map((d) => d.text), o.file ? o.file.title : ''].filter(Boolean).join('\n')
        });
    };
    const notYet = { hint: 'not yet' };

    // 1. Big Envelope (Stage 1) para a gráfica. Os erros do Stage 1 nunca são limpos no sucesso: data e fila vêm antes.
    if (s1Sent) add('s1', 'Big Envelope sent to printer (PH)', { state: 'done', hint: 'sent', date: s1Sent, file: stage1 });
    else if (c.Claim_Created_ZIP_for_UPLOAD__c) add('s1', 'Big Envelope sent to printer (PH)', { hint: 'queued', details: [{ text: 'Goes to PH at the next hourly upload' }], file: stage1 });
    else if (!blank(c.FTP_Claim_Created_Error__c)) add('s1', 'Big Envelope sent to printer (PH)', { state: 'err', hint: 'upload error', details: [{ text: brief(c.FTP_Claim_Created_Error__c), cls: 'err' }], file: stage1 });
    else if (!c.Is_envelope_created__c) add('s1', 'Big Envelope sent to printer (PH)', { state: 'warn', hint: 'not built', details: [{ text: 'Short form not submitted', cls: 'warn' }] });
    else if (!blank(c.FTP_Claim_Created_ZIP_Error__c)) add('s1', 'Big Envelope sent to printer (PH)', { state: 'err', hint: 'ZIP not built', details: [{ text: brief(c.FTP_Claim_Created_ZIP_Error__c), cls: 'err' }], file: stage1 });
    else add('s1', 'Big Envelope sent to printer (PH)', { ...notYet, file: stage1 });

    // 2. Postado para o cliente: campos Big_Envelop_* (e-mail BIG ENV POSTED da gráfica). Stage_1_Pack_* estão mortos.
    if (c.Big_Envelop_Posted_Date__c) {
        const tracking = blank(c.Big_Envelop_Tracking_Number__c) ? '' : c.Big_Envelop_Tracking_Number__c.trim();
        add('posted1', 'Big Envelope posted to client', { state: 'done', hint: tracking || 'posted, no tracking', date: c.Big_Envelop_Posted_Date__c });
    } else add('posted1', 'Big Envelope posted to client', notYet);

    // 3. Assinatura. 2 envelopes só com nome E e-mail do dono da conta (sendEnvelopeMethod), não pelo Owns_This_Account__c.
    const ownerName = blank(c.Bank_Account_Owner_Name__c) ? '' : c.Bank_Account_Owner_Name__c.trim();
    const ownerEmail = !blank(c.Bank_Account_Owner_Email__c);
    const two = !!ownerName && ownerEmail;
    const owns = c.Owns_This_Account__c;
    const plan = two ? '2 envelopes' : '1 envelope to the client';
    const planDetail = two ? `Summary to client, mandate to ${ownerName}` : '';
    // Conta de outra pessoa sem e-mail do dono: vai 1 envelope e o cliente assina o mandato de uma conta que não é dele.
    const risk = !signed && !blank(owns) && owns !== 'Claimant' && !ownerEmail
        ? { text: `Account owner: ${owns}, no owner email. The client would sign the DD mandate for an account that isn't theirs.`, cls: 'warn' }
        : null;
    if (signed) {
        add('sign', 'Signature', { state: 'done', hint: 'signed', date: signed, file: summary });
    } else {
        const round = latestRound(envelopes);
        if (round.length) {
            const bad = round.find(failed);
            const done = round.filter((e) => e.status === 'Completed').length;
            const split = envelopeKind(round[0].subject) !== 'both';
            let hint;
            if (bad) hint = word(bad.status);
            else if (!split) hint = word(round[0].status);
            else if (done === round.length) hint = 'signed';
            else hint = done ? `waiting, ${done} of ${round.length} signed` : 'waiting';
            const who = (e) => (envelopeKind(e.subject) === 'summary' ? 'Summary (client)' : `Mandate (${ownerName || 'account owner'})`);
            const details = split ? round.map((e) => ({ text: `${who(e)}: ${word(e.status)}`, cls: failed(e) ? 'err' : '' })) : [];
            // Envelope 1 foi e o 2 falhou (sendMandateEnvelope): só se resolve anulando no DocuSign.
            if (split && round.length === 1 && !bad) {
                details.push({ text: envelopeKind(round[0].subject) === 'summary' ? 'DD mandate envelope not sent' : 'Summary envelope not sent', cls: 'warn' });
            }
            if (bad) details.push({ text: `Next send: ${plan}${planDetail ? ': ' + planDetail : ''}` });
            const newest = round.map((e) => e.sent || e.created).sort().pop();
            add('sign', 'Signature', { state: bad ? 'err' : 'wait', hint, date: toDay(newest), details: [...details, risk], file: summary });
        } else {
            add('sign', 'Signature', { hint: plan, hintCls: risk ? 'warn' : '', details: [{ text: planDetail }, risk], file: summary });
        }
    }

    // 4. Mandato do GoCardless: criado sozinho ao entrar em Signed (createMandate). Só a partir de Signed.
    if (between(n, SIGNED, LAST_ACTIVE) || signed) {
        if (!blank(c.GoCardless_Mandate_Id__c)) add('mandate', 'DD mandate', { state: 'done', hint: 'created' });
        else add('mandate', 'DD mandate', { state: 'warn', hint: 'not created' });
    }

    // 5. Documentos do cliente na gráfica: só o checkbox do e-mail "CLAIM - BIG ENVELOPE", sem data. O Resend apaga o
    // checkbox também quando falha, então um erro de envio do Stage 2 sem data conta como "chegou".
    const s2Err = !blank(c.FTP_Claim_Full_Form_Error__c);
    const back = !!c.Claim_Full_Form_ZIP_for_UPLOAD__c || (s2Err && !s2Sent);
    if (back && !s2Sent) add('back', 'Documents back at PH', { state: 'act', hint: 'received', details: [{ text: 'Send Stage 2 (Resend Big Envelope button)', cls: 'warn' }] });
    else if (back || s2Sent) add('back', 'Documents back at PH', { state: 'done', hint: 'received' });
    else if (s1Sent || c.Big_Envelop_Posted_Date__c || between(n, SIGNED, LAST_ACTIVE)) add('back', 'Documents back at PH', { hint: 'waiting' });
    else add('back', 'Documents back at PH', notYet);

    // 6. Full forms (Stage 2). Montar o ZIP de novo limpa o erro do ZIP e a data de envio, então o erro do ZIP é atual.
    if (s2Sent) add('s2', 'Full forms (Stage 2) sent', { state: 'done', hint: 'sent', date: s2Sent, details: s2Err ? [{ text: `Last resend failed: ${brief(c.FTP_Claim_Full_Form_Error__c)}`, cls: 'err' }] : [], file: stage2 });
    else if (!blank(c.FTP_Claim_Full_Form_ZIP_Error__c)) add('s2', 'Full forms (Stage 2) sent', { state: 'err', hint: 'ZIP not built', details: [{ text: brief(c.FTP_Claim_Full_Form_ZIP_Error__c), cls: 'err' }], file: stage2 });
    else if (s2Err) add('s2', 'Full forms (Stage 2) sent', { state: 'err', hint: 'upload error', details: [{ text: brief(c.FTP_Claim_Full_Form_Error__c), cls: 'err' }], file: stage2 });
    else if (stage2) add('s2', 'Full forms (Stage 2) sent', { hint: 'ZIP ready, not sent', file: stage2 });
    else add('s2', 'Full forms (Stage 2) sent', notYet);

    // 7. Postado ao DWP (e-mail "CLAIM"): nenhum campo guarda a data, vem do histórico do Status__c. Sem histórico, a
    // data do e-mail ao cliente (mesmo dia).
    const postedIso = postedAt(history);
    const postedDay = postedIso ? toDay(postedIso) : c.Process_Claim_Email_Date__c || '';
    const tracking = blank(c.Tracking_Number__c) ? '' : c.Tracking_Number__c.trim();
    const posted = !!postedIso || !!tracking || between(n, POSTED, LAST_ACTIVE);
    if (posted) {
        add('dwp', 'Posted to DWP', {
            state: 'done',
            hint: tracking || 'posted, no tracking',
            date: postedDay,
            details: c.Process_Claim_Email_Date__c ? [] : [{ text: 'Client email not sent', cls: 'warn' }]
        });
    } else add('dwp', 'Posted to DWP', notYet);

    // 8. Checagem dos 45 dias: postado + 45. Depois do 45D Check (Awaiting Lump Sum Letter em diante) já foi feita.
    if (!posted) add('d45', '45-day check', notYet);
    else if (!postedDay) add('d45', '45-day check', { hint: 'no posted date' });
    else {
        const due = addDays(postedDay, 45);
        if (between(n, PAST_45D, LAST_ACTIVE)) add('d45', '45-day check', { state: 'done', hint: 'done', date: due });
        else if (today && today > due) add('d45', '45-day check', { state: 'warn', hint: 'overdue', date: due, dateWarn: true });
        else add('d45', '45-day check', { hint: 'due', date: due });
    }
    return rows;
}
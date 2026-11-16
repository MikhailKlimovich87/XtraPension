/**
 * Quadro "Lived & Worked" da página do Claim (LWC xpLivedWorked), no lugar do Work do Sales.
 * Lê o claim e as três listas da história de vida (endereços e empregadores no UK, do cliente e do cônjuge;
 * países depois do UK; filhos para o HRP) e calcula as conferências de consistência (01 §4.6).
 * Também grava e apaga linhas pelo quadro, com a trava por status aplicada aqui, não só na tela:
 *   - edita em Form In Progress, Validation Call, Form completed, Pending Client, Agent Check e QC Approved;
 *   - em Sent for eSignature recusa (anular o envelope antes, como o BasicTriggerHandler faz no Basic__c);
 *   - de Signed - Waiting Docs at WDM em diante, só leitura (mudança vai para o IPC por carta).
 * Depois de gravar com o pacote já gerado (Form completed a QC Approved), põe na fila o
 * BP_RegeneratePackQueueable: mudança nos filhos não dispara nada hoje.
 */
public with sharing class XpLivedWorkedController {

    private static final Set<String> EDITABLE = new Set<String>{
        'Form In Progress', 'Validation Call', 'Form completed', 'Pending Client', 'Agent Check', 'QC Approved'
    };
    // O cliente ainda usa o formulário: o passo 2 apaga e recria países e filhos.
    private static final Set<String> CLIENT_FORM_OPEN = new Set<String>{ 'Form In Progress', 'Validation Call', 'Pending Client' };
    // O pacote existe: refaz IPCBR1, IPC1394, Client Summary, formulários wet e mandato (Stage 1 só se não foi enviado).
    private static final Set<String> REGENERATE = new Set<String>{ 'Form completed', 'Pending Client', 'Agent Check', 'QC Approved' };
    private static final Set<String> ASIDE = new Set<String>{ 'On Hold', 'Deposit Refund', 'Closed' };
    private static final String ESIGN = 'Sent for eSignature';
    private static final String SIGNED = 'Signed - Waiting Docs at WDM';

    // Datas aproximadas dos clientes (o portal força dia cheio): 90 dias de sobreposição, 365 de buraco.
    private static final Integer OVERLAP_DAYS = 90;
    private static final Integer HOLE_DAYS = 365;
    private static final Integer MAX_CHECKS = 5;

    private static final List<String> MONTHS = new List<String>{ 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' };
    // Países do endereço no UK (o portal grava GBR para o Reino Unido).
    private static final Map<String, String> UK_PLACES = new Map<String, String>{
        'United Kingdom' => 'GBR', 'Isle of Man' => 'IMN', 'Jersey' => 'JEY', 'Guernsey' => 'GGY'
    };

    // Campos que o quadro grava, por tipo de linha. As marcas (Is_Addresses__c, Is_Partner__c) vêm do tipo.
    private static final Map<String, List<String>> KIND_FIELDS = new Map<String, List<String>>{
        'ownAddress' => new List<String>{ 'Address1__c', 'Address2__c', 'City__c', 'Postcode__c', 'Country__c', 'From_Date__c', 'To_Date__c' },
        'spouseAddress' => new List<String>{ 'Address1__c', 'Address2__c', 'City__c', 'Postcode__c', 'Country__c', 'From_Date__c', 'To_Date__c' },
        'ownEmployer' => new List<String>{ 'Name', 'Address1__c', 'Address2__c', 'City__c', 'Postcode__c', 'From_Date__c', 'To_Date__c' },
        'spouseEmployer' => new List<String>{ 'Name', 'Address1__c', 'Address2__c', 'City__c', 'Postcode__c', 'From_Date__c', 'To_Date__c' },
        'country' => new List<String>{ 'Country_Type__c', 'From_date__c', 'To_Date__c', 'Is_Live_Here_Now__c', 'Social_Security_Number__c' },
        'spouseCountry' => new List<String>{ 'Country_Type__c', 'From_date__c', 'To_Date__c', 'Is_Live_Here_Now__c', 'Social_Security_Number__c' },
        'child' => new List<String>{ 'Name', 'Dob__c', 'Minded_From__c', 'Minded_To__c', 'Nino__c' }
    };
    private static final Set<String> DATE_FIELDS = new Set<String>{ 'From_Date__c', 'To_Date__c', 'From_date__c', 'Dob__c', 'Minded_From__c', 'Minded_To__c' };

    public class CardData {
        @AuraEnabled public Basic__c claim;
        @AuraEnabled public List<Claimant_Company__c> companies;
        @AuraEnabled public List<Claimant_Country_lived__c> countries;
        @AuraEnabled public List<Claimant_Child__c> children;
        @AuraEnabled public List<Check> checks;
        @AuraEnabled public Integer moreChecks;
        @AuraEnabled public Boolean editable;
        @AuraEnabled public String lockReason;
        @AuraEnabled public Boolean clientCanEdit;
        @AuraEnabled public Boolean regenerates;
        @AuraEnabled public Id ipcbr1Id;
        @AuraEnabled public String today;
    }

    public class Check {
        @AuraEnabled public String text;
        @AuraEnabled public List<Id> rowIds;
        Check(String text, List<Id> rowIds) {
            this.text = text;
            this.rowIds = rowIds == null ? new List<Id>() : rowIds;
        }
    }

    public class SaveResult {
        @AuraEnabled public Boolean regenerating;
        @AuraEnabled public Id rowId;
    }

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    // ------------------------------------------------------------------ leitura

    @AuraEnabled
    public static CardData getData(Id claimId) {
        try {
            Basic__c b = load(claimId);
            CardData d = new CardData();
            d.claim = b;
            d.companies = b.Claimant_Companies__r;
            d.countries = b.ClaimantCountrieslived__r;
            d.children = b.Clamant_Children__r;
            Date today = Date.today();
            d.today = String.valueOf(today);
            List<Check> all = checks(b, d.companies, d.countries, d.children, today);
            d.checks = new List<Check>();
            for (Integer i = 0; i < all.size() && i < MAX_CHECKS; i++) d.checks.add(all[i]);
            d.moreChecks = Math.max(0, all.size() - MAX_CHECKS);
            d.lockReason = lockReason(b.Status__c);
            d.editable = d.lockReason == null;
            d.clientCanEdit = CLIENT_FORM_OPEN.contains(b.Status__c);
            d.regenerates = REGENERATE.contains(b.Status__c);
            d.ipcbr1Id = latestIpcbr1(claimId);
            return d;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw fail(e.getMessage());
        }
    }

    /** Países da tabela Country__c (a mesma do portal): nome e código ISO de 2 letras. */
    @AuraEnabled(cacheable=true)
    public static List<Option> getCountryOptions() {
        List<Option> out = new List<Option>();
        for (Country__c c : [SELECT Name, Country_Code__c FROM Country__c WHERE Country_Code__c != null WITH USER_MODE ORDER BY Name LIMIT 1000]) {
            out.add(new Option(c.Name, c.Country_Code__c));
        }
        return out;
    }

    private static Basic__c load(Id claimId) {
        List<Basic__c> rows = [
            SELECT Id, Name, Status__c, Track__c, Step__c, Agent_Form_Step__c, Is_envelope_created__c, Is_Partner_alive__c,
                   Claimant_title__c, Claimant_dob__c, Claimant_marital_Status__c, Partner_Title__c, Partner_DOB__c,
                   Has_Nino__c, Claimant_hasNino__c, Claimant_nino__c, Partner_Has_Nino_values__c, Partner_Has_Nino__c, Partner_Nino__c,
                   Claimant_ever_Lived_UK__c, Claimant_lived_UK_From__c, Claimant_lived_UK_to__c, Approx_Years_in_UK__c,
                   Claimant_Ever_Worked_UK__c, Claimant_worked_UK_From__c, Claimant_worked_UK_To__c,
                   Partner_Ever_Lived_UK__c, Partner_Ever_Worked_UK__c, Partner_Left_UK__c, Partner_Towns_Lived__c,
                   Claimant_Minded_Kids__c, Current_Address_Abroad_Country_Name__c,
                   (SELECT Id, Name, Address1__c, Address2__c, City__c, Postcode__c, Country__c, Country_Type__c, From_Date__c, To_Date__c,
                           Is_Addresses__c, Is_Partner__c, isFullForm__c, Verification_Status__c, Address_Validated__c
                      FROM Claimant_Companies__r ORDER BY From_Date__c ASC NULLS LAST, CreatedDate ASC),
                   (SELECT Id, Name, Country_Type__c, From_date__c, To_Date__c, Is_Live_Here_Now__c, Is_Partner__c, Social_Security_Number__c
                      FROM ClaimantCountrieslived__r ORDER BY From_date__c ASC NULLS LAST, CreatedDate ASC),
                   (SELECT Id, Name, Dob__c, Minded_From__c, Minded_To__c, Nino__c
                      FROM Clamant_Children__r ORDER BY Dob__c ASC NULLS LAST, CreatedDate ASC)
            FROM Basic__c
            WHERE Id = :claimId
            WITH USER_MODE
        ];
        if (rows.isEmpty()) throw fail('Claim not found.');
        return rows[0];
    }

    // O IPCBR1 mais novo, sem o de assinatura molhada. O título é "..._IPCBR1" (pacote do portal) ou
    // "..._D5_IPCBR1" (editor): os dois são o mesmo arquivo, com versões novas.
    private static Id latestIpcbr1(Id claimId) {
        for (ContentDocumentLink l : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :claimId
              AND ContentDocument.Title LIKE '%IPCBR1%'
              AND (NOT ContentDocument.Title LIKE '%Wet_Signature%')
            ORDER BY ContentDocument.LastModifiedDate DESC
            LIMIT 1
        ]) {
            return l.ContentDocumentId;
        }
        return null;
    }

    @TestVisible
    private static String lockReason(String status) {
        if (String.isBlank(status) || EDITABLE.contains(status)) return null;
        if (status == ESIGN) return 'Out for eSignature: void the DocuSign envelope first.';
        if (status == SIGNED) return 'Signed: changes go to IPC by letter.';
        if (ASIDE.contains(status)) return 'Read-only while the claim is ' + status + '.';
        return 'Posted: changes go to IPC by letter.';
    }

    // ------------------------------------------------------------------ gravação

    /**
     * kind: ownAddress, ownEmployer, spouseAddress, spouseEmployer, country, spouseCountry, child.
     * rowId vazio = linha nova. fields: só os campos do tipo; o resto é ignorado.
     */
    @AuraEnabled
    public static SaveResult saveRow(Id claimId, String kind, Id rowId, Map<String, Object> fields) {
        Basic__c claim = guard(claimId);
        if (kind == null || !KIND_FIELDS.containsKey(kind)) throw fail('Unknown list: ' + kind);
        // A linha inteira em memória (nova, ou a do banco) para derivar e conferir; grava só os campos do quadro.
        SObject row = rowId == null ? newRow(claimId, kind) : existingRow(claimId, kind, rowId);
        Map<String, Object> values = fields == null ? new Map<String, Object>() : fields;
        for (String f : KIND_FIELDS.get(kind)) {
            if (!values.containsKey(f)) continue;
            Object v = values.get(f);
            if (DATE_FIELDS.contains(f)) row.put(f, toDate(v));
            else if (f == 'Is_Live_Here_Now__c') row.put(f, v == true || String.valueOf(v) == 'true');
            else row.put(f, v == null || String.isBlank(String.valueOf(v)) ? null : String.valueOf(v).trim());
        }
        fill(kind, row);
        validate(kind, row);
        SObject toSave = row;
        if (rowId != null) {
            toSave = rowId.getSObjectType().newSObject(rowId);
            Set<String> write = new Set<String>(KIND_FIELDS.get(kind));
            write.addAll(DERIVED.get(kind));
            for (String f : write) toSave.put(f, row.get(f));
        }
        try {
            if (rowId == null) insert as user toSave;
            else update as user toSave;
        } catch (Exception e) {
            throw fail(dmlMessage(e));
        }
        SaveResult r = new SaveResult();
        r.rowId = toSave.Id;
        r.regenerating = regenerate(claim);
        return r;
    }

    @AuraEnabled
    public static SaveResult deleteRow(Id claimId, Id rowId) {
        Basic__c claim = guard(claimId);
        if (rowId == null) throw fail('Nothing to delete.');
        existingRow(claimId, kindOf(rowId), rowId);
        try {
            delete as user rowId.getSObjectType().newSObject(rowId);
        } catch (Exception e) {
            throw fail(dmlMessage(e));
        }
        SaveResult r = new SaveResult();
        r.rowId = rowId;
        r.regenerating = regenerate(claim);
        return r;
    }

    // Trava por status, a mesma da tela.
    private static Basic__c guard(Id claimId) {
        if (claimId == null) throw fail('No claim.');
        List<Basic__c> rows = [SELECT Id, Status__c FROM Basic__c WHERE Id = :claimId WITH USER_MODE];
        if (rows.isEmpty()) throw fail('Claim not found.');
        String reason = lockReason(rows[0].Status__c);
        if (reason != null) throw fail(reason);
        return rows[0];
    }

    private static SObject newRow(Id claimId, String kind) {
        if (kind == 'country' || kind == 'spouseCountry') {
            return new Claimant_Country_lived__c(Basic__c = claimId, Is_Partner__c = kind == 'spouseCountry');
        }
        if (kind == 'child') return new Claimant_Child__c(Basic__c = claimId);
        // isFullForm__c = false: o passo 2 do formulário só apaga as linhas com true.
        return new Claimant_Company__c(
            Basic__c = claimId,
            Is_Addresses__c = kind.endsWith('Address'),
            Is_Partner__c = kind.startsWith('spouse'),
            isFullForm__c = false
        );
    }

    // A linha tem de ser deste claim e da lista em que foi clicada (as marcas não mudam pelo quadro).
    private static SObject existingRow(Id claimId, String kind, Id rowId) {
        Schema.SObjectType t = rowId.getSObjectType();
        SObject row;
        if (t == Claimant_Company__c.SObjectType) {
            List<Claimant_Company__c> rows = [
                SELECT Id, Basic__c, Is_Addresses__c, Is_Partner__c, Name, Address1__c, Address2__c, City__c, Postcode__c,
                       Country__c, Country_Type__c, From_Date__c, To_Date__c
                FROM Claimant_Company__c WHERE Id = :rowId WITH USER_MODE
            ];
            if (!rows.isEmpty() && kindOf(rows[0]) == kind) row = rows[0];
        } else if (t == Claimant_Country_lived__c.SObjectType) {
            List<Claimant_Country_lived__c> rows = [
                SELECT Id, Basic__c, Is_Partner__c, Name, Country_Type__c, From_date__c, To_Date__c, Is_Live_Here_Now__c, Social_Security_Number__c
                FROM Claimant_Country_lived__c WHERE Id = :rowId WITH USER_MODE
            ];
            if (!rows.isEmpty() && (rows[0].Is_Partner__c ? 'spouseCountry' : 'country') == kind) row = rows[0];
        } else if (t == Claimant_Child__c.SObjectType) {
            List<Claimant_Child__c> rows = [
                SELECT Id, Basic__c, Name, Dob__c, Minded_From__c, Minded_To__c, Nino__c
                FROM Claimant_Child__c WHERE Id = :rowId WITH USER_MODE
            ];
            if (!rows.isEmpty() && kind == 'child') row = rows[0];
        }
        if (row == null || (Id) row.get('Basic__c') != claimId) throw fail('This row is not in this list any more. Refresh the page.');
        return row;
    }

    private static String kindOf(Id rowId) {
        Schema.SObjectType t = rowId.getSObjectType();
        if (t == Claimant_Company__c.SObjectType) {
            for (Claimant_Company__c c : [SELECT Is_Addresses__c, Is_Partner__c FROM Claimant_Company__c WHERE Id = :rowId WITH USER_MODE]) return kindOf(c);
        } else if (t == Claimant_Country_lived__c.SObjectType) {
            for (Claimant_Country_lived__c c : [SELECT Is_Partner__c FROM Claimant_Country_lived__c WHERE Id = :rowId WITH USER_MODE]) {
                return c.Is_Partner__c ? 'spouseCountry' : 'country';
            }
        } else if (t == Claimant_Child__c.SObjectType) {
            return 'child';
        }
        throw fail('This row is not in this list any more. Refresh the page.');
    }

    private static String kindOf(Claimant_Company__c c) {
        return (c.Is_Partner__c ? 'spouse' : 'own') + (c.Is_Addresses__c ? 'Address' : 'Employer');
    }

    // Campos que o quadro deriva, como o portal grava: nome e código do país.
    private static final Map<String, List<String>> DERIVED = new Map<String, List<String>>{
        'ownAddress' => new List<String>{ 'Name', 'Country_Type__c' },
        'spouseAddress' => new List<String>{ 'Name', 'Country_Type__c' },
        'ownEmployer' => new List<String>{ 'Country__c', 'Country_Type__c' },
        'spouseEmployer' => new List<String>{ 'Country__c', 'Country_Type__c' },
        'country' => new List<String>{ 'Name' },
        'spouseCountry' => new List<String>{ 'Name' },
        'child' => new List<String>()
    };

    private static void fill(String kind, SObject row) {
        if (kind.endsWith('Address')) {
            // Endereço: Name = país (como o formulário curto), e o código de 3 letras do portal.
            String place = (String) row.get('Country__c');
            if (String.isBlank(place) || !UK_PLACES.containsKey(place)) place = 'United Kingdom';
            row.put('Country__c', place);
            row.put('Country_Type__c', UK_PLACES.get(place));
            row.put('Name', place);
        } else if (kind.endsWith('Employer')) {
            if (String.isBlank((String) row.get('Country__c'))) {
                row.put('Country__c', 'United Kingdom');
                row.put('Country_Type__c', 'GBR');
            }
        } else if (kind == 'country' || kind == 'spouseCountry') {
            String code = (String) row.get('Country_Type__c');
            if (String.isBlank(code)) throw fail('Pick the country from the list.');
            code = code.trim().toUpperCase();
            String name = null;
            for (Country__c c : [SELECT Name FROM Country__c WHERE Country_Code__c = :code WITH USER_MODE LIMIT 1]) name = c.Name;
            if (name == null) throw fail('Pick the country from the list.');
            row.put('Country_Type__c', code);
            row.put('Name', name);
            if (row.get('Is_Live_Here_Now__c') == true) row.put('To_Date__c', null);
        }
    }

    private static String dmlMessage(Exception e) {
        if (e instanceof DmlException && ((DmlException) e).getNumDml() > 0) return ((DmlException) e).getDmlMessage(0);
        return e.getMessage();
    }

    private static void validate(String kind, SObject row) {
        if (kind.endsWith('Employer') && String.isBlank((String) row.get('Name'))) throw fail('Add the employer name.');
        if (kind == 'child' && String.isBlank((String) row.get('Name'))) throw fail('Add the child\'s name.');
        if (kind.endsWith('Address') && String.isBlank((String) row.get('Address1__c')) && String.isBlank((String) row.get('Postcode__c'))) {
            throw fail('Add the street or the postcode.');
        }
        String name = (String) row.get('Name');
        if (name != null && name.length() > 80) throw fail('The name is longer than 80 characters.');
        Date fromDay = (Date) row.get(kind == 'child' ? 'Minded_From__c' : (kind.endsWith('ountry') ? 'From_date__c' : 'From_Date__c'));
        Date toDay = (Date) row.get(kind == 'child' ? 'Minded_To__c' : 'To_Date__c');
        if (fromDay != null && toDay != null && toDay < fromDay) throw fail('The end date is before the start date.');
    }

    // Refaz o pacote quando ele já existe; o fluxo em si é o mesmo do BasicTriggerHandler.
    private static Boolean regenerate(Basic__c claim) {
        if (!REGENERATE.contains(claim.Status__c) || Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) return false;
        // XpClaimDocs (10/11/2026): for an agent the job runs as XtraPension Admin, who can add versions to the files
        return XpClaimDocs.request(claim.Id, XpClaimDocs.REGENERATE);
    }

    private static Date toDate(Object v) {
        if (v == null) return null;
        if (v instanceof Date) return (Date) v;
        String s = String.valueOf(v).trim();
        if (String.isBlank(s)) return null;
        try {
            return Date.valueOf(s.left(10));
        } catch (Exception e) {
            throw fail('Not a date: ' + s);
        }
    }

    private static AuraHandledException fail(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    // ------------------------------------------------------------------ conferências (01 §4.6)

    /**
     * Só o que o DWP pergunta ou o que muda o dinheiro, na ordem de gravidade. Sem detectar buracos e
     * sobreposições entre endereços ou empregadores no UK: o formulário não pede história contínua.
     */
    @TestVisible
    private static List<Check> checks(Basic__c b, List<Claimant_Company__c> companies, List<Claimant_Country_lived__c> countries, List<Claimant_Child__c> children, Date today) {
        List<Check> reversed = new List<Check>();
        List<Check> impossible = new List<Check>();
        List<Check> current = new List<Check>();
        List<Check> abroadInUk = new List<Check>();
        List<Check> holes = new List<Check>();
        List<Check> outside = new List<Check>();
        List<Check> numbers = new List<Check>();

        Date ukFrom = b.Claimant_lived_UK_From__c;
        Date ukTo = b.Claimant_lived_UK_to__c;
        String his = possessive(b);

        // Faixas do UK no próprio claim.
        if (isReversed(ukFrom, ukTo)) reversed.add(new Check('In UK: end date before start date', null));
        if (isReversed(b.Claimant_worked_UK_From__c, b.Claimant_worked_UK_To__c)) reversed.add(new Check('Worked in UK: end date before start date', null));
        String ukProblem = impossibleDate(new List<Date>{ ukFrom, ukTo, b.Claimant_worked_UK_From__c, b.Claimant_worked_UK_To__c }, b.Claimant_dob__c, today);
        if (ukProblem != null) impossible.add(new Check('UK years: ' + ukProblem, null));

        // Empregadores e endereços no UK.
        Date rangeFrom = earliest(ukFrom, b.Claimant_worked_UK_From__c);
        Date rangeTo = latest(ukTo, b.Claimant_worked_UK_To__c);
        for (Claimant_Company__c c : companies) {
            String label = companyLabel(c) + (c.Is_Partner__c ? ' (' + his + ')' : '');
            List<Id> ids = new List<Id>{ c.Id };
            if (isReversed(c.From_Date__c, c.To_Date__c)) {
                reversed.add(new Check(label + ': end date before start date', ids));
                continue;
            }
            Date born = c.Is_Partner__c ? b.Partner_DOB__c : b.Claimant_dob__c;
            String problem = impossibleDate(new List<Date>{ c.From_Date__c, c.To_Date__c }, born, today);
            if (problem == null && !c.Is_Addresses__c && born != null && c.From_Date__c != null && c.From_Date__c < born.addYears(14)) {
                problem = 'starts before age 14';
            }
            if (problem != null) {
                impossible.add(new Check(label + ': ' + problem, ids));
                continue;
            }
            if (!c.Is_Partner__c && !c.Is_Addresses__c && rangeFrom != null && rangeTo != null && c.From_Date__c != null) {
                Date endDay = c.To_Date__c == null ? c.From_Date__c : c.To_Date__c;
                if (c.From_Date__c < rangeFrom.addDays(-OVERLAP_DAYS) || endDay > rangeTo.addDays(OVERLAP_DAYS)) {
                    outside.add(new Check(label + ': outside the UK years (' + day(rangeFrom) + ' – ' + day(rangeTo) + ')', ids));
                }
            }
        }

        // Países depois do UK (só os do cliente contam para os buracos e o "now").
        List<Claimant_Country_lived__c> own = new List<Claimant_Country_lived__c>();
        List<Claimant_Country_lived__c> nowRows = new List<Claimant_Country_lived__c>();
        for (Claimant_Country_lived__c c : countries) {
            String label = String.isBlank(c.Name) ? 'Country' : c.Name;
            if (c.Is_Partner__c) label += ' (' + his + ')';
            List<Id> ids = new List<Id>{ c.Id };
            Boolean bad = false;
            if (!c.Is_Live_Here_Now__c && isReversed(c.From_date__c, c.To_Date__c)) {
                reversed.add(new Check(label + ': end date before start date', ids));
                bad = true;
            } else {
                String problem = impossibleDate(new List<Date>{ c.From_date__c, c.Is_Live_Here_Now__c ? null : c.To_Date__c },
                    c.Is_Partner__c ? b.Partner_DOB__c : b.Claimant_dob__c, today);
                if (problem != null) {
                    impossible.add(new Check(label + ': ' + problem, ids));
                    bad = true;
                }
            }
            if (c.Is_Partner__c) continue;
            own.add(c);
            if (c.Is_Live_Here_Now__c) nowRows.add(c);
            if (String.isBlank(c.Social_Security_Number__c)) numbers.add(new Check(label + ': ' + numberName(c) + ' missing', ids));
            if (!bad && ukFrom != null && ukTo != null && c.From_date__c != null) {
                Date endDay = c.Is_Live_Here_Now__c ? today : (c.To_Date__c == null ? c.From_date__c : c.To_Date__c);
                Date a = c.From_date__c > ukFrom ? c.From_date__c : ukFrom;
                Date z = endDay < ukTo ? endDay : ukTo;
                if (a.daysBetween(z) > OVERLAP_DAYS) {
                    abroadInUk.add(new Check(label + ': overlaps the UK years by ' + span(a.daysBetween(z)) + ' (Q16 and Q57 disagree)', ids));
                }
            }
        }

        if (!own.isEmpty()) {
            if (nowRows.isEmpty()) {
                current.add(new Check('No country is marked "now" (Q57 needs the current one)', null));
            } else if (nowRows.size() > 1) {
                List<Id> ids = new List<Id>();
                for (Claimant_Country_lived__c c : nowRows) ids.add(c.Id);
                current.add(new Check(nowRows.size() + ' countries are marked "now"', ids));
            } else if (String.isNotBlank(b.Current_Address_Abroad_Country_Name__c)
                && String.isNotBlank(nowRows[0].Name)
                && b.Current_Address_Abroad_Country_Name__c.trim().toLowerCase() != nowRows[0].Name.trim().toLowerCase()) {
                current.add(new Check(nowRows[0].Name + ' is "now", but the address (Q6) is in ' + b.Current_Address_Abroad_Country_Name__c,
                    new List<Id>{ nowRows[0].Id }));
            }
        }

        // Tempo sem país depois de sair do UK. Começa na saída do UK: um país dentro dos anos do UK não abre buraco
        // (já aparece como sobreposição). A lista já vem por From_date__c.
        Date reach = ukTo;
        Claimant_Country_lived__c last = null;
        for (Claimant_Country_lived__c c : own) {
            if (c.From_date__c == null) continue;
            if (reach != null && reach.daysBetween(c.From_date__c) > HOLE_DAYS) {
                String before = last == null ? 'leaving the UK (' + day(reach) + ')' : last.Name;
                List<Id> ids = last == null ? new List<Id>{ c.Id } : new List<Id>{ last.Id, c.Id };
                holes.add(new Check(span(reach.daysBetween(c.From_date__c)) + ' not accounted for between ' + before + ' and ' + c.Name, ids));
            }
            Date endDay = c.Is_Live_Here_Now__c ? today : c.To_Date__c;
            if (endDay != null && (reach == null || endDay > reach)) {
                reach = endDay;
                last = c;
            }
        }
        if (!own.isEmpty() && nowRows.isEmpty() && last != null && reach.daysBetween(today) > HOLE_DAYS) {
            holes.add(new Check('Nothing listed since ' + last.Name + ' (' + day(reach) + ')', new List<Id>{ last.Id }));
        }

        // Filhos: só datas trocadas ou impossíveis; a janela do HRP aparece na própria linha.
        for (Claimant_Child__c c : children) {
            String label = String.isBlank(c.Name) ? 'Child' : c.Name;
            List<Id> ids = new List<Id>{ c.Id };
            if (isReversed(c.Minded_From__c, c.Minded_To__c)) {
                reversed.add(new Check(label + ': minded dates reversed', ids));
            } else if (c.Dob__c != null && c.Minded_From__c != null && c.Minded_From__c < c.Dob__c) {
                impossible.add(new Check(label + ': minded from before born', ids));
            } else {
                String problem = impossibleDate(new List<Date>{ c.Dob__c, c.Minded_From__c, c.Minded_To__c }, null, today);
                if (problem != null) impossible.add(new Check(label + ': ' + problem, ids));
            }
        }

        List<Check> out = new List<Check>();
        out.addAll(reversed);
        out.addAll(impossible);
        out.addAll(current);
        out.addAll(abroadInUk);
        out.addAll(holes);
        out.addAll(outside);
        out.addAll(numbers);
        return out;
    }

    private static Boolean isReversed(Date fromDay, Date toDay) {
        return fromDay != null && toDay != null && toDay < fromDay;
    }

    private static String impossibleDate(List<Date> days, Date born, Date today) {
        for (Date d : days) {
            if (d == null) continue;
            if (d > today) return 'date in the future (' + day(d) + ')';
            if (born != null && d < born) return 'date before birth (' + day(d) + ')';
        }
        return null;
    }

    private static Date earliest(Date a, Date b) {
        return a == null ? b : (b == null || a < b ? a : b);
    }

    private static Date latest(Date a, Date b) {
        return a == null ? b : (b == null || a > b ? a : b);
    }

    private static String companyLabel(Claimant_Company__c c) {
        if (!c.Is_Addresses__c) return String.isBlank(c.Name) ? 'UK employer' : c.Name;
        if (String.isNotBlank(c.Address1__c)) return c.Address1__c;
        return String.isBlank(c.City__c) ? 'UK address' : c.City__c;
    }

    // O nome do número de previdência pelo país, como no BP_MissingInfo.
    @TestVisible
    private static String numberName(Claimant_Country_lived__c c) {
        String code = String.isBlank(c.Country_Type__c) ? '' : c.Country_Type__c.trim().toUpperCase();
        if (code == 'IE') return 'PPS number';
        if (code == 'AU') return 'TFN';
        if (code == 'NZ') return 'IRD number';
        if (code == 'CA') return 'SIN';
        if (code == 'US') return 'SSN';
        return 'social security number';
    }

    // his / her pelo título, como o spouseNoun do BP_MissingInfo; B = marido, C = esposa.
    @TestVisible
    private static String possessive(Basic__c b) {
        if (b.Track__c == 'B') return 'his';
        if (b.Track__c == 'C') return 'her';
        String partner = title(b.Partner_Title__c);
        if (partner == 'mr') return 'his';
        if (partner == 'mrs' || partner == 'ms' || partner == 'miss') return 'her';
        String self = title(b.Claimant_title__c);
        if (self == 'mrs' || self == 'ms' || self == 'miss') return 'his';
        if (self == 'mr') return 'her';
        return 'spouse';
    }

    private static String title(String t) {
        return String.isBlank(t) ? '' : t.toLowerCase().replace('.', '').trim();
    }

    @TestVisible
    private static String span(Integer days) {
        if (days >= 365) return (days / 365) + ' y';
        return Math.max(1, days / 30) + ' months';
    }

    @TestVisible
    private static String day(Date d) {
        if (d == null) return '';
        return String.valueOf(d.day()).leftPad(2, '0') + ' ' + MONTHS[d.month() - 1] + ' ' + d.year();
    }
}
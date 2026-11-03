/**
 * PC1_RecordPageService — @AuraEnabled bridge for the 5 record-page LWCs
 * (Header, PathBar, ApplicationData, CallHistory, StageTimeline).
 *
 * All read methods are `cacheable=true` so the framework can wire them and
 * refresh via `refreshApex`. Write methods (saveField, saveNotes, changeStage)
 * are non-cacheable and audit-trail via PC1_Stage_Log__c where appropriate.
 * The legacy scheduleCall write was removed 2026-07-29 — scheduling now
 * flows through PC1_Call_Schedule__c (Pending rows), not Next_Call_At__c.
 *
 * getFlowConfig() returns the raw pc1-flow.json StaticResource body — the
 * ApplicationData LWC parses it client-side so we don't pay the JSON parse
 * cost on every render.
 */
public with sharing class PC1_RecordPageService {

    // ── APPLICATION ──────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static PC1_Application__c getApplication(Id recordId) {
        List<PC1_Application__c> rows = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Full_Name__c,
                   Email__c, Phone__c, DOB__c,
                   Address_Line1__c, Address_Line2__c, City__c, Postcode__c,
                   Notes__c, Stage__c, Stage_Changed_At__c, Next_Call_At__c,
                   DWP_Reference__c, Task_Instruction__c,
                   Progress_Filled__c, Progress_Total__c, Progress_Percent__c,
                   Mary_Progress_Filled__c, Mary_Progress_Total__c, Mary_Progress_Complete__c,
                   CreatedDate
              FROM PC1_Application__c
             WHERE Id = :recordId
             LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    // ── ANSWERS (application data) ───────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<PC1_Answer__c> getAnswers(Id recordId) {
        return [
            SELECT Id, Field_Id__c, Value__c, Source__c, Confidence__c, LastModifiedDate
              FROM PC1_Answer__c
             WHERE Application__c = :recordId
             ORDER BY Field_Id__c ASC
             LIMIT 1000
        ];
    }

    @AuraEnabled
    public static Id saveField(Id applicationId, String fieldId, String value, String source) {
        if (String.isBlank(fieldId)) throw new AuraHandledException('field_id is required');
        if (String.isBlank(source))  source = 'human';

        List<PC1_Answer__c> existing = [
            SELECT Id FROM PC1_Answer__c
             WHERE Application__c = :applicationId AND Field_Id__c = :fieldId
             LIMIT 1
        ];

        PC1_Answer__c ans;
        if (!existing.isEmpty()) {
            ans = existing[0];
            ans.Value__c = value;
            ans.Source__c = source;
            update ans;
        } else {
            ans = new PC1_Answer__c(
                Application__c = applicationId,
                Field_Id__c    = fieldId,
                Value__c       = value,
                Source__c      = source
            );
            insert ans;
        }
        try { PC1_MaryProgressCalculator.updateMaryProgress(applicationId); } catch (Exception ignore) {}
        return ans.Id;
    }

    // ── CALL HISTORY ─────────────────────────────────────────────────────

    /** Rows the Call History cards load; getCallHistoryCount says how many exist. */
    @TestVisible private static final Integer CALL_HISTORY_LIMIT = 50;

    /**
     * Newest calls first. Hidden: personalization-only placeholders that were
     * closed without a conversation (an inbound ring that never connected, or
     * a probe) — they are not calls. One still in progress is shown.
     * Transcript/recording links are re-signed here (PC1_UrlSigner.resignFileUrl)
     * because the token stored on the row goes stale when the signing scheme
     * changes; the record is not updated (cacheable read).
     */
    @AuraEnabled(cacheable=true)
    public static List<PC1_Call_Log__c> getCallHistory(Id recordId) {
        List<PC1_Call_Log__c> rows = [
            SELECT Id, Name, Direction__c, Started_At__c, Ended_At__c,
                   Duration_Min__c, Status__c, Voicemail_Left__c,
                   Detail__c, Task_Instruction__c, Rescheduled_To__c,
                   Conversation_Id__c, Source__c, Rep_Name__c, Transcript_URL__c,
                   Recording_URL__c, Summary__c, Personalization_Only__c
              FROM PC1_Call_Log__c
             WHERE Application__c = :recordId
               AND (Personalization_Only__c = false OR Status__c = 'in_progress')
             ORDER BY Started_At__c DESC NULLS LAST
             LIMIT :CALL_HISTORY_LIMIT
        ];
        for (PC1_Call_Log__c r : rows) {
            r.Transcript_URL__c = PC1_UrlSigner.resignFileUrl(r.Transcript_URL__c);
            r.Recording_URL__c  = PC1_UrlSigner.resignFileUrl(r.Recording_URL__c);
        }
        return rows;
    }

    /** Same filter as getCallHistory, without the row limit. */
    @AuraEnabled(cacheable=true)
    public static Integer getCallHistoryCount(Id recordId) {
        return [
            SELECT COUNT() FROM PC1_Call_Log__c
             WHERE Application__c = :recordId
               AND (Personalization_Only__c = false OR Status__c = 'in_progress')
        ];
    }

    // ── STAGE TIMELINE ───────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<PC1_Stage_Log__c> getStageHistory(Id recordId) {
        return [
            SELECT Id, From_Stage__c, To_Stage__c, Actor__c, Note__c,
                   Changed_At__c, Changed_By__r.Name
              FROM PC1_Stage_Log__c
             WHERE Application__c = :recordId
             ORDER BY Changed_At__c DESC
             LIMIT 50
        ];
    }

    // ── STAGES (path bar) ────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<PC1_Stage__mdt> getStages() {
        return [
            SELECT MasterLabel, DeveloperName, Order__c, Description__c,
                   Is_Terminal__c, Is_Human_Only__c
              FROM PC1_Stage__mdt
             ORDER BY Order__c ASC
        ];
    }

    // ── FLOW CONFIG (pc1-flow.json static resource) ──────────────────────

    @AuraEnabled(cacheable=true)
    public static String getFlowConfig() {
        List<StaticResource> rows = [SELECT Body FROM StaticResource WHERE Name = 'pc1FlowConfig' LIMIT 1];
        if (rows.isEmpty()) return '{"PAGES":[]}';
        return rows[0].Body.toString();
    }

    // ── FILES (native ContentDocument) ───────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getFiles(Id recordId) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (ContentDocumentLink l : [
            SELECT ContentDocumentId,
                   ContentDocument.Title, ContentDocument.FileType,
                   ContentDocument.ContentSize, ContentDocument.CreatedDate,
                   ContentDocument.LastModifiedDate,
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocument.OwnerId, ContentDocument.Owner.Name
              FROM ContentDocumentLink
             WHERE LinkedEntityId = :recordId
             ORDER BY ContentDocument.LastModifiedDate DESC
             LIMIT 200
        ]) {
            out.add(new Map<String, Object>{
                'id'             => l.ContentDocumentId,
                'title'          => l.ContentDocument.Title,
                'fileType'       => l.ContentDocument.FileType,
                'size'           => l.ContentDocument.ContentSize,
                'createdAt'      => l.ContentDocument.CreatedDate,
                'lastModified'   => l.ContentDocument.LastModifiedDate,
                'versionId'      => l.ContentDocument.LatestPublishedVersionId,
                'ownerId'        => l.ContentDocument.OwnerId,
                'ownerName'      => l.ContentDocument.Owner != null ? l.ContentDocument.Owner.Name : null
            });
        }
        return out;
    }

    /**
     * Delete a ContentDocument (removes the file from SF for everyone —
     * ContentDocument is org-wide, not per-record). Called from the pc1FilesFull
     * / pc1FilesCard row menu. Throws AuraHandledException with a friendly
     * message if the caller lacks delete permission on ContentDocument.
     */
    @AuraEnabled
    public static void deleteFile(Id contentDocumentId) {
        if (contentDocumentId == null) throw new AuraHandledException('Missing file id.');
        try {
            delete new ContentDocument(Id = contentDocumentId);
        } catch (DmlException e) {
            throw new AuraHandledException('Could not delete file: ' + e.getDmlMessage(0));
        }
    }

    // ── WRITES (notes / schedule / stage) ────────────────────────────────

    @AuraEnabled
    public static void saveNotes(Id applicationId, String notes) {
        update new PC1_Application__c(Id = applicationId, Notes__c = notes);
    }

    // scheduleCall removed 2026-07-29 — writing Next_Call_At__c directly
    // bypasses the PC1_Call_Schedule__c model (Pending rows + mirror trigger)
    // that everything else in the app now relies on. Scheduling flows come
    // in via pc1CallSchedule LWC → PC1_CallScheduleService.

    // ── CLIENTS LIST (home page) ─────────────────────────────────────────

    // Allowlist of every valid Stage__c picklist value, used by the LWC's
    // "stage:<Name>" filter keys so a hostile caller can't inject arbitrary
    // SOQL through the filter parameter — we bind the value only if it's
    // exactly one of these strings. Read from the picklist itself (2026-10-02):
    // the hand-kept list lacked every post-submission stage (Awarded, Fee
    // Charged, Closed - …), so those filters silently showed all clients.
    private static Set<String> knownStages {
        get {
            if (knownStages == null) {
                knownStages = new Set<String>();
                for (Schema.PicklistEntry p : PC1_Application__c.Stage__c.getDescribe().getPicklistValues()) {
                    if (p.isActive()) knownStages.add(p.getValue());
                }
            }
            return knownStages;
        }
        set;
    }

    /**
     * Resolve a filter key from the Clients LWC into a SOQL WHERE clause +
     * bind vars. Returns [whereSql, stageBind] — stageBind is non-null only
     * when the key is a 'stage:X' pattern the WHERE clause references as :stage.
     * Legacy shortcut keys (needs_human / awaiting_first_call / etc.) are
     * kept for backwards-compat with any bookmarked-state.
     */
    private static Map<String, Object> resolveFilter(String filter) {
        String f = String.isBlank(filter) ? 'all' : filter;
        String fLower = f.toLowerCase();
        String whereSql = '';
        String stageBind = null;

        if (f.startsWith('stage:')) {
            String stage = f.substring(6);
            if (knownStages.contains(stage)) {
                whereSql  = ' WHERE Stage__c = :stage';
                stageBind = stage;
            }
        } else if (fLower == 'needs_human')          whereSql = ' WHERE Stage__c = \'Needs Human\'';
        else if (fLower == 'awaiting_first_call')    whereSql = ' WHERE Stage__c = \'Awaiting First Call\'';
        else if (fLower == 'ready_for_review')       whereSql = ' WHERE Stage__c = \'Ready for Review\'';
        else if (fLower == 'ready_for_submit')       whereSql = ' WHERE Stage__c IN (\'Ready for Submit\',\'Reviewed\')';
        else if (fLower == 'my_clients')             whereSql = ' WHERE OwnerId = :currentUser';

        return new Map<String, Object>{ 'where' => whereSql, 'stage' => stageBind };
    }

    /**
     * getClientsList — list rows for the Pension Credit home-page Clients LWC.
     * Filter is 'all', 'my_clients', 'stage:<Any Picklist Value>', or one of
     * the legacy shortcut keys (needs_human / awaiting_first_call / etc).
     * Returns lightweight rows so 100+ clients render quickly. CreatedDate DESC.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getClientsList(String filter, Integer pageSize, Integer offset) {
        Integer lim  = (pageSize == null || pageSize <= 0 || pageSize > 200) ? 100 : pageSize;
        Integer skip = (offset == null || offset < 0) ? 0 : offset;
        Id currentUser = UserInfo.getUserId();
        Map<String, Object> f = resolveFilter(filter);
        String whereSql = (String) f.get('where');
        String stage    = (String) f.get('stage');

        String soql =
            'SELECT Id, Name, Full_Name__c, First_Name__c, Last_Name__c, ' +
            '       Phone__c, Stage__c, Next_Call_At__c, Notes__c, ' +
            '       Progress_Filled__c, Progress_Total__c, Progress_Percent__c, ' +
            '       CreatedDate ' +
            '  FROM PC1_Application__c' +
            whereSql +
            ' ORDER BY CreatedDate DESC' +
            ' LIMIT :lim OFFSET :skip';

        List<PC1_Application__c> rows = Database.query(soql);
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (PC1_Application__c a : rows) {
            String descriptor = null;
            if (a.Notes__c != null) {
                String n = a.Notes__c.trim();
                if (n.length() > 0 && n.length() <= 80) descriptor = n;
                else if (n.length() > 80) descriptor = n.substring(0, 77) + '...';
            }
            out.add(new Map<String, Object>{
                'id'            => a.Id,
                'name'          => a.Name,
                'fullName'      => a.Full_Name__c,
                'descriptor'    => descriptor,
                'phone'         => a.Phone__c,
                'stage'         => a.Stage__c,
                'nextCallAt'    => a.Next_Call_At__c,
                'progressFilled'=> a.Progress_Filled__c,
                'progressTotal' => a.Progress_Total__c,
                'progressPct'   => a.Progress_Percent__c,
                'createdAt'     => a.CreatedDate
            });
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static Integer getClientsCount(String filter) {
        Id currentUser = UserInfo.getUserId();
        Map<String, Object> f = resolveFilter(filter);
        String whereSql = (String) f.get('where');
        String stage    = (String) f.get('stage');
        String soql = 'SELECT COUNT() FROM PC1_Application__c' + whereSql;
        return Database.countQuery(soql);
    }

    @AuraEnabled
    public static void changeStage(Id applicationId, String newStage, String note) {
        List<PC1_Application__c> rows = [SELECT Id, Stage__c FROM PC1_Application__c WHERE Id = :applicationId LIMIT 1];
        if (rows.isEmpty()) throw new AuraHandledException('Application not found');
        // PC1_StageTransitionHelper (before-update trigger) writes the audit
        // row; hand it the note. This method used to insert its own row too,
        // so every record-page stage change was logged twice.
        PC1_StageTransitionHelper.pendingNote = String.isBlank(note) ? 'Changed via record page' : note;
        try {
            update new PC1_Application__c(Id = applicationId, Stage__c = newStage);
        } finally {
            PC1_StageTransitionHelper.pendingNote = null;
        }
    }
}
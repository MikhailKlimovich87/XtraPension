/**
 * Backing controller for the aaApplicationHistory LWC. Returns the most
 * recent AA_Application__History rows for one Application, along with
 * user-friendly field labels. Salesforce's own `force:relatedListSingleContainer`
 * silently ignores Histories on custom objects, so we render our own.
 */
public with sharing class AA_ApplicationHistoryController {

    public class HistoryRow {
        @AuraEnabled public Id      Id;
        @AuraEnabled public Datetime CreatedDate;
        @AuraEnabled public String  FieldLabel;    // e.g. "Stage"
        @AuraEnabled public String  FieldApiName;  // e.g. "Stage__c"
        @AuraEnabled public String  UserName;
        @AuraEnabled public Id      UserId;
        @AuraEnabled public String  OldValueDisplay;
        @AuraEnabled public String  NewValueDisplay;
    }

    /** Field ApiName → user-friendly label. Falls back to the API name when
     *  a field isn't in this map. Kept as static map instead of describe()
     *  so the LWC render stays fast on every wire refresh. */
    private static final Map<String, String> LABELS = new Map<String, String>{
        'Stage__c'             => 'Stage',
        'First_Name__c'        => 'First Name',
        'Last_Name__c'         => 'Last Name',
        'Phone__c'             => 'Phone',
        'Email__c'             => 'Email',
        'Address_Line1__c'     => 'Address',
        'City__c'              => 'City',
        'Postcode__c'          => 'Postcode',
        'DOB__c'               => 'Date of Birth',
        'Next_Call_At__c'      => 'Next Call',
        'Progress_Filled__c'   => 'Data Collected',
        'OwnerId'              => 'Owner',
        'Task_Instruction__c'  => 'Task Instruction',
        'DWP_Reference__c'     => 'DWP Reference',
        'created'              => 'Created'
    };

    @AuraEnabled(cacheable=true)
    public static List<HistoryRow> getHistory(Id recordId, Integer maxRows) {
        List<HistoryRow> out = new List<HistoryRow>();
        if (recordId == null) return out;
        Integer lim = (maxRows == null || maxRows <= 0) ? 5 : maxRows;

        List<AA_Application__History> raw = [
            SELECT Id, Field, CreatedDate, CreatedById, CreatedBy.Name,
                   OldValue, NewValue
              FROM AA_Application__History
             WHERE ParentId = :recordId
             ORDER BY CreatedDate DESC
             LIMIT :lim
        ];

        for (AA_Application__History h : raw) out.add(toRow(h));
        return out;
    }

    /** One History row → the LWC shape. Split out so the test class can
     *  cover the mapping: Apex tests never generate field-history rows, so
     *  the loop above always runs zero times under test (the class sat at
     *  0% coverage, audit 2026-10-02 F157). */
    @TestVisible
    private static HistoryRow toRow(AA_Application__History h) {
        HistoryRow r = new HistoryRow();
        r.Id              = h.Id;
        r.CreatedDate     = h.CreatedDate;
        r.FieldApiName    = h.Field;
        r.FieldLabel      = LABELS.containsKey(h.Field) ? LABELS.get(h.Field) : h.Field;
        r.UserName        = h.CreatedBy != null ? h.CreatedBy.Name : null;
        r.UserId          = h.CreatedById;
        r.OldValueDisplay = h.OldValue == null ? null : String.valueOf(h.OldValue);
        r.NewValueDisplay = h.NewValue == null ? null : String.valueOf(h.NewValue);
        return r;
    }

    /** Total count so the card header can show "Application History (N+)". */
    @AuraEnabled(cacheable=true)
    public static Integer getHistoryCount(Id recordId) {
        if (recordId == null) return 0;
        return [SELECT COUNT() FROM AA_Application__History WHERE ParentId = :recordId];
    }
}
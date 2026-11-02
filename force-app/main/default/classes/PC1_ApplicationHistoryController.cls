/**
 * Backing controller for the pc1ApplicationHistory LWC. Returns the most
 * recent PC1_Application__History rows for one Application, along with
 * user-friendly field labels. Salesforce's own `force:relatedListSingleContainer`
 * silently ignores Histories on custom objects, so we render our own.
 */
public with sharing class PC1_ApplicationHistoryController {

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

        List<PC1_Application__History> raw = [
            SELECT Id, Field, CreatedDate, CreatedById, CreatedBy.Name,
                   OldValue, NewValue
              FROM PC1_Application__History
             WHERE ParentId = :recordId
             ORDER BY CreatedDate DESC
             LIMIT :lim
        ];

        for (PC1_Application__History h : raw) {
            HistoryRow r = new HistoryRow();
            r.Id              = h.Id;
            r.CreatedDate     = h.CreatedDate;
            r.FieldApiName    = h.Field;
            r.FieldLabel      = LABELS.containsKey(h.Field) ? LABELS.get(h.Field) : h.Field;
            r.UserName        = h.CreatedBy != null ? h.CreatedBy.Name : null;
            r.UserId          = h.CreatedById;
            r.OldValueDisplay = h.OldValue == null ? null : String.valueOf(h.OldValue);
            r.NewValueDisplay = h.NewValue == null ? null : String.valueOf(h.NewValue);
            out.add(r);
        }
        return out;
    }

    /** Total count so the card header can show "Application History (N+)". */
    @AuraEnabled(cacheable=true)
    public static Integer getHistoryCount(Id recordId) {
        if (recordId == null) return 0;
        return [SELECT COUNT() FROM PC1_Application__History WHERE ParentId = :recordId];
    }
}
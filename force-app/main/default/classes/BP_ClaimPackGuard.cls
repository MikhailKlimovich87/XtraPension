/**
 * Knows which Basic__c fields feed the document pack (BR1, IPC1394, Client Summary, DD mandate)
 * and detects when one of them was changed.
 *
 * Used to (1) stop edits while the pack is out for eSignature and (2) regenerate the whole pack
 * when the data changes before it is sent, so the documents never disagree with each other.
 */
public without sharing class BP_ClaimPackGuard {

    private static final List<String> SOURCE_PREFIXES = new List<String>{
        'Claimant_', 'Partner_', 'Pension_', 'Bank_', 'Current_Address_Abroad'
    };

    private static final Set<String> SOURCE_EXACT = new Set<String>{
        'First_Name__c', 'Last_Name__c', 'Phone__c', 'Email__c', 'Eircode__c', 'PPS__c', 'Has_Nino__c',
        'Owns_This_Account__c', 'Paid_Interval__c', 'Ever_Self_Employed_UK_after_1978__c',
        'Work_In_UK_during_2_years__c', 'Ever_Pay_Reduced_UK_nino__c', 'Is_Partner_alive__c'
    };

    // Written by the document generation itself (country / state codes) - never a user edit
    private static final Set<String> DERIVED_FIELDS = new Set<String>{
        'Bank_Country_Code__c', 'Current_Address_Abroad_State__c', 'Current_Address_Abroad_Country__c',
        'Partner_State_Code__c', 'Partner_Country_Code__c'
    };

    private static Map<String, String> sourceFieldLabels;

    private static Map<String, String> getSourceFieldLabels() {
        if (sourceFieldLabels != null) {
            return sourceFieldLabels;
        }
        sourceFieldLabels = new Map<String, String>();
        for (Schema.SObjectField field : Schema.SObjectType.Basic__c.fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            String name = describe.getName();
            if (describe.isCalculated() || !describe.isUpdateable() || DERIVED_FIELDS.contains(name)
                || describe.getType() == Schema.DisplayType.ADDRESS
                || name.endsWith('__Latitude__s') || name.endsWith('__Longitude__s') || name.endsWith('__GeocodeAccuracy__s')) {
                continue;
            }
            Boolean isSource = SOURCE_EXACT.contains(name);
            for (String prefix : SOURCE_PREFIXES) {
                if (name.startsWith(prefix)) {
                    isSource = true;
                    break;
                }
            }
            if (isSource) {
                sourceFieldLabels.put(name, describe.getLabel());
            }
        }
        return sourceFieldLabels;
    }

    // Labels of the pack source fields whose value differs between old and updated
    public static List<String> changedSourceFields(Basic__c oldClaim, Basic__c updated) {
        List<String> changed = new List<String>();
        for (String name : getSourceFieldLabels().keySet()) {
            if (updated.get(name) != oldClaim.get(name)) {
                changed.add(getSourceFieldLabels().get(name));
            }
        }
        return changed;
    }
}
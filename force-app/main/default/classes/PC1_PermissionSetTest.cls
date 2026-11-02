/**
 * Non-admin access to PC1 (audit 2026-10-02 C9). Runs as a Standard User
 * with only PC1_Agent / PC1_Admin assigned and checks what the LWCs and
 * the standard UI rely on: object access, field visibility, and that money
 * fields stay read-only for agents.
 *
 * If this fails after adding a field or object, re-run
 *   node scripts/build-pc1-permsets.cjs --deploy
 */
@IsTest
private class PC1_PermissionSetTest {

    private static User userWith(String permSet) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String key = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        User u = new User(
            Alias = 'pc1' + key.left(5), Email = 'pc1.' + key + '@example.com', EmailEncodingKey = 'UTF-8',
            LastName = 'Agent', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_GB', ProfileId = p.Id,
            TimeZoneSidKey = 'Europe/London', UserName = 'pc1.' + key + '@example.com.pc1test');
        insert u;
        insert new PermissionSetAssignment(AssigneeId = u.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permSet].Id);
        return u;
    }

    @IsTest static void agent_can_work_applications_but_not_edit_money() {
        System.runAs(userWith('PC1_Agent')) {
            Schema.DescribeSObjectResult app = PC1_Application__c.SObjectType.getDescribe();
            System.assert(app.isAccessible() && app.isCreateable() && app.isUpdateable(), 'agents work applications');
            System.assert(!app.isDeletable(), 'agents do not delete applications');
            System.assert(PC1_Answer__c.SObjectType.getDescribe().isUpdateable());
            System.assert(PC1_Call_Schedule__c.SObjectType.getDescribe().isCreateable());
            System.assert(PC1_Handoff__c.SObjectType.getDescribe().isUpdateable());
            System.assert(PC1_Fee_Installment__c.SObjectType.getDescribe().isAccessible());
            System.assert(!PC1_Fee_Installment__c.SObjectType.getDescribe().isUpdateable(), 'installments read-only');
            System.assert(!PC1_Message_Template__c.SObjectType.getDescribe().isUpdateable(), 'templates are admin-only');
            System.assert(!Intake_User__c.SObjectType.getDescribe().isAccessible(), 'intake logins are admin-only');

            Map<String, Schema.SObjectField> f = app.fields.getMap();
            for (String readable : new List<String>{ 'Address_Line1__c', 'Bank_Sort_Code__c', 'DD_Mandate_Status__c',
                    'Fee_Amount__c', 'Award_Amount__c', 'AA_Intended__c' }) {
                System.assert(f.get(readable).getDescribe().isAccessible(), readable + ' must be visible');
            }
            System.assert(f.get('Address_Line1__c').getDescribe().isUpdateable(), 'agents correct addresses');
            for (String locked : new List<String>{ 'DD_Mandate_Id__c', 'DD_Mandate_Status__c', 'Award_Amount__c',
                    'Bank_Verification_Status__c', 'Auto_Submit_DWP__c' }) {
                if (f.containsKey(locked.toLowerCase()) || f.containsKey(locked)) {
                    System.assert(!f.get(locked).getDescribe().isUpdateable(), locked + ' only changes through guarded code');
                }
            }
        }
    }

    @IsTest static void admin_manages_templates_and_intake_logins() {
        // Intake_User__c.Password_Hash__c is a REQUIRED field, and required
        // fields are visible to anyone with object access (FLS cannot hide
        // them). It holds a bcrypt hash; only PC1_Admin reaches the object.
        System.runAs(userWith('PC1_Admin')) {
            System.assert(PC1_Message_Template__c.SObjectType.getDescribe().isUpdateable());
            System.assert(Intake_User__c.SObjectType.getDescribe().isAccessible());
            System.assert(PC1_Inbound_Email_DLQ__c.SObjectType.getDescribe().isAccessible());
        }
    }
}
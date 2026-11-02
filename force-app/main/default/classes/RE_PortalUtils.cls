public class RE_PortalUtils {
    private static final String UK_YEAR_FIELD_NAME = 'Years_Of_Work_In_The_UK__c';

    public static Reapply__c getFullReapplyData(Id recordId) {
        List<Reapply__c> reapplyData = new List<Reapply__c>();
        if (recordId != null) {
            reapplyData = [
                SELECT
                    Id,
                    Name,
                    Salutation__c,
                    First_Name__c, 
                    Second_Name__c,
                    UK_Address__City__s,
                    UK_Address__PostalCode__s,
                    UK_Address__Street__s,
                    NINO__c,
                    Date_of_birth__c,
                    Live_in_UK__c,
                    NINO_contribution_pay__c,
                    What_date_did_or_will_you_leave_the_UK__c,
                    Are_you_currently_living_outside_the_UK__c,
                    Prefer_contact_address__c,
                    living_working_abroad_current_tax_year__c,
                    Pay_voluntary_contributions__c,
                    NINO_contributions_in_tax_years__c,
                    Resident_in_rhe_UK_before_left__c,
                    employment_status_before_left_UK__c,
                    Stopped_working_for_last_UK_employer__c,
                    Last_employment_ended_date__c,
                    Has_your_UK_self_employment_ended__c,
                    Uk_self_employment_ended_date__c,
                    Where_you_receiving_JSA_before_left_UK__c,
                    Where_you_receiving_Child_Benefit__c,
                    Last_received_JSA_date__c,
                    Last_received_Child_Benefit_date__c,
                    Address_abroad__City__s,
                    toLabel(Address_abroad__CountryCode__s),
                    Address_abroad__PostalCode__s,
                    toLabel(Address_abroad__StateCode__s),
                    Address_abroad__Street__s,
                    Last_employer_Name__c,
                    Last_employer_Address__Street__s,
                    toLabel(Last_employer_Address__StateCode__s),
                    Last_employer_Address__PostalCode__s,
                    Last_employer_Address__City__s,
                    Is_previously_worked_abroad_as_an_emp__c,
                    Employer_abroad_Name__c,
                    Employer_abroad_Address__City__s,
                    toLabel(Employer_abroad_Address__CountryCode__s),
                    Employer_abroad_Address__PostalCode__s,
                    toLabel(Employer_abroad_Address__StateCode__s),
                    Employer_abroad_Address__Street__s,
                    Employment_ceased_end_date__c,
                    Start_employment_date__c,
                    Employer_an_overseas_gov_international__c,
                    Self_employer_work_before_left_UK__c,
                    Employer_s_UK_address__City__s,
                    Employer_s_UK_address__PostalCode__s,
                    Employer_s_UK_address__Street__s,
                    Employer_hold_your_contract_of_service__c,
                    Any_other_employments_abroad__c,
                    Phone__c,
                    Self_employed_abroad__c,
                    Start_self_employment_abroad_date__c,
                    End_self_employment_abroad_date__c,
                    Countries_names_with_dates__c,
                    Wish_to_pay_by__c,
                    Direct_debit_chosen__c
                FROM Reapply__c
                WHERE Id = :recordId
                LIMIT 1
            ];
        }
        if (reapplyData.size() > 0) {
            return reapplyData[0];
        } else return null;
    }
    
    public static Reapply__c getFindReapplyData(Id recordId) {
        List<Reapply__c> reapplyData = new List<Reapply__c>();
        if (recordId != null) {
            reapplyData = [
                SELECT
                    Application__c,
                    Application__r.Years_Of_Work_In_The_UK__c,
                    NINO_contributions_in_tax_years__c,
                    Live_in_UK__c,
                    NINO_contribution_pay__c,
                    Where_you_receiving_JSA_before_left_UK__c,
                    Last_received_JSA_date__c,
                    Where_you_receiving_Child_Benefit__c,
                    Last_received_Child_Benefit_date__c,
                    Submit_Form__c,
                    Address_abroad__City__s,
                    Address_abroad__CountryCode__s,
                    toLabel(Address_abroad__CountryCode__s) CountryCode,
                    Address_abroad__PostalCode__s,
                    Address_abroad__StateCode__s,
                    Address_abroad__Street__s,
                    Former_Name__c,
                    Phone__c,
                    Email__c,
                    First_Name__c,
                    Second_Name__c,
                    Application__r.Status__c,
                    Wish_to_pay_by__c,
                    (SELECT 
                        Status__c,
                        Payment_Date__c
                    FROM Reapply_Payments__r
                    WHERE Status__c ='Paid'
                    AND Product__r.Name = 'Reapply'
                    LIMIT 1)
                FROM Reapply__c
                WHERE Id = :recordId
                LIMIT 1
            ];
        }
        if (reapplyData.size() > 0) {
            return reapplyData[0];
        } else return null;
    }
    
    public static List<Application__History> getApplicationHistory(Id recordId) {
        List<Application__History> history = new List<Application__History>();
        if (recordId != null) {
            history = [
                SELECT
                    OldValue,
                    NewValue 
                FROM Application__History 
                WHERE Field = :UK_YEAR_FIELD_NAME 
                AND ParentId = :recordId
                ORDER BY CreatedDate
            ];
        }
        return history;
    }
    
    public static Reapply__c getRVN_ReapplyData(Id recordId) {
        List<Reapply__c> reapplyData = new List<Reapply__c>();
        if (recordId != null) {
            reapplyData = [
                SELECT
                    NINO__c,
                    Name,
                    Salutation__c,
                    First_Name__c,
                    Second_Name__c,
                    Date_of_birth__c,
                    Phone__c,
                    Address_abroad__City__s,
                    toLabel(Address_abroad__CountryCode__s),
                    Address_abroad__PostalCode__s,
                    toLabel(Address_abroad__StateCode__s),
                    Address_abroad__Street__s,
                    Class_2_Class_3_2024_2025_2025_2026__c,
                    Best_time_to_call__c,
                    Is_this_the_address_where_we_can_send_yo__c,
                    Abroad_for_the_full_2026_2027_taxYear__c,
                    employer_be_paying_your_NI_contr_abroad__c,
                    NINO_contribution_pay__c,
                    Wish_to_pay_by__c,
                    annual_payment_details_sent_to_someone_e__c,
                    NINO_contributions_in_tax_years__c
                FROM Reapply__c
                WHERE Id = :recordId
                LIMIT 1    
            ];
        }
        if (reapplyData.size() > 0) {
            return reapplyData[0];
        } else return null;
    }
    
    public static List<Application__c> getApplicationData(Id recordId) {
        List<Application__c> applicationData = new List<Application__c>();
        if (recordId != null) {
            applicationData = [
                SELECT
                    Id,
                    Name,
                    First_Name__c,
                    Second_Name__c,
                    Email__c,
                    Related_Contact_Phone__c,
                    Payment_Method__c,
                    Stripe_Customer_Id__c,
                    Current_Customer_Id__c,
                    Salutation__c,
                    National_Insurance_Number__c,
                    Date_Of_Birth__c,
                    Last_UK_Home_Address__City__s,
                    Last_UK_Home_Address__Street__s,
                    Last_UK_Home_Address__PostalCode__s,
                    Date_Of_Leaving_Last_UK__c,
                    Current_Address_Abroad__Street__s,
                    Current_Address_Abroad__StateCode__s,
                    Current_Address_Abroad__PostalCode__s,
                    Current_Address_Abroad__City__s,
                    Current_Address_Abroad__CountryCode__s,
                    Employed_Direcly__c,
                    (SELECT
                        Name,
                        Type__c,
                        Type_Of_After_UK_Employment__c,
                        Type_Of_UK_Employment__c,
                        Employer_Name__c,
                        Employers_Address__CountryCode__s,
                        Employers_Address__StateCode__s,
                        Employers_Address__PostalCode__s,
                        Employers_Address__Street__s,
                        Employers_Address__City__s,
                        Start_Date__c,
                        End_Date__c,
                        Current_Work__c
                    FROM Employers__r
                    ORDER BY Start_Date__c)
                FROM Application__c
                WHERE Id = :recordId
            ];
        }
        return applicationData;
    }
}
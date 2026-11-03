public with sharing class BP_IPC1394_Wrapper {
    public class ApplicationDataWrapper {
        Public String Q1;
        Public String Q2;
        Public String Q3;
        Public String Q4;
        Public String Q5_NINO;
        Public Boolean Q5_check_No;
        Public Boolean Q5_check_Yes;
        Public String Q6;
        Public String Q7DATE;
        Public String Q8;
        Public Boolean Q9_check_Mobile;
        Public Boolean Q9c;
        Public String Q10;
        Public String Q11;
        Public String Q12;
        Public String Q13;
        Public Boolean Q13_check_Checking;
        Public Boolean Q14_check_4weeks;
        Public Boolean Q14_check_13weeks;
        Public String Q14;
        Public String Q15;
        Public String Q16;
        Public String Q17;
        Public String Q17a;
        Public String Q17b;
        Public String Q18;
        Public String bankCountryCode;




        // ONLY ADDED FOR DATE FORMATTING
        private String formatDate(Date value) {
            if (value == null) {
                return '';
            }

            return String.valueOf(value.day()).leftPad(2, '0') + '/' +
                   String.valueOf(value.month()).leftPad(2, '0') + '/' +
                   String.valueOf(value.year());
        }

        // Comb fields: strip all whitespace and upper-case. A value longer than the comb is dropped
        // (left blank for the agent to notice) rather than printed truncated and wrong.
        private String combValue(String value, Integer maxLength) {
            if (String.isBlank(value)) {
                return null;
            }
            String normalised = value.deleteWhitespace().toUpperCase();
            return normalised.length() > maxLength ? null : normalised;
        }

        // Free-text comb: keep spaces, only trim and cap the length
        private String textValue(String value, Integer maxLength) {
            if (String.isBlank(value)) {
                return null;
            }
            String trimmed = value.normalizeSpace();
            return trimmed.length() > maxLength ? trimmed.substring(0, maxLength) : trimmed;
        }

        private String formatBankAddress(String address) {
            if (String.isBlank(address)) {
                return address;
            }

            String result = '';
            Integer start = 0;
            Integer chunkSize = 35;

            while (start < address.length()) {
                Integer targetPosition = start + chunkSize;

                if (targetPosition >= address.length()) {
                    result += address.substring(start);
                    break;
                }

                Integer commaPosition = address.indexOf(', ', targetPosition);

                if (commaPosition == -1) {
                    result += address.substring(start);
                    break;
                }

                result += address.substring(start, commaPosition + 2);
                result += '\n';

                start = commaPosition + 2;
            }

            return result;
        }

        public ApplicationDataWrapper(Basic__c app) {
            this.Q1 = app.Claimant_title__c;
            this.Q2 = app.First_Name__c;
            this.Q3 = app.Claimant_Middle_Name__c;
            this.Q4 = app.Last_Name__c;
            this.Q5_NINO = combValue(app.Claimant_nino__c, 9);

            if(String.isNotBlank(app.Bank_Country_Code__c)) {
                this.bankCountryCode = app.Bank_Country_Code__c;
            }

            if(String.isNotBlank(app.Has_Nino__c) && app.Has_Nino__c == 'Never Had') {
                this.Q5_check_No = true;
            }
            else if(String.isNotBlank(app.Has_Nino__c) && app.Has_Nino__c == 'Forgot') {
                this.Q5_check_Yes = true;
            }
            else if(!app.Claimant_hasNino__c) {
                this.Q5_check_No = true;
            }

            this.Q6 = app.Claimant_maiden_Name__c;
            String q6Name = '';
            q6Name = String.isBlank(app.Claimant_maiden_Name__c) ?  q6Name : q6Name + app.Claimant_maiden_Name__c + ', ';
            q6Name = String.isBlank(app.Claimant_other_names__c) ? q6Name : q6Name + app.Claimant_other_names__c + ', ';

            this.Q6 = q6Name.removeEnd(', ');
            this.Q7DATE = formatDate(app.Claimant_dob__c);
            this.Q8 = app.Phone__c; 
            this.Q9_check_Mobile = true; 

            String addressLine = '';

            if(String.isNotBlank(app.Claimant_address1__c)) {
                addressLine = addressLine + app.Claimant_address1__c;
            }
            if(String.isNotBlank(app.Claimant_address2__c)) {
                addressLine = addressLine + ', ' + app.Claimant_address2__c;
            }
            if(String.isNotBlank(app.Claimant_City__c)) {
                addressLine = addressLine + ', ' + app.Claimant_City__c;
            }
            if(String.isNotBlank(app.Current_Address_Abroad_State_Name__c)) {
                addressLine = addressLine + ', ' + app.Current_Address_Abroad_State_Name__c;
            }
            if(String.isNotBlank(app.Eircode__c)) {
                addressLine = addressLine + ', ' + app.Eircode__c;
            }
            if(String.isNotBlank(app.Current_Address_Abroad_Country_Name__c)){
                addressLine = addressLine + ', ' + app.Current_Address_Abroad_Country_Name__c;
            }

            this.Q10 = formatBankAddress(addressLine);
            this.Q11 = app.Bank_Name__c;

            String bankAddressLine = '';

            if(String.isNotBlank(app.Bank_Address__c)) {
                bankAddressLine = bankAddressLine + app.Bank_Address__c;
            }
            if(String.isNotBlank(app.Bank_City__c)) {
                bankAddressLine = bankAddressLine + ', ' + app.Bank_City__c;
            }
            if(String.isNotBlank(app.Bank_Post_Code__c)) {
                bankAddressLine = bankAddressLine + ', ' + app.Bank_Post_Code__c;
            }
            if(String.isNotBlank(app.Bank_Country__c)) {
                bankAddressLine = bankAddressLine + ', ' + app.Bank_Country__c;
            }

            this.Q12 = formatBankAddress(bankAddressLine);
            this.Q13_check_Checking = true;
            this.Q14_check_4weeks = app.Paid_Interval__c == '4 weeks';
            this.Q14_check_13weeks = String.isNotBlank(app.Paid_Interval__c) && app.Paid_Interval__c != '4 weeks';
            this.Q15 = textValue(app.Bank_Account_Owner_Name__c, 35);
            this.Q16 = combValue(app.Bank_Account__c, 34);
            if(String.isNotBlank(app.Bank_Country_Code__c) &&  app.Bank_Country_Code__c == 'AU') {
                if(String.isNotBlank(app.Bank_Sort_Code__c)) {
                    List<String> parts = app.Bank_Sort_Code__c.deleteWhitespace().split('-');
                    if(parts.size()>0) {
                        this.Q17a = parts[0];
                    }
                    if(parts.size()>1) {
                        this.Q17b = parts[1];
                    }
                }
                
            } else {
                this.Q17 = combValue(app.Bank_IBAN__c, 34);
            }
            this.Q18 = combValue(app.Bank_BIC__c, 11);
        }
    }
}
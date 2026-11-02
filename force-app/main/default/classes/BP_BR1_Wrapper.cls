public with sharing class BP_BR1_Wrapper {

    public class ApplicationDataWrapper {
        Public String q1;
        Public String q2;
        Public String q3;
        Public String q4;
        Public String q5;
        Public Boolean q5a_no;
        Public Boolean q5a_yes;
        Public String q6a;
        Public String q6b;
        Public String q6c;
        Public String q6d;
        Public String q7;
        Public String q8;
        Public Boolean q9_mobile;
        Public String q10;
        Public Boolean q11_no;
        Public Boolean q11_yes;
        Public Boolean q12a;
        Public Boolean q12b;
        Public Boolean q12c;
        Public Boolean q12d;
        Public Boolean q13a;
        Public Boolean q13b;
        Public Boolean q13c;
        Public Boolean q13d;
        Public Boolean q14_no;
        Public Boolean q14_yes;

        // Missing variables
        Public String q15a;
        Public String q15b;
        Public String q15c;
        Public String q15d;
        Public String q15e;
        Public String q15f;
        Public String q15g;
        Public String q15h;
        Public String q15i;
        Public String q15j;
        Public String q15k;
        Public String q15l;

        Public String q16a;
        Public String q16b;
        Public String q16c;
        Public String q16d;
        Public String q16e;
        Public String q16f;
        Public String q16g;
        Public String q16h;
        Public Boolean q17_no;
        Public Boolean q18_no;
        Public Boolean q18_yes;
        Public String q18a;
        Public String q18b;
        Public String q18c;
        Public String q18d;
        Public String q18e;
        Public String q18f;
        Public String q18g;
        Public String q18h;
        Public String q18i;
        Public String q18j;
        Public String q18k;
        Public String q18l;
        Public String q18m;
        Public String q18n;
        Public Boolean q19_no;
        Public Boolean q19_yes;
        Public Boolean q20_single;
        Public Boolean q20_married;
        Public Boolean q20_divorced;
        Public Boolean q20_annulled;
        Public Boolean q20_separated;
        Public Boolean q20_widowed;
        Public String q21;
        Public String q22;
        Public String q23;
        Public String q24;
        Public Boolean q25_yes;
        Public Boolean q25_no;
        Public String q26a;
        Public String q26b;
        Public String q26c;
        Public String q26d;
        Public String q27;
        Public String q28;
        Public String q29;
        Public String q30;
        Public Boolean q31_no;
        Public Boolean q31_yes;
        Public Boolean q32_no;
        Public Boolean q32_yes;
        Public Boolean q33_no;
        Public Boolean q33_yes;

        Public Boolean q46_no;
        Public Boolean q46_yes;
        Public String q46a;
        Public Boolean q47_no;
        Public Boolean q47_yes;
        Public Boolean q48_no;
        Public Boolean q48_yes;
        Public Boolean q49_no;
        Public Boolean q49_yes;

        // Missing variables
        Public String q50a;
        Public String q50b;
        Public String q50c;
        Public String q50d;
        Public String q50f;
        Public String q50g;
        Public String q50h;
        Public String q50i;
        Public String q50j;
        Public String q50k;
        Public String q50m;
        Public String q50n;
        Public String q51a;
        Public String q51d;
        Public String q51g;
        Public Boolean q51b_you;
        Public Boolean q51b_partner;
        Public Boolean q51e_you;
        Public Boolean q51e_partner;
        Public Boolean q51h_you;
        Public Boolean q51h_partner;

        Public Boolean q51_no;
        Public Boolean q51_yes;
        Public Boolean q52_no;
        Public Boolean q53_no;
        Public Boolean q53_yes;
        Public Boolean q54_no;
        Public Boolean q54_yes;
        Public String q55;
         Public Boolean q55a;
        Public Boolean q55b;
        Public String q56;
        Public String q57;
        Public String q57a;
        Public Boolean q58_no;
        Public Boolean q58_yes;
        Public String q58a;
        Public String q59;
        Public Boolean q59a;
        Public Boolean q59b;
        Public String q60;
        Public String q61a;
        Public String q61b;
        Public Boolean q62_no;
        Public Boolean q62_yes;
        Public String q62a;
        Public String q63;
        Public String q64;
        Public Boolean q67;
        Public String name;
        Public String stateName;
        Public String countryName;
        Public String partnerCountryName;
        Public String partnerStateName;
        Public List<Claimant_Country_lived__c> contryLivedList;


        // ONLY ADDED FOR DATE FORMATTING
        private String formatDate(Date value) {
            if (value == null) {
                return '';
            }

            return String.valueOf(value.day()).leftPad(2, '0') + '/' +
                   String.valueOf(value.month()).leftPad(2, '0') + '/' +
                   String.valueOf(value.year());
        }


        // Country arrives pre-prefixed with ', '; a blank city must not print "null"
        private String cityWithCountry(String city, String countryWithComma) {
            if (String.isBlank(city)) {
                return String.isBlank(countryWithComma) ? '' : countryWithComma.removeStart(', ');
            }
            return city + (String.isBlank(countryWithComma) ? '' : countryWithComma);
       }

        public ApplicationDataWrapper(Basic__c app) {
            String notes = '';
            this.name = app.Name;
            this.stateName = app.Current_Address_Abroad_State_Name__c;
            this.countryName = app.Current_Address_Abroad_Country_Name__c;
            this.partnerCountryName = app.Partner_Country__c;
            this.partnerStateName = app.Partner_State_Name__c;

            this.q1 = app.Claimant_title__c;
            this.q2 = app.First_Name__c;
            this.q3 = app.Claimant_Middle_Name__c;
            this.q4 = app.Last_Name__c;
            this.q5 = app.Claimant_nino__c;

            
            if(String.isNotBlank(app.Claimant_Ever_Lived_UK_Notes__c)||
                String.isNotBlank(app.Partner_Ever_Lived_UK_Notes__c) ||
                String.isNotBlank(app.Partner_Reference_on_Any_DWP_Letters__c)||
                String.isNotBlank(app.Claimant_is_Waiting_Uk_Benefits_text__c)||
                String.isNotBlank(app.Partner_is_Waiting_Uk_Benefits_text__c)) {
                notes = notes + '===================\n'; 
                notes = notes + 'UK Residence, DWP References and Pending UK Benefits - Additional Info: \n\n'; 

                if(String.isNotBlank(app.Claimant_Ever_Lived_UK_Notes__c)) {
                notes = notes + app.Claimant_Ever_Lived_UK_Notes__c;
                notes = notes + '\n\n';
                }
                if(String.isNotBlank(app.Partner_Ever_Lived_UK_Notes__c)) {
                    notes = notes + app.Partner_Ever_Lived_UK_Notes__c;
                    notes = notes + '\n\n';
                }
                 if(String.isNotBlank(app.Partner_Reference_on_Any_DWP_Letters__c)) {
                notes = notes +  app.Partner_Reference_on_Any_DWP_Letters__c;
                notes = notes + '\n\n';
                }
                
                if(String.isNotBlank(app.Claimant_is_Waiting_Uk_Benefits_text__c)) {
                    notes = notes  + app.Claimant_is_Waiting_Uk_Benefits_text__c;
                    notes = notes + '\n\n';
                }
                if(String.isNotBlank(app.Partner_is_Waiting_Uk_Benefits_text__c)) {
                    notes = notes + app.Partner_is_Waiting_Uk_Benefits_text__c;
                    notes = notes + '\n\n';
            }
            }
            
            
            if(String.isNotBlank(app.Has_Nino__c) && app.Has_Nino__c == 'Never Had') {
                this.q5a_no = true;
            }
            else if(String.isNotBlank(app.Has_Nino__c) && app.Has_Nino__c == 'Forgot') {
                this.q5a_yes = true;
            } 
            else if(!app.Claimant_hasNino__c) {
                this.q5a_no = true;
            }
            
            

            this.q6a = app.Claimant_address1__c;
            this.q6b = app.Claimant_address2__c;

            String addressStr = '';
            addressStr = String.isNotBlank(app.Claimant_City__c) ? app.Claimant_City__c + ', ' : '';
            addressStr = String.isNotBlank(app.Current_Address_Abroad_State_Name__c) ? addressStr + app.Current_Address_Abroad_State_Name__c + ', ' : addressStr;
            addressStr = String.isNotBlank(app.Eircode__c) ? addressStr + app.Eircode__c + ', ' : addressStr;
            
            this.q6c = addressStr.removeEnd(', ');
            this.q6d = app.Current_Address_Abroad_Country_Name__c;

            if(String.isBlank(app.Claimant_address2__c)) {
                this.q6b = addressStr.removeEnd(', ');
                this.q6c = app.Current_Address_Abroad_Country_Name__c;
                this.q6d = '';
            }
            String q7Name = '';
            q7Name = String.isBlank(app.Claimant_maiden_Name__c) ?  q7Name : q7Name + app.Claimant_maiden_Name__c + ', ';
            q7Name = String.isBlank(app.Claimant_other_names__c) ? q7Name : q7Name + app.Claimant_other_names__c + ', ';

            this.q7 = q7Name.removeEnd(', ');
            this.q8 = app.Phone__c;

            this.q9_mobile = true;

            this.q10 = formatDate(app.Claimant_dob__c);

            this.q11_no = true;
            this.q11_yes = false;

            this.q12a = app.Claimant_State_Pension__c;
            this.q12b = app.Claimant_Graduated_Retirement_Benefit__c;
            this.q12c = app.Claimant_Widows_Benefit__c;
            this.q12d = app.Claimant_Bereavement_Benefit__c;

            this.q13a = app.Partner_State_Pension__c;
            this.q13b = app.Partner_Graduated_Retirement_Benefit__c;
            this.q13c = app.Partner_Widows_Benefit__c;
            this.q13d = app.Partner_Bereavement_Benefit__c;

            this.q14_no = app.Claimant_ever_Lived_UK__c ? false : true;
            this.q14_yes = app.Claimant_ever_Lived_UK__c ? true : false;

            this.q16a = formatDate(app.Claimant_lived_UK_From__c);
            this.q16b = formatDate(app.Claimant_lived_UK_to__c);
            this.q16c = formatDate(app.Claimant_worked_UK_From__c);
            this.q16d = formatDate(app.Claimant_worked_UK_To__c);

            // No selector in source JSON
            this.q17_no = true;

            this.q18_no = app.Claimant_Ever_Worked_UK__c ? false : true;
            this.q18_yes = app.Claimant_Ever_Worked_UK__c ? true : false;

            // q18a-q18f, q18h-q18m are taken from Claimant_Companies__r.
            // They cannot be populated directly from Basic__c because
            // selector contains array indexes [0] and [1].
            //
            // If Claimant_Companies__r is queried:
            List<Claimant_Company__c> ukCompaniesPartner = new List<Claimant_Company__c>();
            List<Claimant_Company__c> ukHadAddress = new List<Claimant_Company__c>();
            List<Claimant_Company__c> ukCompaniesClaim = new List<Claimant_Company__c>();

            if(app.Claimant_Companies__r != null && app.Claimant_Companies__r.size()>0) {
                for(Claimant_Company__c itemwrap : app.Claimant_Companies__r) {
                    if(itemwrap.Is_Partner__c && !itemwrap.Is_Addresses__c) {
                        ukCompaniesPartner.add(itemwrap);
                    } else if(itemwrap.Is_Addresses__c) {
                        ukHadAddress.add(itemwrap);
                    } else {
                        ukCompaniesClaim.add(itemwrap);
                    }
                }
            }
            List<Claimant_Company__c> withoutAddressCompanies = new List<Claimant_Company__c>();
            if( ukHadAddress.size()>0) {
                if(ukHadAddress[0] != null) {
                    this.q15a = ukHadAddress[0].Address1__c;
                    this.q15b = ukHadAddress[0].Address2__c;
                    String country = String.isBlank(ukHadAddress[0].Country__c) ? '' : ', ' + ukHadAddress[0].Country__c;
                    String city = String.isBlank(ukHadAddress[0].City__c) ? '' : ukHadAddress[0].City__c; 

                    this.q15c = city + country;
                    this.q15d = ukHadAddress[0].Postcode__c;
                    this.q15e = formatDate(ukHadAddress[0].From_Date__c);
                    this.q15f = formatDate(ukHadAddress[0].To_Date__c);

                    if(String.isBlank(ukHadAddress[0].Address2__c)) {
                        this.q15b =  city + country;
                        this.q15c = '';
                        this.q15d = ukHadAddress[0].Postcode__c;
                    }
                }

                if(ukHadAddress.size()>1 && ukHadAddress[1] != null) {
                    this.q15g = ukHadAddress[1].Address1__c;
                    this.q15h = ukHadAddress[1].Address2__c;
                    String country = String.isBlank(ukHadAddress[1].Country__c) ? '' :  ', ' + ukHadAddress[1].Country__c;
                    String city = String.isBlank(ukHadAddress[1].City__c) ? '' : ukHadAddress[1].City__c; 
                    this.q15i = city + country;
                    this.q15j = ukHadAddress[1].Postcode__c;
                    this.q15k = formatDate(ukHadAddress[1].From_Date__c);
                    this.q15l = formatDate(ukHadAddress[1].To_Date__c);

                    if(String.isBlank(ukHadAddress[1].Address2__c)) {
                        this.q15h =  city + country;
                        this.q15i = '';
                        this.q15j = ukHadAddress[1].Postcode__c;
                    }
                }
                

                if(ukHadAddress.size()>2) {
                    Integer index = 0;
                    notes = notes + '===================\n'; 
                    notes = notes + 'Q15 - Additional Info: \n\n';            
                    for(Claimant_Company__c item : ukHadAddress) {
                        index ++;
                        if(index>2) { 
                            if(String.isNotBlank(item.Address1__c)) {                           
                                notes = notes + 'UK address: ';                         
                                if (String.isNotBlank(item.Address1__c)) {
                                    notes = notes + item.Address1__c + ', ';
                                }
                                if (String.isNotBlank(item.Address2__c)) {
                                    notes = notes + item.Address2__c + ', ';
                                }
                                if (String.isNotBlank(item.City__c)) {
                                    notes = notes + item.City__c + ', ';
                                }
                                if (String.isNotBlank(item.Country__c)) {
                                    notes = notes + item.Country__c + ', ';
                                }
                                if (String.isNotBlank(item.Postcode__c)) {
                                    notes = notes + item.Postcode__c + ', ';
                                }
                                if (item.From_Date__c != null) {
                                    notes = notes + formatDate(item.From_Date__c) + ', ';
                                }
                                if (item.To_Date__c!= null) {
                                    notes = notes + formatDate(item.To_Date__c) + ', ';
                                }
                                notes = notes.removeEnd(', ');
                                notes = notes + '\n\n'; 
                            } else {
                                withoutAddressCompanies.add(item);
                            }                          
                        }
                    }
                }
            }
            if(withoutAddressCompanies.size()>0) {
                if (withoutAddressCompanies[0].From_Date__c != null) {
                    this.q16e =   formatDate(withoutAddressCompanies[0].From_Date__c);
                }
                if (withoutAddressCompanies[0].To_Date__c != null) {
                    this.q16f =   formatDate(withoutAddressCompanies[0].To_Date__c);
                }
            }
            if(withoutAddressCompanies.size()>1) {
                if (withoutAddressCompanies[1].From_Date__c != null) {
                    this.q16g =   formatDate(withoutAddressCompanies[1].From_Date__c);
                }
                if (withoutAddressCompanies[1].To_Date__c != null) {
                    this.q16h =   formatDate(withoutAddressCompanies[1].To_Date__c);
                }
            }

            if(withoutAddressCompanies.size()>2) {
                Integer index = 0;  
                notes = notes + '===================\n'; 
                notes = notes + 'Q16 - Additional Info: \n\n';    
                for(Claimant_Company__c item : withoutAddressCompanies) {
                    notes = notes + 'UK address: ';
                    if (item.From_Date__c != null) {
                        notes = notes + 'From: ' + formatDate(item.From_Date__c) + ', ';
                    }
                    if (item.To_Date__c!= null) {
                        notes = notes + 'To: ' + formatDate(item.To_Date__c) + ', ';
                    }
                    notes = notes.removeEnd(', ');
                    notes = notes + '\n\n'; 
                }
            }

            if( ukCompaniesClaim.size()>0) {
                if(ukCompaniesClaim[0] != null) {
                    String firstLine = '';
                    if(String.isNotBlank(ukCompaniesClaim[0].Name)) {
                        firstLine = ukCompaniesClaim[0].Name + ', ';
                    }
                    if(String.isNotBlank(ukCompaniesClaim[0].Address1__c)) {
                        firstLine = firstLine + ukCompaniesClaim[0].Address1__c + ', ';
                    }
                    this.q18a = firstLine.removeEnd(', ');
                    this.q18b = ukCompaniesClaim[0].Address2__c;
                    String country = String.isBlank(ukCompaniesClaim[0].Country__c) ? '' : ', ' + ukCompaniesClaim[0].Country__c;
                    this.q18c = cityWithCountry(ukCompaniesClaim[0].City__c, country);
                    this.q18d = ukCompaniesClaim[0].Postcode__c;
                    this.q18e = formatDate(ukCompaniesClaim[0].From_Date__c);
                    this.q18f = formatDate(ukCompaniesClaim[0].To_Date__c);

                    if(String.isBlank(ukCompaniesClaim[0].Address2__c)) {
                        this.q18b = cityWithCountry(ukCompaniesClaim[0].City__c, country);
                        this.q18c = '';
                        this.q18d = ukCompaniesClaim[0].Postcode__c;
                    }
                }

                if(ukCompaniesClaim.size()>1 && ukCompaniesClaim[1] != null) {
                    String firstLine = '';
                    if(String.isNotBlank(ukCompaniesClaim[1].Name)) {
                        firstLine = ukCompaniesClaim[1].Name + ', ';
                    }
                    if(String.isNotBlank(ukCompaniesClaim[1].Address1__c)) {
                        firstLine = firstLine + ukCompaniesClaim[1].Address1__c + ', ';
                    }
                    this.q18h = firstLine.removeEnd(', ');
                    this.q18i = ukCompaniesClaim[1].Address2__c;
                    String country = String.isBlank(ukCompaniesClaim[1].Country__c) ? '' : ', ' + ukCompaniesClaim[1].Country__c;
                    this.q18j = cityWithCountry(ukCompaniesClaim[1].City__c, country);
                    this.q18k = ukCompaniesClaim[1].Postcode__c;
                    this.q18l = formatDate(ukCompaniesClaim[1].From_Date__c);
                    this.q18m = formatDate(ukCompaniesClaim[1].To_Date__c);

                    if(String.isBlank(ukCompaniesClaim[1].Address2__c)) {
                        this.q18i =  cityWithCountry(ukCompaniesClaim[1].City__c, country);
                        this.q18j = '';
                        this.q18k = ukCompaniesClaim[1].Postcode__c;
                    }
                }

                if(ukCompaniesClaim.size()>2) {
                    Integer index = 0; 
                    notes = notes + '===================\n'; 
                    notes = notes + 'Q18 - Additional Info: \n\n';        
                    for(Claimant_Company__c item : ukCompaniesClaim) {
                        index ++;
                        if(index>2) { 
                            notes = notes + 'Employer ' + index + ': ';
                            if(String.isNotBlank(item.Name)) {
                                notes = notes + item.Name + ', ';
                            }                         
                            if (String.isNotBlank(item.Address1__c)) {
                                notes = notes + item.Address1__c + ', ';
                            }
                            if (String.isNotBlank(item.Address2__c)) {
                                notes = notes + item.Address2__c + ', ';
                            }
                            if (String.isNotBlank(item.City__c)) {
                                notes = notes + item.City__c + ', ';
                            }
                            if (String.isNotBlank(item.Country__c)) {
                                notes = notes + item.Country__c + ', ';
                            }
                            if (String.isNotBlank(item.Postcode__c)) {
                                notes = notes + item.Postcode__c + ', ';
                            }
                            if (item.From_Date__c != null) {
                                notes = notes + formatDate(item.From_Date__c) + ', ';
                            }
                            if (item.To_Date__c!= null) {
                                notes = notes + formatDate(item.To_Date__c) + ', ';
                            }
                            notes = notes.removeEnd(', ');
                            notes = notes + '\n\n';                            
                        }
                    }
                }
            }

            

            if( ukCompaniesPartner.size()>0) {
                if(ukCompaniesPartner[0] != null) {
                    this.q50a = ukCompaniesPartner[0].Address1__c;
                    this.q50b = ukCompaniesPartner[0].Address2__c;
                    String country = String.isBlank(ukCompaniesPartner[0].Country__c) ?  '' : ', ' + ukCompaniesPartner[0].Country__c;
                    this.q50c = cityWithCountry(ukCompaniesPartner[0].City__c, country);
                    this.q50d = ukCompaniesPartner[0].Postcode__c;
                    this.q50f = formatDate(ukCompaniesPartner[0].From_Date__c);
                    this.q50g = formatDate(ukCompaniesPartner[0].To_Date__c);

                    if(String.isBlank(ukCompaniesPartner[0].Address2__c)) {
                        this.q50b = cityWithCountry(ukCompaniesPartner[0].City__c, country);
                        this.q50c = '';
                        this.q50d = ukCompaniesPartner[0].Postcode__c;
                    }
                }

                if(ukCompaniesPartner.size()>1 &&  ukCompaniesPartner[1] != null) {
                    this.q50h = ukCompaniesPartner[1].Address1__c;
                    this.q50i = ukCompaniesPartner[1].Address2__c;
                    String country = String.isBlank(ukCompaniesPartner[1].Country__c) ? '' : ', ' + ukCompaniesPartner[1].Country__c;
                    this.q50j = cityWithCountry(ukCompaniesPartner[1].City__c, country);
                    this.q50k = ukCompaniesPartner[1].Postcode__c;
                    this.q50m = formatDate(ukCompaniesPartner[1].From_Date__c);
                    this.q50n = formatDate(ukCompaniesPartner[1].To_Date__c);

                    if(String.isBlank(ukCompaniesPartner[1].Address2__c)) {
                        this.q50i = cityWithCountry(ukCompaniesPartner[1].City__c, country);
                        this.q50j = '';
                        this.q50k = ukCompaniesPartner[1].Postcode__c;
                    }
                }

                if(ukCompaniesPartner.size()>2) {
                    notes = notes + '===================\n'; 
                    notes = notes + 'Q50 - Additional Info: \n\n';
                    Integer index = 0;         
                    for(Claimant_Company__c item : ukCompaniesPartner) {
                        index ++;
                        if(index>2) { 
                            notes = notes + 'Partner Employer ' + index + ': ';                         
                            if (String.isNotBlank(item.Address1__c)) {
                                notes = notes + item.Address1__c + ', ';
                            }
                            if (String.isNotBlank(item.Address2__c)) {
                                notes = notes + item.Address2__c + ', ';
                            }
                            if (String.isNotBlank(item.City__c)) {
                                notes = notes + item.City__c + ', ';
                            }
                            if (String.isNotBlank(item.Country__c)) {
                                notes = notes + item.Country__c + ', ';
                            }
                            if (String.isNotBlank(item.Postcode__c)) {
                                notes = notes + item.Postcode__c + ', ';
                            }
                            if (item.From_Date__c != null) {
                                notes = notes + formatDate(item.From_Date__c) + ', ';
                            }
                            if (item.To_Date__c!= null) {
                                notes = notes + formatDate(item.To_Date__c) + ', ';
                            }
                            notes = notes.removeEnd(', ');
                            notes = notes + '\n\n';                            
                        }
                    }
                }
            }

            this.q19_no = app.Claimant_has_Proof_Of_UK_Work__c ? false : true;
            this.q19_yes = app.Claimant_has_Proof_Of_UK_Work__c ? true : false;

            this.q20_single = app.Claimant_marital_Status__c == 'Single' ? true : false;
            this.q20_married = app.Claimant_marital_Status__c == 'Married'? true : false;
            if(app.Claimant_marital_Status__c == 'Civil Partner') {
                this.q20_married = true;
            }
            this.q20_divorced = app.Claimant_marital_Status__c == 'Divorced'? true : false;
            this.q20_annulled = app.Claimant_marital_Status__c == 'Annulled'? true : false;
            this.q20_separated = app.Claimant_marital_Status__c == 'Separated'? true : false;
            this.q20_widowed = app.Claimant_marital_Status__c == 'Widowed'? true : false;

            if(app.Claimant_marital_Status__c != 'Single') {
                this.q21 = app.Partner_Surname__c;
                this.q22 = String.isNotBlank(app.Partner_First_Name__c) ? app.Partner_First_Name__c + ' ' + app.Partner_Other_Name__c : app.Partner_Other_Name__c;
                if(String.isBlank(app.Partner_Other_Name__c)) {
                    this.q22 = app.Partner_First_Name__c;
                }
                if(String.isBlank(app.Partner_Other_Name__c) && String.isBlank(app.Partner_First_Name__c)) {
                    this.q22 = '';
                }
                
                this.q23 = app.Partner_Maiden_Name__c;
                this.q24 = app.Partner_Nino__c;

                this.q25_yes = app.Partner_Ever_Lived_UK__c ? true : false;
                this.q25_no = app.Partner_Ever_Lived_UK__c ?  false : true;

                if(!app.Partner_same_as_claimant__c) {
                    this.q26a = app.Partner_Address1__c;
                    this.q26b = app.Partner_Address2__c;
                    String addressPartnerStr = '';
                    addressPartnerStr = String.isNotBlank(app.Partner_City__c) ? app.Partner_City__c + ', ' : '';
                    addressPartnerStr = String.isNotBlank(app.Partner_State_Name__c) ? addressPartnerStr + app.Partner_State_Name__c + ', ' : addressPartnerStr;
                    addressPartnerStr = String.isNotBlank(app.Partner_Country__c) ? addressPartnerStr + app.Partner_Country__c + ', ' : addressPartnerStr;
                    this.q26c = addressPartnerStr.removeEnd(', ');
                    this.q26d = app.Partner_Postcode__c;

                    if(String.isBlank(app.Partner_Address2__c)) {
                        this.q26b =  addressPartnerStr.removeEnd(', ');
                        this.q26c = '';
                        this.q26d = app.Partner_Postcode__c;
                    }
                }
                

                this.q27 = formatDate(app.Partner_DOB__c);
                this.q28 = formatDate(app.Claimant_date_Of_Marriage__c);
                this.q29 = formatDate(app.Claimant_date_Of_Divorce__c);
                this.q30 = formatDate(app.Claimant_date_Of_Bereavement__c);

                // No selector in source JSON
                this.q31_no = app.Claimant_marital_Status__c == 'Single' ? true : false;
                this.q31_yes = app.Claimant_marital_Status__c == 'Single' ? false : true;

                //this.q32_no = app.Claimant_marital_Status__c == 'Divorced' ? false : true;
                if(app.Claimant_marital_Status__c == 'Divorced') {
                    this.q32_yes = true;
                }

                //this.q33_no = app.Claimant_marital_Status__c == 'Widowed' ? false : true;
                if(app.Claimant_marital_Status__c == 'Widowed') {
                    this.q33_yes = true;
                }
            }

            // Q46 asks "claim from the earliest date possible?". The portal only offers a start date
            // (today or a chosen date), so the answer is always "No" and Q46a carries that start date.
            // The q46_yes / q46_no PDF widgets are named after their printed labels.

           this.q46_no = app.Pension_Claiming_from_Today__c ? false : true;
            this.q46_yes = app.Pension_Claiming_from_Today__c ? true : false;

            this.q46a = formatDate(app.DocuSign_Date__c);

            Boolean selfEmployedUK = app.Ever_Self_Employed_UK_after_1978__c == true;
            this.q47_no = !selfEmployedUK;
            this.q47_yes = selfEmployedUK;

            this.q48_no = app.Ever_Pay_Reduced_UK_nino__c  ? false : true;
            this.q48_yes = app.Ever_Pay_Reduced_UK_nino__c ? true : false;

            this.q49_no = app.Work_In_UK_during_2_years__c  ? false : true;
            this.q49_yes = app.Work_In_UK_during_2_years__c ? true : false;

            

            List<BenefitWrapper> benefits = new List<BenefitWrapper>();

            if(app.Claimant_State_Pension__c || app.Partner_State_Pension__c) {
                benefits.add(new BenefitWrapper('State Pension', app.Claimant_State_Pension__c, app.Partner_State_Pension__c));
            }
            if(app.Claimant_Graduated_Retirement_Benefit__c || app.Partner_Graduated_Retirement_Benefit__c) {
                benefits.add(new BenefitWrapper('Graduated Retirement Benefit', app.Claimant_Graduated_Retirement_Benefit__c, app.Partner_Graduated_Retirement_Benefit__c));
            }
            if(app.Claimant_Widows_Benefit__c || app.Partner_Widows_Benefit__c) {
                benefits.add(new BenefitWrapper('Widows Benefit', app.Claimant_Widows_Benefit__c, app.Partner_Widows_Benefit__c));
            }
            if(app.Claimant_Bereavement_Benefit__c || app.Partner_Bereavement_Benefit__c) {
                benefits.add(new BenefitWrapper('Bereavement Benefit', app.Claimant_Bereavement_Benefit__c, app.Partner_Bereavement_Benefit__c));
            }
            if(benefits.size()>0) {
                this.q51_yes = true;

                this.q51a = benefits[0].name;
                this.q51b_you = benefits[0].you;
                this.q51b_partner = benefits[0].partner;

                if(benefits.size()>1) {
                    this.q51d = benefits[1].name;
                    this.q51e_you = benefits[1].you;
                    this.q51e_partner = benefits[1].partner;
                }

                if(benefits.size()>2) {
                    this.q51g = benefits[2].name;
                    this.q51h_you = benefits[2].you;
                    this.q51h_partner = benefits[2].partner;
                }
                if(benefits.size()>3) {
                    Integer index = 0;
                    notes = notes + '===================\n'; 
                    notes = notes  + 'Q51 - Additional Info: \n\n';
                    for(BenefitWrapper item : benefits) {
                        index ++;
                        if(index>3) {
                             notes = notes  + 'Name of benefit entitlement: ' + item.name + ' ';
                             notes = notes  + 'Getting this or waiting to hear about this: ';
                            if(item.you && !item.partner) {
                                notes = notes  +  'You\n\n';
                            }
                            else if (!item.you && item.partner) {
                                notes = notes  +  'Your husband, wife or civil partner\n\n';
                            }
                            else if(item.you && item.partner) {
                                notes = notes  +  'You and Your husband, wife or civil partner\n\n';
                            }
                        }
                    }
                }
                
            } else {
                this.q51_no = true;
            }           

            

            // No selector in source JSON
            this.q52_no = true;

            this.q53_no = app.Claimant_Minded_Kids__c  ? false : true;
            this.q53_yes = app.Claimant_Minded_Kids__c ? true : false;

            if(app.Clamant_Children__r.size()>0) {
                Integer index = 0;  
                notes = notes + '===================\n'; 
                notes = notes + 'Q53 - Additional Info: \n\n';
                for(Claimant_Child__c item : app.Clamant_Children__r) {
                    index ++;
                    notes = notes + 'Child' + index + ': ';
                    if(String.isNotBlank(item.Name)) {
                        notes = notes + item.Name + ', ';
                    }
                    if(item.Dob__c != null) {
                        notes = notes + formatDate(item.Dob__c) + ', ';
                    }
                    if(item.Minded_From__c != null) {
                            notes = notes + formatDate(item.Minded_From__c) + ', ';
                    }
                    if(item.Minded_To__c != null) {
                            notes = notes + ' - ' + formatDate(item.Minded_To__c) + ', ';
                    }
                    if(String.isNotBlank(item.Nino__c)) {
                        notes = notes + item.Nino__c + ', ';
                    }
                    notes = notes.removeEnd(', ');
                    notes = notes + '\n\n';  
                }
            }

            this.q54_no = app.Is_Your_Partner_Currently_Get_Pension__c  ? false : true;
            this.q54_yes = app.Is_Your_Partner_Currently_Get_Pension__c ? true : false;

            if(String.isNotBlank(app.isYourPartnerCurrentlyGetPensionText__c)) {
                notes = notes + '===================\n'; 
                notes = notes + 'Q54 - Additional Info: \n\n' + app.isYourPartnerCurrentlyGetPensionText__c;
                notes = notes + '\n\n';
            }
            
            this.q55 = app.Claimant_nationality__c;
            this.q55a = true;
            this.q55b = true;

            contryLivedList = new List<Claimant_Country_lived__c>();

            if(app.ClaimantCountrieslived__r != null && app.ClaimantCountrieslived__r.size()>0) { 
                contryLivedList.addAll(app.ClaimantCountrieslived__r);

                if(app.ClaimantCountrieslived__r[0] != null) {
                    this.q55a = app.ClaimantCountrieslived__r[0].Is_Live_Here_Now__c ? true : false;
                    this.q55b = app.ClaimantCountrieslived__r[0].Is_Live_Here_Now__c ? true : false;

                    this.q56 = app.ClaimantCountrieslived__r[0].Name;

                    this.q57 = formatDate(
                        app.ClaimantCountrieslived__r[0].From_date__c
                    );

                    this.q57a = formatDate(
                        app.ClaimantCountrieslived__r[0].To_Date__c
                    );

                    if( app.ClaimantCountrieslived__r[0].Is_Live_Here_Now__c) {
                        this.q57a = 'CURRENT';
                    }

                    this.q58_no =
                        app.ClaimantCountrieslived__r[0].Is_Live_Here_Now__c
                        ? false
                        : true;

                    this.q58_yes =
                        app.ClaimantCountrieslived__r[0].Is_Live_Here_Now__c
                        ? true
                        : false;

                    this.q58a =
                        app.ClaimantCountrieslived__r[0].Social_Security_Number__c;
                    if(app.ClaimantCountrieslived__r[0].Name == 'Australia') {
                        this.q59 = 'Services Australia\n' + 'Seniors Services\n' + 'PO Box 7808\n' + 'Canberra BC ACT 2610\n' + 'Australia\n';
                    } else if (app.ClaimantCountrieslived__r[0].Name == 'Ireland') {
                        this.q59 = 'Dept of Social Protection\n' + 'College Road\n' + 'Sligo, F91 T384\n' + 'Ireland\n';
                    }
                    
                }

                if(app.ClaimantCountrieslived__r.size()>1 && app.ClaimantCountrieslived__r[1] != null) {
                    this.q59a = app.ClaimantCountrieslived__r[1].Is_Live_Here_Now__c ? true : false;
                    this.q59b = app.ClaimantCountrieslived__r[1].Is_Live_Here_Now__c ? true : false;

                    this.q60 = app.ClaimantCountrieslived__r[1].Name;

                    this.q61a = formatDate(
                        app.ClaimantCountrieslived__r[1].From_date__c
                    );

                    this.q61b = formatDate(
                        app.ClaimantCountrieslived__r[1].To_Date__c
                    );
                    if( app.ClaimantCountrieslived__r[1].Is_Live_Here_Now__c) {
                        this.q61b = 'CURRENT';
                    }

                    this.q62_no =
                        app.ClaimantCountrieslived__r[1].Is_Live_Here_Now__c
                        ? false
                        : true;

                    this.q62_yes =
                        app.ClaimantCountrieslived__r[1].Is_Live_Here_Now__c
                        ? true
                        : false;

                    this.q62a =
                        app.ClaimantCountrieslived__r[1].Social_Security_Number__c;
                     if(app.ClaimantCountrieslived__r[1].Name == 'Australia') {
                        this.q63 = 'Services Australia\n' + 'Seniors Services\n' + 'PO Box 7808\n' + 'Canberra BC ACT 2610\n' + 'Australia\n';
                    } else if (app.ClaimantCountrieslived__r[1].Name == 'Ireland') {
                        this.q63 = 'Dept of Social Protection\n' + 'College Road\n' + 'Sligo, F91 T384\n' + 'Ireland\n';
                    }
                }

                if(app.ClaimantCountrieslived__r.size()>2) {
                    Integer index = 0; 
                    notes = notes + '===================\n';  
                    notes = notes + 'Q55 - Additional Info: \n\n';      
                    for(Claimant_Country_lived__c item : app.ClaimantCountrieslived__r) {
                        index ++;
                        if(index>2) { 
                            notes = notes + 'Country ' + index + ': ';                         
                            if (String.isNotBlank(item.Name)) {
                                notes = notes + item.Name + ', ';
                            }
                            if (item.From_date__c != null) {
                                notes = notes + formatDate(item.From_date__c);
                            }
                            if (item.To_Date__c != null) {
                                notes = notes +  ' - ' + formatDate(item.To_Date__c) + ', ';
                            }
                            if(item.Is_Live_Here_Now__c) {
                                notes = notes + ' - CURRENT, ';
                            }
                            if(item.Is_Live_Here_Now__c) {
                                notes = notes + 'Did you pay into the social security system of that country? - Yes, ';
                            } else {
                                notes = notes + 'Did you pay into the social security system of that country? - No, ';
                            }
                            if (String.isNotBlank(item.Social_Security_Number__c)) {
                                notes = notes + item.Social_Security_Number__c + ', ';
                            }
                            notes = notes.removeEnd(', ');
                            notes = notes + '\n\n';                            
                        }
                    }
                }
                
                
            }

            notes = String.isBlank(app.Notes__c) ? notes : notes +   'Notes: \n\n' + app.Notes__c;

            this.q64 = 'Please note:\n\n' +
                ' 1 - This is a first-time claim — not a LEAP underpayment review.\n\n' +
                ' 2 - Claim is deferred, not a late claim. Do not apply 12-month backdating or treat as retrospective arrears.\n\n' +
                ' 3 - Pre-2016 (old system) rules only apply.\n\n' +
                ' 4 - Post-2016 10-year minimum qualifying period does not apply.\n\n' +
                ' 5 - Authorised representative is XtraPension Ltd (Letter of Authority encl).\n\n' +
                ' 6 - Clarify if inherited Additional Pension / SERPS / Graduated Benefit is due.\n\n' +
                ' 7 - Trace existing NINO, or allocate a DWP administrative NINO if none exists.\n\n' +
                ' 8 - Process under the reciprocal agreement rules for claimant\'s country of residence.\n\n' +
                ' 9 - Claimant confirms no Adult Dependency Increase or disqualifying overlapping benefits were received during the deferral period.\n\n' +
                notes;

            this.q67 = false;
        }
    }

    public class BenefitWrapper {
        public String name;
        public Boolean you;
        public Boolean partner;
        public BenefitWrapper(String name, Boolean you, Boolean partner) {
            this.name = name;
            this.you = you;
            this.partner = partner;
        }
    }
}
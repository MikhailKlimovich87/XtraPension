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
        // HM Forces (Q17): yes, Army / Navy / RAF, enlisted, discharged, where, regiment or corps, service number, rank
        Public Boolean q17_yes;
        Public Boolean q17a;
        Public Boolean q17b;
        Public Boolean q17c;
        Public String q17d;
        Public String q17e;
        Public String q17f;
        Public String q17g;
        Public String q17h;
        Public String q17i;
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


        // Q18 has two employer slots: the two longest jobs go there (John, 10/11/2026), in their own order; the rest go
        // to Other information. A job without both dates counts as the shortest; equal lengths keep the earlier one.
        private List<Claimant_Company__c> longestFirst(List<Claimant_Company__c> employers) {
            if (employers.size() <= 2) {
                return employers;
            }
            List<Integer> days = new List<Integer>();
            for (Claimant_Company__c employer : employers) {
                days.add(employer.From_Date__c != null && employer.To_Date__c != null
                    ? employer.From_Date__c.daysBetween(employer.To_Date__c) : -1);
            }
            Integer first = 0;
            for (Integer i = 1; i < employers.size(); i++) {
                if (days[i] > days[first]) first = i;
            }
            Integer second = first == 0 ? 1 : 0;
            for (Integer i = 0; i < employers.size(); i++) {
                if (i != first && days[i] > days[second]) second = i;
            }
            List<Claimant_Company__c> sorted = new List<Claimant_Company__c>{
                employers[Math.min(first, second)], employers[Math.max(first, second)]
            };
            for (Integer i = 0; i < employers.size(); i++) {
                if (i != first && i != second) sorted.add(employers[i]);
            }
            return sorted;
        }

        private String textOf(Object value) {
            return value == null ? '' : String.valueOf(value);
        }

        // Q58 / Q62 "Did you pay into the social security system of that country?": Yes, unless the number is "N/A"
        // (worked there for a UK employer, NI paid in the UK; John, 11/11/2026). A blank number is still Yes, as before.
        private Boolean paidThere(String socialSecurityNumber) {
            String n = socialSecurityNumber == null ? '' : socialSecurityNumber.replaceAll('[\\s./]', '').toUpperCase();
            return n != 'NA';
        }

        // ---- Call of 11/11/2026 17h13 (docs/claims-call-1111b/CONTRACT.md) ----
        // Other information: the previous marriage when remarried (BR1 Q20), a divorced client's former spouse who has
        // died since, and the marriage notes box of the forms (Marriage_Notes__c). '' when there is nothing to say.
        @TestVisible
        private String previousMarriageBlock(Basic__c app) {
            // Every field from the populated fields: callers (and the devs' tests) query different field lists
            Map<String, Object> g = app.getPopulatedFieldsAsMap();
            String status = (String) g.get('Claimant_marital_Status__c');
            Boolean remarried = status == 'Remarried';
            String notes = (String) g.get('Marriage_Notes__c');
            Date died = (Date) g.get('Claimant_date_Of_Bereavement__c');
            if (!remarried && !(status == 'Divorced' && died != null) && String.isBlank(notes)) return '';
            String title = (String) g.get('Partner_Title__c');
            String spouse = spouseWord(title);
            List<String> lines = new List<String>();
            if (remarried) {
                Boolean widowed = (String) g.get('Previous_Marriage_Ended__c') == 'Widowed';
                String who = (widowed ? 'Late ' : 'Former ') + spouse;
                String name = spouseFullName(g);
                String line = who + ': ' + (String.isBlank(name) ? 'name not known' : name);
                if (g.get('Partner_DOB__c') != null) line += ', born ' + formatDate((Date) g.get('Partner_DOB__c'));
                line += ', National Insurance number: ' + spouseNino(g) + '.';
                lines.add(line);
                if (g.get('Claimant_date_Of_Marriage__c') != null) lines.add('We married on ' + formatDate((Date) g.get('Claimant_date_Of_Marriage__c')) + '.');
                if (g.get('Claimant_date_Of_Divorce__c') != null) lines.add('We divorced on ' + formatDate((Date) g.get('Claimant_date_Of_Divorce__c')) + '.');
                if (died != null) lines.add(pronoun(title) + ' died on ' + formatDate(died) + '.');
                if (g.get('Partner_Address_Unknown__c') == true) {
                    lines.add(possessive(title) + ' address is not known.');
                } else if (g.get('Partner_same_as_claimant__c') != true && String.isNotBlank((String) g.get('Partner_Address1__c'))) {
                    lines.add(possessive(title) + ' last address: ' + joinParts(new List<String>{ (String) g.get('Partner_Address1__c'),
                        (String) g.get('Partner_Address2__c'), (String) g.get('Partner_City__c'), (String) g.get('Partner_State_Name__c'),
                        (String) g.get('Partner_Postcode__c'), (String) g.get('Partner_Country__c') }) + '.');
                }
                Date again = (Date) g.get('Date_Of_Remarriage__c');
                lines.add(again != null ? 'I remarried on ' + formatDate(again) + '.' : 'I have since remarried.');
                lines.add('Please check whether my ' + who.toLowerCase() + '\'s National Insurance record can be used for my State Pension.');
            } else if (status == 'Divorced' && died != null) {
                lines.add('My former ' + spouse + ' died on ' + formatDate(died) + '.');
            }
            if (String.isNotBlank(notes)) {
                if (!lines.isEmpty()) lines.add('');
                lines.add(notes.trim());
            }
            String heading = remarried ? 'Previous marriage (BR1 Q20: married more than once)' : 'Marriage - Additional Info';
            return '===================\n' + heading + ': \n\n' + String.join(lines, '\n') + '\n\n';
        }

        // The new fields are read from the populated fields, so a caller whose query does not select them still works
        private Map<String, Object> given1111b(Basic__c app) {
            return app.getPopulatedFieldsAsMap();
        }

        private String spouseWord(String title) {
            if (title == 'Mr') return 'husband';
            if (title == 'Mrs' || title == 'Ms' || title == 'Miss') return 'wife';
            return 'husband / wife';
        }

        private String pronoun(String title) {
            return title == 'Mr' ? 'He' : (title == 'Mrs' || title == 'Ms' || title == 'Miss') ? 'She' : 'They';
        }

        private String possessive(String title) {
            return title == 'Mr' ? 'His' : (title == 'Mrs' || title == 'Ms' || title == 'Miss') ? 'Her' : 'Their';
        }

        // Title, first, middle and last name. The middle-name box sometimes holds the whole name ("Desmond Victor
        // Waters", C05502): then it is used as it is.
        private String spouseFullName(Map<String, Object> g) {
            String middle = g.get('Partner_Other_Name__c') == null ? '' : ((String) g.get('Partner_Other_Name__c')).trim();
            String last = g.get('Partner_Surname__c') == null ? '' : ((String) g.get('Partner_Surname__c')).trim();
            List<String> parts = new List<String>{ (String) g.get('Partner_Title__c') };
            if (String.isNotBlank(middle) && String.isNotBlank(last) && middle.toLowerCase().contains(last.toLowerCase())) {
                parts.add(middle);
            } else {
                parts.addAll(new List<String>{ (String) g.get('Partner_First_Name__c'), middle, last });
            }
            List<String> kept = new List<String>();
            for (String part : parts) {
                if (String.isNotBlank(part)) kept.add(part.trim());
            }
            return String.join(kept, ' ');
        }

        // BR1 Q22 "Other names in full": first name + middle names. When the middle-name box holds the whole name, the
        // surname (Q21) is taken out of it and the first name is not repeated.
        @TestVisible
        private String otherNamesInFull(String first, String middle, String last) {
            String f = first == null ? '' : first.normalizeSpace();
            String m = middle == null ? '' : middle.normalizeSpace();
            String l = last == null ? '' : last.normalizeSpace();
            if (String.isNotBlank(m) && String.isNotBlank(l)) {
                m = (' ' + m + ' ').replaceAll('(?i)\\s' + Pattern.quote(l) + '(?=\\s)', ' ').normalizeSpace();
            }
            if (String.isNotBlank(m) && String.isNotBlank(f) && (m.equalsIgnoreCase(f) || m.toLowerCase().startsWith(f.toLowerCase() + ' '))) {
                m = m.substring(f.length()).normalizeSpace();
            }
            return String.isBlank(f) ? m : (String.isBlank(m) ? f : f + ' ' + m);
        }

        private String spouseNino(Map<String, Object> g) {
            String nino = (String) g.get('Partner_Nino__c');
            if (String.isNotBlank(nino)) return nino;
            return (String) g.get('Partner_Has_Nino_values__c') == 'Never Had' ? 'none' : 'not known';
        }

        private String joinParts(List<String> parts) {
            List<String> kept = new List<String>();
            for (String part : parts) {
                if (String.isNotBlank(part)) kept.add(part.trim());
            }
            return String.join(kept, ', ');
        }

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
            // Single (12/11/2026 audit): what the record still holds about a spouse (an earlier status, rows from the Short
            // Form) is kept on the claim but never printed: no spouse notes, no Q13, no spouse employers or addresses
            Boolean withSpouse = app.Claimant_marital_Status__c != 'Single';
            String partnerLivedNotes = withSpouse ? app.Partner_Ever_Lived_UK_Notes__c : null;
            String partnerDwpReference = withSpouse ? app.Partner_Reference_on_Any_DWP_Letters__c : null;
            String partnerWaitingText = withSpouse ? app.Partner_is_Waiting_Uk_Benefits_text__c : null;
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
                String.isNotBlank(partnerLivedNotes) ||
                String.isNotBlank(partnerDwpReference)||
                String.isNotBlank(app.Claimant_is_Waiting_Uk_Benefits_text__c)||
                String.isNotBlank(partnerWaitingText)) {
                notes = notes + '===================\n'; 
                notes = notes + 'UK Residence, DWP References and Pending UK Benefits - Additional Info: \n\n'; 

                if(String.isNotBlank(app.Claimant_Ever_Lived_UK_Notes__c)) {
                notes = notes + app.Claimant_Ever_Lived_UK_Notes__c;
                notes = notes + '\n\n';
                }
                if(String.isNotBlank(partnerLivedNotes)) {
                    notes = notes + partnerLivedNotes;
                    notes = notes + '\n\n';
                }
                 if(String.isNotBlank(partnerDwpReference)) {
                notes = notes +  partnerDwpReference;
                notes = notes + '\n\n';
                }
                
                if(String.isNotBlank(app.Claimant_is_Waiting_Uk_Benefits_text__c)) {
                    notes = notes  + app.Claimant_is_Waiting_Uk_Benefits_text__c;
                    notes = notes + '\n\n';
                }
                if(String.isNotBlank(partnerWaitingText)) {
                    notes = notes + partnerWaitingText;
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

            this.q13a = withSpouse ? app.Partner_State_Pension__c : null;
            this.q13b = withSpouse ? app.Partner_Graduated_Retirement_Benefit__c : null;
            this.q13c = withSpouse ? app.Partner_Widows_Benefit__c : null;
            this.q13d = withSpouse ? app.Partner_Bereavement_Benefit__c : null;

            this.q14_no = app.Claimant_ever_Lived_UK__c ? false : true;
            this.q14_yes = app.Claimant_ever_Lived_UK__c ? true : false;

            this.q16a = formatDate(app.Claimant_lived_UK_From__c);
            this.q16b = formatDate(app.Claimant_lived_UK_to__c);
            this.q16c = formatDate(app.Claimant_worked_UK_From__c);
            this.q16d = formatDate(app.Claimant_worked_UK_To__c);

            // Q17 HM Forces, from the Claimant_HM_Forces_* fields (long form or Claim page, 10/11/2026); No until asked.
            // Read from the populated fields, so a caller whose query does not select them still gets "No".
            Map<String, Object> given = app.getPopulatedFieldsAsMap();
            Boolean forces = given.get('Claimant_HM_Forces__c') == true;
            String service = forces ? (String) given.get('Claimant_HM_Forces_Service__c') : null;
            this.q17_no = !forces;
            this.q17_yes = forces;
            this.q17a = service == 'Army';
            this.q17b = service == 'Navy';
            this.q17c = service == 'RAF';
            this.q17d = forces ? formatDate((Date) given.get('Claimant_HM_Forces_Enlisted__c')) : '';
            this.q17e = forces ? formatDate((Date) given.get('Claimant_HM_Forces_Discharged__c')) : '';
            this.q17f = forces ? textOf(given.get('Claimant_HM_Forces_Discharged_Where__c')) : '';
            this.q17g = forces ? textOf(given.get('Claimant_HM_Forces_Regiment__c')) : '';
            this.q17h = forces ? textOf(given.get('Claimant_HM_Forces_Service_No__c')) : '';
            this.q17i = forces ? textOf(given.get('Claimant_HM_Forces_Rank__c')) : '';

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
                    // Single: the spouse's employers and UK addresses left on the record are not printed (Q50, Q15)
                    if(itemwrap.Is_Partner__c && !withSpouse) {
                        continue;
                    }
                    if(itemwrap.Is_Partner__c && !itemwrap.Is_Addresses__c) {
                        ukCompaniesPartner.add(itemwrap);
                    } else if(itemwrap.Is_Addresses__c) {
                        ukHadAddress.add(itemwrap);
                    } else {
                        ukCompaniesClaim.add(itemwrap);
                    }
                }
            }
            ukCompaniesClaim = longestFirst(ukCompaniesClaim);
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
            // Remarried (call of 11/11/2026 17h13): Q20 asks for the CURRENT status, so married
            Boolean remarried = app.Claimant_marital_Status__c == 'Remarried';
            if (remarried) {
                this.q20_married = true;
            }
            this.q20_divorced = app.Claimant_marital_Status__c == 'Divorced'? true : false;
            this.q20_annulled = app.Claimant_marital_Status__c == 'Annulled'? true : false;
            this.q20_separated = app.Claimant_marital_Status__c == 'Separated'? true : false;
            this.q20_widowed = app.Claimant_marital_Status__c == 'Widowed'? true : false;

            if (remarried) {
                // BR1 Q20: "If married more than once give details of previous marriages in the section named 'Other
                // information'". Q21-Q28 are the current husband / wife; the spouse of the form's section 3 (the former
                // one, whose UK record we claim on) goes in Other information (previousMarriageBlock).
                this.q21 = ((String) given1111b(app).get('Current_Spouse_Last_Name__c'));
                this.q22 = ((String) given1111b(app).get('Current_Spouse_First_Name__c'));
                this.q23 = '';
                this.q24 = ((String) given1111b(app).get('Current_Spouse_Nino__c'));
                this.q25_yes = false;
                this.q25_no = false;
                this.q27 = formatDate(((Date) given1111b(app).get('Current_Spouse_DOB__c')));
                this.q28 = formatDate(((Date) given1111b(app).get('Date_Of_Remarriage__c')));
                this.q29 = '';
                this.q30 = '';
                this.q31_no = false;
                this.q31_yes = true;
                this.q32_yes = ((String) given1111b(app).get('Previous_Marriage_Ended__c')) == 'Divorced';
                this.q33_yes = ((String) given1111b(app).get('Previous_Marriage_Ended__c')) == 'Widowed';
            } else if(app.Claimant_marital_Status__c != 'Single') {
                this.q21 = app.Partner_Surname__c;
                this.q22 = String.isNotBlank(app.Partner_First_Name__c) ? app.Partner_First_Name__c + ' ' + app.Partner_Other_Name__c : app.Partner_Other_Name__c;
                if(String.isBlank(app.Partner_Other_Name__c)) {
                    this.q22 = app.Partner_First_Name__c;
                }
                if(String.isBlank(app.Partner_Other_Name__c) && String.isBlank(app.Partner_First_Name__c)) {
                    this.q22 = '';
                }
                // The whole name typed in Middle Name(s) ("Desmond Victor Waters", C05502) printed "Desmond Desmond
                // Victor Waters": Q22 is the other names in full, without the surname or the first name twice (12/11/2026)
                this.q22 = otherNamesInFull(app.Partner_First_Name__c, app.Partner_Other_Name__c, app.Partner_Surname__c);

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
                // Not known (11/11/2026 17h13): a blank Q26 reads as "same address as you"
                if (given1111b(app).get('Partner_Address_Unknown__c') == true) {
                    this.q26a = 'Not known';
                    this.q26b = '';
                    this.q26c = '';
                    this.q26d = '';
                }
                

                this.q27 = formatDate(app.Partner_DOB__c);
                this.q28 = formatDate(app.Claimant_date_Of_Marriage__c);
                this.q29 = formatDate(app.Claimant_date_Of_Divorce__c);
                this.q30 = formatDate(app.Claimant_date_Of_Bereavement__c);
                // Q30 is for widows: a divorced client's former spouse who died since goes in Other information
                if (app.Claimant_marital_Status__c == 'Divorced') {
                    this.q30 = '';
                }

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

            if(app.Claimant_State_Pension__c || (withSpouse && app.Partner_State_Pension__c)) {
                benefits.add(new BenefitWrapper('State Pension', app.Claimant_State_Pension__c, (withSpouse && app.Partner_State_Pension__c)));
            }
            if(app.Claimant_Graduated_Retirement_Benefit__c || (withSpouse && app.Partner_Graduated_Retirement_Benefit__c)) {
                benefits.add(new BenefitWrapper('Graduated Retirement Benefit', app.Claimant_Graduated_Retirement_Benefit__c, (withSpouse && app.Partner_Graduated_Retirement_Benefit__c)));
            }
            if(app.Claimant_Widows_Benefit__c || (withSpouse && app.Partner_Widows_Benefit__c)) {
                benefits.add(new BenefitWrapper('Widows Benefit', app.Claimant_Widows_Benefit__c, (withSpouse && app.Partner_Widows_Benefit__c)));
            }
            if(app.Claimant_Bereavement_Benefit__c || (withSpouse && app.Partner_Bereavement_Benefit__c)) {
                benefits.add(new BenefitWrapper('Bereavement Benefit', app.Claimant_Bereavement_Benefit__c, (withSpouse && app.Partner_Bereavement_Benefit__c)));
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
            // Single (12/11/2026 audit): spouse rows left on the record are not the client's countries
            List<Claimant_Country_lived__c> livedIn = new List<Claimant_Country_lived__c>();
            if (app.ClaimantCountrieslived__r != null) {
                for (Claimant_Country_lived__c livedRow : app.ClaimantCountrieslived__r) {
                    if (withSpouse || livedRow.getPopulatedFieldsAsMap().get('Is_Partner__c') != true) livedIn.add(livedRow);
                }
            }

            if(livedIn.size()>0) { 
                contryLivedList.addAll(livedIn);

                if(livedIn[0] != null) {
                    // Slide 202: every country prints Lived and Worked and Q58 Yes; "live here now" only sets CURRENT (04/11/2026)
                    this.q55a = true;
                    this.q55b = true;

                    this.q56 = livedIn[0].Name;

                    this.q57 = formatDate(
                        livedIn[0].From_date__c
                    );

                    this.q57a = formatDate(
                        livedIn[0].To_Date__c
                    );

                    if( livedIn[0].Is_Live_Here_Now__c) {
                        this.q57a = 'CURRENT';
                    }

                    // "N/A" = worked there for a UK employer, NI paid in the UK: did not pay in that country (John, 11/11/2026)
                    this.q58_no = !paidThere(livedIn[0].Social_Security_Number__c);
                    this.q58_yes = !this.q58_no;

                    this.q58a =
                        livedIn[0].Social_Security_Number__c;
                    if(livedIn[0].Name == 'Australia') {
                        this.q59 = 'Services Australia\n' + 'Seniors Services\n' + 'PO Box 7808\n' + 'Canberra BC ACT 2610\n' + 'Australia\n';
                    } else if (livedIn[0].Name == 'Ireland') {
                        this.q59 = 'Dept of Social Protection\n' + 'College Road\n' + 'Sligo, F91 T384\n' + 'Ireland\n';
                    } else if (livedIn[0].Name == 'Canada') {
                        this.q59 = 'Service Canada\n' + 'International Operations\n' + 'PO Box 250\n' + 'Fredericton NB E3B 4Z6\n' + 'Canada\n';
                    }
                    
                }

                if(livedIn.size()>1 && livedIn[1] != null) {
                    this.q59a = true;
                    this.q59b = true;

                    this.q60 = livedIn[1].Name;

                    this.q61a = formatDate(
                        livedIn[1].From_date__c
                    );

                    this.q61b = formatDate(
                        livedIn[1].To_Date__c
                    );
                    if( livedIn[1].Is_Live_Here_Now__c) {
                        this.q61b = 'CURRENT';
                    }

                    this.q62_no = !paidThere(livedIn[1].Social_Security_Number__c);
                    this.q62_yes = !this.q62_no;

                    this.q62a =
                        livedIn[1].Social_Security_Number__c;
                     if(livedIn[1].Name == 'Australia') {
                        this.q63 = 'Services Australia\n' + 'Seniors Services\n' + 'PO Box 7808\n' + 'Canberra BC ACT 2610\n' + 'Australia\n';
                    } else if (livedIn[1].Name == 'Ireland') {
                        this.q63 = 'Dept of Social Protection\n' + 'College Road\n' + 'Sligo, F91 T384\n' + 'Ireland\n';
                    } else if (livedIn[1].Name == 'Canada') {
                        this.q63 = 'Service Canada\n' + 'International Operations\n' + 'PO Box 250\n' + 'Fredericton NB E3B 4Z6\n' + 'Canada\n';
                    }
                }

                if(livedIn.size()>2) {
                    Integer index = 0; 
                    notes = notes + '===================\n';  
                    notes = notes + 'Q55 - Additional Info: \n\n';      
                    for(Claimant_Country_lived__c item : livedIn) {
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
                            notes = notes + 'Lived and worked, Did you pay into the social security system of that country? - ' + (paidThere(item.Social_Security_Number__c) ? 'Yes' : 'No') + ', ';
                            if (String.isNotBlank(item.Social_Security_Number__c)) {
                                notes = notes + item.Social_Security_Number__c + ', ';
                            }
                            notes = notes.removeEnd(', ');
                            notes = notes + '\n\n';                            
                        }
                    }
                }
                
                
            }

            notes = notes + previousMarriageBlock(app);
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
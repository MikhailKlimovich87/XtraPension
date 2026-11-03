public with sharing class PK_PortalCheckYourEntitlementHelper {
    private static final String ORG_WIDE_EMAIL_ADDRESS = 'keeper@xtrapension.com';
    private static final String PK_REQUEST_CHECK_AGENT_EMAIL = 'daniel@xtrapension.com';

    public static Map<String, Object> getCheckYourEntitlementData(PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.id);
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                result.put('status', 'success');
                result.put(
                    'application',
                    new PK_ResponseWrappers.InitialEntitlementDataWrapper(apps[0])
                );
                result.put(
                    'isSeeWhatHMRCTold',
                    PK_PortalUtils.getRequestCheck(wrapper?.id) == null ? false : true
                );
                return result;
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> saveTaxYearAllocations(PK_RequestWrappers.SaveTaxYearWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.id);
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                String taxYearAllocationValue = '';
                for (PK_RequestWrappers.TaxYearAllocationWrapper tax : wrapper.taxYearAllocation) {
                    if (tax.isChecked) {
                        taxYearAllocationValue += tax.label + ';';
                    }
                }
                if (!String.isBlank(taxYearAllocationValue)) {
                    taxYearAllocationValue = taxYearAllocationValue.substring(0, taxYearAllocationValue.length() - 1);
                }
                update new Application__c (
                    Id = wrapper.id,
                    Tax_Year_Allocation__c = taxYearAllocationValue
                );
                result.put('status', 'success');
                result.put(
                    'application',
                    new PK_ResponseWrappers.InitialEntitlementDataWrapper(PK_PortalUtils.getApplication(wrapper?.id)[0])
                );
                return result;
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> saveRequestCheck(PK_RequestWrappers.RequestCheckWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.id);
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                Application__c app = apps[0];
                String taxYearAllocationValue = '';
                if (wrapper?.yearsSelected != null) {   
                    for (PK_RequestWrappers.TaxYearAllocationWrapper tax : wrapper?.yearsSelected) {
                        if (tax.isChecked) {
                        taxYearAllocationValue += tax.label + ';';
                    }
                }
                if (!String.isBlank(taxYearAllocationValue)) {
                    taxYearAllocationValue = taxYearAllocationValue.substring(0, taxYearAllocationValue.length() - 1);
                }
            }
                PK_Request_Check__c request = new PK_Request_Check__c(
                    Application__c = wrapper?.id,
                    PK_Requested_Check_Date__c = Date.today(),
                    PK_Amount_Paid__c = wrapper?.amountPaid,
                    PK_When_Paid__c = wrapper?.whenPaid != null ? Date.valueOf(wrapper.whenPaid) : null,
                    CurrencyIsoCode = 'GBP',
                    Tax_Year_Allocation__c = taxYearAllocationValue
                );
                insert request;

                OrgWideEmailAddress[] owea = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
                ];
                List<PK_Request_Check__c> currRequest = [
                    SELECT Name
                    FROM PK_Request_Check__c
                    WHERE Id = :request.Id
                    LIMIT 1
                ];
                Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
                message.setUseSignature(false);
                message.setBccSender(false);
                message.setSaveAsActivity(true);
                message.setTreatTargetObjectAsRecipient(false);
                message.setSubject(currRequest[0].Name + ' - ' + app.Name + ' - ' + app.First_Name__c + ' ' + app.Second_Name__c + ' Check If Payment was Received');
                String emailBody = 'Paid £' + wrapper?.amountPaid +' on ' + Datetime.newInstance(wrapper?.whenPaid, Time.newInstance(0, 0, 0, 0)).format('dd/MM/yyyy');

                if( wrapper?.yearsSelected != null && wrapper?.yearsSelected.size() > 0) {
                    emailBody += '<br/><br/>Years Selected:<ul>';
                    for (PK_RequestWrappers.TaxYearAllocationWrapper tax : wrapper.yearsSelected) {
                        if (tax.isChecked) {
                            emailBody += '<li>' + tax.label + '</li>';
                        }
                    }
                    emailBody += '</ul>';
                }
                message.setHtmlBody(emailBody);
                message.setWhatId(app.id);
                if ( owea.size() > 0 ) {
                    message.setOrgWideEmailAddressId(owea.get(0).Id);
                }
                message.toAddresses = new String[] { PK_REQUEST_CHECK_AGENT_EMAIL };
                Messaging.SingleEmailMessage[] messages = new List<Messaging.SingleEmailMessage> {message};
                Messaging.SendEmailResult[] results = Messaging.sendEmail(messages);
                result.put('status', 'success');
                return result;
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getRequestCheck(PK_RequestWrappers.RequestCheckWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.id);
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                result.put(
                    'checkRequest',
                    new PK_ResponseWrappers.RequestCheckWrapper(PK_PortalUtils.getRequestCheck(wrapper?.id))
                );
                result.put('status', 'success');
                return result;
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> editExtraYears(PK_RequestWrappers.EditExtraYearsWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.id);
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                update new Application__c (
                        Id = wrapper.id,
                        PK_Extra_Years__c = wrapper.extraYears
                );
                result.put(
                    'application',
                    new PK_ResponseWrappers.InitialEntitlementDataWrapper(PK_PortalUtils.getApplication(wrapper?.id)[0])
                );
                result.put('status', 'success');
                return result;
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> tickEntitlementOption(PK_RequestWrappers.RecordDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.id);
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                Application__c currApp = apps[0];
                if (currApp.Tax_Year_Allocation__c == null || !currApp.Tax_Year_Allocation__c.contains('2025 to 2026')) {
                    update new Application__c (
                        Id = wrapper.id,
                        Tax_Year_Allocation__c = currApp.Tax_Year_Allocation__c != null
                                                    ? currApp.Tax_Year_Allocation__c + ';2025 to 2026'
                                                    : '2025 to 2026'
                    );
                }
                result.put('status', 'success');
                return result;
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }
}
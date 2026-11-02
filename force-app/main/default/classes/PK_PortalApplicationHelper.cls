public with sharing class PK_PortalApplicationHelper {
    private static final String PENSION_KEEPER_PRODUCT = 'Pension Keeper';
    private static final String ORG_WIDE_EMAIL_ADDRESS = 'keeper@xtrapension.com';
    private static final String PK_EMAIL = 'pk@xtrapension.com';
    private static final String SLACK_SUPPORT_EMAIL = 'pk-support-aaaatazovt3za4cn3t4jya4m5u@xtrapensionworkspace.slack.com';

    public static Map<String, Object> createApplication(PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        if (wrapper == null) {
            result.put('status', 'error');
            result.put('message', 'Application data is empty');
            return result;
        }
        try {
            Account account = new Account();
            String phoneDuplicateFinder = '%' + wrapper.phone.substring(1, wrapper.phone.length() - 4) + '%';
            String personContactId = '';
            account = new Account(
                LastName                = wrapper?.name,
                PersonEmail             = wrapper?.email,
                PersonMobilePhone       = wrapper?.phone,
                PersonMailingCity       = wrapper.address?.city,
                PersonMailingCountry    = wrapper.address?.country,
                PersonMailingState      = wrapper.address?.state,
                PersonMailingPostalCode = wrapper.address?.postalCode,
                PersonMailingStreet     = wrapper.address?.street,
                Mailing_Country__c      = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.address?.country),
                Mailing_State__c        = wrapper?.address?.country == 'IE' ?
                                                wrapper?.address?.state :
                                                CountryCodeHelper.getCountryStateNameByIsoCode(
                                                    wrapper?.address?.country,
                                                    wrapper?.address?.state)
            );
            insert account;

            List<Contact> currentContact = [
                SELECT
                    Id,
                    AccountId
                FROM Contact
                WHERE AccountId = :account.Id
                LIMIT 1
            ];
            if (!currentContact.isEmpty()) {
                personContactId = currentContact[0].Id;
            }
            Application__c application = new Application__c(
                First_Name__c                         = wrapper?.firstName,
                Second_Name__c                        = wrapper?.lastName,
                Expiry_Date__c                        = Datetime.now().addYears(1),
                Payment_Method__c                     = wrapper?.paymentMethod,
                Stripe_Customer_Id__c                 = wrapper?.customer,
                Status__c                             = 'Pension Keeper',
                Last_Payment_Date__c                  = Date.today(),
                Stripe_Transaction_Id__c              = wrapper?.id,
                Contact__c                            = personContactId,
                Amount__c                             = wrapper?.amount != null ?  wrapper?.amount / 100 : 0,
                Related_Contact_Phone__c              = account.PersonMobilePhone,
                Email__c                              = account.PersonEmail,
                Current_Address_Abroad__City__s       = wrapper?.address?.city,
                Current_Address_Abroad__Street__s     = wrapper?.address?.street,
                Current_Address_Abroad__StateCode__s  = PK_PortalUtils.getContryStateName( wrapper?.address?.country,  wrapper?.address?.state),
                CurrencyIsoCode                       = wrapper?.currencyCode,
                Current_Address_Abroad__CountryCode__s= wrapper?.address?.country,
                Current_Address_Abroad__PostalCode__s = wrapper?.address?.postalCode,
                Current_Address_Abroad_Country__c     = CountryCodeHelper.getCountryNameByIsoCode(wrapper?.address?.country),
                Live_In_The_EU__c                     = wrapper?.currencyCode == 'EUR' ? true : false,
                Pension_Keeper_Changed_Date__c        = Date.today(),
                How_Did_You_Hear_About_Us__c          = wrapper?.howDidYouHearAboutUs,
                PK_Sale_Agent__c                      = wrapper?.agent,
                Package_Name__c                       = 'Standard',
                Current_Address_Abroad_State__c       = wrapper?.address?.country == 'IE' ?
                                                                wrapper.address?.state :
                                                                CountryCodeHelper.getCountryStateNameByIsoCode(
                                                                    wrapper?.address?.country,
                                                                    wrapper.address?.state
                                                                ),
                PK_Auto_Renewal__c                    = true,
                PK_Registration_Date__c               = Date.today()
            );
            insert application;
            SuccessDocsController.generateDocs(application.Id);
            result.putAll(createPayment(application.Id, wrapper?.latestCharge, account.Id, wrapper?.id));
            if (result.get('status') != 'error') {
                result.put('status', 'success');
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String,Object> createPayment(Id appId, String source, Id acctId, String paymentIntentId) {
        List<Application__c> currApps = PK_PortalUtils.getApplication(appId);
        if (currApps.size() == 0) {
            Map<String, Object> result = new Map<String, Object>();
            result.put('status', 'error');
            result.put('message', 'Not found application');
            return result;
        }
        Application__c app = currApps[0];
        List<PriceBookEntry> priceBookEntries = new List<PriceBookEntry>();
        Map<String, Object> result = new Map<String, Object>();
            if (!Test.isRunningTest()) {
                priceBookEntries = [
                    SELECT
                        Id,
                        Product2Id,
                        Product2.Name,
                        Pricebook2Id,
                        CurrencyIsoCode,
                        Pricebook2.IsStandard,
                        UnitPrice
                    FROM PriceBookEntry
                    WHERE Product2.Name = :PENSION_KEEPER_PRODUCT AND
                          CurrencyIsoCode = :app?.CurrencyIsoCode
                ];
            } else {
                priceBookEntries = [
                    SELECT
                            Id,
                            Product2Id,
                            Product2.Name,
                            Pricebook2Id,
                            Pricebook2.IsStandard,
                            UnitPrice
                    FROM PriceBookEntry
                ];
            }
            if (priceBookEntries.isEmpty()) {
                result.put('status', 'Error');
                result.put('message', 'PriceBookEntries are empty');
                return result;
            }
            PriceBookEntry pkPrice = priceBookEntries[0];
            Order currentOrder;
            List<Order> existingOrders = [
                SELECT Id
                FROM Order
                WHERE Application__c = :app.Id
            ];
            if (existingOrders.size() > 0) {
                currentOrder = existingOrders[0];
            }
            if (currentOrder == null) {
                currentOrder = new Order(
                    Status          = 'Draft',
                    EffectiveDate   = Date.today(),
                    Pricebook2Id    = pkPrice.Pricebook2Id,
                    AccountId       = acctId,
                    Application__c  = app.Id,
                    CurrencyIsoCode = app?.CurrencyIsoCode
                );
                insert currentOrder;
            }

            List<Sobject> newSobjects = new List<Sobject>();
            newSobjects.add(
                new OrderItem(
                    Product2Id       = pkPrice.Product2Id,
		            OrderId          = currentOrder.Id,
		            PricebookEntryId = pkPrice.Id,
		            Quantity         = 1,
                    UnitPrice        = pkPrice.UnitPrice
		        )
            );
            String paymentMethodId = '';
            if(app.Payment_Method__c != null && app.Payment_Method__c.contains(';')) {
                List<String> paymentMethods = app.Payment_Method__c.split(';');
                paymentMethodId = paymentMethods[paymentMethods.size() - 1].trim();
            } else if(app.Payment_Method__c != null) paymentMethodId = app.Payment_Method__c;
            newSobjects.add(
                new Payment__c (
                    Amount__c         = pkPrice.UnitPrice,
                    Product__c        = pkPrice.Product2Id,
                    Status__c         = 'Paid',
                    CurrencyIsoCode   = app?.CurrencyIsoCode,
                    Payment_Method__c = paymentMethodId,
                    Customer_Id__c    = String.isNotBlank(app.Current_Customer_Id__c) ? app.Current_Customer_Id__c : app.Stripe_Customer_Id__c,
                    Order__c          = currentOrder.Id,
                    Application__c    = app?.id,
                    Payment_Date__c   = Date.today(),
                    Payment_Intent__c = paymentIntentId,
                    Source__c         = source
                )
            );
            if (newSobjects != null) {
                insert newSobjects;
           }
           return result;
    }

    public static Map<String, Object> createRegistrationPayment(PK_RequestWrappers.PaymentDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.applicationId);
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                Application__c app = apps[0];
                Date pensionAge = PK_PortalUtils.calculatePensionDate(app.Date_Of_Birth__c);
                update new Application__c(
                    Id = app.id,
                    Status__c = 'Pension Keeper',
                    PK_Portal_User_Active__c = true,
                    PK_Portal_User_PW__c = PK_PortalAuthHelper.generatePassword(app),
                    PK_Registration_Date__c = Date.today(),
                    PK_Sale_Agent__c = wrapper?.agent,
                    PK_Date_Pension_Age_Reached__c = pensionAge,
                    Pension_Age__c = pensionAge != null ? PK_PortalUtils.getYearsMonthsDaysBetween(app.Date_Of_Birth__c, pensionAge) : null,
                    PK_Auto_Renewal__c = true
                );
                result.putAll(createPayment(app.Id, wrapper?.latestCharge, null, wrapper.id));
                PK_PortalUtils.sendRegistrationEmail(app);
                if (wrapper?.isPartnerXPClient == true) {
                    PK_PortalUtils.sendCouplesEmail(app);
                }
                if (result.get('status') != 'error') {
                    result.put('status', 'success');
                }
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> updatePaymentMethod(PK_RequestWrappers.PaymentDataWrapper wrapper) {
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
                update new Application__c(
                    Id = app.id,
                    Status__c = 'Pension Keeper',
                    Payment_Method__c = app.Payment_Method__c == null ?
                                            wrapper?.paymentMethod :
                                            app.Payment_Method__c != wrapper?.paymentMethod ?
                                                app.Payment_Method__c + '; ' + wrapper?.paymentMethod :
                                                ''                    
                );
                if (result.get('status') != 'error') {
                    result.put('status', 'success');
                }
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> updatePaymentMethodAfterReqistration(PK_RequestWrappers.PaymentDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.applicationId == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.applicationId);
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                Application__c app = apps[0];
                Date pensionAge = PK_PortalUtils.calculatePensionDate(app.Date_Of_Birth__c);
                update new Application__c(
                    Id = app.id,
                    Status__c = 'Pension Keeper',
                    PK_Portal_User_Active__c = true,
                    PK_Portal_User_PW__c = PK_PortalAuthHelper.generatePassword(app),
                    PK_Registration_Date__c = Date.today(),
                    PK_Date_Pension_Age_Reached__c = pensionAge,
                    PK_Sale_Agent__c = wrapper?.agent,
                    Pension_Age__c = pensionAge != null ? PK_PortalUtils.getYearsMonthsDaysBetween(app.Date_Of_Birth__c, pensionAge) : null,
                    Payment_Method__c = app.Payment_Method__c == null ?
                                            wrapper?.paymentMethod :
                                            app.Payment_Method__c != wrapper?.paymentMethod ?
                                                app.Payment_Method__c + '; ' + wrapper?.paymentMethod :
                                                '',
                    //First_Name__c                          = wrapper?.firstName,
                    //Second_Name__c                         = wrapper?.lastName,
                    Email__c                               = wrapper?.email,
                    Related_Contact_Phone__c               = wrapper?.phone,
                    // Current_Address_Abroad__City__s        = wrapper?.address?.city,
                    // Current_Address_Abroad__Street__s      = wrapper?.address?.street,
                    // Current_Address_Abroad__StateCode__s   = PK_PortalUtils.getContryStateName( wrapper?.address?.country,  wrapper?.address?.state),
                    // Current_Address_Abroad__CountryCode__s = wrapper?.address?.country,
                    // Current_Address_Abroad__PostalCode__s  = wrapper?.address?.postalCode,
                    PK_Auto_Renewal__c = true
                );
                result.putAll(createPayment(app.Id, wrapper?.latestCharge, null, wrapper.id));
                PK_PortalUtils.sendRegistrationEmail(app);
                if (wrapper?.isPartnerXPClient == true) {
                    PK_PortalUtils.sendCouplesEmail(app);
                }
                if (result.get('status') != 'error') {
                    result.put('status', 'success');
                }
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getApplicationDetail(PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper) {
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
                result.put('status', 'success');
                result.put(
                    'application',
                    new PK_ResponseWrappers.ApplicationDataWrapper(currApp)
                );
                return result;
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> updateApplicationDetails(PK_RequestWrappers.PortalApplicationDetailsDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null) {
                result.put('status', 'error');
                result.put('message', 'Input data is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.id);
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                Application__c currApp = apps[0];
                String stateCode = PK_PortalUtils.getStateCodeByLabel(wrapper?.application?.currentAddress?.state);
                if (currApp.Current_Address_Abroad__City__s != wrapper?.application?.currentAddress?.city ||
                    currApp.Current_Address_Abroad__Street__s != wrapper?.application?.currentAddress?.street ||
                    currApp.Current_Address_Abroad__StateCode__s != wrapper?.application?.currentAddress?.state ||        
                    currApp.Current_Address_Abroad__CountryCode__s != wrapper?.application?.currentAddress?.countryCode) {
                    PK_PortalUtils.sendChangeAddressEmail(currApp);
                }
                Application__c updatedApp = new Application__c(
                    Id = wrapper?.id,
                    Salutation__c = wrapper?.application?.title,
                    // First_Name__c = wrapper?.application?.firstName,
                    // Second_Name__c = wrapper?.application?.lastName,
                    Full_Maiden_Previous_Name__c = wrapper?.application?.fullMaidenName,
                    Date_Of_Birth__c = wrapper?.application?.dob,
                    National_Insurance_Number__c = wrapper?.application?.nationalInsuranceNumber,
                    Private_UK_Pension__c = wrapper?.application?.isPrivateUKPension != null ? Boolean.valueOf(wrapper?.application?.isPrivateUKPension) : false,
                    Current_Occupation__c = wrapper?.application?.currentOccupation
                    // Current_Address_Abroad__City__s = wrapper?.application?.currentAddress?.city,
                    // Current_Address_Abroad__Street__s = wrapper?.application?.currentAddress?.street,
                    // Current_Address_Abroad__StateCode__s = stateCode != null ? stateCode : null,
                    // Current_Address_Abroad__CountryCode__s = wrapper?.application?.currentAddress?.countryCode,
                    // Current_Address_Abroad__PostalCode__s = wrapper?.application?.currentAddress?.postalCode
                );
                update updatedApp;

                result.put('status', 'success');
                result.put(
                    'application',
                    new PK_ResponseWrappers.ApplicationDataWrapper(PK_PortalUtils.getApplication(wrapper?.id)[0])
                );
                return result;
            }

        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getLatestComments(PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<EmailMessage> messages = PK_PortalUtils.getEmailMessages(wrapper);
            if (messages.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found latest comments');
            } else {
                List<PK_ResponseWrappers.LatestCommentsWrapper> commentWrappers = new List<PK_ResponseWrappers.LatestCommentsWrapper>();
                for (EmailMessage mess : messages) {
                    commentWrappers.add(new PK_ResponseWrappers.LatestCommentsWrapper(mess));
                }
                result.put('status', 'success');
                result.put(
                    'comments',
                    commentWrappers
                );
                return result;
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getApplicationOverview(PK_RequestWrappers.ApplicationDetailsDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplicationOverview(wrapper?.id);
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                result.put(
                    'overview',
                    new PK_ResponseWrappers.OverviewDataWrapper(apps[0])
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

    public static Map<String, Object> createContentNotes(PK_RequestWrappers.CreateNotesDataWrapper wrapper) {
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
                ContentNote cnt = new ContentNote();
                cnt.Content = Blob.valueof(wrapper?.message);
                cnt.Title = wrapper?.subject;
                insert cnt;

                ContentDocumentLink clnk = new ContentDocumentLink();
                clnk.LinkedEntityId = wrapper?.id;
                clnk.ContentDocumentId = cnt.Id;
                clnk.ShareType = 'V';
                insert clnk;

                OrgWideEmailAddress[] owea = [
                    SELECT Id
                    FROM OrgWideEmailAddress
                    WHERE Address = :ORG_WIDE_EMAIL_ADDRESS
                ];
                Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
                message.setUseSignature(false);
                message.setBccSender(false);
                message.setSaveAsActivity(true);
                message.setCcAddresses(new String[] { 'clients@xtrapension.com' });
                message.setTreatTargetObjectAsRecipient(false);
                message.setSubject(wrapper?.subject);
                String body = wrapper?.message != null ? wrapper?.message : '<div></div>';
                body += '<br/><br/><div>' + apps[0].Name + ' - ' + apps[0].First_Name__c + ' ' + apps[0].Second_Name__c + '</div>';
                body += '<div>' + apps[0].Email__c + '</div>';
                message.setHtmlBody(body);
                message.setWhatId(wrapper?.id);
                if ( owea.size() > 0 ) {
                    message.setOrgWideEmailAddressId(owea.get(0).Id);
                }
                message.toAddresses = new String[] { PK_EMAIL, SLACK_SUPPORT_EMAIL };
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

    public static Map<String, Object> getPkApplication(PK_RequestWrappers.RecordDataWrapper wrapper) {
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
                result.put('application',
                    new PK_ResponseWrappers.PensionKeeperApplicationDataWrapper(
                        apps[0]
                    )
                );
                result.put('status', 'success');
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> updatePkApplication(PK_RequestWrappers.PensionKeeperApplicationDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.id == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.id);
            Boolean isNewCustomer = false;
            if (apps[0].PK_Registration_Date__c == null) isNewCustomer = true;
            if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                Application__c currApp = apps[0];
                update new Application__c(
                    Id = wrapper?.id,
                    //First_Name__c = wrapper?.firstName,
                    //Second_Name__c = wrapper?.lastName,
                    Email__c = wrapper?.email,
                    National_Insurance_Number__c = wrapper?.nino != null ? wrapper?.nino.deleteWhitespace() : null,
                    Related_Contact_Phone__c = wrapper?.phone,
                    Date_Of_Birth__c = wrapper?.dateOfBirth,
                    Years_Of_Work_In_The_UK__c = wrapper?.ukYears,
                    Heroku_Request__c = JSON.serializePretty(wrapper),
                    PK_Portal_User_Active__c = true,
                    PK_Registration_Date__c = Date.today(),
                    PK_Portal_User_PW__c = (wrapper?.nino + wrapper?.lastName).replaceAll('\'', '').toUpperCase().deleteWhitespace()
                );
                if (isNewCustomer) {
                    PK_PortalUtils.sendRegistrationEmail(currApp);
                }
                result.put('status', 'success');
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> savePkUploadedFile(PK_RequestWrappers.UploadDocumentDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.recordId == null) {
                result.put('status', 'error');
                result.put('message', 'Application Id is null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getApplication(wrapper?.recordId);
             if (apps.size() == 0) {
                result.put('status', 'error');
                result.put('message', 'Not found application');
            } else {
                Application__c app = apps[0];
                wrapper.fileName = app.First_Name__c + '_' + app.Second_Name__c + '_' + app.Name + '_' + 'APPROVAL_LETTER';
                result = PK_PortalDocumentHelper.uploadFileToRecord(wrapper);
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getEmailMessage(PK_RequestWrappers.EmailMessageDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.commentId == null) {
                result.put('status', 'error');
                result.put('message', 'Email Message Id or Application Id is null');
                return result;
            }
            EmailMessage currMessage = PK_PortalUtils.getLatestComment(wrapper?.commentId);
            if (currMessage == null) {
                result.put('status', 'error');
                result.put('message', 'Not found email message');
            } else {
                result.put('emailMessage',
                    new PK_ResponseWrappers.EmailMessageWrapper(
                        currMessage,
                        wrapper?.commentId
                    )
                );
                result.put('status', 'success');
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> getAttachment(PK_RequestWrappers.AttachmentDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || wrapper.attachmentId == null) {
                result.put('status', 'error');
                result.put('message', 'Attachment Id is null');
                return result;
            }
            ContentVersion currAttachment = PK_PortalUtils.getAttachment(wrapper?.attachmentId);
            if (currAttachment == null) {
                result.put('status', 'error');
                result.put('message', 'Not found attachment');
            } else {
                result.put('attachment',
                    new PK_ResponseWrappers.EmailAttachmentDocumentWrapper(currAttachment)
                );
                result.put('status', 'success');
            }
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }

    public static Map<String, Object> checkExistingApplication(PK_RequestWrappers.ExistApplicationDataWrapper wrapper) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            if (wrapper == null || 
                wrapper.email == null || 
                wrapper.firstName == null || 
                wrapper.lastName == null) {
                result.put('status', 'error');
                result.put('message', 'One or more required fields are null');
                return result;
            }
            List<Application__c> apps = PK_PortalUtils.getExistingApplication(wrapper?.email);
            if (apps.size() == 0) {
                result.put('isExist', false);
            } else {
                result.put('isExist', true);
                Set<String> appNumbers = new Set<String>();
                for (Application__c app : apps) {
                    appNumbers.add(app.Name);
                }
                result.put('applicationNumbers', appNumbers);
            }
            result.put('status', 'success');
        } catch (Exception e) {
            result.put('status', 'error');
            result.put('message', e.getLineNumber() + '-' + e.getMessage());
        }
        return result;
    }
}
public class PK_ResponseWrappers {

    public class CurrentApplicationDataWrapper {
        public String applicationId;
        public String applicationNumber;
        public String firstName;
        public String lastName;
        public String email;
        public Date dob;
        public String nationalInsuranceNumber;
        public AddressDataWrapper currentAddress;
        public String paymentMethod;
        public String customerId;
        public String phone;
        public String currencyCode;
        public CardDataWrapper cardData;
        public Boolean isShowApplicationDetails;

        public CurrentApplicationDataWrapper(Application__c app) {
            this.applicationId = app.Id;
            this.applicationNumber = app.Name;
            this.firstName = app.First_Name__c;
            this.lastName = app.Second_Name__c;
            this.email = app.Email__c;
            this.dob = app.Date_Of_Birth__c;
            this.nationalInsuranceNumber = app.National_Insurance_Number__c;
            this.currentAddress = new AddressDataWrapper(app);
            this.customerId = String.isNotBlank(app.Current_Customer_Id__c) ? app.Current_Customer_Id__c : app.Stripe_Customer_Id__c;
            this.phone = app.Related_Contact_Phone__c;
            this.currencyCode = app.CurrencyIsoCode;
            this.isShowApplicationDetails = app.PK_HideAppData__c == null ? false : !app.PK_HideAppData__c;
            if(app.Payment_Method__c != null && app.Payment_Method__c.contains(';')) {
                List<String> paymentMethods = app.Payment_Method__c.split(';');
                this.paymentMethod = paymentMethods[paymentMethods.size() - 1].trim();
            } else if(app.Payment_Method__c != null && !app.Payment_Method__c.contains(';')) this.paymentMethod = app.Payment_Method__c;
            if (this.paymentMethod != null) {
                StripeApiHandler.StripeAPIResponseWrapper requestPaymentMethodResult = StripeApiHandler.requestStripeApi(
					'payment_methods/' + this.paymentMethod,
					'GET',
					null
				);
                if (requestPaymentMethodResult.isError != true) {
                    Map<String,Object> methodData = (Map<String,Object>) JSON.deserializeUntyped(requestPaymentMethodResult?.responseBody);
                    cardData = new CardDataWrapper((Map<String,Object>) methodData.get('card'));

                }
            }
        }
    }

    public class CardDataWrapper {
        public String last4Digits;
        public String cardBrand;
        public Integer expireYear;
        public Integer expireMonth;

        public CardDataWrapper(Map<String,Object> inputData) {
            this.last4Digits = (String)inputData.get('last4');
            this.cardBrand = (String)inputData.get('brand');
            this.expireYear = (Integer)inputData.get('exp_year');
            this.expireMonth = (Integer)inputData.get('exp_month');
        }
    }

    public class ApplicationDataWrapper {
        public String id;
        public String title;
        public String firstName;
        public String lastName;
        public String fullMaidenName;
        public Date dob;
        public Boolean isPrivateUKPension;
        public String nationalInsuranceNumber;
        public String currentOccupation;
        public AddressDataWrapper currentAddress;
        public String phone;
        public String email;

        public ApplicationDataWrapper(Application__c app) {
            this.id = app.Id;
            this.title = app.Salutation__c;
            this.firstName = app.First_Name__c;
            this.lastName = app.Second_Name__c;
            this.fullMaidenName = app.Full_Maiden_Previous_Name__c;
            this.dob = app.Date_Of_Birth__c;
            this.nationalInsuranceNumber = app.National_Insurance_Number__c;
            this.isPrivateUKPension = app.Private_UK_Pension__c;
            this.currentOccupation = app.Current_Occupation__c;
            this.currentAddress = new AddressDataWrapper(app);
            this.phone = app.Related_Contact_Phone__c;
            this.email = app.Email__c;
        }
    }

    public class AddressDataWrapper {
        public String street;
        public String postalCode;
        public String state;
        public String city;
        public String country;
        public String countryCode;

        public AddressDataWrapper(Application__c app) {
            this.street = app.Current_Address_Abroad__Street__s;
            this.postalCode = app.Current_Address_Abroad__PostalCode__s;
            this.state = app.Current_Address_Abroad__StateCode__s;
            this.city = app.Current_Address_Abroad__City__s;
            this.countryCode =  app.Current_Address_Abroad__CountryCode__s;
            this.country = (String)app.get('CountryCode');
        }
    }

    public class FAQ_Wrapper {
        public String topic;
        public String question;
        public String answer;

        public FAQ_Wrapper(Frequently_Asked_Question__c faq) {
            this.topic = faq.Topic__c;
            this.question = faq.Question__c;
            this.answer = faq.Answer__c;
        }
    }

    public class EmailMessageWrapper {
        public String commentId;
        public String subject;
        public String body;
        public String fromAddress;
        public String toAddress;
        public String createdDate;
        public List<AttachmentDataWrapper> attachments;

        public EmailMessageWrapper(EmailMessage emailMsg, Id commentId) {
            this.subject = emailMsg.Subject;
            this.body = emailMsg.HtmlBody;
            this.fromAddress = emailMsg.FromAddress;
            this.toAddress = emailMsg.ToAddress;
            this.createdDate = emailMsg.CreatedDate.format('dd/MM/yyyy');
            this.commentId = commentId;
            if (emailMsg.HasAttachment) {
                this.attachments = new List<AttachmentDataWrapper>();
                List<ContentDocumentLink> attachmentsLink = [
                    SELECT
                        ContentDocument.Id,
                        ContentDocument.Title 
                    FROM ContentDocumentLink 
                    WHERE LinkedEntityId = :commentId
                ];
                for (ContentDocumentLink link : attachmentsLink) {
                    this.attachments.add(
                        new AttachmentDataWrapper(link)
                    );
                }
            }
        }
    }

    public class AttachmentDataWrapper {
        public String attachmentId;
        public String name;

        public AttachmentDataWrapper(ContentDocumentLink link) {
            this.attachmentId = link.ContentDocument.Id;
            this.name = link.ContentDocument.Title;
        }
    }

    public class EmailAttachmentDocumentWrapper {
        public String documentId;
        public String documentTitle;
        public String documentType;
        public Integer documentSize;
        public String createdDate;
        public String documentBody;

        public EmailAttachmentDocumentWrapper(ContentVersion attachment) {
            this.documentId = attachment.ContentDocumentId;
            this.documentTitle = attachment.ContentDocument.Title;
            this.documentType = attachment.ContentDocument.FileType;
            this.documentSize = attachment.ContentDocument.ContentSize;
            this.createdDate = attachment.CreatedDate.format('dd/MM/yyyy');
            this.documentBody = EncodingUtil.base64Encode(attachment.VersionData);
        }
    }

    public class LatestCommentsWrapper {
        public String subject;
        public String commentId;
        public String createdDate;

        public LatestCommentsWrapper(EmailMessage emailMsg) {
            this.subject = emailMsg.Subject;
            this.commentId = emailMsg.Id;
            this.createdDate = emailMsg.CreatedDate.format('dd/MM/yyyy');
        }
    }

    public class OverviewDataWrapper {
        public Date pensionDate;
        public String pensionAge;
        public String taxYear;
        public String payFrom;
        public Boolean isPaid;
        public List<TaxYearAllocationWrapper> taxYearAllocation;

        public OverviewDataWrapper(Application__c app) {
            if (app.PK_Date_Pension_Age_Reached__c != null && app.Pension_Age__c != null) {
                this.pensionDate = app.PK_Date_Pension_Age_Reached__c.addMonths(-4);
                this.pensionAge = app.Pension_Age__c;
            } else {
                this.pensionDate = PK_PortalUtils.calculatePensionDate(app.Date_Of_Birth__c);
                this.pensionAge = PK_PortalUtils.getYearsMonthsDaysBetween(app.Date_Of_Birth__c, this.pensionDate);
                update new Application__c (
                            Id = app.Id,
                            PK_Date_Pension_Age_Reached__c = this.pensionDate,
                            Pension_Age__c = this.pensionAge
                        );
            }
            Pension_Keeper_Settings__c settings = Pension_Keeper_Settings__c.getInstance();
            this.taxYear = settings.Tax_Year__c;
            this.payFrom = settings.Pay_From__c;
            this.isPaid = app.Tax_Year_Allocation__c != null && app.Tax_Year_Allocation__c.contains('2025 to 2026')
                            ? true
                            : false;
            this.taxYearAllocation = new List<TaxYearAllocationWrapper>();
            for (Schema.PicklistEntry entry : PK_PortalUtils.getAllMultiSelectPicklistValues('PK_Request_Check__c', 'Tax_Year_Allocation__c')) {
                Boolean isChecked = false;
                if (app.Tax_Year_Allocation__c != null) {
                    List<String> selectedValues = app.Tax_Year_Allocation__c.split(';');
                    if (selectedValues.contains(entry.getValue())) {
                        isChecked = true;
                    }
                }
                this.taxYearAllocation.add(new TaxYearAllocationWrapper(entry.getLabel(), isChecked));
            }
        }
    }

    public class InitialEntitlementDataWrapper {
        public String firstName;
        public String lastName;
        public Decimal uk_years;
        public String pension_age;
        public Decimal entitlement;
        public List<TaxYearAllocationWrapper> taxYearAllocation;
        public Integer numberOfTickBoxes;
        public Decimal fullEntitlement;
        public Integer yearsToBuyLimit;
        public Integer extraYears;
        public Decimal projection;
        public Integer c3Cost;

        public InitialEntitlementDataWrapper(Application__c app) {
            this.firstName = app.First_Name__c;
            this.lastName = app.Second_Name__c;
            this.uk_years = app.Years_Of_Work_In_The_UK__c;
            this.pension_age = app.Pension_Age__c;
            this.entitlement = app.Entitlement__c;
            this.numberOfTickBoxes = app.Number_of_Tick_Task_Year__c != null ? Integer.valueOf(app.Number_of_Tick_Task_Year__c) : null;
            this.fullEntitlement = app.Full_Entitlement__c;
            this.yearsToBuyLimit = app.Years_To_Buy__c != null ? Integer.valueOf(app.Years_To_Buy__c) : null;
            this.extraYears = app.PK_Extra_Years__c != null ? Integer.valueOf(app.PK_Extra_Years__c) : null;
            this.projection = app.Projection__c;
            this.c3Cost = Pension_Keeper_Settings__c.getInstance().C3_Cost__c != null ? Integer.valueOf(Pension_Keeper_Settings__c.getInstance().C3_Cost__c) : null;
            this.taxYearAllocation = new List<TaxYearAllocationWrapper>();
            for (Schema.PicklistEntry entry : PK_PortalUtils.getAllMultiSelectPicklistValues('Application__c', 'Tax_Year_Allocation__c')) {
                Boolean isChecked = false;
                if (app.Tax_Year_Allocation__c != null) {
                    List<String> selectedValues = app.Tax_Year_Allocation__c.split(';');
                    if (selectedValues.contains(entry.getValue())) {
                        isChecked = true;
                    }
                }
                this.taxYearAllocation.add(new TaxYearAllocationWrapper(entry.getLabel(), isChecked));
            }
        }
    }

    public class TaxYearAllocationWrapper {
        public String label;
        public Boolean isChecked;

        public TaxYearAllocationWrapper(String label, Boolean isChecked) {
            this.label = label;
            this.isChecked = isChecked;
        }
    }

    public class RequestCheckWrapper {
        public String checkDate;
        public Decimal amountPaid;
        public String paymentReceived;

        public RequestCheckWrapper(PK_Request_Check__c check) {
            this.checkDate = check.PK_Requested_Check_Date__c != null ? DateTime.newInstance(check.PK_Requested_Check_Date__c,Time.newInstance(0, 0, 0, 0)).format('dd/MM/yyyy') : null;
            this.amountPaid = check.PK_Amount_Paid__c;
            this.paymentReceived = check.PK_Payment_Received__c != null ? DateTime.newInstance(check.PK_Payment_Received__c,Time.newInstance(0, 0, 0, 0)).format('dd/MM/yyyy') : null;
        }
    }

    public class BillingDataWrapper {
        public String applicationId;
        public String curencyCode;
        public Integer amount;
        public String renewsDate;
        public CardDataWrapper cardData;
        public List<ReceiptDataWrapper> receiptData;
        public String customerId;

        public BillingDataWrapper(Application__c app) {
            this.applicationId = app.Id;
            this.curencyCode = app.CurrencyIsoCode;
            this.amount = app.PK_Billing_Plan__c != null ? Integer.valueOf(app.PK_Billing_Plan__c) : null;
            this.renewsDate = app.PK_Registration_Date__c != null ? DateTime.newInstance(app.PK_Registration_Date__c.addYears(1),Time.newInstance(0, 0, 0, 0)).format('dd/MM/yyyy') : null;
            this.customerId = app.Stripe_Customer_Id__c;
            String paymentMethod;
            if(app.Payment_Method__c != null && app.Payment_Method__c.contains(';')) {
                List<String> paymentMethods = app.Payment_Method__c.split(';');
                paymentMethod = paymentMethods[paymentMethods.size() - 1].trim();
            } else if(app.Payment_Method__c != null && !app.Payment_Method__c.contains(';')) paymentMethod = app.Payment_Method__c;
            if (paymentMethod != null) {
                StripeApiHandler.StripeAPIResponseWrapper requestPaymentMethodResult = StripeApiHandler.requestStripeApi(
					'payment_methods/' + paymentMethod,
					'GET',
					null
				);
                if (requestPaymentMethodResult.isError != true) {
                    Map<String,Object> methodData = (Map<String,Object>) JSON.deserializeUntyped(requestPaymentMethodResult?.responseBody);
                    cardData = new CardDataWrapper((Map<String,Object>) methodData.get('card'));
                }
                List<Payment__c> payments = PK_PortalUtils.getPayment(app.Id);
                if (payments.size() != 0) {
                    this.receiptData = new List<ReceiptDataWrapper>();
                    for (Payment__c payment : payments) {
                        receiptData.add(new ReceiptDataWrapper(payment));
                    }
                }
            }
        }
    }

    public class ReceiptDataWrapper {
        public String paymentId;
        public String paymentDate;
        public Integer amount;
        public String currencyCode;

        public ReceiptDataWrapper(Payment__c payment) {
            this.paymentId = payment.Id;
            this.paymentDate = ((Datetime)payment.Payment_Date__c).format('MMM yyyy');
            this.amount = payment.Amount__c != null ? Integer.valueOf(payment.Amount__c) : null;
            this.currencyCode = payment.CurrencyIsoCode;
        }
    }

    public class PensionKeeperApplicationDataWrapper {
        public String id;
        public String title;
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public String nino;
        public Date dob;
        public Long ukYears;
        public AddressDataWrapper currentAddress;

        public PensionKeeperApplicationDataWrapper(Application__c app) {
            this.id = app.Id;
            this.title = app.Name;
            this.firstName = app.First_Name__c;
            this.lastName = app.Second_Name__c;
            this.email = app.Email__c;
            this.phone = app.Related_Contact_Phone__c;
            this.nino = app.National_Insurance_Number__c;
            this.dob = app.Date_Of_Birth__c != null ? Date.valueOf(app.Date_Of_Birth__c) : null;
            this.ukYears = app.Years_Of_Work_In_The_UK__c != null ? app.Years_Of_Work_In_The_UK__c.round(System.RoundingMode.HALF_UP) : null;
            this.currentAddress = new AddressDataWrapper(app);
        }
    }
}
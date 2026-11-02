public class PK_RequestWrappers {

    public class ApplicationDataWrapper {
        public String applicationNumber;
        public String email;

        public ApplicationDataWrapper(String inputData) {
            ApplicationDataWrapper wrapper = (ApplicationDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ApplicationDataWrapper.class);
            this.applicationNumber = wrapper.applicationNumber;
            this.email = wrapper.email;
        }
    }

    public class LoginDataWrapper {
        public String applicationNumber;
        public String password;
        public String ip;
        public String device;
        public String countryISO;
        public String browser;

        public LoginDataWrapper(String inputData) {
            LoginDataWrapper wrapper = (LoginDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), LoginDataWrapper.class);
            this.applicationNumber = wrapper.applicationNumber;
            this.password = wrapper.password;
            this.ip = wrapper.ip;
            this.device = wrapper.device;
            this.countryISO = wrapper.countryISO;
            this.browser = wrapper.browser;
        }
    }

    // Get Documents
    public class GetDocumentsDataWrapper {
        public String recordId;
        public String docLimit;

        public GetDocumentsDataWrapper(String jsonString) {
            GetDocumentsDataWrapper wrapper = (GetDocumentsDataWrapper) JSON.deserialize(jsonString.replaceAll('""', 'null'), GetDocumentsDataWrapper.class);
            this.recordId = wrapper.recordId;
            this.docLimit = wrapper.docLimit;
        }

        public GetDocumentsDataWrapper() {}
    }

    // Upload Document
    public class UploadDocumentDataWrapper {
        public String recordId;
        public String base64;
        public String fileType;
        public String fileName;

        public UploadDocumentDataWrapper(String jsonString) {
            UploadDocumentDataWrapper wrapper = (UploadDocumentDataWrapper) JSON.deserialize(jsonString.replaceAll('""', 'null'), UploadDocumentDataWrapper.class);
            recordId = wrapper.recordId;
            base64 = wrapper.base64;
            fileType = wrapper.fileType;
            fileName = wrapper.fileName;
        }
    }

    // Get Document
    public class GetDocumentDataWrapper {
        public String documentId;

        public GetDocumentDataWrapper(String jsonString) {
            GetDocumentDataWrapper wrapper = (GetDocumentDataWrapper) JSON.deserialize(jsonString.replaceAll('""', 'null'), GetDocumentDataWrapper.class);
            documentId = wrapper.documentId;
        }
    }

    public class ApplicationDetailsDataWrapper {
        public String id;
        public Integer commentsLimit;
        public Decimal amount;
        public String email;
        public String phone;
        public String name;
        public AddressDataWrapper address;
        public String firstName;
        public String lastName;
        public String paymentMethod;
        public String customer;
        public String foundApplicationId;
        public String currencyCode;
        public String latestCharge;
        public String howDidYouHearAboutUs;
        public String agent;

        public ApplicationDetailsDataWrapper(String inputData) {
            ApplicationDetailsDataWrapper wrapper = (ApplicationDetailsDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ApplicationDetailsDataWrapper.class);
            this.foundApplicationId = wrapper.foundApplicationId;
            this.id = wrapper.id;
            this.amount = wrapper.amount;
            this.email = wrapper.email;
            this.phone = wrapper.phone;
            this.name   = wrapper.name;
            this.address   = wrapper.address;
            this.firstName= wrapper.firstName;
            this.lastName= wrapper.lastName;
            this.paymentMethod= wrapper.paymentMethod;
            this.customer= wrapper.customer;
            this.commentsLimit = wrapper.commentsLimit;
            this.currencyCode = wrapper.currencyCode;
            this.latestCharge = wrapper.latestCharge;
            this.howDidYouHearAboutUs = wrapper.howDidYouHearAboutUs;
            this.agent = wrapper.agent;
        }

        public ApplicationDetailsDataWrapper() {}
    }

    public class AddressDataWrapper {
        public String street;
        public String postalCode;
        public String state;
        public String city;
        public String country;
        public String countryCode;
    }

    public class PortalApplicationDetailsDataWrapper {
        public String id;
        public ApplicationDetailDataWrapper application;

        public PortalApplicationDetailsDataWrapper(String inputData) {
            PortalApplicationDetailsDataWrapper wrapper = (PortalApplicationDetailsDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), PortalApplicationDetailsDataWrapper.class);
            this.id = wrapper.id;
            this.application = wrapper.application;
        }
    }

    public class ApplicationDetailDataWrapper {
        public String title;
        public String firstName;
        public String lastName;
        public String fullMaidenName;
        public Date dob;
        public Boolean isPrivateUKPension;
        public String nationalInsuranceNumber;
        public String currentOccupation;
        public AddressDataWrapper currentAddress;
    }

    public class CreateNotesDataWrapper {
        public String id;
        public String subject;
        public String message;

        public CreateNotesDataWrapper(String jsonString) {
            CreateNotesDataWrapper wrapper = (CreateNotesDataWrapper) JSON.deserialize(jsonString.replaceAll('""', 'null'), CreateNotesDataWrapper.class);
            id = wrapper.id;
            subject = wrapper.subject;
            message = wrapper.message;
        }
    }

    public class SaveTaxYearWrapper{
        public String id;
        public List<TaxYearAllocationWrapper> taxYearAllocation;

        public SaveTaxYearWrapper(String jsonString) {
            SaveTaxYearWrapper wrapper = (SaveTaxYearWrapper) JSON.deserialize(jsonString.replaceAll('""', 'null'), SaveTaxYearWrapper.class);
            id = wrapper.id;
            taxYearAllocation = wrapper.taxYearAllocation;
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
        public String id;
        public Decimal amountPaid;
        public Date whenPaid;
        public List<TaxYearAllocationWrapper> yearsSelected;

        public RequestCheckWrapper(String jsonString) {
            RequestCheckWrapper wrapper = (RequestCheckWrapper) JSON.deserialize(jsonString.replaceAll('""', 'null'), RequestCheckWrapper.class);
            this.id = wrapper.id;
            this.amountPaid = wrapper.amountPaid;
            this.whenPaid = wrapper.whenPaid;
            this.yearsSelected = wrapper.yearsSelected;
        }
    }

    public class EditExtraYearsWrapper {
        public String id;
        public Integer extraYears;

        public EditExtraYearsWrapper(String jsonString) {
            EditExtraYearsWrapper wrapper = (EditExtraYearsWrapper) JSON.deserialize(jsonString.replaceAll('""', 'null'), EditExtraYearsWrapper.class);
            this.id = wrapper.id;
            this.extraYears = wrapper.extraYears;
        }
    }

    public class RecordDataWrapper {
        public String id;

        public RecordDataWrapper(String jsonString) {
            RecordDataWrapper wrapper = (RecordDataWrapper) JSON.deserialize(jsonString.replaceAll('""', 'null'), RecordDataWrapper.class);
            id = wrapper.id;
        }
    }

    public class PaymentDataWrapper {
        public String id;
        public String applicationId;
        public String paymentMethod;
        public String customer;
        public Decimal amount;
        public String email;
        public String name;
        public String firstName;
        public String lastName;
        public String phone;
        public String currencyCode;
        public String latestCharge;
        public AddressDataWrapper address;
        public Boolean isPartnerXPClient;
        public String agent;

        public PaymentDataWrapper(String jsonString) {
            PaymentDataWrapper wrapper = (PaymentDataWrapper) JSON.deserialize(jsonString.replaceAll('""', 'null'), PaymentDataWrapper.class);
            this.id = wrapper.id;
            this.applicationId = wrapper.applicationId;
            this.paymentMethod = wrapper.paymentMethod;
            this.customer = wrapper.customer;
            this.amount = wrapper.amount;
            this.email = wrapper.email;
            this.name = wrapper.name;
            this.firstName = wrapper.firstName;
            this.lastName = wrapper.lastName;
            this.phone = wrapper.phone;
            this.currencyCode = wrapper.currencyCode;
            this.latestCharge = wrapper.latestCharge;
            this.address = wrapper.address;
            this.isPartnerXPClient = wrapper.isPartnerXPClient;
            this.agent = wrapper.agent;
        }
    }

    public class PensionKeeperApplicationDataWrapper {
        public String id;
        public String firstName;
        public String lastName;
        public String email;
        public String nino;
        public Integer ukYears;
        public Date dateOfBirth;
        public String phone;
        public AddressDataWrapper address;

        public PensionKeeperApplicationDataWrapper(String jsonString) {
            PensionKeeperApplicationDataWrapper wrapper = (PensionKeeperApplicationDataWrapper) JSON.deserialize(jsonString.replaceAll('""', 'null'), PensionKeeperApplicationDataWrapper.class);
            this.id = wrapper.id;
            this.firstName = wrapper.firstName;
            this.lastName = wrapper.lastName;
            this.email = wrapper.email;
            this.nino = wrapper.nino;
            this.ukYears = wrapper.ukYears;
            this.dateOfBirth = wrapper.dateOfBirth != null ? Date.valueOf(wrapper.dateOfBirth) : null;
            this.phone = wrapper.phone;
            this.address = wrapper.address;
        }
    }

    public class EmailMessageDataWrapper {
        public String commentId;

        public EmailMessageDataWrapper(String inputData) {
            EmailMessageDataWrapper wrapper = (EmailMessageDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), EmailMessageDataWrapper.class);
            this.commentId = wrapper.commentId;
        }
    }

    public class  AttachmentDataWrapper {
        public String attachmentId;

        public AttachmentDataWrapper(String inputData) {
            AttachmentDataWrapper wrapper = (AttachmentDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), AttachmentDataWrapper.class);
            this.attachmentId = wrapper.attachmentId;
        }
    }

    public class ExistApplicationDataWrapper {
        public String email;
        public String firstName;
        public String lastName;

        public ExistApplicationDataWrapper(String inputData) {
            ExistApplicationDataWrapper wrapper = (ExistApplicationDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ExistApplicationDataWrapper.class);
            this.email = wrapper.email;
            this.firstName = wrapper.firstName;
            this.lastName = wrapper.lastName;
        }
    }
}
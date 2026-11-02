public class RE_RequestWrapper {
    public class ReapplyDataWrapper {
        public Id recordId;
        
        public ReapplyDataWrapper(String inputData) {
            ReapplyDataWrapper wrapper = (ReapplyDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), ReapplyDataWrapper.class);
            this.recordId = wrapper.recordId;
        }
    }
    
    public class UpdateReapplyDataWrapper {
        public Id recordId;
        public String firstName;
        public String secondName;
        public String formerName;
        public String email;
        public String phone;
        public AddressDataWrapper currentAddress;
        public String ukYears;
        public String payNationalInsuranceYears;
        public Boolean receivedJobSeekersAllowance;
        public Date receiveJSALastDate;
        public Boolean receivedChildBenefit;
        public Date receiveChildBenefitLastDate;
        public Boolean isApr2024;
        public Boolean isApr2025;
        
        public UpdateReapplyDataWrapper(String inputData) {
            UpdateReapplyDataWrapper wrapper = (UpdateReapplyDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), UpdateReapplyDataWrapper.class);
            this.recordId = wrapper.recordId;
            this.firstName = wrapper.firstName;
            this.secondName = wrapper.secondName;
            this.formerName = wrapper.formerName;
            this.email = wrapper.email;
            this.phone = wrapper.phone;
            this.currentAddress = wrapper.currentAddress;
            this.ukYears = wrapper.ukYears;
            this.payNationalInsuranceYears = wrapper.payNationalInsuranceYears;
            this.receivedJobSeekersAllowance = wrapper.receivedJobSeekersAllowance;
            this.receiveJSALastDate = wrapper.receiveJSALastDate;
            this.receivedChildBenefit = wrapper.receivedChildBenefit;
            this.receiveChildBenefitLastDate = wrapper.receiveChildBenefitLastDate;
            this.isApr2024 = wrapper.isApr2024;
            this.isApr2025 = wrapper.isApr2025;
        }
    }
    
    public class UploadDocumentDataWrapper {
        public String recordId;
        public String base64;
        public String fileType;
        public String fileName;
        
        public UploadDocumentDataWrapper(String jsonString) {
            UploadDocumentDataWrapper wrapper = (UploadDocumentDataWrapper) JSON.deserialize(jsonString, UploadDocumentDataWrapper.class);
            this.recordId = wrapper.recordId;
            this.base64 = wrapper.base64;
            this.fileType = wrapper.fileType;
            this.fileName = wrapper.fileName;
        }
        
        public UploadDocumentDataWrapper(String recordId, String base64, String fileType, String fileName) {
            this.recordId = recordId;
            this.base64 = base64;
            this.fileType = fileType;
            this.fileName = fileName;
        }
    }
    
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
        public Boolean isPensionKeeperCustomer;

        public CurrentApplicationDataWrapper() {

        }
        
    }
    
    public class AddressDataWrapper {
        public String street;
        public String postalCode;
        public String state;
        public String city;
        public String country;
        public String countryCode;
    
        public AddressDataWrapper() {
        }
    }
    
    public class CardDataWrapper {
        public String last4Digits;
        public String cardBrand;
        public Integer expireYear;
        public Integer expireMonth;
    
        public CardDataWrapper() {

        }
    }
    
    public class PaymentDataWrapper {
        public String id;
        public CurrentApplicationDataWrapper foundApplication;
        public String recordId;
        public Integer amount;
        public String currencyCode;
        public String email;
        public String name;
        public String firstName;
        public String lastName;
        public String phone;
        public AddressDataWrapper address;
        public String paymentMethod;
        public String customer;
        public String latest_charge;
        public String stageOption;
        public String agent;
        
        public PaymentDataWrapper(String inputData) {
            PaymentDataWrapper wrapper = (PaymentDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), PaymentDataWrapper.class);
            this.id = wrapper.id;
            this.foundApplication = wrapper.foundApplication;
            this.recordId = wrapper.recordId;
            this.amount = wrapper.amount;
            this.currencyCode = wrapper.currencyCode;
            this.email = wrapper.email;
            this.name = wrapper.name;
            this.firstName = wrapper.firstName;
            this.lastName = wrapper.lastName;
            this.phone = wrapper.phone;
            this.address = wrapper.address;
            this.paymentMethod = wrapper.paymentMethod;
            this.customer = wrapper.customer;
            this.latest_charge = wrapper.latest_charge;
            this.stageOption = wrapper.stageOption;
            this.agent = wrapper.agent;
        }
    }

    public class MakeChangeDataWrapper {
        public String recordId;

        public MakeChangeDataWrapper(String inputData) {
            MakeChangeDataWrapper wrapper = (MakeChangeDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), MakeChangeDataWrapper.class);
            this.recordId = wrapper.recordId;
        }
    }

    public class NewReapplyDataWrapper {
        public String id;
        public Decimal amount;
        public String email;
        public String phone;
        public String name;
        public AddressDataWrapper address;
        public String firstName;
        public String lastName;
        public String paymentMethod;
        public String customer;
        public Boolean tax;
        public String latest_charge;
        public String howDidYouHearAboutUs;
        public String agent;
        public String currencyCode;

        public NewReapplyDataWrapper(String inputData) {
            NewReapplyDataWrapper wrapper = (NewReapplyDataWrapper) JSON.deserialize(inputData.replaceAll('""', 'null'), NewReapplyDataWrapper.class);
            this.id = wrapper.id;
            this.amount = wrapper.amount;
            this.email = wrapper.email;
            this.phone = wrapper.phone;
            this.name = wrapper.name;
            this.address = wrapper.address;
            this.firstName = wrapper.firstName;
            this.lastName = wrapper.lastName;
            this.paymentMethod = wrapper.paymentMethod;
            this.customer = wrapper.customer;
            this.tax = wrapper.tax;
            this.latest_charge = wrapper.latest_charge;
            this.howDidYouHearAboutUs = wrapper.howDidYouHearAboutUs;
            this.agent = wrapper.agent;
            this.currencyCode = wrapper.currencyCode;
        }
    }

}
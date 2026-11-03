public with sharing class BP_CheckBank {

    public static final String BP_BANK_VALIDATION_URL = Data8__c.getInstance().BankAccountValidationURL__c;
    //public static final String BP_BANK_IBAN_VALIDATION_URL = Data8__c.getInstance().BankIBANValidation__c;
    public static final String BP_BANK_USERNAME = Data8__c.getInstance().username__c;

    private static final Map<String, String> SWIFT_AU =
        new Map<String, String>{
            'CBA' => 'CTBAAU2S',
            'WBC' => 'WPACAU2S',
            'ANZ' => 'ANZBAU3M',
            'NAB' => 'NATAAU3303M'
        };

    public static BankAccountValidationResponseWrapper validAUSCheck(Map<String, String> outputMap) {
        BankAccountValidationResponseWrapper bankAccountValidationResult = new BankAccountValidationResponseWrapper();
        String sortCode='';
        String accountNumber = '';
        sortCode = outputMap.get('sortCode');
        accountNumber = outputMap.get('accountNumber');
        Id recordTypeIdBank = Schema.SObjectType.Bank_Address_Cache__c
                                .getRecordTypeInfosByDeveloperName()
                                .get('Australia_Bank')
                                .getRecordTypeId();
        String formattedSortCode = sortCode.replace('-', '').replaceAll('(.{3})(?=.)', '$1-');
        List<Bank_Address_Cache__c> bankCache = new List<Bank_Address_Cache__c>();
        bankCache = [
            SELECT Id, Account__c, Bank_Address__c, Bank_City__c, Bank_State__c, Bank_Name__c, Bank_Postcode__c, BIC_SWIFT__c, IBAN__c, Sort_Code__c, Branch_Name__c, LastModifiedDate,
            Mnemonic__c, RecordTypeId
            FROM Bank_Address_Cache__c
            WHERE  Sort_Code__c=: formattedSortCode
            AND  RecordTypeId =: recordTypeIdBank
            LIMIT 1];

        if(bankCache.isEmpty()) {
            StatusWrapper status = new StatusWrapper();
            status.Success = false;
            status.CreditsRemaining = null;
            bankAccountValidationResult.Status = status;
            bankAccountValidationResult.Valid = 'Try manually';
            return bankAccountValidationResult;
        }
        Bank_Address_Cache__c cacheData = bankCache[0];
        StatusWrapper status = new StatusWrapper();
        status.Success = true;
        status.CreditsRemaining = null;

        // Only the big four have a known SWIFT; for any other bank the 3-letter mnemonic is NOT a BIC, so leave it empty
        String bigSWIFT = SWIFT_AU.containsKey(cacheData.Mnemonic__c) ? SWIFT_AU.get(cacheData.Mnemonic__c) : '';
        bankAccountValidationResult.Status = status;
        bankAccountValidationResult.Valid = 'Cache';
        bankAccountValidationResult.SortCode = cacheData.Sort_Code__c.replaceAll('-', '').replaceAll('(.{2})(?=.)', '$1-');
        bankAccountValidationResult.BICCode = bigSWIFT;
        bankAccountValidationResult.IBAN = cacheData.IBAN__c;
        bankAccountValidationResult.BranchName = cacheData.Branch_Name__c;
        bankAccountValidationResult.AccountNumber = cacheData.Account__c;
        if(String.isBlank(bankAccountValidationResult.AccountNumber)) {
            bankAccountValidationResult.AccountNumber = accountNumber;
        }
        bankAccountValidationResult.ShortBankName = cacheData.Bank_Name__c;

        AddressWrapper addressData = new AddressWrapper();
        RawAddressWrapper rawAddress = new RawAddressWrapper();

        rawAddress.Postcode =  cacheData.Bank_Postcode__c;
        rawAddress.Locality = cacheData.Bank_City__c + ' ' + cacheData.Bank_State__c;
        rawAddress.Organisation = cacheData.Bank_Name__c;
        rawAddress.ThoroughfareName = cacheData.Bank_Address__c;

        addressData.RawAddress = rawAddress;
        bankAccountValidationResult.Address = addressData;


        
        return bankAccountValidationResult;
    }

    public static BankAccountValidationResponseWrapper validCheck(Map<String, String> outputMap) {
        String accountNumber='';
        String sortCode='';

        BankAccountValidationResponseWrapper bankAccountValidationResult = new BankAccountValidationResponseWrapper();
        
        BankValidationWrapper wrap = new BankValidationWrapper();
        //wrap.username = BP_BANK_USERNAME;
        

        String endpoint = BP_BANK_VALIDATION_URL;
         if(String.isNotBlank(outputMap.get('IBAN'))){
            endpoint = BP_BANK_VALIDATION_URL;
            BP_IrishIbanUtil.IrishIbanResult result =BP_IrishIbanUtil.parseIrishIban(outputMap.get('IBAN'));
            wrap.bankAccountNumber = result.account;
            wrap.sortCode = result.sortCode;
            OptionWrapper options = new OptionWrapper(true,true, 'IE');
            wrap.options = options;
            accountNumber = wrap.bankAccountNumber;
            sortCode = wrap.sortCode;
            
        } else if(String.isNotBlank(outputMap.get('sortCode')) && String.isNotBlank(outputMap.get('accountNumber'))) {
            endpoint = BP_BANK_VALIDATION_URL;
            wrap.bankAccountNumber = outputMap.get('accountNumber');
            wrap.sortCode =outputMap.get('sortCode');
            OptionWrapper options = new OptionWrapper(true,true, 'IE');
            wrap.options = options;
            accountNumber = wrap.bankAccountNumber;
            sortCode = wrap.sortCode;
        } 

        Id recordTypeIdBank = Schema.SObjectType.Bank_Address_Cache__c
                                .getRecordTypeInfosByDeveloperName()
                                .get('Irish_Bank')
                                .getRecordTypeId();
        
        List<Bank_Address_Cache__c> bankCache = new List<Bank_Address_Cache__c>();
        bankCache = [
            SELECT Id, Account__c, Bank_Address__c, Bank_City__c, Bank_Name__c, Bank_Postcode__c, BIC_SWIFT__c, IBAN__c, Sort_Code__c, Branch_Name__c, LastModifiedDate, RecordTypeId
            FROM Bank_Address_Cache__c
            WHERE Account__c =: accountNumber AND Sort_Code__c=: sortCode.replace('-', '')
            AND  RecordTypeId =: recordTypeIdBank
            LIMIT 1];
        if(bankCache.size()>0) {
            return parseCacheData(bankCache[0]);
        }

        Http http = new Http();
	    HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint+'?key='+BP_BANK_USERNAME);
        request.setMethod('POST');
        request.setBody(JSON.serialize(wrap));

        HttpResponse response = http.send(request);
        bankAccountValidationResult = (BankAccountValidationResponseWrapper) JSON.deserialize(
            response.getBody(),
            BankAccountValidationResponseWrapper.class
        );
        
        BP_EircodeService.EircodeResult result = BP_EircodeService.getEircodeIE(
            bankAccountValidationResult?.ShortBankName, 
            bankAccountValidationResult?.BranchName, 
            bankAccountValidationResult?.Address?.RawAddress?.Locality);
        
        bankAccountValidationResult.Address.RawAddress.ThoroughfareName = result.address;
        bankAccountValidationResult.Address.RawAddress.Postcode = result.eircode;

        insert new Bank_Address_Cache__c(
            Sort_Code__c =  bankAccountValidationResult.SortCode.replace('-', ''),
            Account__c =  bankAccountValidationResult.AccountNumber,
            BIC_SWIFT__c =  bankAccountValidationResult.BICCode,
            IBAN__c =  bankAccountValidationResult.IBAN,
            Bank_Name__c =  bankAccountValidationResult.ShortBankName,
            Bank_Postcode__c =  bankAccountValidationResult.Address.RawAddress.Postcode,
            Bank_Address__c =  bankAccountValidationResult.Address.RawAddress.ThoroughfareName,
            Branch_Name__c =  bankAccountValidationResult.BranchName,
            Bank_City__c =  bankAccountValidationResult.Address.RawAddress.Locality,
            RecordTypeId = Schema.SObjectType.Bank_Address_Cache__c
                                .getRecordTypeInfosByDeveloperName()
                                .get('Irish_Bank')
                                .getRecordTypeId()

        );

        return bankAccountValidationResult;
    }

    
    public static BankAccountValidationResponseWrapper parseCacheData(Bank_Address_Cache__c cacheData) {
        BankAccountValidationResponseWrapper bankAccountValidationResult = new BankAccountValidationResponseWrapper();
        String PostalCode = '';
        String Address = '';
        if(String.isBlank(cacheData.Sort_Code__c) && cacheData.LastModifiedDate < Datetime.now().addDays(-30)) {
            BP_EircodeService.EircodeResult result = BP_EircodeService.getEircodeIE(cacheData.Bank_Name__c, cacheData.Branch_Name__c, cacheData.Bank_City__c);
            PostalCode = result.eircode;
            Address =  result.address;
            update new Bank_Address_Cache__c(Id = cacheData.Id, Bank_Address__c = Address, Bank_Postcode__c = PostalCode);
        } else {
            PostalCode =  String.isBlank(cacheData.Bank_Postcode__c)? '' : cacheData.Bank_Postcode__c;
            Address =  String.isBlank(cacheData.Bank_Address__c) ? '' : cacheData.Bank_Address__c;
            
        }
        StatusWrapper status = new StatusWrapper();
        status.Success = true;
        status.CreditsRemaining = null;

        bankAccountValidationResult.Status = status;
        bankAccountValidationResult.Valid = 'Cache';
        bankAccountValidationResult.SortCode = cacheData.Sort_Code__c.replaceAll('(.{2})(?=.)', '$1-');
        bankAccountValidationResult.AccountNumber = cacheData.Account__c;
        bankAccountValidationResult.BICCode = cacheData.BIC_SWIFT__c;
        bankAccountValidationResult.IBAN = cacheData.IBAN__c;
        bankAccountValidationResult.BranchName = cacheData.Branch_Name__c;
        bankAccountValidationResult.AccountNumber = cacheData.Account__c;
        bankAccountValidationResult.ShortBankName = cacheData.Bank_Name__c;

        AddressWrapper addressData = new AddressWrapper();
        RawAddressWrapper rawAddress = new RawAddressWrapper();

        rawAddress.Postcode = PostalCode;
        rawAddress.Locality = cacheData.Bank_City__c;
        rawAddress.Organisation = cacheData.Bank_Name__c;
        rawAddress.ThoroughfareName = Address;

        addressData.RawAddress = rawAddress;
        bankAccountValidationResult.Address = addressData;
        return bankAccountValidationResult;
    }


    public class BankValidationWrapper {
        public String username;
        public String password;
        public String sortCode;
        public String bankAccountNumber;
        public OptionWrapper options;
        public String bic;
        public String iban;
    }


    public class OptionWrapper {
        public Boolean NormalizeCase;
        public Boolean NormalizeTownCase;
        public String CountryCode;
        public OptionWrapper(Boolean NormalizeCase, Boolean NormalizeTownCase, String CountryCode) {
            this.NormalizeCase = NormalizeCase;
            this.NormalizeTownCase = NormalizeTownCase;
            this.CountryCode = CountryCode;
        }
    }
 


    public class BankAccountValidationResponseWrapper {
    
        public StatusWrapper Status;
        public String Valid;
        public String SortCode;
        public String AccountNumber;
        public String BICCode;
        public String IBAN;
        public String BranchName;
        public String ShortBankName;
        public String FullBankName;
        public AddressWrapper Address;
        public Boolean AcceptsBACSPayments;
        public Boolean AcceptsDirectDebitTransactions;
        public Boolean AcceptsDirectCreditTransactions;
        public Boolean AcceptsUnpaidChequeClaimTransactions;
        public Boolean AcceptsBuildingSocietyCreditTransactions;
        public Boolean AcceptsDividendInterestPaymentTransactions;
        public Boolean AcceptsDirectDebitInstructionTransactions;
        public Boolean AcceptsCHAPSPayments;
        public Boolean AcceptsCheques;
        public Boolean AcceptsFasterPayments;

    }

    public class StatusWrapper {
            public Boolean Success;
            public Integer CreditsRemaining;
        }


        public class AddressWrapper {
            public AddressLinesWrapper Address;
            public RawAddressWrapper RawAddress;
        }


        public class AddressLinesWrapper {
            public List<String> Lines;
        }


        public class RawAddressWrapper {
            public String Organisation;
            public String Department;
            public Integer AddressKey;
            public Integer OrganisationKey;
            public Integer BuildingNumber;
            public String SubBuildingName;
            public String BuildingName;
            public String DependentThoroughfareName;
            public String ThoroughfareName;
            public String DoubleDependentLocality;
            public String DependentLocality;
            public String Locality;
            public String Postcode;
            public String Dps;
            public String PoBox;
            public String PostalCounty;
        }
    
}
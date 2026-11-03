public class BP_GoCardlessPaymentSchedulerController {

    @AuraEnabled(cacheable=true)
    public static Boolean hasExistingSchedule(Id claimId) {
        if (claimId == null) return false;
        return [
            SELECT COUNT()
            FROM Basic_Payment__c
            WHERE Basic__c = :claimId
            AND Product__r.Name = 'Claim - Direct Debit'
            AND Status__c IN ('Schedule', 'Submitted', 'Confirmed', 'Paid')
        ] > 0;
    }


    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getGbpExchangeInfo(String targetCurrency) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            // Normalise the target currency (default = GBP → no conversion)
            String ccy = String.isBlank(targetCurrency) ? 'GBP' : targetCurrency.toUpperCase();
            result.put('targetCurrency', ccy);

            // GBP → GBP needs no conversion
            if (ccy == 'GBP') {
                result.put('rate', 1);
                result.put('rateDate', null);
                result.put('fetchedAt', null);
                result.put('error', null);
                return result;
            }

            // Get the most recent daily rate record
            List<Daily_Exchange_Rate__c> latest = [
                SELECT Rate_Date__c, GBP_to_EUR__c, GBP_to_AUD__c, Fetched_At__c
                FROM Daily_Exchange_Rate__c
                ORDER BY Rate_Date__c DESC
                LIMIT 1
            ];

            if (latest.isEmpty()) {
                result.put('rate', null);
                result.put('rateDate', null);
                result.put('fetchedAt', null);
                result.put('error', 'No Daily Exchange Rate records found.');
                return result;
            }

            Daily_Exchange_Rate__c rec = latest[0];

            // Pick the correct rate for the requested currency
            Decimal rate = null;
            if (ccy == 'EUR') {
                rate = rec.GBP_to_EUR__c;
            } else if (ccy == 'AUD') {
                rate = rec.GBP_to_AUD__c;
            }

            result.put('rate', rate);
            result.put('rateDate', rec.Rate_Date__c);
            result.put('fetchedAt', rec.Fetched_At__c);
            result.put('gbpToEur', rec.GBP_to_EUR__c);
            result.put('gbpToAud', rec.GBP_to_AUD__c);
            result.put(
                'error',
                rate == null ? 'No GBP→' + ccy + ' rate available on the latest record.' : null
            );

        } catch (Exception e) {
            result.put('rate', null);
            result.put('rateDate', null);
            result.put('fetchedAt', null);
            result.put('error', e.getMessage());
        }

        return result;
    }


    @AuraEnabled
    public static String createDDPayments(MandateWrapper wrapper) {
        Savepoint sp = Database.setSavepoint();
        try {
            // --- 1. Validation ---
            if (wrapper == null) {
                AuraHandledException ex = new AuraHandledException('Wrapper is null.');
                ex.setMessage('Wrapper is null.');
                throw ex;
            }

            if (wrapper.claimId == null) {
                AuraHandledException ex = new AuraHandledException('claimId is required.');
                ex.setMessage('claimId is required.');
                throw ex;
            }

            // --- DUPLICATE GUARD ---
            if (hasExistingSchedule(wrapper.claimId)) {
                AuraHandledException ex = new AuraHandledException('A direct debit schedule already exists for this claim.');
                ex.setMessage('A direct debit schedule already exists for this claim.');
                throw ex;
            }

            if (wrapper.installments == null || wrapper.installments < 1) {
                AuraHandledException ex = new AuraHandledException('installments must be 1 or more.');
                ex.setMessage('installments must be 1 or more.');
                throw ex;
            }

            if (wrapper.firstChargeDate == null) {
                AuraHandledException ex = new AuraHandledException('firstChargeDate is required.');
                ex.setMessage('firstChargeDate is required.');
                throw ex;
            }

            if (wrapper.feeAmount == null || wrapper.feeAmount <= 0) {
                AuraHandledException ex = new AuraHandledException('feeAmount must be greater than 0.');
                ex.setMessage('feeAmount must be greater than 0.');
                throw ex;
            }

            if (wrapper.awardAmount == null || wrapper.awardAmount < 0) {
                AuraHandledException ex = new AuraHandledException('awardAmount must be 0 or greater.');
                ex.setMessage('awardAmount must be 0 or greater.');
                throw ex;
            }


            // --- 2. Load parent Basic__c ---
            List<Basic__c> claims = [
                SELECT Id, CurrencyIsoCode, Award_Amount_GBP__c
                FROM Basic__c
                WHERE Id = :wrapper.claimId
                LIMIT 1
            ];

            if (claims.isEmpty()) {
                AuraHandledException ex = new AuraHandledException('Claim not found: ' + wrapper.claimId);
                ex.setMessage('Claim not found: ' + wrapper.claimId);
                throw ex;
            }
            Basic__c claim = claims[0];

            // --- 3. Convert the FEE (GBP) to the record currency ---
            String recordCcy = claim.CurrencyIsoCode == null ? 'GBP' : claim.CurrencyIsoCode;
            Decimal gbpToRecordRate = 1.0;

            if (recordCcy != 'GBP') {
                List<Daily_Exchange_Rate__c> latest = [
                    SELECT GBP_to_EUR__c, GBP_to_AUD__c
                    FROM Daily_Exchange_Rate__c
                    ORDER BY Rate_Date__c DESC
                    LIMIT 1
                ];

                if (latest.isEmpty()) {
                    AuraHandledException ahe = new AuraHandledException('No Daily Exchange Rate record found.');
                    ahe.setMessage('No Daily Exchange Rate record found.');
                    throw ahe;
                }

                if (recordCcy == 'EUR') {
                    gbpToRecordRate = latest[0].GBP_to_EUR__c;
                } else if (recordCcy == 'AUD') {
                    gbpToRecordRate = latest[0].GBP_to_AUD__c;
                }

                if (gbpToRecordRate == null || gbpToRecordRate == 0) {
                    AuraHandledException ahe = new AuraHandledException('No GBP → ' + recordCcy + ' rate available.');
                    ahe.setMessage('No GBP → ' + recordCcy + ' rate available.');
                    throw ahe;
                }
            }

            Decimal feeInRecordCcy = (wrapper.feeAmount * gbpToRecordRate).setScale(2, RoundingMode.HALF_UP);

            // --- 4. Split into installments ---
            Decimal perInstallment = feeInRecordCcy.divide(wrapper.installments, 2, RoundingMode.HALF_UP);
            Decimal totalAssigned = perInstallment * wrapper.installments;
            Decimal remainder = feeInRecordCcy - totalAssigned;

            // --- 5. Product ---
            Product2 product = [
                SELECT Id
                FROM Product2
                WHERE Name = 'Claim - Direct Debit'
                LIMIT 1
            ];

            // --- 6. Build rows ---
            List<Basic_Payment__c> rows = new List<Basic_Payment__c>();

            for (Integer i = 0; i < wrapper.installments; i++) {
                Decimal thisAmount = perInstallment + (i == 0 ? remainder : 0);

                rows.add(
                    new Basic_Payment__c(
                        Amount__c = thisAmount,
                        Status__c = 'Schedule',
                        Payment_Date__c = wrapper.firstChargeDate.addMonths(i),
                        Basic__c = wrapper.claimId,
                        CurrencyIsoCode = claim.CurrencyIsoCode,
                        Product__c = product.Id
                    )
                );
            }

            Database.SaveResult[] results = Database.insert(rows, false);
            Integer successCount = 0;
            List<String> errors = new List<String>();
            
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    successCount++;
                } else {
                    for (Database.Error err : sr.getErrors()) {
                        errors.add(err.getMessage());
                    }
                }
            }
            
            if (!errors.isEmpty()) {
                // rollback the partial insert
                Database.rollback(sp);
                AuraHandledException ex = new AuraHandledException(
                    'Inserted ' + successCount + ' of ' + rows.size() + '. Errors: ' + String.join(errors, '; ')
                );
                ex.setMessage(
                    'Inserted ' + successCount + ' of ' + rows.size() + '. Errors: ' + String.join(errors, '; ')
                );
                throw ex;
            }

            claim.Award_Amount__c     = (wrapper.awardAmount * gbpToRecordRate).setScale(2, RoundingMode.HALF_UP);
            claim.Award_Amount_GBP__c = wrapper.awardAmount; 
            
            if (wrapper.dwpPaymentDate != null) {
                claim.DWP_Payment_Date__c = wrapper.dwpPaymentDate;
            }
            update claim;

            return 'Created ' + successCount + ' scheduled payment(s).';

        } catch (AuraHandledException ahe) {
            try { Database.rollback(sp); } catch (Exception ignored) {}
            throw ahe;
        } catch (Exception e) {
            try { Database.rollback(sp); } catch (Exception ignored) {}
            AuraHandledException ahe = new AuraHandledException('Error: ' + e.getMessage());
            ahe.setMessage('Error: ' + e.getMessage());
            throw ahe;
        }
    }


    @AuraEnabled
    public static void saveAwardAmount(
        Id claimId,
        Decimal awardAmount,          // GBP value typed by user
        Date dwpPaymentDate
    ) {
        if (claimId == null) {
            AuraHandledException ex = new AuraHandledException('claimId is required.');
            ex.setMessage('claimId is required.');
            throw ex;
        }
        if (awardAmount == null || awardAmount < 0) {
            AuraHandledException ex = new AuraHandledException('awardAmount must be 0 or greater.');
            ex.setMessage('awardAmount must be 0 or greater.');
            throw ex;
        }

        try {
            List<Basic__c> claims = [
                SELECT Id, CurrencyIsoCode
                FROM Basic__c
                WHERE Id = :claimId
                LIMIT 1
            ];
            if (claims.isEmpty()) {
                AuraHandledException ex = new AuraHandledException('Claim not found: ' + claimId);
                ex.setMessage('Claim not found: ' + claimId);
                throw ex;
            }
            Basic__c claim = claims[0];

            String recordCcy = claim.CurrencyIsoCode == null ? 'GBP' : claim.CurrencyIsoCode;
            Decimal awardInRecordCcy = awardAmount;   // default GBP
            
            if (recordCcy != 'GBP') {
                Decimal rate = getGbpRateFor(recordCcy);   // helper, see below
                awardInRecordCcy = (awardAmount * rate).setScale(2, RoundingMode.HALF_UP);
            }

            claim.Award_Amount__c     = awardInRecordCcy;   // multi-currency field (display)
            claim.Award_Amount_GBP__c = awardAmount;        // true GBP value
            claim.DWP_Payment_Date__c = dwpPaymentDate;
            update claim;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            AuraHandledException ex = new AuraHandledException('Error saving award amount: ' + e.getMessage());
            ex.setMessage('Error saving award amount: ' + e.getMessage());
            throw ex;
        }
    }

    @AuraEnabled(cacheable=true)
    public static Boolean isMandateChargeable(Id claimId) {
        if (claimId == null) {
            return false;
        }

        // Query the mandate ID from the claim
        Basic__c claim = [
            SELECT Id, GoCardless_Mandate_Id__c
            FROM Basic__c
            WHERE Id = :claimId
            LIMIT 1
        ];

        // If no mandate ID exists, it's definitely not chargeable
        if (String.isEmpty(claim.GoCardless_Mandate_Id__c)) {
            return false;
        }

        // Instantiate the service and check the mandate
        GocardlessApiService service = new GocardlessApiService(claim);
        return service.isMandateChargeable(claim.GoCardless_Mandate_Id__c);
    }


    @AuraEnabled
    public static Map<String, Object> getMandateStatus(Id claimId) {
        Map<String, Object> result = new Map<String, Object>();

        if (claimId == null) {
            result.put('isActive', false);
            result.put('status', 'Not set up');
            result.put('message', 'Needs: confirmed bank details + Direct Debit terms read to the client.');
            result.put('reference', null);
            result.put('createdAt', null);
            result.put('customerId', null);
            result.put('bankAccountId', null);
            result.put('mandateId', null);
            return result;
        }

        Basic__c claim = [
            SELECT Id, GoCardless_Mandate_Id__c, GoCardless_Customer_Id__c, GoCardless_Bank_Account_Id__c, CreatedDate
            FROM Basic__c
            WHERE Id = :claimId
            LIMIT 1
        ];

        // Defaults
        result.put('customerId', claim.GoCardless_Customer_Id__c);
        result.put('bankAccountId', claim.GoCardless_Bank_Account_Id__c);
        result.put('mandateId', claim.GoCardless_Mandate_Id__c);

        if (String.isEmpty(claim.GoCardless_Mandate_Id__c)) {
            result.put('isActive', false);
            result.put('status', 'Not set up');
            result.put('message', 'Needs: confirmed bank details + Direct Debit terms read to the client.');
            result.put('reference', null);
            result.put('createdAt', null);
            return result;
        }

        // Call GoCardless to get full mandate details
        GocardlessApiService service = new GocardlessApiService(claim);
        GocardlessApiService.MandateDetails details = service.getMandateDetails(claim.GoCardless_Mandate_Id__c);

        if (details.isSuccess && details.mandateData != null) {
            String status = (String) details.mandateData.get('status');
            String reference = (String) details.mandateData.get('reference');
            String createdAt = (String) details.mandateData.get('created_at');

            Boolean isActive = new Set<String>{
                'pending_customer_approval',
                'pending_submission',
                'submitted',
                'active'
            }.contains(status);

            result.put('isActive', isActive);
            result.put('status', isActive ? 'Active' : status);
            result.put('message', isActive ? null : 'Mandate status: ' + status);
            result.put('reference', reference);
            result.put('createdAt', createdAt);

        } else {
            result.put('isActive', false);
            result.put('status', 'Error');
            result.put('message', 'Could not retrieve mandate details: ' + details.errorMessage);
            result.put('reference', null);
            result.put('createdAt', null);
        }

        return result;
    }


    @AuraEnabled
    public static String setupMandate(Id claimId) {
        if (claimId == null) {
            AuraHandledException ex = new AuraHandledException('Claim ID is required.');
            ex.setMessage('Claim ID is required.');
            throw ex;
        }

        Basic__c claim = [
            SELECT Id, First_Name__c, Last_Name__c, Email__c, Contact__c, 
                   Claimant_address1__c, Claimant_address2__c, Claimant_City__c, 
                   Eircode__c, Current_Address_Abroad_Country_Name__c, 
                   Current_Address_Abroad__CountryCode__s, Current_Address_Abroad_Country__c, 
                   Current_Address_Abroad_State_Name__c, Bank_IBAN__c, Bank_BIC__c, 
                   BSB_Number__c, GoCardless_Customer_Id__c, GoCardless_Bank_Account_Id__c, 
                   GoCardless_Mandate_Id__c, CurrencyIsoCode, Bank_Account__c, 
                   Bank_Sort_Code__c, Name
            FROM Basic__c
            WHERE Id = :claimId
            LIMIT 1
        ];

        GocardlessApiService service = new GocardlessApiService(claim);
        GocardlessApiService.MandateResult result = service.createMandateDirectly();

        if (!result.isSuccess) {
            AuraHandledException ex = new AuraHandledException(result.errorMessage);
            ex.setMessage(result.errorMessage);
            throw ex;
        }

        return result.mandateId;
    }


    public class MandateWrapper {
        @AuraEnabled public Id claimId { get; set; }
        @AuraEnabled public Decimal awardAmount { get; set; }
        @AuraEnabled public Decimal feeAmount { get; set; }
        @AuraEnabled public Integer installments { get; set; }
        @AuraEnabled public Date firstChargeDate { get; set; }
        @AuraEnabled public Decimal installmentAmount { get; set; }
        @AuraEnabled public Date dwpPaymentDate { get; set; }
    }

    private static Decimal getGbpRateFor(String recordCcy) {
        if (recordCcy == 'GBP') return 1.0;

        List<Daily_Exchange_Rate__c> latest = [
            SELECT GBP_to_EUR__c, GBP_to_AUD__c
            FROM Daily_Exchange_Rate__c
            ORDER BY Rate_Date__c DESC
            LIMIT 1
        ];
        
        if (latest.isEmpty()) {
            AuraHandledException ex = new AuraHandledException('No Daily Exchange Rate record found.');
            ex.setMessage('No Daily Exchange Rate record found.');
            throw ex;
        }
        
        Decimal rate = recordCcy == 'EUR' ? 
                        latest[0].GBP_to_EUR__c
                        : recordCcy == 'AUD' ? 
                            latest[0].GBP_to_AUD__c
                            : null;
                            
        if (rate == null || rate == 0) {
            AuraHandledException ex = new AuraHandledException('No GBP → ' + recordCcy + ' rate available.');
            ex.setMessage('No GBP → ' + recordCcy + ' rate available.');
            throw ex;
        }
        
        return rate;
    }
}
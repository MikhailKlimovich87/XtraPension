public class GocardlessApiService {

    // ==================================================================
    //  STATE
    // ==================================================================

    public Basic__c claim;

    public GocardlessApiService(Basic__c currentClaim) {
        this.claim = currentClaim;
    }

    public GocardlessApiService() {}


    // ==================================================================
    //  CONSTANTS — error message prefixes
    // ==================================================================

    private static final String ERROR_BILLING_REQUEST  = 'Failed to create billing request: ';
    private static final String ERROR_INIT_FLOW        = 'Failed to initialize billing request flow: ';
    private static final String ERROR_POLLING          = 'Failed to poll mandate status: ';
    private static final String ERROR_FULFIL           = 'Failed to fulfil action: ';
    private static final String ERROR_PAYMENT          = 'Failed to create payment: ';
    private static final String ERROR_GENERAL          = 'Error in GoCardless process: ';
    private static final String ERROR_MANDATE          = 'Failed to create or retrieve mandate: ';
    private static final String ERROR_BANK_ACCOUNT     = 'Failed to create customer bank account: ';
    private static final String ERROR_CUSTOMER         = 'Failed to create customer: ';
    private static final String ERROR_REFUND           = 'Failed to create refund: ';


    // ==================================================================
    //  CONSTANTS — API endpoints
    // ==================================================================

    private static final String PAYMENTS               = 'payments';
    private static final String MANDATES               = 'mandates';
    private static final String CUSTOMERS              = 'customers';
    private static final String CUSTOMER_BANK_ACCOUNTS = 'customer_bank_accounts';
    private static final String REFUNDS                = 'refunds';


    // ==================================================================
    //  CONSTANTS — currency
    // ==================================================================

    private static final String DEFAULT_CURRENCY = 'GBP';

    private static final Set<String> ZERO_DECIMAL_CURRENCIES =
        new Set<String>{ 'JPY', 'KRW', 'VND', 'CLP', 'ISK' };

    private static final Set<String> THREE_DECIMAL_CURRENCIES =
        new Set<String>{ 'KWD', 'BHD', 'OMR', 'JOD', 'TND' };


    // ==================================================================
    //  MANDATE — orchestration
    // ==================================================================

    public MandateResult createMandateDirectly() {
        try {
            // ---------- Step 1: Customer ----------
            String customerId = claim.GoCardless_Customer_Id__c;

            if (String.isEmpty(customerId)) {
                customerId = findExistingCustomerId();
                if (String.isEmpty(customerId)) {
                    customerId = createCustomer(); // Callout 1
                }

                if (String.isEmpty(customerId)) {
                    return new MandateResult(false, null, 'Failed to create customer');
                }
                claim.GoCardless_Customer_Id__c = customerId;
            }

            // ---------- Step 2: Bank account ----------
            String bankAccountId = claim.GoCardless_Bank_Account_Id__c;

            if (String.isEmpty(bankAccountId)) {
                bankAccountId = createCustomerBankAccount(customerId); // Callout 2

                if (String.isEmpty(bankAccountId)) {
                    return new MandateResult(false, null, 'Failed to create customer bank account');
                }
                claim.GoCardless_Bank_Account_Id__c = bankAccountId;
            }

            // ---------- Step 3: Mandate ----------
            String mandateId = claim.GoCardless_Mandate_Id__c;

            if (String.isEmpty(mandateId)) {
                mandateId = createMandateWithBankAccount(customerId, bankAccountId); // Callout 3

                if (String.isEmpty(mandateId)) {
                    return new MandateResult(false, null, 'Failed to create mandate');
                }
                claim.GoCardless_Mandate_Id__c = mandateId;
            }

            // ---------- Step 4: COMMIT ALL DML AT THE END ----------
            update claim;

            return new MandateResult(true, mandateId, null);

        } catch (Exception ex) {
            System.debug(ERROR_GENERAL + ex.getMessage());
            return new MandateResult(false, null, ERROR_GENERAL + ex.getMessage());
        }
    }

    // ==================================================================
    //  MANDATE — API calls
    // ==================================================================

    private String findExistingCustomerId() {
        if (claim == null || claim.Id == null || !claim.isSet('Contact__c') || !claim.isSet('Email__c')) {
            return null;
        }
        List<Basic__c> others = [
            SELECT GoCardless_Customer_Id__c
            FROM Basic__c
            WHERE Id != :claim.Id
              AND GoCardless_Customer_Id__c != null
              AND ((Contact__c != null AND Contact__c = :claim.Contact__c)
                   OR (Email__c != null AND Email__c = :claim.Email__c))
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return others.isEmpty() ? null : others[0].GoCardless_Customer_Id__c;
    }


    // ==================================================================
    //  CONFLICT / DUPLICATE RESOURCE HANDLING
    // ==================================================================

    private static String conflictingResourceId(GocardlessApiHandler.GocardlessAPIResponseWrapper response) {
        if (response == null
            || String.isBlank(response.responseBody)
            || (response.statusCode != 409 && response.statusCode != 422)) {
            return null;
        }

        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(response.responseBody);
            if (body == null) return null;

            // Some errors put the payload at the top level, some under 'error'.
            Map<String, Object> error = body.containsKey('error')
                ? (Map<String, Object>) body.get('error')
                : body;

            // The resource may also be surfaced directly at the top level.
            String directId = firstNonBlank4(
                asString(error.get('resource_id')),
                asString(error.get('id')),
                asString(body.get('resource_id')),
                asString(body.get('id'))
            );
            if (String.isNotBlank(directId)) {
                return directId;
            }

            Object errorsObj = error.get('errors');
            if (errorsObj == null) {
                return null;
            }

            // Apex has no instanceof — cast defensively.
            List<Object> errorsList;
            try {
                errorsList = (List<Object>) errorsObj;
            } catch (Exception castEx) {
                return null;
            }
            if (errorsList == null) {
                return null;
            }

            for (Object item : errorsList) {
                Map<String, Object> detail;
                try {
                    detail = (Map<String, Object>) item;
                } catch (Exception castEx) {
                    continue;
                }
                if (detail == null) continue;

                String reason = asString(detail.get('reason'));

                Boolean isDuplicateReason =
                    reason == null ||
                    reason.contains('exist') ||
                    reason.contains('duplicate') ||
                    reason.contains('conflict');

                if (!isDuplicateReason) {
                    continue;
                }

                Map<String, Object> links;
                try {
                    links = (Map<String, Object>) detail.get('links');
                } catch (Exception castEx) {
                    links = null;
                }

                if (links != null) {
                    String id = firstNonBlank7(
                        asString(links.get('conflicting_resource_id')),
                        asString(links.get('customer_bank_account')),
                        asString(links.get('bank_account')),
                        asString(links.get('customer')),
                        asString(links.get('mandate')),
                        asString(links.get('payment')),
                        asString(links.get('refund'))
                    );
                    if (String.isNotBlank(id)) {
                        return id;
                    }
                }

                // Last resort: id on the error item itself.
                String itemId = firstNonBlank2(
                    asString(detail.get('resource_id')),
                    asString(detail.get('id'))
                );
                if (String.isNotBlank(itemId)) {
                    return itemId;
                }
            }
        } catch (Exception ex) {
            System.debug(ERROR_GENERAL + ex.getMessage());
        }
        return null;
    }


    // ---------- small helpers ----------

    private static String asString(Object o) {
        return o == null ? null : String.valueOf(o);
    }

    // Apex has no varargs, so we provide fixed-arity overloads.

    private static String firstNonBlank2(String a, String b) {
        return firstNonBlankList(new List<String>{ a, b });
    }
    private static String firstNonBlank3(String a, String b, String c) {
        return firstNonBlankList(new List<String>{ a, b, c });
    }
    private static String firstNonBlank4(String a, String b, String c, String d) {
        return firstNonBlankList(new List<String>{ a, b, c, d });
    }
    private static String firstNonBlank7(String a, String b, String c, String d, String e, String f, String g) {
        return firstNonBlankList(new List<String>{ a, b, c, d, e, f, g });
    }
    private static String firstNonBlankList(List<String> values) {
        if (values == null) return null;
        for (String v : values) {
            if (String.isNotBlank(v)) return v;
        }
        return null;
    }

    private static String fingerprint(String value) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(value))).substring(0, 16);
    }


    // ==================================================================
    //  CUSTOMER
    // ==================================================================

    public String createCustomer() {
        try {
            Map<String, Object> requestBody = new Map<String, Object>();
            Map<String, Object> customer    = new Map<String, Object>();

            customer.put('given_name',  claim.First_Name__c);
            customer.put('family_name', claim.Last_Name__c);
            customer.put('email',       claim.Email__c);

            if (claim.Claimant_address1__c != null) {
                customer.put('address_line1', claim.Claimant_address1__c);
            }
            if (claim.Claimant_address2__c != null) {
                customer.put('address_line2', claim.Claimant_address2__c);
            }
            if (claim.Claimant_City__c != null) {
                customer.put('city', claim.Claimant_City__c);
            }
            if (claim.Eircode__c != null) {
                customer.put('postal_code', claim.Eircode__c);
            }
            if (claim.Current_Address_Abroad__CountryCode__s != null ||
                claim.Current_Address_Abroad_Country__c != null) {

                customer.put('country_code',
                    claim.Current_Address_Abroad__CountryCode__s != null
                        ? claim.Current_Address_Abroad__CountryCode__s
                        : claim.Current_Address_Abroad_Country__c);
            }

            Map<String, Object> metadata = new Map<String, Object>();
            metadata.put('salesforce_record_id', claim.Id);
            metadata.put('source',               'Salesforce');
            metadata.put('created_by',           UserInfo.getUserId());

            customer.put('metadata', metadata);
            requestBody.put('customers', customer);

            GocardlessApiHandler.GocardlessAPIResponseWrapper response =
                GocardlessApiHandler.requestGocardlessApi(CUSTOMERS, 'POST', requestBody, true, 'sf-customer-' + claim.Id);

            if (!response.isSuccess) {
                String conflictId = conflictingResourceId(response);
                if (String.isNotBlank(conflictId)) {
                    System.debug('Reusing existing customer from conflict response: ' + conflictId);
                    return conflictId;
                }

                if (response.statusCode == 409 || response.statusCode == 422) {
                    String existing = findExistingCustomerIdByEmail();
                    if (String.isNotBlank(existing)) {
                        System.debug('Reusing existing customer from lookup: ' + existing);
                        return existing;
                    }
                }

                System.debug(ERROR_CUSTOMER + response.errorMessage);
                System.debug('Response body: ' + response.responseBody);
                return null;
            }

            return extractCustomerId(response.responseBody);

        } catch (Exception ex) {
            System.debug(ERROR_GENERAL + ex.getMessage());
            return null;
        }
    }


    private String findExistingCustomerIdByEmail() {
        try {
            if (String.isBlank(claim.Email__c)) return null;

            GocardlessApiHandler.GocardlessAPIResponseWrapper response =
                GocardlessApiHandler.requestGocardlessApi(
                    CUSTOMERS + '?email=' + EncodingUtil.urlEncode(claim.Email__c, 'UTF-8'),
                    'GET', null, true);

            if (!response.isSuccess || String.isBlank(response.responseBody)) {
                return null;
            }

            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(response.responseBody);
            Object listObj = data.get('customers');
            if (listObj == null) return null;

            List<Object> customersList;
            try {
                customersList = (List<Object>) listObj;
            } catch (Exception castEx) {
                return null;
            }
            if (customersList == null || customersList.isEmpty()) return null;

            Map<String, Object> firstCustomer = (Map<String, Object>) customersList[0];
            return asString(firstCustomer.get('id'));

        } catch (Exception ex) {
            System.debug(ERROR_GENERAL + ex.getMessage());
            return null;
        }
    }


    // ==================================================================
    //  CUSTOMER BANK ACCOUNT
    // ==================================================================

    public String createCustomerBankAccount(String customerId) {
        try {
            Map<String, Object> requestBody = new Map<String, Object>();
            Map<String, Object> bankAccount = new Map<String, Object>();

            // ---------- Link to customer ----------
            Map<String, Object> links = new Map<String, Object>();
            links.put('customer', customerId);
            bankAccount.put('links', links);

            // ---------- Country-specific account details ----------
            String countryCode = claim.Current_Address_Abroad__CountryCode__s != null
                ? claim.Current_Address_Abroad__CountryCode__s
                : claim.Current_Address_Abroad_Country__c;

            // Trim inputs up front so retries produce a stable fingerprint.
            String accountNumber = claim.Bank_Account__c == null ? null : claim.Bank_Account__c.trim();
            String bsb           = claim.Bank_Sort_Code__c == null ? null : claim.Bank_Sort_Code__c.trim();
            String iban          = claim.Bank_IBAN__c == null ? null : claim.Bank_IBAN__c.trim();

            if ('DE'.equals(countryCode) || 'FR'.equals(countryCode) ||
                'ES'.equals(countryCode) || 'IT'.equals(countryCode) ||
                'NL'.equals(countryCode) || 'BE'.equals(countryCode) ||
                'AT'.equals(countryCode) || 'CH'.equals(countryCode) ||
                'IE'.equals(countryCode) || 'PT'.equals(countryCode) ||
                'FI'.equals(countryCode) || 'DK'.equals(countryCode) ||
                'SE'.equals(countryCode) || 'NO'.equals(countryCode) ||
                'LU'.equals(countryCode) || 'GR'.equals(countryCode) ||
                'MT'.equals(countryCode) || 'CY'.equals(countryCode) ||
                'SI'.equals(countryCode) || 'SK'.equals(countryCode) ||
                'EE'.equals(countryCode) || 'LV'.equals(countryCode) ||
                'LT'.equals(countryCode) || 'BG'.equals(countryCode) ||
                'HR'.equals(countryCode) || 'CZ'.equals(countryCode) ||
                'HU'.equals(countryCode) || 'PL'.equals(countryCode) ||
                'RO'.equals(countryCode)) {

                // SEPA country — IBAN
                if (String.isNotBlank(iban)) {
                    bankAccount.put('iban', iban);
                } else {
                    throw new IllegalArgumentException('IBAN is required for SEPA countries');
                }

            } else if ('AU'.equals(countryCode)) {

                // Australia — BSB + account number
                if (String.isNotBlank(accountNumber) && String.isNotBlank(bsb)) {
                    String cleanBsb = bsb.replace('-', '').replace(' ', '').trim();

                    bankAccount.put('branch_code',    cleanBsb);
                    bankAccount.put('account_number', accountNumber);
                    bankAccount.put('country_code',   'AU');
                } else {
                    throw new IllegalArgumentException(
                        'BSB and account number required for Australia. ' +
                        'BSB=[' + bsb + '] AccountNumber=[' + accountNumber + ']'
                    );
                }
            } else {
                // Fallback — SEPA with IBAN
                if (String.isNotBlank(iban)) {
                    bankAccount.put('iban', iban);
                } else {
                    throw new IllegalArgumentException('IBAN is required for country: ' + countryCode);
                }
            }

            bankAccount.put('account_holder_name', claim.First_Name__c + ' ' + claim.Last_Name__c);
            requestBody.put('customer_bank_accounts', bankAccount);

            GocardlessApiHandler.GocardlessAPIResponseWrapper response =
                GocardlessApiHandler.requestGocardlessApi(CUSTOMER_BANK_ACCOUNTS, 'POST', requestBody, true,
                    'sf-bank-' + claim.Id + '-' + customerId + '-' + fingerprint(JSON.serialize(bankAccount)));

            if (!response.isSuccess) {
                String conflictId = conflictingResourceId(response);
                if (String.isNotBlank(conflictId)) {
                    System.debug('Reusing existing bank account from conflict response: ' + conflictId);
                    return conflictId;
                }

                if (response.statusCode == 409 || response.statusCode == 422) {
                    String existingId = findExistingBankAccountId(customerId);
                    if (String.isNotBlank(existingId)) {
                        System.debug('Reusing existing bank account from lookup: ' + existingId);
                        return existingId;
                    }
                }

                System.debug(ERROR_BANK_ACCOUNT + response.errorMessage);
                System.debug('Response body: ' + response.responseBody);
                return null;
            }

            return extractBankAccountId(response.responseBody);

        } catch (Exception ex) {
            System.debug(ERROR_GENERAL + ex.getMessage());
            return null;
        }
    }


    private String findExistingBankAccountId(String customerId) {
        try {
            if (String.isBlank(customerId)) return null;

            GocardlessApiHandler.GocardlessAPIResponseWrapper response =
                GocardlessApiHandler.requestGocardlessApi(
                    CUSTOMER_BANK_ACCOUNTS + '?customer=' + customerId,
                    'GET', null, true);

            if (!response.isSuccess || String.isBlank(response.responseBody)) {
                return null;
            }

            Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(response.responseBody);
            Object listObj = data.get('customer_bank_accounts');
            if (listObj == null) return null;

            List<Object> bankAccountsList;
            try {
                bankAccountsList = (List<Object>) listObj;
            } catch (Exception castEx) {
                return null;
            }
            if (bankAccountsList == null || bankAccountsList.isEmpty()) return null;

            String countryCode = claim.Current_Address_Abroad__CountryCode__s != null
                ? claim.Current_Address_Abroad__CountryCode__s
                : claim.Current_Address_Abroad_Country__c;

            String targetAcct = claim.Bank_Account__c == null ? null : claim.Bank_Account__c.trim();
            String targetBsb  = claim.Bank_Sort_Code__c == null
                ? null
                : claim.Bank_Sort_Code__c.replace('-', '').replace(' ', '').trim();
            String targetIban = claim.Bank_IBAN__c == null ? null : claim.Bank_IBAN__c.trim();

            for (Object o : bankAccountsList) {
                Map<String, Object> ba = (Map<String, Object>) o;
                String acct   = asString(ba.get('account_number'));
                String branch = asString(ba.get('branch_code'));
                String iban   = asString(ba.get('iban'));
                String ctry   = asString(ba.get('country_code'));

                if (countryCode != null && ctry != null && !countryCode.equalsIgnoreCase(ctry)) {
                    continue;
                }

                if ('AU'.equalsIgnoreCase(countryCode)) {
                    if (targetAcct != null && targetAcct.equals(acct)
                        && targetBsb != null && targetBsb.equals(branch)) {
                        return asString(ba.get('id'));
                    }
                } else {
                    if (targetIban != null && targetIban.equalsIgnoreCase(iban)) {
                        return asString(ba.get('id'));
                    }
                }
            }
        } catch (Exception ex) {
            System.debug(ERROR_GENERAL + ex.getMessage());
        }
        return null;
    }


    // ==================================================================
    //  MANDATE
    // ==================================================================

    public String createMandateWithBankAccount(String customerId, String bankAccountId) {
        try {
            // ---------- Pick scheme from country ----------
            String scheme;
            String countryCode = claim.Current_Address_Abroad__CountryCode__s != null
                ? claim.Current_Address_Abroad__CountryCode__s
                : claim.Current_Address_Abroad_Country__c;

            if ('IE'.equals(countryCode)) {
                scheme = 'sepa_core';
            } else if ('AU'.equals(countryCode)) {
                scheme = 'becs';
            } else {
                return null;
            }

            // ---------- Build request ----------
            Map<String, Object> requestBody = new Map<String, Object>();
            Map<String, Object> mandate     = new Map<String, Object>();

            Map<String, Object> links = new Map<String, Object>();
            links.put('customer_bank_account', bankAccountId);
            mandate.put('links', links);

            mandate.put('scheme',               scheme);
            mandate.put('authorisation_source', 'paper');

            requestBody.put('mandates', mandate);

            GocardlessApiHandler.GocardlessAPIResponseWrapper response =
                GocardlessApiHandler.requestGocardlessApi(MANDATES, 'POST', requestBody, true, 'sf-mandate-' + claim.Id + '-' + bankAccountId);

            if (!response.isSuccess) {
                String conflictId = conflictingResourceId(response);
                if (String.isNotBlank(conflictId)) {
                    System.debug('Reusing existing mandate from conflict response: ' + conflictId);
                    return conflictId;
                }
                System.debug(ERROR_MANDATE + response.errorMessage);
                System.debug('Response body: ' + response.responseBody);
                return null;
            }

            return extractMandateId(response.responseBody);

        } catch (Exception ex) {
            System.debug(ERROR_GENERAL + ex.getMessage());
            return null;
        }
    }


    // ==================================================================
    //  PAYMENT — charge and lookup
    // ==================================================================

    public PaymentResult chargeDirectDebitPayment(Decimal amount) {
        return chargeDirectDebitPayment(amount, null);
    }


    public PaymentResult chargeDirectDebitPayment(Decimal amount, String idempotencyKey) {
        try {
            // ---------- Validation ----------
            if (String.isEmpty(claim.GoCardless_Mandate_Id__c)) {
                return new PaymentResult(false, null, 'Mandate ID is required');
            }

            if (amount == null || amount <= 0) {
                return new PaymentResult(false, null, 'A positive amount is required');
            }

            if (!isMandateChargeable(claim.GoCardless_Mandate_Id__c)) {
                String errorMsg = 'Mandate ' + claim.GoCardless_Mandate_Id__c +
                    ' is not active. Please ensure the mandate has been fully authorized.';
                System.debug(errorMsg);
                return new PaymentResult(false, null, errorMsg);
            }

            // ---------- Build body ----------
            String ccy = String.isNotBlank(claim.CurrencyIsoCode)
                ? claim.CurrencyIsoCode
                : DEFAULT_CURRENCY;

            Map<String, Object> paymentBody = buildPaymentBody(amount, ccy, claim.Name);

            System.debug('Creating direct debit payment. Body: ' + JSON.serialize(paymentBody));

            // ---------- Call API ----------
            GocardlessApiHandler.GocardlessAPIResponseWrapper response =
                GocardlessApiHandler.requestGocardlessApi(PAYMENTS, 'POST', paymentBody, true, idempotencyKey);

            if (!response.isSuccess) {
                System.debug(ERROR_PAYMENT + response.errorMessage);
                System.debug('Response body: ' + response.responseBody);
                return new PaymentResult(false, null, ERROR_PAYMENT + response.errorMessage);
            }

            String paymentId = extractPaymentId(response.responseBody);

            if (String.isEmpty(paymentId)) {
                return new PaymentResult(false, null, 'Failed to extract payment ID from response');
            }

            return new PaymentResult(true, paymentId, null);

        } catch (Exception ex) {
            System.debug(ERROR_GENERAL + ex.getMessage());
            return new PaymentResult(false, null, ERROR_GENERAL + ex.getMessage());
        }
    }


    private Map<String, Object> buildPaymentBody(Decimal amount, String currencyCode, String reference) {
        Integer amountInMinorUnits = toMinorUnits(amount, currencyCode);

        Map<String, Object> links = new Map<String, Object>();
        links.put('mandate', claim.GoCardless_Mandate_Id__c);

        Map<String, Object> paymentData = new Map<String, Object>();
        paymentData.put('amount',   amountInMinorUnits);
        paymentData.put('currency', String.isNotBlank(currencyCode) ? currencyCode : DEFAULT_CURRENCY);
        paymentData.put('links',    links);

        if (!String.isEmpty(reference)) {
            paymentData.put('reference', reference);
        }

        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('payments', paymentData);

        return requestBody;
    }


    public MandateDetails getMandateDetails(String mandateId) {
        try {
            if (String.isEmpty(mandateId)) {
                return new MandateDetails(false, null, 'Mandate ID is required');
            }

            GocardlessApiHandler.GocardlessAPIResponseWrapper response =
                GocardlessApiHandler.requestGocardlessApi(MANDATES + '/' + mandateId, 'GET', null, true);

            if (!response.isSuccess) {
                System.debug('Failed to get mandate details: ' + response.errorMessage);
                return new MandateDetails(false, null, response.errorMessage);
            }

            Map<String, Object> responseData =
                (Map<String, Object>) JSON.deserializeUntyped(response.responseBody);
            Map<String, Object> mandateData =
                (Map<String, Object>) responseData.get('mandates');

            if (mandateData == null) {
                return new MandateDetails(false, null, 'Mandate not found');
            }

            return new MandateDetails(true, mandateData, null);

        } catch (Exception ex) {
            System.debug('Error getting mandate details: ' + ex.getMessage());
            return new MandateDetails(false, null, ERROR_GENERAL + ex.getMessage());
        }
    }


    public Boolean isMandateChargeable(String mandateId) {
        MandateDetails details = getMandateDetails(mandateId);

        if (!details.isSuccess || details.mandateData == null) {
            return false;
        }

        String status = (String) details.mandateData.get('status');

        return new Set<String>{
            'pending_customer_approval',
            'pending_submission',
            'submitted',
            'active'
        }.contains(status);
    }


    // ==================================================================
    //  REFUND — create and lookup
    // ==================================================================

    public RefundResult createRefund(String  paymentId,
                                     Integer amountToRefund,
                                     Integer totalAmountConfirmation,
                                     String  reference) {
        try {
            if (String.isEmpty(paymentId)) {
                return new RefundResult(false, null, 'Payment ID is required');
            }
            if (amountToRefund == null || amountToRefund <= 0) {
                return new RefundResult(false, null, 'Valid refund amount is required');
            }
            if (totalAmountConfirmation == null || totalAmountConfirmation < amountToRefund) {
                return new RefundResult(false, null, 'Total amount confirmation must be >= refund amount');
            }

            Map<String, Object> refundBody = buildRefundBody(
                paymentId, amountToRefund, totalAmountConfirmation, reference
            );

            System.debug('Creating refund. Body: ' + JSON.serialize(refundBody));

            GocardlessApiHandler.GocardlessAPIResponseWrapper response =
                GocardlessApiHandler.requestGocardlessApi(REFUNDS, 'POST', refundBody, true);

            if (!response.isSuccess) {
                System.debug(ERROR_REFUND + response.errorMessage);
                System.debug('Response body: ' + response.responseBody);
                return new RefundResult(false, null, ERROR_REFUND + response.errorMessage);
            }

            String refundId = extractRefundId(response.responseBody);

            if (String.isEmpty(refundId)) {
                return new RefundResult(false, null, 'Failed to extract refund ID from response');
            }

            return new RefundResult(true, refundId, null);

        } catch (Exception ex) {
            System.debug(ERROR_GENERAL + ex.getMessage());
            return new RefundResult(false, null, ERROR_GENERAL + ex.getMessage());
        }
    }


    public RefundResult createFullRefund(String paymentId, Integer paymentAmount) {
        return createRefund(paymentId, paymentAmount, paymentAmount, null);
    }


    private Map<String, Object> buildRefundBody(String  paymentId,
                                                Integer amount,
                                                Integer totalAmountConfirmation,
                                                String  reference) {
        Map<String, Object> links = new Map<String, Object>();
        links.put('payment', paymentId);

        Map<String, Object> refundData = new Map<String, Object>();
        refundData.put('amount',                    amount);
        refundData.put('total_amount_confirmation', totalAmountConfirmation);
        refundData.put('links',                     links);

        if (!String.isEmpty(reference)) {
            refundData.put('reference', reference);
        }

        Map<String, Object> metadata = new Map<String, Object>();
        metadata.put('salesforce_record_id', claim.Id);
        metadata.put('refunded_by',          UserInfo.getUserId());
        metadata.put('refunded_at',          String.valueOf(System.now()));
        refundData.put('metadata', metadata);

        Map<String, Object> requestBody = new Map<String, Object>();
        requestBody.put('refunds', refundData);

        return requestBody;
    }


    public RefundDetails getRefundDetails(String refundId) {
        try {
            if (String.isEmpty(refundId)) {
                return new RefundDetails(false, null, 'Refund ID is required');
            }

            GocardlessApiHandler.GocardlessAPIResponseWrapper response =
                GocardlessApiHandler.requestGocardlessApi(REFUNDS + '/' + refundId, 'GET', null, true);

            if (!response.isSuccess) {
                return new RefundDetails(false, null, response.errorMessage);
            }

            Map<String, Object> responseData =
                (Map<String, Object>) JSON.deserializeUntyped(response.responseBody);
            Map<String, Object> refundData =
                (Map<String, Object>) responseData.get('refunds');

            if (refundData == null) {
                return new RefundDetails(false, null, 'Refund not found');
            }

            return new RefundDetails(true, refundData, null);

        } catch (Exception ex) {
            return new RefundDetails(false, null, ERROR_GENERAL + ex.getMessage());
        }
    }


    public List<Map<String, Object>> getRefundsForPayment(String paymentId) {
        List<Map<String, Object>> refunds = new List<Map<String, Object>>();

        try {
            if (String.isEmpty(paymentId)) {
                return refunds;
            }

            GocardlessApiHandler.GocardlessAPIResponseWrapper response =
                GocardlessApiHandler.requestGocardlessApi(
                    REFUNDS + '?payment=' + paymentId, 'GET', null, true
                );

            if (!response.isSuccess) {
                return refunds;
            }

            Map<String, Object> responseData =
                (Map<String, Object>) JSON.deserializeUntyped(response.responseBody);
            List<Object> refundsList = (List<Object>) responseData.get('refunds');

            if (refundsList != null) {
                for (Object refund : refundsList) {
                    refunds.add((Map<String, Object>) refund);
                }
            }

            return refunds;

        } catch (Exception ex) {
            return refunds;
        }
    }


    // ==================================================================
    //  CURRENCY HELPERS
    // ==================================================================

    public static Integer toMinorUnits(Decimal amount, String currencyCode) {
        if (amount == null) {
            return 0;
        }

        String ccy = String.isBlank(currencyCode)
            ? DEFAULT_CURRENCY
            : currencyCode.toUpperCase();

        Decimal factor = Decimal.valueOf(Math.pow(10, minorUnitExponent(ccy)));
        Decimal scaled = (amount * factor).setScale(0, System.RoundingMode.HALF_UP);

        return scaled.intValue();
    }


    public static Decimal fromMinorUnits(Integer minorAmount, String currencyCode) {
        if (minorAmount == null) {
            return 0;
        }

        String ccy = String.isBlank(currencyCode)
            ? DEFAULT_CURRENCY
            : currencyCode.toUpperCase();

        Decimal factor = Decimal.valueOf(Math.pow(10, minorUnitExponent(ccy)));

        return Decimal.valueOf(minorAmount)
                      .divide(factor, 2, System.RoundingMode.HALF_UP);
    }

    public static Integer minorUnitExponent(String currencyCode) {
        if (String.isBlank(currencyCode)) {
            return 2;
        }

        String ccy = currencyCode.toUpperCase();

        if (ZERO_DECIMAL_CURRENCIES.contains(ccy))  return 0;
        if (THREE_DECIMAL_CURRENCIES.contains(ccy)) return 3;

        return 2;
    }

    // ==================================================================
    //  EXTRACTION HELPERS
    // ==================================================================

    private String extractCustomerId(String responseBody) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> obj  = (Map<String, Object>) data.get('customers');
        return (String) obj.get('id');
    }

    private String extractBankAccountId(String responseBody) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> obj  = (Map<String, Object>) data.get('customer_bank_accounts');
        return (String) obj.get('id');
    }

    private String extractMandateId(String responseBody) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> obj  = (Map<String, Object>) data.get('mandates');
        return (String) obj.get('id');
    }

    private String extractPaymentId(String responseBody) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> obj  = (Map<String, Object>) data.get('payments');
        return obj == null ? null : (String) obj.get('id');
    }

    private String extractRefundId(String responseBody) {
        Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> obj  = (Map<String, Object>) data.get('refunds');
        return obj == null ? null : (String) obj.get('id');
    }

    // ==================================================================
    //  INNER CLASSES — result wrappers
    // ==================================================================

    public class MandateResult {
        public Boolean isSuccess    { get; set; }
        public String  mandateId    { get; set; }
        public String  errorMessage { get; set; }

        public MandateResult(Boolean isSuccess, String mandateId, String errorMessage) {
            this.isSuccess    = isSuccess;
            this.mandateId    = mandateId;
            this.errorMessage = errorMessage;
        }
    }

    public class MandatePaymentResult {
        public Boolean isSuccess    { get; set; }
        public String  mandateId    { get; set; }
        public String  paymentId    { get; set; }
        public String  errorMessage { get; set; }

        public MandatePaymentResult(Boolean isSuccess, String mandateId, String paymentId, String errorMessage) {
            this.isSuccess    = isSuccess;
            this.mandateId    = mandateId;
            this.paymentId    = paymentId;
            this.errorMessage = errorMessage;
        }
    }

    public class PaymentResult {
        public Boolean isSuccess    { get; set; }
        public String  paymentId    { get; set; }
        public String  errorMessage { get; set; }

        public PaymentResult(Boolean isSuccess, String paymentId, String errorMessage) {
            this.isSuccess    = isSuccess;
            this.paymentId    = paymentId;
            this.errorMessage = errorMessage;
        }
    }

    public class MandateDetails {
        public Boolean             isSuccess    { get; set; }
        public Map<String, Object> mandateData  { get; set; }
        public String              errorMessage { get; set; }

        public MandateDetails(Boolean isSuccess, Map<String, Object> mandateData, String errorMessage) {
            this.isSuccess    = isSuccess;
            this.mandateData  = mandateData;
            this.errorMessage = errorMessage;
        }
    }

    public class RefundResult {
        public Boolean isSuccess    { get; set; }
        public String  refundId     { get; set; }
        public String  errorMessage { get; set; }

        public RefundResult(Boolean isSuccess, String refundId, String errorMessage) {
            this.isSuccess    = isSuccess;
            this.refundId     = refundId;
            this.errorMessage = errorMessage;
        }
    }

    public class RefundDetails {
        public Boolean             isSuccess    { get; set; }
        public Map<String, Object> refundData   { get; set; }
        public String              errorMessage { get; set; }

        public RefundDetails(Boolean isSuccess, Map<String, Object> refundData, String errorMessage) {
            this.isSuccess    = isSuccess;
            this.refundData   = refundData;
            this.errorMessage = errorMessage;
        }
    }
}
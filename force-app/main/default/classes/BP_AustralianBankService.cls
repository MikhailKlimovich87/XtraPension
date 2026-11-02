public with sharing class BP_AustralianBankService {

    // ================================================================
    // SWIFT / BIC
    // ================================================================

    private static final Map<String, String> SWIFT_AU =
        new Map<String, String>{
            'CBA' => 'CTBAAU2S',
            'WBC' => 'WPACAU2S',
            'ANZ' => 'ANZBAU3M',
            'NAB' => 'NATAAU3303M'
        };


    // ================================================================
    // BSB ROW
    // ================================================================

    public class BsbRow {
        public String bsb;
        public String mnemonic;
        public String branch;
        public String address;
        public String suburb;
        public String state;
        public String postcode;
        public String flags;
    }


    // ================================================================
    // RESULT
    // ================================================================

    public class BankInfo {
        public String account;
        public String sortCode;
        public String bic;
        public String bankName;
        public String bankCity;
        public String bankAddress;
        public String bankPostcode;
        public String bankCountry;
        public String valid;
    }


    // ================================================================
    // CACHE
    // ================================================================

    private static Map<String, BsbRow> bsbs;
    private static Map<String, String> owners;


    // ================================================================
    // PUBLIC METHOD
    // ================================================================

    public static BankInfo getBankInfoAU(
        String bsbInput,
        String accountInput
    ) {

        loadDirectory();


        // ------------------------------------------------------------
        // Normalize BSB
        // ------------------------------------------------------------

        String digits =
            normalizeDigits(bsbInput);

        if (digits.length() != 6) {
            throw new BankException(
                'bsb_format: 6 digits'
            );
        }


        // ------------------------------------------------------------
        // Normalize account
        // ------------------------------------------------------------

        String account =
            normalizeDigits(accountInput);

        if (
            account.length() < 4 ||
            account.length() > 10
        ) {
            throw new BankException(
                'account_format: 4 to 10 digits'
            );
        }


        // ------------------------------------------------------------
        // Format BSB
        // ------------------------------------------------------------

        String bsb =
            digits.substring(0, 3) +
            '-' +
            digits.substring(3, 6);


        // ------------------------------------------------------------
        // Find BSB
        // ------------------------------------------------------------

        BsbRow row =
            bsbs.get(bsb);

        if (row == null) {
            throw new BankException(
                'bsb_not_found'
            );
        }


        // ------------------------------------------------------------
        // Resolve merged BSBs
        //
        // Example:
        //
        // 012-003
        //     |
        //     +--> 012-019
        //
        // Also supports chains:
        //
        // 012-003 -> 012-019 -> 012-020
        // ------------------------------------------------------------

        for (
            Integer hop = 0;
            hop < 5;
            hop++
        ) {

            String address =
                row.address == null
                    ? ''
                    : row.address;


            String nextBsb =
                extractMergedBsb(address);


            if (nextBsb == null) {
                break;
            }


            BsbRow next =
                bsbs.get(nextBsb);


            if (next == null) {
                break;
            }


            if (next == row) {
                break;
            }


            row = next;
        }


        // ------------------------------------------------------------
        // Check unresolved merge
        // ------------------------------------------------------------

        String remainingMergedBsb =
            extractMergedBsb(
                row.address == null
                    ? ''
                    : row.address
            );


        if (remainingMergedBsb != null) {

            if (!bsbs.containsKey(remainingMergedBsb)) {

                throw new BankException(
                    'bsb_merged_unresolved'
                );
            }
        }


        // ------------------------------------------------------------
        // Build result
        // ------------------------------------------------------------

        BankInfo result =
            new BankInfo();


        result.account =
            account;


        result.sortCode =
            bsb;


        // ------------------------------------------------------------
        // BIC
        // ------------------------------------------------------------

        if (
            row.mnemonic != null &&
            SWIFT_AU.containsKey(row.mnemonic)
        ) {

            result.bic =
                SWIFT_AU.get(
                    row.mnemonic
                );

        }
        else {

            result.bic = '';
        }


        // ------------------------------------------------------------
        // Bank name
        // ------------------------------------------------------------

        if (
            row.mnemonic != null &&
            owners.containsKey(row.mnemonic)
        ) {

            result.bankName =
                owners.get(
                    row.mnemonic
                );

        }
        else {

            result.bankName =
                row.mnemonic == null
                    ? ''
                    : row.mnemonic;
        }


        // ------------------------------------------------------------
        // City
        // ------------------------------------------------------------

        String suburb =
            row.suburb == null
                ? ''
                : row.suburb;


        String state =
            row.state == null
                ? ''
                : row.state;


        result.bankCity =
            (
                suburb +
                ' ' +
                state
            ).trim();


        // ------------------------------------------------------------
        // Address
        // ------------------------------------------------------------

        result.bankAddress =
            row.address == null
                ? ''
                : row.address;


        // ------------------------------------------------------------
        // Postcode
        //
        // New BSBDirectoryFull may not contain postcode.
        // In that case return empty string.
        // ------------------------------------------------------------

        result.bankPostcode =
            row.postcode == null
                ? ''
                : row.postcode;


        // ------------------------------------------------------------
        // Country
        // ------------------------------------------------------------

        result.bankCountry =
            'AUS';


        // ------------------------------------------------------------
        // Validation
        // ------------------------------------------------------------

        result.valid =
            'NotValidated';


        return result;
    }


    // ================================================================
    // LOAD DIRECTORY
    // ================================================================

    private static void loadDirectory() {

        if (
            bsbs != null &&
            owners != null
        ) {
            return;
        }


        bsbs =
            new Map<String, BsbRow>();


        owners =
            new Map<String, String>();


        // ============================================================
        // BSBKey
        // ============================================================

        List<StaticResource> keyResources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'BSBKey'
            LIMIT 1
        ];


        if (keyResources.isEmpty()) {

            throw new BankException(
                'bsb_key_not_found'
            );
        }


        StaticResource keyResource =
            keyResources[0];


        if (keyResource.Body == null) {

            throw new BankException(
                'bsb_key_empty'
            );
        }


        loadOwnersJson(
            keyResource.Body.toString()
        );


        // ============================================================
        // BSBDirectoryFull
        // ============================================================

        List<StaticResource> directoryResources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = 'BSBDirectoryFull'
            LIMIT 1
        ];


        if (directoryResources.isEmpty()) {

            throw new BankException(
                'bsb_directory_not_found'
            );
        }


        StaticResource directoryResource =
            directoryResources[0];


        if (directoryResource.Body == null) {

            throw new BankException(
                'bsb_directory_empty'
            );
        }


        loadDirectoryJson(
            directoryResource.Body.toString()
        );
    }


    // ================================================================
    // LOAD BSB KEY
    //
    // Expected structure:
    //
    // [
    //   {
    //     "BSB Owner": "ABA",
    //     "Owner Name": "Auswide...",
    //     "BSB Prefix": 645
    //   }
    // ]
    //
    // Streaming JSON parser.
    // ================================================================

    private static void loadOwnersJson(
        String jsonText
    ) {

        if (String.isBlank(jsonText)) {

            throw new BankException(
                'bsb_key_empty'
            );
        }


        JSONParser parser;


        try {

            parser =
                JSON.createParser(
                    jsonText
                );

        }
        catch (Exception e) {

            throw new BankException(
                'bsb_key_json_invalid'
            );
        }


        Integer rowsLoaded = 0;


        while (
            parser.nextToken() != null
        ) {

            if (
                parser.getCurrentToken() !=
                JSONToken.START_OBJECT
            ) {
                continue;
            }


            String mnemonic;
            String ownerName;


            while (
                parser.nextToken() != null
            ) {

                JSONToken token =
                    parser.getCurrentToken();


                if (
                    token ==
                    JSONToken.END_OBJECT
                ) {
                    break;
                }


                if (
                    token !=
                    JSONToken.FIELD_NAME
                ) {
                    continue;
                }


                String fieldName =
                    parser.getText();


                parser.nextToken();


                if (
                    fieldName ==
                    'BSB Owner'
                ) {

                    mnemonic =
                        readJsonValue(parser);
                }


                else if (
                    fieldName ==
                    'Owner Name'
                ) {

                    ownerName =
                        readJsonValue(parser);
                }


                else {

                    skipJsonValue(parser);
                }
            }


            if (
                !String.isBlank(mnemonic) &&
                !String.isBlank(ownerName)
            ) {

                mnemonic =
                    removeBom(
                        mnemonic
                    ).trim();


                ownerName =
                    ownerName.trim();


                if (
                    !owners.containsKey(
                        mnemonic
                    )
                ) {

                    owners.put(
                        mnemonic,
                        ownerName
                    );


                    rowsLoaded++;
                }
            }
        }


        if (rowsLoaded == 0) {

            throw new BankException(
                'bsb_key_empty'
            );
        }
    }


    // ================================================================
    // LOAD BSB DIRECTORY
    //
    // Expected structure:
    //
    // [
    //   {
    //     "bsb": "012-003",
    //     "mnemonic": "ANZ",
    //     "branch": "Merged",
    //     "address": "Refer to BSB 012-019",
    //     "suburb": "Sydney",
    //     "state": "NSW"
    //   },
    //   ...
    // ]
    //
    // IMPORTANT:
    // Does NOT use JSON.deserializeUntyped().
    //
    // One JSON object is processed at a time.
    // ================================================================

    private static void loadDirectoryJson(
        String jsonText
    ) {

        if (String.isBlank(jsonText)) {

            throw new BankException(
                'bsb_directory_empty'
            );
        }


        JSONParser parser;


        try {

            parser =
                JSON.createParser(
                    jsonText
                );

        }
        catch (Exception e) {

            throw new BankException(
                'bsb_directory_json_invalid'
            );
        }


        Integer rowsLoaded = 0;


        while (
            parser.nextToken() != null
        ) {

            if (
                parser.getCurrentToken() !=
                JSONToken.START_OBJECT
            ) {
                continue;
            }


            BsbRow row =
                parseBsbObject(parser);


            if (
                row == null ||
                String.isBlank(row.bsb)
            ) {
                continue;
            }


            String normalizedBsb =
                normalizeBsb(
                    row.bsb
                );


            if (
                String.isBlank(normalizedBsb)
            ) {
                continue;
            }


            row.bsb =
                normalizedBsb;


            // --------------------------------------------------------
            // Normalize mnemonic
            // --------------------------------------------------------

            if (
                row.mnemonic != null
            ) {

                row.mnemonic =
                    removeBom(
                        row.mnemonic
                    ).trim();
            }


            // --------------------------------------------------------
            // Put into map
            // --------------------------------------------------------

            bsbs.put(
                normalizedBsb,
                row
            );


            rowsLoaded++;
        }


        if (rowsLoaded == 0) {

            throw new BankException(
                'bsb_directory_empty'
            );
        }
    }


    // ================================================================
    // PARSE ONE BSB OBJECT
    //
    // Supports both:
    //
    // lowercase:
    //   bsb
    //   mnemonic
    //   branch
    //   address
    //   suburb
    //   state
    //   postcode
    //   flags
    //
    // and old uppercase format.
    // ================================================================

    private static BsbRow parseBsbObject(
        JSONParser parser
    ) {

        BsbRow row =
            new BsbRow();


        while (
            parser.nextToken() != null
        ) {

            JSONToken token =
                parser.getCurrentToken();


            if (
                token ==
                JSONToken.END_OBJECT
            ) {
                break;
            }


            if (
                token !=
                JSONToken.FIELD_NAME
            ) {
                continue;
            }


            String fieldName =
                parser.getText();


            parser.nextToken();


            // --------------------------------------------------------
            // BSB
            // --------------------------------------------------------

            if (
                fieldName == 'bsb' ||
                fieldName == 'BSB'
            ) {

                row.bsb =
                    readJsonValue(parser);

                continue;
            }


            // --------------------------------------------------------
            // Mnemonic
            // --------------------------------------------------------

            if (
                fieldName == 'mnemonic' ||
                fieldName == 'Mnemonic'
            ) {

                row.mnemonic =
                    readJsonValue(parser);

                continue;
            }


            // --------------------------------------------------------
            // Branch
            // --------------------------------------------------------

            if (
                fieldName == 'branch' ||
                fieldName == 'Branch'
            ) {

                row.branch =
                    readJsonValue(parser);

                continue;
            }


            // --------------------------------------------------------
            // Address
            // --------------------------------------------------------

            if (
                fieldName == 'address' ||
                fieldName == 'Address'
            ) {

                row.address =
                    readJsonValue(parser);

                continue;
            }


            // --------------------------------------------------------
            // Suburb
            // --------------------------------------------------------

            if (
                fieldName == 'suburb' ||
                fieldName == 'Suburb'
            ) {

                row.suburb =
                    readJsonValue(parser);

                continue;
            }


            // --------------------------------------------------------
            // State
            // --------------------------------------------------------

            if (
                fieldName == 'state' ||
                fieldName == 'State'
            ) {

                row.state =
                    readJsonValue(parser);

                continue;
            }


            // --------------------------------------------------------
            // Postcode
            // --------------------------------------------------------

            if (
                fieldName == 'postcode' ||
                fieldName == 'Postcode'
            ) {

                row.postcode =
                    readJsonValue(parser);

                continue;
            }


            // --------------------------------------------------------
            // Flags
            // --------------------------------------------------------

            if (
                fieldName == 'flags' ||
                fieldName == 'Flags'
            ) {

                row.flags =
                    readJsonValue(parser);

                continue;
            }


            // --------------------------------------------------------
            // Unknown field
            // --------------------------------------------------------

            skipJsonValue(parser);
        }


        return row;
    }


    // ================================================================
    // READ JSON VALUE AS STRING
    // ================================================================

    private static String readJsonValue(
        JSONParser parser
    ) {

        JSONToken token =
            parser.getCurrentToken();


        if (
            token ==
            JSONToken.VALUE_NULL
        ) {

            return '';
        }


        if (
            token ==
            JSONToken.VALUE_STRING
        ) {

            return parser.getText();
        }


        if (
            token ==
            JSONToken.VALUE_NUMBER_INT ||
            token ==
            JSONToken.VALUE_NUMBER_FLOAT ||
            token ==
            JSONToken.VALUE_TRUE ||
            token ==
            JSONToken.VALUE_FALSE
        ) {

            return parser.getText();
        }


        // ------------------------------------------------------------
        // Unexpected object / array
        // ------------------------------------------------------------

        if (
            token ==
            JSONToken.START_OBJECT ||
            token ==
            JSONToken.START_ARRAY
        ) {

            parser.skipChildren();

            return '';
        }


        return '';
    }


    // ================================================================
    // SKIP JSON VALUE
    // ================================================================

    private static void skipJsonValue(
        JSONParser parser
    ) {

        JSONToken token =
            parser.getCurrentToken();


        if (
            token ==
            JSONToken.START_OBJECT ||
            token ==
            JSONToken.START_ARRAY
        ) {

            parser.skipChildren();
        }
    }


    // ================================================================
    // NORMALIZE BSB
    //
    // Accepts:
    //
    // 062-000
    // 062000
    // "062 000"
    // ================================================================

    private static String normalizeBsb(
        String value
    ) {

        String digits =
            normalizeDigits(value);


        if (
            digits.length() != 6
        ) {

            return '';
        }


        return
            digits.substring(0, 3) +
            '-' +
            digits.substring(3, 6);
    }


    // ================================================================
    // NORMALIZE DIGITS
    //
    // Removes:
    //
    // - hyphens
    // - spaces
    // - brackets
    // - letters
    // - other non-digit characters
    // ================================================================

    private static String normalizeDigits(
        String value
    ) {

        if (
            String.isBlank(value)
        ) {

            return '';
        }


        String result = '';


        for (
            Integer i = 0;
            i < value.length();
            i++
        ) {

            String c =
                value.substring(
                    i,
                    i + 1
                );


            if (
                c >= '0' &&
                c <= '9'
            ) {

                result += c;
            }
        }


        return result;
    }


    // ================================================================
    // EXTRACT MERGED BSB
    //
    // Supported examples:
    //
    // Refer to BSB 123456
    // Refer to BSB 123-456
    // Merging with 123456
    // Merging with BSB 123456
    // ================================================================

    private static String extractMergedBsb(
        String address
    ) {

        if (
            String.isBlank(address)
        ) {

            return null;
        }


        String lower =
            address.toLowerCase();


        Integer start =
            lower.indexOf(
                'refer to bsb'
            );


        if (
            start < 0
        ) {

            start =
                lower.indexOf(
                    'merging with'
                );
        }


        if (
            start < 0
        ) {

            return null;
        }


        String text =
            address.substring(
                start
            );


        String digits = '';


        for (
            Integer i = 0;
            i < text.length();
            i++
        ) {

            String c =
                text.substring(
                    i,
                    i + 1
                );


            if (
                c >= '0' &&
                c <= '9'
            ) {

                digits += c;


                if (
                    digits.length() == 6
                ) {

                    break;
                }
            }
        }


        if (
            digits.length() != 6
        ) {

            return null;
        }


        return
            digits.substring(0, 3) +
            '-' +
            digits.substring(3, 6);
    }


    // ================================================================
    // REMOVE BOM
    // ================================================================

    private static String removeBom(
        String value
    ) {

        if (
            value == null
        ) {

            return null;
        }


        if (
            value.length() > 0 &&
            value.substring(0, 1) ==
                '\uFEFF'
        ) {

            return value.substring(1);
        }


        return value;
    }

    public class BankException extends Exception {}
}
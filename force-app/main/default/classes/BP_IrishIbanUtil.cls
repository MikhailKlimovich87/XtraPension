public class BP_IrishIbanUtil {



    /**
     * Removes spaces, dashes, dots and other non-alphanumeric characters
     * and converts the value to uppercase.
     */
    public static String normaliseIban(String input) {
        if (String.isBlank(input)) {
            return '';
        }

        return input
            .replaceAll('[^A-Za-z0-9]', '')
            .toUpperCase();
    }

    /**
     * Calculates Mod-97 for a potentially very large number.
     * We process the number digit by digit to avoid integer overflow.
     */
    private static Integer mod97(String digits) {
        Integer remainder = 0;

        for (Integer i = 0; i < digits.length(); i++) {
            String ch = digits.substring(i, i + 1);
            Integer digit = Integer.valueOf(ch);

            remainder = Math.mod(remainder * 10 + digit, 97);
        }

        return remainder;
    }

    /**
     * Converts IBAN letters to numbers:
     * A = 10 ... Z = 35
     */
    private static String lettersToDigits(String value) {
        String result = '';

        for (Integer i = 0; i < value.length(); i++) {
            String ch = value.substring(i, i + 1);

            if (ch >= 'A' && ch <= 'Z') {
                Integer code = ch.charAt(0) - 'A'.charAt(0) + 10;

                result += String.valueOf(code);
            } else {
                result += ch;
            }
        }

        return result;
    }

    /**
     * Validates IBAN checksum using ISO 13616 Mod-97.
     */
    public static Boolean ibanChecksumOk(String iban) {
        if (String.isBlank(iban) || iban.length() < 4) {
            return false;
        }

        // Move first 4 characters to the end.
        String moved = iban.substring(4) + iban.substring(0, 4);

        // Convert letters A-Z to 10-35.
        String digits = lettersToDigits(moved);

        return mod97(digits) == 1;
    }

    /**
     * Parses and validates an Irish IBAN.
     *
     * Expected format:
     * IE + 2 check digits + 4 letters bank code + 14 digits
     *
     * Example:
     * IE29AIBK93115212345678
     */
    public static IrishIbanResult parseIrishIban(String input) {
        String iban = normaliseIban(input);

        // Irish IBAN = exactly 22 characters:
        // IE + 2 digits + 4 letters + 14 digits
        Pattern pattern = Pattern.compile(
            '^IE\\d{2}[A-Z]{4}\\d{14}$'
        );

        if (!pattern.matcher(iban).matches()) {
            throw new IbanException(
                'iban_format: Irish IBANs are 22 characters'
            );
        }

        if (!ibanChecksumOk(iban)) {
            throw new IbanException('iban_checksum');
        }

        return new IrishIbanResult(
            iban,
            iban.substring(4, 8),   // bankCode
            iban.substring(8, 14),  // sortCode
            iban.substring(14, 22)  // account
        );
    }

        public class IrishIbanResult {
        public String iban;
        public String bankCode;
        public String sortCode;
        public String account;

        public IrishIbanResult(
            String iban,
            String bankCode,
            String sortCode,
            String account
        ) {
            this.iban = iban;
            this.bankCode = bankCode;
            this.sortCode = sortCode;
            this.account = account;
        }
    }

    public class IbanException extends Exception {}
}
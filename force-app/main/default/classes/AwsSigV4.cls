public class AwsSigV4 {

    public static Blob hmacSHA256(Blob key, String data) {
        return Crypto.generateMac('HmacSHA256', Blob.valueOf(data), key);
    }

    public static String sign(
        String secretKey,
        String dateData,
        String region,
        String service,
        String stringToSign
    ) {
        Blob kDate = hmacSHA256(
            Blob.valueOf('AWS4' + secretKey), dateData
        );
        Blob kRegion = hmacSHA256(kDate, region);
        Blob kService = hmacSHA256(kRegion, service);
        Blob kSigning = hmacSHA256(kService, 'aws4_request');

        Blob signature = hmacSHA256(kSigning, stringToSign);
        return EncodingUtil.convertToHex(signature);
    }
}
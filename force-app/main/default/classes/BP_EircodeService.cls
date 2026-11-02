public with sharing class BP_EircodeService {

    private static final String EIRCODE_REGEX ='\\b[A-Z0-9]{3}\\s?[A-Z0-9]{4}\\b';
    private static final String PLACE_KEY = GooglePlacesConfig__c.getInstance().Place_API_key__c;



    public static EircodeResult getEircodeIE(
        String bankName,
        String branchName,
        String bankCity
    ) {
        
        HttpRequest req = new HttpRequest();
        req.setEndpoint(
            'https://places.googleapis.com/v1/places:searchText'
        );
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('X-Goog-Api-Key', PLACE_KEY);
        req.setHeader(
            'X-Goog-FieldMask',
            'places.displayName,places.formattedAddress,' +
            'places.postalAddress,places.types'
        );
        req.setTimeout(10000);

        String textQuery =
            String.valueOf(bankName) + ' ' +
            String.valueOf(branchName) + ', Ireland';

        Map<String, Object> body = new Map<String, Object>{
            'textQuery' => textQuery,
            'regionCode' => 'IE',
            'languageCode' => 'en',
            'maxResultCount' => 3
        };

        req.setBody(JSON.serialize(body));

        HttpResponse res;

        try {
            res = new Http().send(req);
        } catch (Exception e) {
            throw new EircodeException(
                'Google Places request failed: ' + e.getMessage()
            );
        }

        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new EircodeException(
                'Google Places returned HTTP ' +
                res.getStatusCode() + ': ' + res.getBody()
            );
        }

        Map<String, Object> json =
            (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

        List<Object> places = json.containsKey('places')
            ? (List<Object>) json.get('places')
            : new List<Object>();

        String town = bankCity == null
            ? ''
            : bankCity.toLowerCase().replaceAll('\\s+\\d+$', '').trim();

        Map<String, Object> pick;

        for (Object item : places) {
            Map<String, Object> place =
                (Map<String, Object>) item;

            List<Object> types = place.containsKey('types')
                ? (List<Object>) place.get('types')
                : new List<Object>();

            Boolean isBank = false;

            for (Object type : types) {
                String t = String.valueOf(type);

                if (t == 'bank' || t == 'finance' || t == 'atm') {
                    isBank = true;
                    break;
                }
            }

            if (!isBank) {
                continue;
            }

            String formattedAddress =
                place.containsKey('formattedAddress')
                    ? String.valueOf(place.get('formattedAddress'))
                    : '';

            if (
                String.isBlank(town) ||
                formattedAddress.toLowerCase().contains(town)
            ) {
                pick = place;
                break;
            }
        }

        EircodeResult result = new EircodeResult();
        result.eircode = '';
        result.address = '';
        result.name = '';

        if (pick != null) {
            Map<String, Object> postalAddress =
                pick.containsKey('postalAddress')
                    ? (Map<String, Object>) pick.get('postalAddress')
                    : new Map<String, Object>();

            String postalCode =
                postalAddress.containsKey('postalCode')
                    ? String.valueOf(postalAddress.get('postalCode'))
                    : '';

            String eircode = postalCode.toUpperCase();

            if (String.isBlank(eircode)) {
                String formattedAddress =
                    pick.containsKey('formattedAddress')
                        ? String.valueOf(pick.get('formattedAddress'))
                        : '';

                Pattern pattern = Pattern.compile(EIRCODE_REGEX);
                Matcher matcher = pattern.matcher(
                    formattedAddress.toUpperCase()
                );

                if (matcher.find()) {
                    eircode = matcher.group(0);
                }
            }

            if (Pattern.matches(EIRCODE_REGEX, eircode)) {
                result.eircode = eircode;
            }

            if (postalAddress.containsKey('addressLines')) {
                List<Object> lines =
                    (List<Object>) postalAddress.get('addressLines');

                List<String> addressLines = new List<String>();

                for (Object line : lines) {
                    addressLines.add(String.valueOf(line));
                }

                result.address = String.join(addressLines, ', ');
            }

            if (pick.containsKey('displayName')) {
                Map<String, Object> displayName =
                    (Map<String, Object>) pick.get('displayName');

                if (displayName.containsKey('text')) {
                    result.name =
                        String.valueOf(displayName.get('text'));
                }
            }
        }

        return result;
    }

    public class EircodeResult {
        public String eircode;
        public String address;
        public String name;
        public Datetime at;
    }

    public class EircodeException extends Exception {}
}
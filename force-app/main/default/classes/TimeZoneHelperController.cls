public class TimeZoneHelperController {

    // Constants
    private static final String NOMINATIM_ENDPOINT = 'https://nominatim.openstreetmap.org/search';
    private static final String TIMEZONEDB_ENDPOINT = 'https://api.timezonedb.com/v2.1/get-time-zone';
    private static final String TIMEZONEDB_API_KEY = '3VFZ3AP5TM0V';
    private static final Integer SUCCESS_STATUS = 200;
    private static final String GET_METHOD = 'GET';
    private static final String JSON_FORMAT = 'json';

    @AuraEnabled(cacheable=true)
    public static TimeZoneWrapper getTimeZones(Id applicationId) {
        if(applicationId == null) {
            throw new TimeZoneException('Application ID is required');
        }

        Application__c application = getApplicationById(applicationId);
        if(application == null) {
            throw new TimeZoneException('Application not found');
        }

        String address = formatAddress(application.Full_Current_Address_Abroad__c);
        GeolocationWrapper geolocation = fetchGeolocation(address);
        
        TimeZoneWrapper timeZone = fetchTimeZone(geolocation.lat, geolocation.lon);
        updateApplicationWithTimeZoneData(application.Id, timeZone);
        return timeZone;
    }

    /**
     * Retrieves Application record by ID
     */
    private static Application__c getApplicationById(Id applicationId) {
        List<Application__c> apps = [
            SELECT
                Name,
                Full_Current_Address_Abroad__c
            FROM Application__c
            WHERE Id = :applicationId
            LIMIT 1
        ];
        return apps.isEmpty() ? null : apps[0];
    }

    /**
     * Formats address for API request
     */
    private static String formatAddress(String address) {
        if(address == null) {
            throw new TimeZoneException('Address is required');
        }
        return EncodingUtil.urlEncode(
            address.replace('<br>', ', '),
            'UTF-8'
        );
    }

    /**
     * Fetches geolocation data from Nominatim API
     */
    private static GeolocationWrapper fetchGeolocation(String encodedAddress) {
        String endpoint = NOMINATIM_ENDPOINT + '?q=' + encodedAddress + '&format=' + JSON_FORMAT + '&limit=1';
        HttpRequest request = buildHttpRequest(endpoint, GET_METHOD);
        
        HttpResponse response = sendHttpRequest(request);
        
        if(response.getStatusCode() != SUCCESS_STATUS) {
            throw new TimeZoneException('Failed to get geolocation data. Status: ' + response.getStatusCode() + ' Error: ' + response.getBody());
        }

        List<GeolocationWrapper> geolocations = (List<GeolocationWrapper>) JSON.deserialize(
            response.getBody(), 
            List<GeolocationWrapper>.class
        );

        if(geolocations.isEmpty()) {
            throw new TimeZoneException('No geolocation data found for the given address');
        }

        return geolocations[0];
    }

    /**
     * Fetches timezone data from TimezoneDB API
     */
    private static TimeZoneWrapper fetchTimeZone(String latitude, String longitude) {
        String endpoint = buildTimeZoneEndpoint(latitude, longitude);
        HttpRequest request = buildHttpRequest(endpoint, GET_METHOD);
        
        HttpResponse response = sendHttpRequest(request);
        
        if(response.getStatusCode() != SUCCESS_STATUS) {
            throw new TimeZoneException('Failed to get time zone data. Status: ' + response.getStatusCode() + ' Error: ' + response.getBody());
        }
        TimeZoneWrapper timeZone = (TimeZoneWrapper) JSON.deserialize(
            response.getBody(), 
            TimeZoneWrapper.class
        );

        if(timeZone == null) {
            throw new TimeZoneException('No time zone data found for the given coordinates');
        }
        return timeZone;
    }

    /**
     * Builds TimezoneDB endpoint URL
     */
    private static String buildTimeZoneEndpoint(String latitude, String longitude) {
        return TIMEZONEDB_ENDPOINT 
            + '?key=' + TIMEZONEDB_API_KEY 
            + '&format=' + JSON_FORMAT 
            + '&by=position' 
            + '&lat=' + latitude 
            + '&lng=' + longitude;
    }

    /**
     * Builds HTTP request with common settings
     */
    private static HttpRequest buildHttpRequest(String endpoint, String method) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod(method);
        request.setTimeout(10000);
        return request;
    }

    /**
     * Sends HTTP request and returns response
     */
    private static HttpResponse sendHttpRequest(HttpRequest request) {
        try {
            Http http = new Http();
            return http.send(request);
        } catch(Exception e) {
            throw new TimeZoneException('HTTP request failed: ' + e.getMessage());
        }
    }

    /**
     * Updates Application record with timezone response data
     */
    private static void updateApplicationWithTimeZoneData(Id applicationId, TimeZoneWrapper timeZone) {
        try {
            update new Application__c(Id = applicationId, Heroku_Request__c = JSON.serialize(timeZone));
        } catch(DmlException e) {
            throw new TimeZoneException('Failed to update Application record: ' + e.getMessage());
        }
    }

    // Wrapper Classes
    public class GeolocationWrapper {
        public String lat;
        public String lon;
    }

    public class TimeZoneWrapper {
        public String countryCode;
        public String countryName;
        public String regionName;
        public String cityName;
        public String zoneName;
        public String abbreviation;
        public String gmtOffset;
        public String dst;
        public String nextAbbreviation;
    }

    public class TimeZoneException extends Exception {}
}
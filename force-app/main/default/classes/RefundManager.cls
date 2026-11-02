@RestResource(UrlMapping='/api/v2/*')
global class RefundManager {
    @HttpPost
    global static void createRefund() {
        RestRequest request = RestContext.request;
        String reqURI = request.requestURI;
        RestResponse response = RestContext.response;
        String requestBody = request.requestBody.toString();
        Map<String, Object> result = new Map<String, Object>();
        String stripeId = request.params.get('id');
        switch on reqURI {
            when '/api/v2/form/create-refund' {
                RequestDataWrapper requestData = (RequestDataWrapper) JSON.deserialize(requestBody, RequestDataWrapper.class);
                response.responseBody = Blob.valueOf(JSON.serialize(RefundManagerHandler.createRefund(requestData)));
            }
        }
    }

    public class RequestDataWrapper {
        public String id;
        public Decimal amount;
        public String email;
        public String phone;
        public String name;
        public AddressDataWrapper address;
        public String firstName;
        public String lastName;
        public String packageName;
        public String paymentMethod;
        public String customer;
        public Boolean tax;
        public String latest_charge;
        public String howDidYouHearAboutUs;
        public String agent;
        public String isEuropeanCountry;
        public String currencyCode;
    }

    public class AddressDataWrapper {
        //line1 == street
        //line2 - optional
        public String line1;
        public String line2;
        public String postal_code;
        public String state;
        public String city;
        public String country;
    }
}
public class DocumentParserOutputAsJSON {
    // The authentication key (API Key).
    // Get your own by registering at https://app.pdf.co/documentation/api
    static String API_KEY = 'mihail.klimovich@outlook.com_Nv2gTgkxZi8701v1ThPH59MMwQ2rK9Ct93zUVHylFihg5C67Yr0aVa7TMI7N5Ris';
    
    // Direct URL of source PDF file.
    static string SourceFileUrl = 'https://tinderpoint--devsuccess.sandbox.lightning.force.com/lightning/r/Application__c/a01RR00000FnMZvYAN/view';
    // PDF document password. Leave empty for unprotected documents.
    static string Password = '';

    @TestVisible
    String jsonOutput;
    public void parseDocumentAsJSON()
    {        
        try
        {
            // Create HTTP client instance
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            // Set API Key
            request.setHeader('x-api-key', API_KEY);
            
            Boolean async = false;
            String inline = 'true';
            String profiles = '';
            Boolean encrypt = false;
            Boolean storeResult = false;
            // Prepare requests params as JSON
            // See documentation: https://apidocs.pdf.co
            // Create JSON payload
            JSONGenerator gen = JSON.createGenerator(true);
            gen.writeStartObject();
            gen.writeStringField('url', SourceFileUrl);
            gen.writeStringField('outputFormat', 'JSON');
            gen.writeStringField('templateId', '1');
            gen.writeBooleanField('async', async);
            gen.writeBooleanField('encrypt', encrypt);
            gen.writeStringField('inline', inline);
            gen.writeStringField('password', password);
            gen.writeStringField('profiles', profiles);
            gen.writeBooleanField('storeResult', false);
            
            gen.writeEndObject();
            // Convert dictionary of params to JSON
            String jsonPayload = gen.getAsString();
        
            // URL of 'PDF Edit' endpoint
            string url = 'https://api.pdf.co/v1/pdf/documentparser';
            request.setEndpoint(url);            
            request.setHeader('Content-Type', 'application/json;charset=UTF-8');
            request.setMethod('POST');
            request.setBody(jsonPayload);
            // Execute request
            HttpResponse response =  http.send(request);                
            
            if(response.getStatusCode() == 200)
            {
                // Parse JSON response
                Map<String, Object> json = (Map<String, Object>)JSON.deserializeUntyped(response.getBody());
                if ((Boolean)json.get('error') == false)
                {
                    jsonOutput = response.getBody();
                    System.debug('JSON '+ jsonOutput);    
                }
            }
            else
            {
                System.debug('Error Response ' + response.getBody());
                System.Debug(' Status ' + response.getStatus());
                System.Debug(' Status Code' + response.getStatusCode());
                System.Debug(' Response String' + response.toString());
            }
        }
        catch (Exception ex)
        {
            String errorBody = 'Message: ' + ex.getMessage() + ' -- Cause: ' + ex.getCause() + ' -- Stacktrace: ' + ex.getStackTraceString();
            System.Debug(errorBody);
        }
    }
}
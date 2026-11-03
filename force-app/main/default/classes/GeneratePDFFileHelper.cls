public class GeneratePDFFileHelper {

    public static void generatePDF() {
        List<Receipt__c> receipts = [
            SELECT
    	        Name,
    	        Paid_Date__c,
    	        Payment_Method__c,
    	        Client_Info__c,
    	        Total__c,
    	        Product_Name__c,
    	        Amount__c,
    	        Tax_EU__c
            FROM Receipt__c
            WHERE Id ='a0YRR000005AXHZ2A4'
        ];
        Receipt__c receipt = receipts[0];
        String receiptData =
            '<html style="overflow-y: hidden;">' +
                '<head>'+
                    '<title>RECEIPT</title>'+
                    '<style type="text/css">'+
                        '* {'+
                            'margin: 0px;'+
                            'padding: 0px;'+
                            'box-sizing: border-box;'+
                            'text-decoration: none;'+
                        '}'+
                        '.main-container {'+
                            'font-family: Arial, Helvetica, sans-serif;'+
                            'color: #000000;'+
                            'font-size: 0.875rem;'+
                            'line-height: 1.4;'+
                            'font-variant: normal;'+
                            'font-style: normal;'+
                            'max-width: 1000px;'+
                            'overflow: hidden;'+
                            'scroll-behavior: smooth;'+
                            'height: auto;'+
                            'width: 100%;'+
                            'background-color: #fff;'+
                            'display: grid;'+
                            'margin: 0 auto;'+
                            'padding: 0.2rem;'+
                        '}'+
                        '.logo {'+
                            'vertical-align: text-top;'+
                            'float: right;'+
                        '}'+
                        '.logo img {'+
                            'max-width: 100%;'+
                            'width: 360px;'+
                            'height: auto;'+
                        '}'+
                        '.recept-container {'+
                            'display: block;'+
                            'width: 100%;'+
                        '}'+
                        '.recept-container-top {'+
                            'vertical-align: text-top;'+
                            'float: left;'+
                            'font-size: 1.25rem;'+
                        '}'+
                        '.recept-container-bottom {'+
                            'display: none;'+
                            'font-size: 1.25rem;'+
                        '}'+
                        '.receipt-details-container {'+
                            'display: block;'+
                            'margin-top: 5rem;'+
                        '}'+
                        '.receipt-details-left {'+
                            'float: left;'+
                            'text-align: left;'+
                        '}'+
                        '.receipt-details-right {'+
                            'text-align: right;'+
                            'float: right;'+
                        '}'+
                        '.title-container {'+
                            'margin-bottom: 1rem;'+
                            'margin-top: 5rem;'+
                            'font-size: 1.5rem;'+
                        '}'+
                        '.table-container {'+
                            'text-align: center;'+
                            'width: 100%;'+
                            'border-collapse: collapse;'+
                        '}'+
                        '.table-container thead th {'+
                            'border: solid 2px black;'+
                            'padding: 5px;'+
                        '}'+
                        '.table-container tbody td {'+
                            'padding: 5px;'+
                        '}'+
                        '.text-center {'+
                            'text-align: center;'+
                        '}'+
                        '.text-left {'+
                            'text-align: left;'+
                        '}'+
                        '.footer-container {'+
                            'padding: 1rem;'+
                            'text-align: center;'+
                            'width: 100%;'+
                            'border: 1px solid #ccc;'+
                            'margin-top: 3rem;'+
                        '}'+
                        '.company-container {'+
                            'margin-top: 1rem;'+
                        '}'+
                        '.red-data{'+
                            'color: red;'+
                            'weight: bold;'+
                            'text-decoration: underline;'+
                        '}'+
                        '.extra-data{'+
                            'margin-top: 3rem;'+
                        '}'+
      '@media (max-width: 768px) {'+
        'body,'+
        'html {'+
          'max-width: 100%;'+
        '}'+
        '.recept-container-top {'+
          'display: none;'+
        '}'+
        '.logo {'+
          'display: block;'+
          'width: 100%;'+
        '}'+
        '.logo img {'+
          'width: 100%;'+
          'height: auto;'+
        '}'+
        '.recept-container-bottom {'+
          'display: block;'+
          'width: 100%;'+
          'text-align: center;'+
        '}'+
        '.receipt-details-container {'+
          'margin-top: 1rem;'+
        '}'+
        '.receipt-details-right,'+
        '.receipt-details-left {'+
          'float: none;'+
          'display: block;'+
          'width: 100%;'+
          'text-align: left;'+
          'margin-bottom: 10px;'+
        '}'+
        '.title-container {'+
          'margin-top: 1rem;'+
        '}'+
        '.table-container {'+
          'font-size: 0.5rem;'+
        '}'+
        '.extra-data{'+
           'margin-top: 1rem; '+
        '}'+
        '.footer-container {'+
          'margin-top:1rem;'+
        '}'+
      '}'+
    '</style>'+
                '</head>'+
                '<body>'+
                    '<div class="main-container">'+
                        '<div class="recept-container">'+
                            '<div class="recept-container-top">'+
                                '<strong>'+
                                    'RECEIPT'+
                                '</strong>'+
                            '</div>'+
                            // '<div class="logo">'+
                            //     '<img'+
                            //         'alt="Logo"'+
                            //         'src=\'https://tinderpoint--devsuccess.sandbox.file.force.com/file-asset-public/Logo?oid=00D7Y0000001WLx\''+
                            //         'title="Logo"'+
                            //     '/>'+
                            // '</div>'+
                            '<div class="recept-container-bottom">'+
                                '<strong>'+
                                    'RECEIPT'+
                                '</strong>'+
                            '</div>'+
                        '</div>'+
                        '<div class="receipt-details-container">'+
                            '<div class="receipt-details-left">'+
                                '<p>'+
                                    '<b>Receipt No:</b>'+
                                    '&nbsp;' +
                                '</p>'+
                            '</div>'+
                        '</div>'+
                    '</div>'+
                '</body>'+
            '</html>';
        //Blob htmlBlob = Blob.valueOf(receiptData);
        try {
            Blob pdfBlob = Blob.toPdf(receiptData);
            ContentVersion cv = new ContentVersion();
            cv.Title = 'NewDocument.pdf';
            cv.PathOnClient = 'NewDocument.pdf';
            cv.VersionData = pdfBlob; // Assign the Blob directly
            cv.IsMajorVersion = true;
            cv.FirstPublishLocationId = 'a0YRR000005AXHZ2A4';
            insert cv;
        } catch (Exception ex) {
            System.debug(ex.getLineNumber() + '-' + ex.getMessage());
        }
    }
}
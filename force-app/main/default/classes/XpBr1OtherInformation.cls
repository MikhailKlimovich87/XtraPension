/**
 * What the PDF service did with the "Other information" box of the IPCBR1 (page 13), kept on the claim for the Docs card.
 *
 * The box holds 52 lines. Since 16/11/2026 the PDF service (claim.xtrapension.com /pdf/fill-pdf) no longer cuts a longer
 * text: it shrinks the font down to 8pt and, past that, the text continues on sheets added at the end of the form. Its
 * answer says what it did: "otherInformation": { "lines", "fontSize", "continuationSheets", "cut" }.
 *
 * save() never stops the documents: an answer without the report (an older PDF service, a test mock) changes nothing,
 * and a failure here is only written to the debug log. The two fields are not pack source fields (BP_ClaimPackGuard
 * goes by prefix), so writing them neither regenerates the pack nor is blocked while the claim is out for eSignature.
 */
public without sharing class XpBr1OtherInformation {

    public class Report {
        public Integer lines;
        public Decimal fontSize;
        public Integer continuationSheets;
        public Boolean cut;
        public String error;
    }

    private class Answer {
        public Report otherInformation;
    }

    // null when the answer carries no report
    public static Report read(String body) {
        if (String.isBlank(body) || !body.contains('"otherInformation"')) {
            return null;
        }
        try {
            return ((Answer) JSON.deserialize(body, Answer.class)).otherInformation;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'BR1 Other information report not read: ' + ex.getMessage());
            return null;
        }
    }

    // Call it after the last callout of the transaction (it may write to the claim)
    public static void save(Id claimId, String body) {
        Report report = read(body);
        if (claimId == null || report == null) {
            return;
        }
        try {
            Decimal sheets = report.continuationSheets == null ? 0 : report.continuationSheets;
            Boolean cut = report.cut == true;
            List<Basic__c> claims = [SELECT Name, BR1_Other_Info_Sheets__c, BR1_Other_Info_Cut__c FROM Basic__c WHERE Id = :claimId];
            if (claims.isEmpty() || (claims[0].BR1_Other_Info_Sheets__c == sheets && claims[0].BR1_Other_Info_Cut__c == cut)) {
                return;
            }
            Database.SaveResult saved = Database.update(
                new Basic__c(Id = claimId, BR1_Other_Info_Sheets__c = sheets, BR1_Other_Info_Cut__c = cut), false);
            if (!saved.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'BR1 Other information not saved on ' + claimId + ': ' + saved.getErrors());
            }
            // Only when the PDF service could not make the sheets: part of the text is not on the form
            if (cut) {
                Database.insert(new Application_Form_Error__c(
                    Error_Body__c = ('IPCBR1 of claim ' + claims[0].Name + ' (' + claimId + '): the "Other information" text did not fit page 13 and '
                        + 'the continuation sheets could not be made, so the end of the text is NOT on the form. '
                        + (String.isBlank(report.error) ? '' : 'PDF service: ' + report.error)).abbreviate(2000),
                    Error_Date__c = Date.today()
                ), false);
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'BR1 Other information not saved on ' + claimId + ': ' + ex.getMessage());
        }
    }
}
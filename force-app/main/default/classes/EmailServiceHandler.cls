global class EmailServiceHandler implements Messaging.InboundEmailHandler {

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
        String subject = email.subject.replaceAll('(\\s+)', '');
        /*if (subject.contains('APPROVED') || subject.contains('UNKNOWN') || subject.contains('REJECT')) {
            XtraPensionHMRCReplyService hmrcReplyService = new XtraPensionHMRCReplyService();
            return hmrcReplyService.handleInboundEmail(email, envelope);
        } else if(subject.contains('C2') || subject.contains('C3') || subject.contains('INFO')|| subject.contains('NONINO') || subject.contains('REJECTED') || subject.contains('APPEAL')) {
            HMRCReplyDataEmailService replyDataEmailService = new HMRCReplyDataEmailService();
            return replyDataEmailService.handleInboundEmail(email, envelope);
        } else {*/
            XtraPensionEmailServiceHandler printingHouseReply = new XtraPensionEmailServiceHandler();
            return printingHouseReply.handleInboundEmail(email, envelope);
        //}
    }
}
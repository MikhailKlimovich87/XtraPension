import { LightningElement, api } from 'lwc';
import sendEmail from '@salesforce/apex/DocumentsContentController.sendHMRCResult';

export default class EditResultMessageModal extends LightningElement {
    @api recordId;
    @api templateBody;
    @api subject;
    @api isPaidAppPayment;
    showSpinner = false;

    allowedFormats = [
        'font',
        'size',
        'bold',
        'italic',
        'underline',
        'strike',
        'list',
        'indent',
        'align',
        'link',
        'image',
        'clean',
        'table',
        'header',
        'color',
        'background',
        'code',
        'code-block',
        'script',
        'blockquote',
        'direction',
    ];

    closeAction() {
        this.dispatchEvent(new CustomEvent('hideresultpopup'));
    }

    handleChange(event) {
        this.templateBody = event.target.value;
    }

    handleChangeSubject(event) {
        this.subject = event.target.value;
    }

    handleExit() {
        this.dispatchEvent(
            new CustomEvent('hidecofirmationpopup')
        );
    }

    handleOpenEditPage() {
        this.isPaidAppPayment = !this.isPaidAppPayment;
    }

    handleSend() {
        this.showSpinner = !this.showSpinner;
        this.dispatchEvent(
            new CustomEvent('sendresultemail', {detail:{
                template: this.templateBody,
                subject: this.subject
            }}
        ));
    }
}
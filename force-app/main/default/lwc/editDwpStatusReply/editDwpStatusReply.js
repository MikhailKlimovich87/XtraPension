import { LightningElement,api } from 'lwc';

export default class EditDwpStatusReply extends LightningElement {
    @api recordId;
    @api choseValue;
    dateToday;
    @api salutation;
    @api firstName;
    @api secondName;
    @api appName;
    @api hmrcRef;
    @api nino;
    @api dateOfBitrh;
    @api emailAddress;
    @api fullAddress;

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

    connectedCallback() {
        var newDate = new Date();
        this.dateToday       = newDate.toLocaleDateString('en-GB');
    }

    handleChange(event) {
        this.choseValue = event.target.value;
    }
    closeAction() {
        this.dispatchEvent(new CustomEvent('hidepopup'));
    }
    handleCreatePDF() {
        this.dispatchEvent(new CustomEvent(
            'generatepdf', {
                detail: this.choseValue
           })
        );
        this.closeAction();
    }
}
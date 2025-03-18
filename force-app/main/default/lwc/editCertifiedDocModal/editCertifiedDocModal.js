import { LightningElement, api } from 'lwc';

export default class EditCertifiedDocModal extends LightningElement {
    @api recordId;
    dateToday;
    @api fullAddress;
    @api hmrcRef;
    @api choseValue;

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

    handleChange(event) {
        this.choseValue = event.target.value;
    }
}
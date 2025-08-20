import { LightningElement,api } from 'lwc';

export default class EditUpdateLetterModal extends LightningElement {
    dateToday;
    @api fullAddress;
    @api firstName;
    @api secondName;
    @api choseValue;
    @api nino;
    @api dateOfBitrh;
    @api phone;
    @api formerName;
    @api homeAddress;
    currDate;

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
        this.dateToday = newDate.toLocaleDateString('en-GB');
        this.currDate  = new Date().toISOString();
    }

    closeAction() {
        this.dispatchEvent(new CustomEvent('hidepopup'));
    }

    handleChange(event) {
        this.choseValue = event.target.value;
    }

    saveCurrDate(event) {
        this.currDate = event.target.value;
    }

    handleCreatePDF() {
        this.dispatchEvent(new CustomEvent(
            'generatepdf', {
                detail: {
                    body:this.choseValue,
                    dateData: this.currDate
                }
           })
        );
        this.closeAction();
    }
}
import { LightningElement, api } from 'lwc';

export default class EditReplyModal extends LightningElement {
    @api recordId;
    @api choseValue;
    dateToday;
    @api firstName;
    @api secondName;
    @api appName;
    @api hmrcRef;
    @api nino;
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

    handleChange(event) {
        this.choseValue = event.target.value;
    }
    closeAction() {
        this.dispatchEvent(new CustomEvent('hidepopup'));
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
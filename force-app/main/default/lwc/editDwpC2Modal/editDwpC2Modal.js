import { LightningElement, api } from 'lwc';

export default class EditDwpC2Modal extends LightningElement {
    @api recordId;
    dateToday;
    @api fullAddress;
    @api nino;
    @api choseValue;
    @api firstName;
    @api secondName;
    @api abroadEmpl;
    @api lastEmpl;
    choseValue;

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
        console.log('this.abroadEmpl === ', this.abroadEmpl);
        console.log('this.lastEmpl === ', this.lastEmpl);

    }

    closeAction() {
        this.dispatchEvent(new CustomEvent('hidepopup'));
    }

    handleChange(event) {
        this.choseValue = event.target.value;
    }

    handleCreatePDF() {
        this.dispatchEvent(new CustomEvent(
            'generatepdf', {
                detail: this.choseValue
           })
        );
        this.closeAction();
    }

    @api
    get isEmployedEmployer() {
        if (this.lastEmpl.Type_Of_UK_Employment__c == 'Employed') return true;
        else return false;
    }
}
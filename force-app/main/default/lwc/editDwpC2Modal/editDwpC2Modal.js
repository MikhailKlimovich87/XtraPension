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
    topData;
    bottomData;

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
        let splitResult = this.choseValue.split("SPLIT=============");
        if(splitResult.length == 2){
            this.topData = splitResult[0];
            this.bottomData = splitResult[1];
        };
    }

    closeAction() {
        this.dispatchEvent(new CustomEvent('hidepopup'));
    }

    handleChangeTopArea(event) {
        this.topData = event.target.value;
    }
    handleChangeBottomArea(event) {
        this.bottomData = event.target.value;
    }

    handleCreatePDF() {
        this.dispatchEvent(new CustomEvent(
            'generatepdf', {
                detail: this.topData + 'SPLIT=============' + this.bottomData
           })
        );
        this.closeAction();
    }

    @api
    get isEmployedEmployer() {
        if (this.lastEmpl.Type_Of_UK_Employment__c == 'Employed') return true;
        else return false;
    }

    @api
    get isExistUKEmployers() {
        console.log('this.lastEmpl === ', this.lastEmpl);
        
        return this.lastEmpl == undefined ? false : true;
    }

    @api
    get isExistAfterUKEmployers() {
        console.log('this.abroadEmpl === ', this.abroadEmpl);

        return this.abroadEmpl == undefined ? false : true;
    }
}
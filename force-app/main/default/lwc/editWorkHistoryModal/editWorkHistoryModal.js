import { LightningElement, api } from 'lwc';

export default class EditWorkHistoryModal extends LightningElement {
    @api recordId;
    @api abroadEmpl;
    @api lastEmpl;


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
        this.dispatchEvent(new CustomEvent('hidepopup'));
    }

    handleCreatePDF() {
        this.dispatchEvent(new CustomEvent(
            'generatepdf', {
                detail: {}
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
        return this.lastEmpl == undefined ? false : true;
    }

    @api
    get isExistAfterUKEmployers() {
        return this.abroadEmpl == undefined ? false : true;
    }

}
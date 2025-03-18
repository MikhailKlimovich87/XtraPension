import { LightningElement, api, track } from 'lwc';

export default class EditDocumentModal extends LightningElement {
    @track startLetterData;
    @track sectionA_Data;
    @track sectionB_Data;
    @track sectionC_Data;
    @track endLetterData;
    @track extraInfoData;
    @api app;
    @api previousAddresses;
    @api lastUkEmployer;
    @api abroadEmployers;
    @api latestAddress;
    @track newPreviousAddressData = [];
    @track newEmployerCheckboxData = [];
    @api showSpinner;
    currDate;

    connectedCallback() {
        this.startLetterData = this.app.Freeform_Text_Line1__c;
        this.sectionA_Data   = this.app.Freeform_Text_Line2__c;
        this.sectionB_Data   = this.app.Freeform_Text_Line3__c;
        this.sectionC_Data   = this.app.Freeform_Text_Line4__c;
        this.extraInfoData   = this.app.Freeform_Text_Line5__c;
        if(!this.app.Custom_Letter_Date__c) {
            let newDate = new Date();
            this.currDate       = newDate.toISOString();
        } else this.currDate = this.app.Custom_Letter_Date__c;

    }
    closeAction() {
        this.dispatchEvent(new CustomEvent('hidepopup'));
    }
    @api
    handleChangeCustomLetter() {
        var selectedEvent = new CustomEvent('changecustomletter', {
            detail: {
                freeformTextLine1: this.startLetterData,
                freeformTextLine2: this.sectionA_Data,
                freeformTextLine3: this.sectionB_Data,
                freeformTextLine4: this.endLetterData,
                freeformTextLine5: this.extraInfoData,
                newPreviousAddressData: this.newPreviousAddressData,
                newEmployerCheckboxData: this.newEmployerCheckboxData,
                currentDate: this.currDate
            }
        });
        this.dispatchEvent(selectedEvent);
    }
    saveStartLetter(event) {
        this.startLetterData = event.target.value;
    }
    saveSectionAData(event) {
        this.sectionA_Data = event.target.value;
    }
    saveSectionBData(event) {
        this.sectionB_Data = event.target.value;
    }
    saveEndLetter(event) {
        this.endLetterData = event.target.value;
    }
    saveExtraInfo(event) {
        this.extraInfoData = event.target.value;
    }
    saveCurrDate(event) {
        this.currDate = event.target.value;
    }

    handleIncludeAddress(event) {
        let findElement = this.newPreviousAddressData.find(element => element.fieldName === event.target.fieldName);
        if (findElement) {
            findElement.value = event.target.checked
        } else {
            let changedValues = {
                fieldName : event.target.fieldName,
                value : event.target.checked
            };
            this.newPreviousAddressData.push(changedValues);
        }
    }
    handleNewCheckboxValue(event) {
        let findElement = this.newEmployerCheckboxData.find(element => element.fieldName === event.target.fieldName);
        if (findElement) {
            findElement.value = event.target.checked
        } else {
            let changedValues = {
                fieldName : event.target.fieldName,
                value : event.target.checked,
                employerId : event.target.employerId
            };
            this.newEmployerCheckboxData.push(changedValues);
        }
    }

    @api
    get isExistUKEmployers() {
        return this.lastUkEmployer == undefined ? false : true;
    }

    @api
    get isExistAfterUKEmployers() {
        return this.abroadEmployers == undefined ? false : true;
    }
    
    @api
    get isExistSecondLastUKAddress() {
        return (this.app.Previous_UK_Address_Start_Date_2__c == null || this.app.Previous_UK_Address_End_Date_2__c == null) ? false : true;
    }

    @api
    get isExistThirdLastUKAddress() {
        return (this.app.Previous_UK_Address_Start_Date_3__c == null || this.app.Previous_UK_Address_End_Date_3__c == null) ? false : true;
    }

    @api
    get lastUKAddressStartDate1() {
        return Date.parse(this.app.Previous_UK_Address_Start_Date_1__c);
    }

    @api
    get lastUKAddressEndDate1() {
        return Date.parse(this.app.Previous_UK_Address_End_Date_1__c);
    }

    @api
    get lastUKAddressStartDate2() {
        return Date.parse(this.app.Previous_UK_Address_Start_Date_2__c);
    }

    @api
    get lastUKAddressEndDate2() {
        return Date.parse(this.app.Previous_UK_Address_End_Date_2__c);
    }

    @api
    get lastUKAddressStartDate3() {
        return Date.parse(this.app.Previous_UK_Address_Start_Date_3__c);
    }

    @api
    get lastUKAddressEndDate3() {
        return Date.parse(this.app.Previous_UK_Address_End_Date_3__c);
    }
}
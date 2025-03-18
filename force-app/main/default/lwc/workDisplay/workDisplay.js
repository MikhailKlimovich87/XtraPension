import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from "lightning/navigation";
import getApplication from '@salesforce/apex/WorkDisplayController.getApplication';

export default class WorkDisplay extends NavigationMixin(LightningElement) {
    @api recordId;
    @track lastUKEmployer;
    @track lastUKEmployerId;
    @track lastUKEmployerType;
    @track firstAfterUKEmployerId;
    @track abroadStartDate;
    @track lastUKWorkDate;
    @track typeOfAbroadUKEmployer;
    @track error;

    connectedCallback(){
        this.handleGetApp();
    }
    @api async handleGetApp() {
        await getApplication({
            recordId : this.recordId
        })
            .then(result => {
                if (result.status == 'Success') {
                    this.lastUKEmployer         = result.lastUKEmployerId;
                    this.lastUKEmployerType     = result.lastUKEmployerId.Type_Of_UK_Employment__c;
                    this.lastUKEmployerId       = result.lastUKEmployerId.Id;
                    this.firstAfterUKEmployerId = result.firstAfterUKEmployerId;
                    this.abroadStartDate        = result.abroadStartDate;
                    this.lastUKWorkDate         = result.lastUKWorkLastDate;
                    this.typeOfAbroadUKEmployer = result.typeOfAfterUKEmployer;
                } else if (result.status == 'Error') {
                    this.error  = result.errorMessage;
                }
                this.error  = undefined;
            }).catch(error => {
                this.error = error;
                console.log('error = ', this.error);
        });
    }
    handleShowAllData() {
        this[ NavigationMixin.Navigate ]( {
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'Application__c',
                relationshipApiName: 'Employers__r',
                actionName: 'view'
            }
        });
    }
    @api
    get isEmployedUkEmployers() {
        return this.lastUKEmployerType == 'Employed' ? true : false;
    }

    @api
    get isEmptyAfterUkEmployers() {
        return this.firstAfterUKEmployerId ? true : false;
    }

    @api
    get urlPath() {
        if(this.lastUKEmployer.Employers_Address__PostalCode__s) {
            var replacePostalCode = this.lastUKEmployer.Employers_Address__PostalCode__s.replace(/\s+/g,"+");
            return 'https://www.google.com/search?q=' + replacePostalCode + '+'+
                    this.lastUKEmployer.Employer_Name__c.replace(/\s+/g,"+");
        } else return null;
    }

    @api
    get isEmployedTypeAfterUkEmployers() {
        return this.typeOfAbroadUKEmployer == 'Employed' ? true : false;
    }

    @api
    get typeOfUkEmployer() {
        // return this.lastUKEmployer.Type_Of_UK_Employment__c;
        return null;
    }
}
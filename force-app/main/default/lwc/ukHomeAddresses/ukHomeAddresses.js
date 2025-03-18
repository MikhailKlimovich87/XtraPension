import { LightningElement, api, track } from 'lwc';
import getUKAddresses from '@salesforce/apex/WorkDisplayController.getUKAddresses';
import ModalAddressEditForm from 'c/modalAddressEditForm';
//import getCountries from '@salesforce/apex/WorkDisplayController.getCountries';
//import getCountryStates from '@salesforce/apex/WorkDisplayController.getCountryStates';

export default class UkHomeAddresses extends LightningElement {
    @api recordId;
    @track result;
    @track error;
    ukAddresses;
    abroadAddress;
    countries;
    states;

    connectedCallback(){
        // this.getAllCountries();
        // this.getStates();
        this.handleGetAddresses();
    }

    // @api async getAllCountries() {
    //     await getCountries()
    //         .then(result => {
    //             if (result) {
    //                 this.countries = result;
    //             } else if (!result) {
    //                 this.error  = result.errorMessage;
    //                 console.log('error: ', this.error);
    //             }
    //         }).catch(error => {
    //             this.error = error;
    //             console.log('error: ', this.error);
    //     });
    // }

    // @api async getStates() {
    //     await getCountryStates()
    //         .then(result => {
    //             if (result) {
    //                 console.log('states == ', result);
    //                 this.states = result;
    //             } else if (!result) {
    //                 this.error  = result.errorMessage;
    //                 console.log('error: ', this.error);
    //             }
    //         }).catch(error => {
    //             this.error = error;
    //             console.log('error: ', this.error);
    //     });
    // }
    @api async handleGetAddresses() {
        await getUKAddresses({
            recordId : this.recordId
        })
            .then(result => {
                if (result.status == 'Success') {
                    console.log('result ', result);
                    this.result = result.ukAddresses;
                    this.ukAddresses = result.ukAddresses;
                    this.abroadAddress = result.abroadAddress;
                } else if (result.status == 'Error') {
                    this.error  = result.errorMessage;
                }
                this.error  = undefined;
            }).catch(error => {
                this.error = error;
        });
    }
    handleOpenModal() {
        console.log('Test');
    }

    async showPopup() {
        await ModalAddressEditForm.open({
            size: "small",
            address: this.abroadAddress,
            currentCountries: this.countries
        });

    }
}
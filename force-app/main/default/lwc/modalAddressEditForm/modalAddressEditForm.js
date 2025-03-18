import { api,wire } from "lwc";
import LightningModal from "lightning/modal";
import getCountries from '@salesforce/apex/WorkDisplayController.getCountries';

export default class ModalAddressEditForm extends LightningModal  {
    @api address;
    @api currentCountries = [];
    // updatedCountries = [];
    countriesToStates = {};
    applicationDefaultRecordTypeId;

    // get countries() {
    //     let countries = JSON.parse(JSON.stringify(this.currentCountries));

    //     countries.filter(country => country.value != this.address.country);
    //     // console.log('this.updatedContries === ', this.updatedContries);
    //     return countries;
    // }
}
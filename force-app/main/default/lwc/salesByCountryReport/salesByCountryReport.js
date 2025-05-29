import { LightningElement, api } from 'lwc';
import getSalesByCountryApps from '@salesforce/apex/SalesByCountryReportController.getSalesByCountryApps';

export default class SalesByCountryReport extends LightningElement {
    salesByCountry;
    countries;
    countryCount;
    error;
    amountByDay;

    connectedCallback() {
        getSalesByCountryApps()
                .then(result => {
                    this.salesByCountry = result.dateData;
                    this.countries = result.countryNames;
                    this.amountByDay = JSON.parse(JSON.stringify(result.amountByDay));
                    let appDate = result.dateData.find(item =>{
                        return item.name == 'This Qtr';
                    });
                    if (appDate != null) {
                        this.countryCount = appDate.countData;
                    }
            }).catch(error =>
                    this.error = error
            );
        }
}
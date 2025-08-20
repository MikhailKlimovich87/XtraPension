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
                    console.log(result.amountByDay);
                    console.log(result.countryNames);
                    console.log(result.dateData);
                    let appDate = result.dateData.find(item =>{
                        return item.name == 'Last Qtr';
                    });
                    if (appDate != null) {
                        this.countryCount = appDate.countData;
                    }
            }).catch(error =>
                    this.error = error
            );
        }
}
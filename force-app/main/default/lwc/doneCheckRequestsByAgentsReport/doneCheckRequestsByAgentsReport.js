import { LightningElement,api } from 'lwc';
import getAgentApps from '@salesforce/apex/DoneCheckRequestsByAgentReportController.getCheckAgentsData';

export default class DoneCheckRequestsByAgentsReport extends LightningElement {
    agentSales;
    agents;
    salesCount;
    error;
    amountByDay

    connectedCallback() {
        getAgentApps()
            .then(result => {
                this.agentSales = result.dateData;
                this.agents = result.agentsName;
                this.amountByDay = JSON.parse(JSON.stringify(result.amountByDay));
                let salesDate = result.dateData.find(item =>{
                    return item.name == 'This Qtr';
                });
                if (salesDate != null) {
                    this.salesCount = salesDate.countData;
                }
        }).catch(error =>
                this.error = error
        );
    }

    @api
    get agentExist() {
        if(this.agents) return true;
        else return false
    }
}
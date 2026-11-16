import { LightningElement } from 'lwc';
import getData from '@salesforce/apex/DoneClaimChecksByAgentReportController.getClaimCheckAgentsData';

// Same table as doneReapplyChecksByAgentsReport, counting Claim_Check__c (DWP checks of claims)
export default class DoneClaimChecksByAgentsReport extends LightningElement {
    agents = [];
    rows = [];
    error;

    connectedCallback() {
        getData()
            .then(result => {
                this.agents = result.agentsName;
                this.rows = result.dateData.map(row => ({
                    name: row.name,
                    fullCount: row.fullCount,
                    cells: row.countData.map((count, i) => ({ key: row.name + '-' + i, agent: this.agents[i], count }))
                }));
            })
            .catch(error => {
                this.error = error;
            });
    }
}
import { LightningElement, api } from 'lwc';
import getSales from '@salesforce/apex/XpAgentSalesController.getSales';
import getTables from '@salesforce/apex/XpTeamTablesController.getTables';

// Staff sites: Total, the product tables, all with the same columns. No report = Agent's Sales;
// report = agentCheck / qcApproved / sendToPH / pensionKeeper (XpTeamTablesController)
export default class XpAgentSales extends LightningElement {
    @api report;
    agents = [];
    tables = [];
    error;

    connectedCallback() {
        (this.report ? getTables({ report: this.report }) : getSales())
            .then(result => {
                this.agents = result.agents;
                this.tables = result.tables.map(table => ({
                    key: table.key,
                    title: table.title,
                    rows: table.rows.map(row => ({
                        key: table.key + '-' + row.name,
                        name: row.name,
                        total: row.total,
                        cells: row.counts.map((count, i) => ({ agent: result.agents[i], count }))
                    }))
                }));
            })
            .catch(error => {
                this.error = error;
            });
    }

    get errorMessage() {
        return (this.error && this.error.body && this.error.body.message) || (this.error && this.error.message) || 'unknown error';
    }
}
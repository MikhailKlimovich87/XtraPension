import { LightningElement } from 'lwc';
import getEnvelopeReportData from '@salesforce/apex/RE_SendForEsignReportController.getEnvelopeReportData';

export default class ReSentForEsignReport extends LightningElement {
    agentSales = [];
    agents = [];
    amountByDay = [];
    error;

    connectedCallback() {
        getEnvelopeReportData()
            .then(result => {
                this.agentSales = result.dateData.map(row => ({
                    name: row.name,
                    fullCount: row.fullCount,
                    countData: row.countData.map((val, idx) => ({
                        id: `${row.name}-${idx}`,
                        value: val
                    }))
                }));
                this.agents = result.agentsName.map((name, idx) => ({
                    id: `agent-${idx}`,
                    label: name
                }));
                // Keep Apex's native shape: { dateName, amount }
                this.amountByDay = result.amountByDay;
            })
            .catch(err => {
                this.error = err;
                console.error('Envelope report error', err);
            });
    }

    get agentExist() {
        return this.amountByDay && this.amountByDay.length > 0;
    }
}
import { LightningElement } from 'lwc';
import getReportData from '@salesforce/apex/MovedFromAgentCallReportController.getReportData';

export default class MovedFromAgentCallReport extends LightningElement {
    users;
    todayData;
    todayTotalCount;
    yesterdayData;
    yesterdayTotalCount;
    thisWeekData;
    thisWeekTotalCount;
    lastWeekData;
    lastWeekTotalCount;
    thisMonthData;
    thisMonthTotalCount;
    lastMonthData;
    lastMonthTotalCount;
    error;

    connectedCallback() {
        getReportData()
        .then(result => {
            this.users = result.activeUsers;
            console.log('todayChanges ==== ', JSON.parse(JSON.stringify(result.todayChanges)));
            this.todayData = result.todayChanges.dataValue;
            this.todayTotalCount = result.todayChanges.fullCount;
            this.yesterdayData = result.yesterdayChanges.dataValue;
            this.yesterdayTotalCount = result.yesterdayChanges.fullCount;
            this.thisWeekData = result.thisWeekChanges.dataValue;
            this.thisWeekTotalCount = result.thisWeekChanges.fullCount;
            this.lastWeekData = result.lastWeekChanges.dataValue;
            this.lastWeekTotalCount = result.lastWeekChanges.fullCount;
            this.thisMonthData = result.thisMonthChanges.dataValue;
            this.thisMonthTotalCount = result.thisMonthChanges.fullCount;
            this.lastMonthData = result.lastMonthChanges.dataValue;
            this.lastMonthTotalCount = result.lastMonthChanges.fullCount;
        }).catch(error => this.error = error);
    }
}
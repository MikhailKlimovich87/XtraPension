import { LightningElement } from 'lwc';
import getReportData from '@salesforce/apex/MovedToQCApprovedReportController.getReportData';

export default class MoveToQcApprovedReport extends LightningElement {
    users;
    todayData;
    yesterdayData;
    thisWeekData;
    lastWeekData;
    thisMonthData;
    lastMonthData;
    error;

    connectedCallback() {
        getReportData()
            .then(result => {
                this.users = result.activeUsers;
                this.todayData =result.todayChanges.dataValue;
                this.yesterdayData = result.yesterdayChanges.dataValue;
                this.thisWeekData = result.thisWeekChanges.dataValue;
                this.lastWeekData = result.lastWeekChanges.dataValue;
                this.thisMonthData = result.thisMonthChanges.dataValue;
                this.lastMonthData = result.lastMonthChanges.dataValue;
            }
        ).catch(error => this.error = error);
    }
}
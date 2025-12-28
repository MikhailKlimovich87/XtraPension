import { LightningElement, api } from 'lwc';

export default class SearchResultCheckModule extends LightningElement {
    @api
    currApp;
    searchBlockColours;
    linkColour;
    checkRequest;
    badgeLabels = [];

    connectedCallback() {
        if(!this.currApp.HMRC_Check_Requests__r) {
            this.searchBlockColours =
                'background-color: white;'+
                'color: black;' +
                'border-color: black;';
            this.linkColour = 'color: black';
            return;
        }
        this.checkRequest = this.currApp.HMRC_Check_Requests__r[0];

        switch (this.checkRequest.Colour_Label__c) {
            case 'RED':
                this.searchBlockColours =
                    'background-color: #fef3f2;'+
                    'color: #9b2935;' +
                    'border-color: #ffcaca;';
                this.linkColour = 'color: #9b2935;';
                break;
            case 'GREEN':
                this.searchBlockColours =
                    'background-color: #effdf4;'+
                    'color: #076838;' +
                    'border-color: #d4fbe1;';
                this.linkColour = 'color: #076838';
                break;
            case 'YELLOW':
                this.searchBlockColours =
                    'background-color: #fffbea;'+
                    'color: #9f5919;' +
                    'border-color: #feea99;';
                this.linkColour = 'color: #9f5919';
                break;
            default:
                this.searchBlockColours =
                    'background-color: white;'+
                    'color: black;' +
                    'border-color: black;';
                this.linkColour = 'color: black';
                break;
        }
        if (this.checkRequest.Not_Received__c == true) this.badgeLabels.push('Not Received');
        if (this.checkRequest.C2__c == true) this.badgeLabels.push('C2');
        if (this.checkRequest.C3__c == true) this.badgeLabels.push('C3');
        if (this.checkRequest.Processing_Received__c == true) this.badgeLabels.push('Processing (Received)');
        if (this.checkRequest.BadNINO__c == true) this.badgeLabels.push('BadNINO');
        if (this.checkRequest.BadInfo__c == true) this.badgeLabels.push('Bad Info');
        if (this.checkRequest.Reject__c == true) this.badgeLabels.push('Reject');
        if (this.checkRequest.Work_Item__c == true) this.badgeLabels.push('Work Item');
        if (this.checkRequest.X64_8__c == true) this.badgeLabels.push('64-8');
        if (this.checkRequest.DWP__c == true) this.badgeLabels.push('DWP');
        if (this.checkRequest.Appeal_Letter_Not_Received__c == true) this.badgeLabels.push('Appeal Letter Not Received');
        if (this.checkRequest.Appeal_Letter_Received__c == true) this.badgeLabels.push('Appeal Letter Received');
        if (this.checkRequest.Payment_Not_Received__c == true) this.badgeLabels.push('Payment Not Received');
        if (this.checkRequest.Payment_Received__c == true) this.badgeLabels.push('Payment Received');
        if (this.checkRequest.DWP_Call__c == true) this.badgeLabels.push('DWP Call');
    }

    get isNotifiactionSentTo() {
        return this.checkRequest &&
               this.checkRequest.Notification_sent_to__c ? true : false;
    }

    get isActionYet() {
        return this.checkRequest.Has_the_request_been_processed__c == 'Not Done' ? true : false;
    }

    get isDWP_App() {
        return  this.currApp.Age__c == 65 ||
                this.currApp.Age__c == 66 ||
                this.currApp.Age__c == 67 ? true : false;
    }

    get isHMRCChecks() {
        return this.checkRequest ? true : false;
    }

    get isShowDWPemptyMessage() {
        return !this.checkRequest && (this.currApp.Status__c == 'DWP Teleclaim' ||
                                      this.currApp.Status__c == 'DWP 2 Emails Sent' ||
                                      this.currApp.Status__c == 'DWP Shortfall Pending') ? true : false;
    }

    get lastPostedDate() {
        return this.currApp.Tracking_Number_Received_Date_3__c ?
            this.currApp.Tracking_Number_Received_Date_3__c :
            this.currApp.Tracking_Number_Received_Date_2__c ?
                this.currApp.Tracking_Number_Received_Date_2__c:
                this.currApp.Tracking_Number_Received_Date__c;
    }
}
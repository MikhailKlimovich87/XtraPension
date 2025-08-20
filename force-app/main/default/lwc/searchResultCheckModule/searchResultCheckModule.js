import { LightningElement, api } from 'lwc';

export default class SearchResultCheckModule extends LightningElement {
    @api
    currApp;
    searchBlockColours;
    linkColour;
    checkRequest;

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

         if (this.checkRequest.Not_Received__c == true ||
             this.checkRequest.BadNINO__c == true
         ) {
            this.searchBlockColours =
                'background-color: #fef3f2;'+
                'color: #9b2935;' +
                'border-color: #ffcaca;';
            this.linkColour = 'color: #9b2935;';
        } else if (this.checkRequest.Processing_Received__c == true ||
                   this.checkRequest.DWP__c == true) {
            this.searchBlockColours =
                'background-color: #effdf4;'+
                'color: #076838;' +
                'border-color: #d4fbe1;';
            this.linkColour = 'color: #076838';
        } else if ((this.checkRequest.C2__c == true ||
                    this.checkRequest.C3__c == true) &&
                    (this.currApp.Status__c == 'Posted' ||
                     this.currApp.Status__c == '64-8 Bounce' ||
                     this.currApp.Status__c == 'HMRC Reply 1' ||
                     this.currApp.Status__c == 'DWP Teleclaim' ||
                     this.currApp.Status__c == 'DWP 2 Emails Sent' ||
                     this.currApp.Status__c == 'DWP Shortfall Pending' ||
                     this.currApp.Status__c == 'XP Letter Sent' ||
                     this.currApp.Status__c == 'HMRC Reply 2')) {
            this.searchBlockColours =
                'background-color: #fffbea;'+
                'color: #9f5919;' +
                'border-color: #feea99;';
            this.linkColour = 'color: #9f5919';
        } else if ((this.checkRequest.C2__c == true ||
                    this.checkRequest.C3__c == true) &&
                    (this.currApp.Status__c == 'Send to Client' ||
                     this.currApp.Status__c == 'Agent Call' ||
                     this.currApp.Status__c == 'Charge CC' ||
                     this.currApp.Status__c == 'Annual Service' ||
                     this.currApp.Status__c == 'No Annual')) {
            this.searchBlockColours =
                'background-color: #effdf4;'+
                'color: #076838;' +
                'border-color: #d4fbe1;';
            this.linkColour = 'color: #076838';
        } else if (this.checkRequest.Work_Item__c == true ||
                   this.checkRequest.X64_8__c == true) {
            this.searchBlockColours =
                'background-color: #fffbea;'+
                'color: #9f5919;' +
                'border-color: #feea99;';
            this.linkColour = 'color: #9f5919';
        } else if (this.checkRequest.Reject__c == true &&
                   (this.currApp.Status__c == 'Posted' ||
                    this.currApp.Status__c == '64-8 Bounce' ||
                    this.currApp.Status__c == 'HMRC Reply 1' ||
                    this.currApp.Status__c == 'DWP Teleclaim' ||
                    this.currApp.Status__c == 'DWP 2 Emails Sent' ||
                    this.currApp.Status__c == 'DWP Shortfall Pending' ||
                    this.currApp.Status__c == 'XP Letter Sent' ||
                    this.currApp.Status__c == 'HMRC Reply 2')) {
            this.searchBlockColours =
                'background-color: #fef3f2;'+
                'color: #9b2935;' +
                'border-color: #ffcaca;';
            this.linkColour = 'color: #9b2935;';
        } else if (this.checkRequest.Reject__c == true &&
                   (this.currApp.Status__c == 'Send to Client' ||
                     this.currApp.Status__c == 'Agent Call' ||
                     this.currApp.Status__c == 'Charge CC' ||
                     this.currApp.Status__c == 'Annual Service' ||
                     this.currApp.Status__c == 'No Annual')) {
            this.searchBlockColours =
                'background-color: white;'+
                'color: black;' +
                'border-color: black;';
            this.linkColour = 'color: black';
        }
        //         if (this.checkRequest.Not_Received__c == false &&
        //             (this.checkRequest.C2__c == true ||
        //              this.checkRequest.C3__c == true)) {
        //     this.searchBlockColours =
        //         'background-color: #effdf4;'+
        //         'color: #076838;' +
        //         'border-color: #d4fbe1;';
        //     this.linkColour = 'color: #076838';
        // } else
        
        
        
        // else if (this.checkRequest.Not_Received__c == false &&
        //            this.checkRequest.C2__c == false &&
        //            this.checkRequest.C3__c == false) {
        //     this.searchBlockColours =
        //         'background-color: #fffbea;'+
        //         'color: #9f5919;' +
        //         'border-color: #feea99;';
        //     this.linkColour = 'color: #9f5919';
        // } else {
        //     this.searchBlockColours =
        //         'background-color: white;'+
        //         'color: black;' +
        //         'border-color: black;';
        //     this.linkColour = 'color: black;';
        // }
    }

    get isNotifiactionSentTo() {
        return this.checkRequest &&
               this.checkRequest.Not_Received__c &&
               this.checkRequest.Notification_sent_to__c ? true : false;
    }

    get isActionYet() {
        return this.checkRequest.Has_the_request_been_processed__c == 'Not Done' ? true : false;
    }

    get isOnDWPStage() {
        return  this.currApp.Status__c == 'DWP Teleclaim' ||
                this.currApp.Status__c == 'DWP 2 Emails Sent' ||
                this.currApp.Status__c == 'DWP Shortfall Pending' ? true : false;
    }

    get isHMRCChecks() {
        return this.checkRequest ? true : false;
    }

    get isShowDWPemptyMessage() {
        return !this.checkRequest && this.isOnDWPStage ? true : false;
    }
}
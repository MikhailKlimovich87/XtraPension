import { LightningElement, api } from 'lwc';

const COLOURS = {
    RED: { block: 'background-color: #fef3f2; color: #9b2935; border-color: #ffcaca;', link: 'color: #9b2935;' },
    GREEN: { block: 'background-color: #effdf4; color: #076838; border-color: #d4fbe1;', link: 'color: #076838;' },
    YELLOW: { block: 'background-color: #fffbea; color: #9f5919; border-color: #feea99;', link: 'color: #9f5919;' }
};
const DEFAULT_COLOURS = { block: 'background-color: white; color: black; border-color: black;', link: 'color: black;' };

const BADGES = [
    ['Not_Received__c', 'Not Received'],
    ['C2__c', 'C2'],
    ['C3__c', 'C3'],
    ['Processing_Received__c', 'Processing (Received)'],
    ['BadNINO__c', 'BadNINO'],
    ['BadInfo__c', 'Bad Info'],
    ['Reject__c', 'Reject'],
    ['Work_Item__c', 'Work Item'],
    ['X64_8__c', '64-8'],
    ['DWP__c', 'DWP'],
    ['DWP_Call__c', 'DWP Call']
];

const toView = check => {
    const badges = BADGES.filter(([field]) => check[field] === true).map(([, label]) => label);
    return {
        id: check.Id,
        badges,
        badgeText: badges.join(', '),
        agent: check.Check_Agents__c,
        createdDate: check.CreatedDate,
        sentDate: check.HMRC_Reply_Sent_Date__c,
        notes: check.Notes__c,
        pdf: check.PDF_GDrive_Link__c,
        colour: check.Colour_Label__c
    };
};

export default class ReapplyCheckSearchResult extends LightningElement {
    @api currApp;

    get checks() {
        return (this.currApp && this.currApp.Reapply_Checks__r) || [];
    }

    get lastCheck() {
        return this.checks.length ? toView(this.checks[0]) : null;
    }

    get history() {
        return this.checks.slice(1).map(toView);
    }

    get hasHistory() {
        return this.checks.length > 1;
    }

    get colours() {
        const last = this.lastCheck;
        return (last && COLOURS[last.colour]) || DEFAULT_COLOURS;
    }

    get blockColours() {
        return this.colours.block;
    }

    get linkColour() {
        return this.colours.link;
    }

    get applicationName() {
        return this.currApp && this.currApp.Application__r ? this.currApp.Application__r.Name : '';
    }
}
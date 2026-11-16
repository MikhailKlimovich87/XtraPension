import { LightningElement, api } from 'lwc';

const COLOURS = {
    RED: { block: 'background-color: #fef3f2; color: #9b2935; border-color: #ffcaca;', link: 'color: #9b2935;' },
    GREEN: { block: 'background-color: #effdf4; color: #076838; border-color: #d4fbe1;', link: 'color: #076838;' },
    YELLOW: { block: 'background-color: #fffbea; color: #9f5919; border-color: #feea99;', link: 'color: #9f5919;' }
};
const DEFAULT_COLOURS = { block: 'background-color: white; color: black; border-color: black;', link: 'color: black;' };

export const BADGES = [
    ['Not_Received__c', 'Not Received'],
    ['Received_by_DWP__c', 'Received by DWP'],
    ['Processing__c', 'Processing'],
    ['More_Info_Requested__c', 'DWP asked for more info'],
    ['Approved__c', 'Approved'],
    ['Rejected__c', 'Rejected'],
    ['Lump_Sum_Letter__c', 'Lump Sum Letter'],
    ['Payment_Started__c', 'Payment Started'],
    ['Called_DWP__c', 'Called DWP']
];

const toView = check => {
    const badges = BADGES.filter(([field]) => check[field] === true).map(([, label]) => label);
    return {
        id: check.Id,
        badges,
        badgeText: badges.join(', '),
        agent: check.Check_Agents__c,
        createdDate: check.CreatedDate,
        notes: check.Notes__c,
        pdf: check.PDF_GDrive_Link__c,
        colour: check.Colour_Label__c
    };
};

export default class ClaimCheckSearchResult extends LightningElement {
    @api currApp;

    get checks() {
        return (this.currApp && this.currApp.Claim_Checks__r) || [];
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

    get postedDate() {
        return this.currApp ? (this.currApp.Stage_1_Pack_Posted_Date__c || this.currApp.Big_Envelop_Posted_Date__c) : null;
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
}
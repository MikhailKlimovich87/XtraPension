import { LightningElement, api } from 'lwc';

/**
 * pc1RecordLayout — single wrapper component that composes the PC1 record page
 * into a Header + three-column grid (3/6/3 on large form factor, stacked on
 * medium/small).
 *
 * Placed inside the standard flexipage:recordHomeTemplateDesktop main region so
 * the whole PC1 record page renders as one tight layout — no Salesforce
 * "auto-stacked" behaviour that comes from having many LWCs in one region.
 *
 *   Header    : pc1ApplicationHeader + pc1PathBar + pc1HandoffCard
 *   Left col  : pc1CallHistory, pc1StageTimeline, pc1ProgressBar
 *   Center    : pc1ApplicationData (168-field grouped editor)
 *   Right col : pc1FillRunPanel
 */
export default class Pc1RecordLayout extends LightningElement {
    @api recordId;
    @api objectApiName;
}
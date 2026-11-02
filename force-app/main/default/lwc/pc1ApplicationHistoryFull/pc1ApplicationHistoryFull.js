import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import getHistory from '@salesforce/apex/PC1_ApplicationHistoryController.getHistory';
import getHistoryCount from '@salesforce/apex/PC1_ApplicationHistoryController.getHistoryCount';

const MAX_ROWS = 500;

/**
 * pc1ApplicationHistoryFull — App-page LWC that renders the entire field
 * history for one PC1_Application__c record as a grid. Hosted by the
 * FlexiPage PC1_Application_History_Page and reached via the card's
 * "View All" button (standard__navItemPage → PC1_Application_History tab
 * with state.c__recordId set to the record's Id).
 */
export default class Pc1ApplicationHistoryFull extends NavigationMixin(LightningElement) {
    @track recordId;
    @track appName;
    @track rows = [];
    @track totalCount = 0;
    error;

    @wire(CurrentPageReference)
    setPageRef(ref) {
        if (ref && ref.state) {
            const rid = ref.state.c__recordId || ref.state.recordId;
            if (rid && rid !== this.recordId) this.recordId = rid;
        }
    }

    @wire(getHistory, { recordId: '$recordId', maxRows: MAX_ROWS })
    wiredRows({ data, error }) {
        if (error) { this.error = error.body?.message || String(error); return; }
        this.rows = (data || []).map((r) => ({
            id:          r.Id,
            when:        r.CreatedDate,
            fieldLabel:  r.FieldLabel,
            userName:    r.UserName || 'System',
            userId:      r.UserId,
            oldValue:    r.OldValueDisplay || '(empty)',
            newValue:    r.NewValueDisplay || '(empty)',
        }));
    }

    @wire(getHistoryCount, { recordId: '$recordId' })
    wiredCount({ data }) { if (typeof data === 'number') this.totalCount = data; }

    get title() {
        if (!this.totalCount) return 'Application History';
        return `Application History (${this.totalCount})`;
    }

    get hasRows() { return this.rows && this.rows.length > 0; }

    handleUserClick(evt) {
        const uid = evt.currentTarget.dataset.userid;
        if (!uid) return;
        evt.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: uid, objectApiName: 'User', actionName: 'view' }
        });
    }

    handleBack(evt) {
        evt.preventDefault();
        if (!this.recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.recordId, objectApiName: 'PC1_Application__c', actionName: 'view' }
        });
    }
}
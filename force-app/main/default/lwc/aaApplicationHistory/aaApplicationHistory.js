import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHistory      from '@salesforce/apex/AA_ApplicationHistoryController.getHistory';
import getHistoryCount from '@salesforce/apex/AA_ApplicationHistoryController.getHistoryCount';

const PAGE_SIZE = 4;
const EXPANDED_SIZE = 200;

/**
 * aaApplicationHistory — native-look field history card. Salesforce's own
 * `force:relatedListSingleContainer` silently ignores Histories on custom
 * objects, so we render the same shape ourselves: title with count, per-row
 * date + field label + user + old→new values, "View All" link at bottom.
 */
export default class AaApplicationHistory extends NavigationMixin(LightningElement) {
    @api recordId;
    @track rows = [];
    @track totalCount = 0;
    @track expanded = false;
    @track loadingAll = false;
    error;

    @wire(getHistory, { recordId: '$recordId', maxRows: PAGE_SIZE })
    wiredRows({ data, error }) {
        if (error) { this.error = error.body?.message || String(error); return; }
        if (!this.expanded) this.rows = this.mapRows(data);
    }

    @wire(getHistoryCount, { recordId: '$recordId' })
    wiredCount({ data }) {
        if (typeof data === 'number') this.totalCount = data;
    }

    mapRows(data) {
        return (data || []).map((r) => ({
            id:         r.Id,
            when:       r.CreatedDate,
            fieldLabel: r.FieldLabel,
            userName:   r.UserName || 'System',
            userId:     r.UserId,
            oldValue:   r.OldValueDisplay || '(empty)',
            newValue:   r.NewValueDisplay || '(empty)',
        }));
    }

    get titleWithCount() {
        if (!this.totalCount) return 'Application History';
        const shown = this.rows.length;
        const suffix = (this.totalCount > shown) ? `${shown}+` : `${this.totalCount}`;
        return `Application History (${suffix})`;
    }

    get hasRows() { return this.rows && this.rows.length > 0; }
    get canExpand() { return !this.expanded && this.totalCount > this.rows.length; }
    get footerLabel() { return this.expanded ? 'Show Less' : 'View All'; }

    handleUserClick(evt) {
        const userId = evt.currentTarget.dataset.userid;
        if (!userId) return;
        evt.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: userId, objectApiName: 'User', actionName: 'view' }
        });
    }

    handleViewAll(evt) {
        evt.preventDefault();
        // Open the AppPage tab in a new browser tab. `standard__navItemPage`
        // with `apiName:'AA_Application_History'` should work, but SF's
        // Lightning app router caches the nav menu and can 404 for freshly
        // deployed tabs until the next login. Falling back to a hardcoded
        // URL via window.open bypasses that cache and is reliable.
        const url = `/lightning/n/AA_Application_History?c__recordId=${encodeURIComponent(this.recordId)}`;
        window.open(url, '_blank', 'noopener');
    }
}
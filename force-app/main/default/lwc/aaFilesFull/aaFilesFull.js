import { LightningElement, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFiles from '@salesforce/apex/AA_RecordPageService.getFiles';
import getApplication from '@salesforce/apex/AA_RecordPageService.getApplication';
import deleteFile from '@salesforce/apex/AA_RecordPageService.deleteFile';

// File extensions accepted by lightning-file-upload — matches SF default
// "Files" picker (broad but excludes obvious executables).
const ACCEPT = [
    '.pdf', '.png', '.jpg', '.jpeg', '.gif', '.svg',
    '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.txt', '.csv', '.zip', '.mp3', '.wav', '.mp4', '.mov'
];

/**
 * aaFilesFull — App-page listing all files linked to one PC Application.
 * Visual matches the standard SF "Files" related-list page:
 *   • breadcrumb "PC Applications > A05768"
 *   • title "Files" + subtitle "N items · Sorted by Last Modified · Updated …"
 *   • "Add Files" button (top-right)
 *   • sortable data table: Title / Owner / Last Modified / Size
 *   • row dropdown ▼ (Preview / Download)
 *
 * Reached via aaFilesCard's "View All (N)" opening
 * /lightning/n/AA_Application_Files?c__recordId=<id> in a new tab.
 */
export default class AaFilesFull extends NavigationMixin(LightningElement) {
    @track recordId;
    @track applicationName;
    @track sortedBy = 'lastModified';
    @track sortedDirection = 'desc';
    @track rawFiles = [];
    @track updatedAt;
    error;

    @wire(CurrentPageReference)
    setPageRef(ref) {
        if (ref && ref.state) {
            const rid = ref.state.c__recordId || ref.state.recordId;
            if (rid && rid !== this.recordId) this.recordId = rid;
        }
    }

    @wire(getApplication, { recordId: '$recordId' })
    wireApp({ data }) {
        if (data) this.applicationName = data.Name;
    }

    wiredFilesResult;

    @wire(getFiles, { recordId: '$recordId' })
    wired(result) {
        this.wiredFilesResult = result;
        if (result.error) { this.error = result.error.body?.message || String(result.error); return; }
        this.rawFiles = result.data || [];
        this.updatedAt = 'a few seconds ago';
    }

    get acceptedFormats() { return ACCEPT; }

    get sortedFiles() {
        const arr = [...this.rawFiles];
        const key = this.sortedBy;
        const dir = this.sortedDirection === 'asc' ? 1 : -1;
        arr.sort((a, b) => {
            const av = a[key], bv = b[key];
            if (av == null) return 1;
            if (bv == null) return -1;
            if (av < bv) return -1 * dir;
            if (av > bv) return 1 * dir;
            return 0;
        });
        return arr.map(f => ({
            id: f.id,
            title: f.title,
            iconName: this.iconFor(f.fileType),
            ownerName: f.ownerName || '—',
            lastModifiedFmt: this.fmtDate(f.lastModified),
            sizeFmt: this.fmtSize(f.size),
            sortLastModified: f.lastModified
        }));
    }

    get itemCount() { return this.rawFiles.length; }
    get subtitle() {
        const sortLabel = this.sortedBy === 'lastModified' ? 'Last Modified' :
                          this.sortedBy === 'title' ? 'Title' :
                          this.sortedBy === 'size' ? 'Size' : 'Owner';
        return `${this.itemCount} items · Sorted by ${sortLabel} · Updated ${this.updatedAt || 'now'}`;
    }
    get breadcrumbLabel() { return this.applicationName || '…'; }
    get hasFiles() { return this.rawFiles && this.rawFiles.length > 0; }

    // ── column sort ────────────────────────────────────────────────────
    handleSort(evt) {
        const key = evt.currentTarget.dataset.key;
        if (this.sortedBy === key) {
            this.sortedDirection = this.sortedDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortedBy = key;
            this.sortedDirection = key === 'title' ? 'asc' : 'desc';
        }
    }

    isSortedBy(key) { return this.sortedBy === key; }
    get titleSortArrow()    { return this.sortedBy === 'title'        ? (this.sortedDirection === 'asc' ? '↑' : '↓') : ''; }
    get ownerSortArrow()    { return this.sortedBy === 'ownerName'    ? (this.sortedDirection === 'asc' ? '↑' : '↓') : ''; }
    get modifiedSortArrow() { return this.sortedBy === 'lastModified' ? (this.sortedDirection === 'asc' ? '↑' : '↓') : ''; }
    get sizeSortArrow()     { return this.sortedBy === 'size'         ? (this.sortedDirection === 'asc' ? '↑' : '↓') : ''; }

    // ── formatting helpers ────────────────────────────────────────────
    fmtDate(iso) {
        if (!iso) return '';
        try {
            const d = new Date(iso);
            const dd = String(d.getDate()).padStart(2, '0');
            const mm = String(d.getMonth() + 1).padStart(2, '0');
            const yy = d.getFullYear();
            const hh = String(d.getHours()).padStart(2, '0');
            const mn = String(d.getMinutes()).padStart(2, '0');
            return `${dd}/${mm}/${yy}, ${hh}:${mn}`;
        } catch (_) { return iso; }
    }
    fmtSize(bytes) {
        if (bytes == null) return '';
        if (bytes < 1024) return `${bytes}B`;
        if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)}KB`;
        return `${(bytes / 1048576).toFixed(1)}MB`;
    }
    iconFor(fileType) {
        const t = (fileType || '').toUpperCase();
        if (t === 'PDF')       return 'doctype:pdf';
        if (t === 'PNG' || t === 'JPG' || t === 'JPEG') return 'doctype:image';
        if (t === 'MP3' || t === 'WAV') return 'doctype:audio';
        if (t === 'DOC' || t === 'DOCX') return 'doctype:word';
        if (t === 'XLS' || t === 'XLSX') return 'doctype:excel';
        if (t === 'ZIP')       return 'doctype:zip';
        if (t === 'TXT')       return 'doctype:txt';
        return 'doctype:unknown';
    }

    // ── row interactions ──────────────────────────────────────────────
    handleOpen(evt) {
        evt.preventDefault();
        const docId = evt.currentTarget.dataset.docid;
        if (!docId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: docId }
        });
    }

    /** Row-level ▼ menu handler. Actions:
     *   preview  → open Salesforce's built-in preview modal
     *   details  → jump to the ContentDocument record page (has native
     *              "Upload New Version", edit-Title-to-rename, Share,
     *              Public Link, Delete — same UI as any other service)
     *   download → fire the standard shepherd download URL
     */
    handleRowAction(evt) {
        const action = evt.detail.value;
        const docId = evt.currentTarget.dataset.docid;
        if (!action || !docId) return;
        if (action === 'preview') {
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: { pageName: 'filePreview' },
                state: { selectedRecordId: docId }
            });
        } else if (action === 'details') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: docId, objectApiName: 'ContentDocument', actionName: 'view' }
            });
        } else if (action === 'download') {
            const row = this.rawFiles.find(f => f.id === docId);
            if (row && row.versionId) {
                window.open(`/sfc/servlet.shepherd/version/download/${row.versionId}`, '_blank', 'noopener');
            }
        } else if (action === 'delete') {
            this.confirmAndDelete(docId);
        }
    }

    async confirmAndDelete(docId) {
        const row = this.rawFiles.find(f => f.id === docId);
        const label = row ? row.title : 'this file';
        // eslint-disable-next-line no-alert
        if (!window.confirm(`Delete "${label}"? This removes the file from Salesforce for everyone.`)) return;
        try {
            await deleteFile({ contentDocumentId: docId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Deleted', variant: 'success', message: `${label} removed.` }));
            await this.handleRefresh();
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Delete failed', variant: 'error',
                message: err?.body?.message || err?.message || 'Unknown error'
            }));
        }
    }

    handleBreadcrumb(evt) {
        evt.preventDefault();
        if (!this.recordId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: this.recordId, objectApiName: 'AA_Application__c', actionName: 'view' }
        });
    }

    /** Called by lightning-file-upload after the user picks and uploads
     *  one or more files. Each file becomes a ContentDocument linked to
     *  the Application (via `record-id` binding). Refresh the wire so
     *  the new rows appear in the table without a page reload. */
    async handleUploadFinished(evt) {
        const uploaded = (evt.detail && evt.detail.files) || [];
        this.dispatchEvent(new ShowToastEvent({
            title: `${uploaded.length} file${uploaded.length === 1 ? '' : 's'} uploaded`,
            variant: 'success'
        }));
        try { await refreshApex(this.wiredFilesResult); }
        catch (_) { /* wire will catch up */ }
    }

    handleRefresh(evt) {
        if (evt && evt.preventDefault) evt.preventDefault();
        // Trigger a wire refresh by re-navigating (cheapest way from an
        // AppPage LWC without importing refreshApex on the wired result).
        window.location.reload();
    }
}
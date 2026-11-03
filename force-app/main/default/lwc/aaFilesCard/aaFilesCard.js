import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getFiles from '@salesforce/apex/AA_RecordPageService.getFiles';
import getApplication from '@salesforce/apex/AA_RecordPageService.getApplication';

const PREVIEW_ROWS = 2;

/**
 * aaFilesCard — Salesforce-native "Docs"-style file list. Every
 * ContentDocument linked to the current Application (call transcripts,
 * summaries, DWP screenshots + PDF), newest first. Each row: a compact
 * label (Check Your Answers / Pre Submit / Fill Issue) + date underneath.
 * Full underlying title stays intact — it appears in the "View all" page
 * (aaFilesFull) and in the SF preview modal.
 *
 * Uses `standard__namedPage` filePreview navigation which is the same
 * behaviour Fernando's Docs card in Sales/Claim uses.
 */
export default class AaFilesCard extends NavigationMixin(LightningElement) {
    @api recordId;
    files = [];
    _fileTag = null; // "AppNo_FName_LName" — prefix stripped for card display

    @wire(getFiles, { recordId: '$recordId' })
    wired({ data }) {
        if (data) this.files = data;
    }

    @wire(getApplication, { recordId: '$recordId' })
    wiredApp({ data }) {
        if (!data) return;
        const parts = [data.Name].filter(Boolean);
        const fn = (data.First_Name__c || '').trim();
        const ln = (data.Last_Name__c || '').trim();
        if (fn) parts.push(fn);
        if (ln) parts.push(ln);
        this._fileTag = parts.join('_');
    }

    get hasFiles()  { return this.files.length > 0; }
    get emptyText() { return 'No files yet. Call transcripts and DWP screenshots will appear here.'; }

    get rows() {
        return this.files.slice(0, PREVIEW_ROWS).map(f => ({
            id: f.id,
            title: this._compactTitle(f.title),
            date: this.fmt(f.lastModified || f.createdAt),
        }));
    }

    get hasMore() { return this.files.length > PREVIEW_ROWS; }
    get viewAllLabel() { return `View all (${this.files.length})`; }

    /**
     * Strip the "<AppNo>_<FName>_<LName>_" prefix (and file extension) from
     * artifact titles so the compact card shows just the label:
     *   "PC00029_Sarah_Smith_Fill Issue.png"       → "Fill Issue"
     *   "PC00029_Sarah_Smith_Check Your Answers.pdf" → "Check Your Answers"
     *   "PC00029_Sarah_Smith_Pre Submit.pdf"       → "Pre Submit"
     * Manually uploaded files (no matching prefix) fall through untouched
     * so ops sees exactly what was uploaded.
     */
    _compactTitle(rawTitle) {
        if (!rawTitle) return '';
        if (this._fileTag && rawTitle.startsWith(this._fileTag + '_')) {
            const rest = rawTitle.slice(this._fileTag.length + 1);
            return rest.replace(/\.[a-z0-9]+$/i, '');
        }
        return rawTitle;
    }

    fmt(iso) {
        if (!iso) return '';
        try {
            const d = new Date(iso);
            // Match Sales/Claim "Docs" pattern: "Wed 20 Mar 2024"
            return d.toLocaleDateString('en-GB', { weekday: 'short', day: '2-digit', month: 'short', year: 'numeric' });
        } catch (_) { return iso; }
    }

    /** Click a title → open Salesforce's built-in file preview modal
     *  (image viewer, PDF viewer). No download, no new tab. */
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

    /** View All → open our dedicated Files page in a new browser tab.
     *  Standard SF "View All Files" 404s on custom objects (same bug as
     *  Histories). We host our own AppPage FlexiPage
     *  `AA_Application_Files_Page` and reach it via the tab
     *  `AA_Application_Files`, passing the record Id in the URL state. */
    handleViewAll(evt) {
        evt.preventDefault();
        const url = `/lightning/n/AA_Application_Files?c__recordId=${encodeURIComponent(this.recordId)}`;
        window.open(url, '_blank', 'noopener');
    }
}
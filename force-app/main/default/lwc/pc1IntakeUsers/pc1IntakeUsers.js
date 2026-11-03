import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listUsers from '@salesforce/apex/PC1_IntakeAdminController.listUsers';
import createUser from '@salesforce/apex/PC1_IntakeAdminController.createUser';
import resetPassword from '@salesforce/apex/PC1_IntakeAdminController.resetPassword';
import setActive from '@salesforce/apex/PC1_IntakeAdminController.setActive';
import deleteUser from '@salesforce/apex/PC1_IntakeAdminController.deleteUser';

const LONDON_FMT = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/London',
    year: 'numeric', month: 'short', day: '2-digit',
    hour: '2-digit', minute: '2-digit'
});

export default class Pc1IntakeUsers extends LightningElement {
    rows = [];
    loading = true;
    saving = false;
    wired;

    // Add-user modal state
    showAdd = false;
    newUsername = '';
    newPassword = '';
    newRole = 'sales';

    roleOptions = [
        { label: 'sales', value: 'sales' },
        { label: 'admin', value: 'admin' }
    ];

    @wire(listUsers)
    handleWire(res) {
        this.wired = res;
        if (res.data) {
            this.rows = this.decorate(res.data);
            this.loading = false;
        } else if (res.error) {
            this.loading = false;
            this.toast('Load failed', 'error', this.errMsg(res.error));
        }
    }

    decorate(rows) {
        return rows.map((r) => {
            const locked = !!r.lockedAt;
            return {
                ...r,
                lastLoginDisplay: r.lastLoginAt ? LONDON_FMT.format(new Date(r.lastLoginAt)) : '—',
                failedDisplay: r.failedLoginCount || 0,
                roleBadgeCls: r.role === 'admin'
                    ? 'slds-badge slds-theme_success'
                    : 'slds-badge',
                activeLabel: r.active ? (locked ? 'Locked' : 'Active') : 'Inactive',
                activeBadgeCls: !r.active
                    ? 'slds-badge slds-theme_warning'
                    : (locked ? 'slds-badge slds-theme_error' : 'slds-badge slds-theme_success'),
                rowCls: r.active ? 'pc1-iu__row' : 'pc1-iu__row pc1-iu__row--inactive',
                canDeactivate: r.active,
                canActivate: !r.active
            };
        });
    }

    get isEmpty() { return !this.loading && this.rows.length === 0; }
    get showTable() { return !this.loading && this.rows.length > 0; }

    // ── row actions ─────────────────────────────────────────────────
    async handleResetPassword(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.id === id);
        if (!row) return;
        // eslint-disable-next-line no-alert
        const pw = prompt(`New password for "${row.username}" (min 8 chars):`);
        if (pw === null) return; // cancelled
        if (!pw || pw.length < 8) {
            this.toast('Invalid password', 'error', 'Password must be at least 8 characters.');
            return;
        }
        this.saving = true;
        try {
            await resetPassword({ userId: id, password: pw });
            this.toast('Password reset', 'success', `New password set for ${row.username}. Live sessions have been revoked.`);
            await refreshApex(this.wired);
        } catch (err) {
            this.toast('Reset failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    async handleDeactivate(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.id === id);
        if (!row) return;
        // eslint-disable-next-line no-alert
        if (!confirm(`Deactivate "${row.username}"? They won't be able to log in until reactivated.`)) return;
        this.saving = true;
        try {
            await setActive({ userId: id, active: false });
            this.toast('Deactivated', 'success', `${row.username} can no longer sign in.`);
            await refreshApex(this.wired);
        } catch (err) {
            this.toast('Deactivate failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    async handleActivate(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.id === id);
        if (!row) return;
        this.saving = true;
        try {
            await setActive({ userId: id, active: true });
            this.toast('Activated', 'success', `${row.username} can sign in again.`);
            await refreshApex(this.wired);
        } catch (err) {
            this.toast('Activate failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    async handleDelete(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.id === id);
        if (!row) return;
        // eslint-disable-next-line no-alert
        if (!confirm(`Delete "${row.username}"? This is permanent — prefer Deactivate to keep history.`)) return;
        this.saving = true;
        try {
            await deleteUser({ userId: id });
            this.toast('Deleted', 'success', `${row.username} removed.`);
            await refreshApex(this.wired);
        } catch (err) {
            this.toast('Delete failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    // ── add-user modal ──────────────────────────────────────────────
    handleShowAdd() {
        this.newUsername = '';
        this.newPassword = '';
        this.newRole = 'sales';
        this.showAdd = true;
    }
    handleCloseAdd() { this.showAdd = false; }
    handleNewUsername(e) { this.newUsername = e.target.value; }
    handleNewPassword(e) { this.newPassword = e.target.value; }
    handleNewRole(e) { this.newRole = e.detail.value; }

    async handleCreate() {
        const username = (this.newUsername || '').trim().toLowerCase();
        const password = this.newPassword || '';
        const role = this.newRole || 'sales';
        if (!username) { this.toast('Missing username', 'error', 'Enter a username.'); return; }
        if (!password || password.length < 8) { this.toast('Invalid password', 'error', 'Password must be at least 8 characters.'); return; }
        this.saving = true;
        try {
            await createUser({ username, password, role });
            this.toast('User added', 'success', `${username} (${role}) can now sign in.`);
            this.showAdd = false;
            await refreshApex(this.wired);
        } catch (err) {
            this.toast('Create failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    // ── util ────────────────────────────────────────────────────────
    toast(title, variant, message) {
        this.dispatchEvent(new ShowToastEvent({ title, variant, message: message || '' }));
    }
    errMsg(e) { return e?.body?.message || e?.message || 'Unknown error'; }
}
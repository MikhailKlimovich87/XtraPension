import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import listAgents from '@salesforce/apex/PC1_ValAgentAdminController.listAgents';
import createAgent from '@salesforce/apex/PC1_ValAgentAdminController.createAgent';
import updateAgent from '@salesforce/apex/PC1_ValAgentAdminController.updateAgent';
import deleteAgent from '@salesforce/apex/PC1_ValAgentAdminController.deleteAgent';

export default class Pc1ValAgentAdmin extends LightningElement {
    rows = [];
    loading = true;
    saving = false;
    wired;

    // Add-agent modal state
    showAdd = false;
    newName = '';
    newWeight = 10;
    newActive = true;

    @wire(listAgents)
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

    // ── decoration ──────────────────────────────────────────────────
    decorate(rows) {
        const active = rows.filter((r) => r.active);
        const totalWeight = active.reduce((s, r) => s + (Number(r.weight) || 0), 0) || 0;
        const totalAssigned = rows.reduce((s, r) => s + (r.assignedCount || 0), 0);
        return rows.map((r) => {
            const pct = r.active && totalWeight > 0
                ? Math.round(((Number(r.weight) || 0) / totalWeight) * 1000) / 10
                : 0;
            return {
                ...r,
                pctDisplay: r.active ? `${pct}%` : '—',
                barStyle: `width:${Math.min(100, pct)}%`,
                assignedDisplay: r.assignedCount || 0,
                rowCls: r.active ? 'pc1-va-row' : 'pc1-va-row pc1-va-row--inactive',
                activeLabel: r.active ? 'Active' : 'Paused',
                activeBadgeCls: r.active
                    ? 'slds-badge slds-theme_success'
                    : 'slds-badge slds-theme_warning'
            };
        });
    }

    get totalWeight() {
        return this.rows.filter((r) => r.active).reduce((s, r) => s + (Number(r.weight) || 0), 0);
    }
    get totalAssigned() {
        return this.rows.reduce((s, r) => s + (Number(r.assignedCount) || 0), 0);
    }
    get isEmpty() { return !this.loading && this.rows.length === 0; }
    get showTable() { return !this.loading && this.rows.length > 0; }

    // ── handlers: rows ──────────────────────────────────────────────
    async handleWeightChange(e) {
        const id = e.currentTarget.dataset.id;
        const raw = e.currentTarget.value;
        const weight = Number(raw);
        if (!(weight > 0)) {
            this.toast('Invalid weight', 'error', 'Weight must be greater than 0.');
            return;
        }
        await this.saveAgent(id, { weight });
    }

    async handleNameBlur(e) {
        const id = e.currentTarget.dataset.id;
        const agentName = (e.currentTarget.value || '').trim();
        const original = this.rows.find((r) => r.id === id);
        if (!agentName || (original && agentName === original.name)) return;
        await this.saveAgent(id, { agentName });
    }

    async handleToggleActive(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.id === id);
        if (!row) return;
        await this.saveAgent(id, { active: !row.active });
    }

    async handleDelete(e) {
        const id = e.currentTarget.dataset.id;
        const row = this.rows.find((r) => r.id === id);
        if (!row) return;
        // eslint-disable-next-line no-alert
        if (!confirm(`Delete "${row.name}"? Existing applications assigned to them will keep the name, but no new ones will route here.`)) return;
        this.saving = true;
        try {
            await deleteAgent({ agentId: id });
            this.toast('Deleted', 'success', `Removed ${row.name} from the pool.`);
            await refreshApex(this.wired);
        } catch (err) {
            this.toast('Delete failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    async saveAgent(id, patch) {
        this.saving = true;
        try {
            await updateAgent({
                agentId: id,
                agentName: patch.agentName ?? null,
                weight: patch.weight ?? null,
                active: patch.active ?? null
            });
            await refreshApex(this.wired);
        } catch (err) {
            this.toast('Save failed', 'error', this.errMsg(err));
        } finally { this.saving = false; }
    }

    // ── handlers: add-agent modal ───────────────────────────────────
    handleShowAdd() {
        this.newName = '';
        this.newWeight = 10;
        this.newActive = true;
        this.showAdd = true;
    }
    handleCloseAdd() { this.showAdd = false; }
    handleNewName(e) { this.newName = e.target.value; }
    handleNewWeight(e) { this.newWeight = Number(e.target.value); }
    handleNewActive(e) { this.newActive = e.target.checked; }

    async handleCreate() {
        const agentName = (this.newName || '').trim();
        if (!agentName) { this.toast('Missing name', 'error', 'Enter an agent name.'); return; }
        if (!(this.newWeight > 0)) { this.toast('Invalid weight', 'error', 'Weight must be greater than 0.'); return; }
        this.saving = true;
        try {
            await createAgent({
                agentName,
                weight: this.newWeight,
                active: this.newActive
            });
            this.toast('Added', 'success', `${agentName} is now in the pool.`);
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
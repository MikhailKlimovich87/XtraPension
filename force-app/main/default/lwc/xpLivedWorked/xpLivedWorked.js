import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent, registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import LightningConfirm from 'lightning/confirm';
import getData from '@salesforce/apex/XpLivedWorkedController.getData';
import saveRow from '@salesforce/apex/XpLivedWorkedController.saveRow';
import deleteRow from '@salesforce/apex/XpLivedWorkedController.deleteRow';
import getCountryOptions from '@salesforce/apex/XpLivedWorkedController.getCountryOptions';
import { buildView, formFor, fieldsFor, checkForm } from './livedWorked';

// Lived & Worked: no lugar do Work do Sales, no alto da coluna da esquerda do Claim. Mostra o que vai no IPCBR1
// (endereços e empregadores no UK, do cliente ou do cônjuge, países depois do UK, filhos do HRP) e as
// conferências que o DWP perguntaria. As listas se editam aqui (+ Add, lápis, lixeira), com as marcas
// (Is_Addresses__c, Is_Partner__c) postas pelo bloco; a trava por status está no Apex. Visual = workDisplay.

const KIND_ROWS = {
    ownAddress: 'companies',
    spouseAddress: 'companies',
    ownEmployer: 'companies',
    spouseEmployer: 'companies',
    country: 'countries',
    spouseCountry: 'countries',
    child: 'children'
};

function errorText(e) {
    if (!e) return 'Unknown error';
    if (e.body && e.body.message) return e.body.message;
    if (e.body && e.body.pageErrors && e.body.pageErrors.length) return e.body.pageErrors[0].message;
    return e.message || String(e);
}

export default class XpLivedWorked extends NavigationMixin(LightningElement) {
    @api recordId;

    data;
    view;
    error;
    loaded = false;
    refreshId;

    // modal
    modal;
    form = {};
    formError;
    saving = false;
    countryOptions;

    get cardTitle() {
        return 'Lived & Worked';
    }

    get isLoading() {
        return !this.loaded && !this.error;
    }

    get ipcbr1Id() {
        return this.view ? this.view.ipcbr1Id : null;
    }

    get editable() {
        return !!(this.view && this.view.editable);
    }

    connectedCallback() {
        this.load();
        // Atualiza junto com a página (ex.: depois do editor do IPCBR1 ou de outro quadro).
        this.refreshId = registerRefreshHandler(this, this.refresh.bind(this));
    }

    disconnectedCallback() {
        if (this.refreshId) unregisterRefreshHandler(this.refreshId);
    }

    refresh() {
        return this.load().then(() => true);
    }

    load() {
        if (!this.recordId) return Promise.resolve();
        return getData({ claimId: this.recordId })
            .then((result) => {
                this.data = result;
                this.view = buildView(result);
                this.error = undefined;
                this.loaded = true;
            })
            .catch((e) => {
                this.error = errorText(e);
            });
    }

    openIpcbr1() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { recordIds: this.ipcbr1Id }
        });
    }

    // ------------------------------------------------------------------ modal

    openAdd(event) {
        this.openModal(event.currentTarget.dataset.kind, null);
    }

    openEdit(event) {
        const { id, kind } = event.currentTarget.dataset;
        const rows = (this.data && this.data[KIND_ROWS[kind]]) || [];
        const row = rows.find((r) => r.Id === id);
        if (row) this.openModal(kind, row);
    }

    openModal(kind, row) {
        const f = formFor(kind, row, this.view.words);
        this.form = f.values;
        this.formError = undefined;
        this.modal = { kind, rowId: row ? row.Id : null, title: f.title };
        if (kind.endsWith('ountry') && !this.countryOptions) {
            getCountryOptions()
                .then((options) => {
                    this.countryOptions = options;
                })
                .catch((e) => {
                    this.formError = errorText(e);
                });
        }
    }

    closeModal() {
        this.modal = undefined;
        this.saving = false;
    }

    get modalFields() {
        return this.modal ? fieldsFor(this.modal.kind, this.form, this.countryOptions) : [];
    }

    handleField(event) {
        const name = event.target.dataset.name;
        const value = event.target.type === 'checkbox' ? event.detail.checked : event.detail.value;
        this.form = { ...this.form, [name]: value === '' ? null : value };
    }

    save() {
        const inputs = [...this.template.querySelectorAll('.modal-fields lightning-input, .modal-fields lightning-combobox')];
        const valid = inputs.reduce((ok, input) => input.reportValidity() && ok, true);
        if (!valid) return;
        const problem = checkForm(this.modal.kind, this.form);
        if (problem) {
            this.formError = problem;
            return;
        }
        this.saving = true;
        this.formError = undefined;
        saveRow({ claimId: this.recordId, kind: this.modal.kind, rowId: this.modal.rowId, fields: this.form })
            .then((result) => {
                this.closeModal();
                this.done('Saved', result);
            })
            .catch((e) => {
                this.saving = false;
                this.formError = errorText(e);
            });
    }

    async remove(event) {
        const { id } = event.currentTarget.dataset;
        const ok = await LightningConfirm.open({ message: 'Delete this row? It is removed from the IPCBR1 too.', label: 'Delete row', theme: 'warning' });
        if (!ok) return;
        try {
            const result = await deleteRow({ claimId: this.recordId, rowId: id });
            this.done('Deleted', result);
        } catch (e) {
            this.toast('Not deleted', errorText(e), 'error');
        }
    }

    // Recarrega o quadro e avisa a página (o Missing Info recalcula). O pacote é refeito no Apex quando já existe.
    done(what, result) {
        const rebuilt = result && result.regenerating;
        this.toast(what, rebuilt ? 'The pack is being rebuilt (IPCBR1, IPC1394, Client Summary, DD mandate).' : '', 'success');
        this.load();
        this.dispatchEvent(new RefreshEvent());
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
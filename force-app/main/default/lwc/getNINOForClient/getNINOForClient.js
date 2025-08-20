import { LightningElement, api, track, wire} from 'lwc';
import getApplicationData from '@salesforce/apex/GetNINOController.getApplicationData';
import saveNINOEnvelopsData from '@salesforce/apex/GetNINOController.saveNINOEnvelopsData';
import generateNINOFile from '@salesforce/apex/GetNINOController.generateGetNINOFile';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {getRecord} from 'lightning/uiRecordApi';

import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Short_Name__c';
import PHONE_FIELD from '@salesforce/schema/User.Phone';

export default class GetNINOForClient extends LightningElement {
    @api recordId;
    @track userName;
    @track phoneData;
    @track error;
    posted2Envs;
    envA = '';
    envB = '';
    postedEnvA;
    postedEnvB;
    dateEnvA;
    dateEnvB;
    copyData;
    getNINOData;
    getFollowUpAgentCallMessage;
    getUrgentDocApprovalMessage;
    isMainPage = true;
    filetableData;
    showSpinner = false;
    options1 =
    [
        { label: 'None', value: '', isSelected: false },
        { label: 'Yes', value: 'Yes', isSelected: false },
        { label: 'No', value: 'No', isSelected: false  }
    ];
    options2 =
    [
        { label: 'None', value: '', isSelected: false },
        { label: 'Yes', value: 'Yes', isSelected: false },
        { label: 'No', value: 'No', isSelected: false  }
    ];

    options3 =
    [
        { label: 'None', value: '', isSelected: false },
        { label: 'Yes', value: 'Yes', isSelected: false },
        { label: 'No', value: 'No', isSelected: false  }
    ];

    options4 =
    [
        { label: 'None', value: '', isSelected: false },
        { label: 'Yes', value: 'Yes', isSelected: false },
        { label: 'No', value: 'No', isSelected: false  }
    ];

    options5 =
    [
        { label: 'None', value: '', isSelected: false },
        { label: 'Yes', value: 'Yes', isSelected: false },
        { label: 'No', value: 'No', isSelected: false  }
    ];

    @wire(getRecord, {
        recordId: USER_ID,
        fields: [NAME_FIELD, PHONE_FIELD]
    }) wireuser({
        error,
        data
    }) {
        if (error) {
           this.error = error ;
        } else if (data) {
            this.userName = data.fields.Short_Name__c.value;
            this.phoneData = data.fields.Phone.value;
        }
    }


    connectedCallback() {
        getApplicationData({
            recordId: this.recordId
        }).then(
            data => {
                if (data.isSuccess) {
                    this.posted2Envs = data?.application?.JR_Posted_2_Env_s__c;
                    this.envA = data?.application?.Envelop_A__c;
                    this.envB = data?.application?.Envelop_B__c;
                    this.postedEnvA = data?.application?.Posted_Env_A__c;
                    this.postedEnvB = data?.application?.Posted_Env_B__c;
                    this.dateEnvA = data?.application?.Envelop_A_Date__c;
                    this.dateEnvB = data?.application?.Envelop_B_Date__c;
                    this.copyData =
                        data?.application?.Salutation__c + ' ' +
                        data?.application?.First_Name__c + ' ' +
                        data?.application?.Second_Name__c +
                        (data?.application?.Current_Address_Abroad__Street__s ? '\n' + data?.application?.Current_Address_Abroad__Street__s : '') +
                        (data?.application?.Current_Address_Abroad__City__s ? '\n' + data?.application?.Current_Address_Abroad__City__s : '') +
                        (data?.application?.Current_Address_Abroad_State__c ? '\n' + data?.application?.Current_Address_Abroad_State__c : '') +
                        (data?.application?.Current_Address_Abroad__PostalCode__s ? '\n' + data?.application?.Current_Address_Abroad__PostalCode__s : '') +
                        (data?.application?.Current_Address_Abroad_Country__c ? '\n' + data?.application?.Current_Address_Abroad_Country__c : '')
                    this.getNINOData = 'Hi ' + data?.application?.First_Name__c +
                                       ' - How was XtraPension\'s UK State Pension Topup Service? Please tell us on this link: https://xpen.uk/google - Thanks!';
                    this.getFollowUpAgentCallMessage =
                        'Hi ' + data?.application?.First_Name__c + ' - ' + this.userName + ' here from XtraPension just following up re UK State Pension next steps for you.\n\n' +
                        'Do you want to give me a call please whenever suits & I\'ll come back to you if I miss you?\n\n' +
                        'Thanks, ' + this.userName + ' ' + this.phoneData;
                    this.getUrgentDocApprovalMessage =
                        'Hi ' + data?.application?.First_Name__c + '.\n\n' +
                        'Your UK State Pension TopUp application has been awaiting your approval for some time.\n\n' +
                        'If you\'re delaying approving it for some reason, please let us know.\n\n' +
                        'Otherwise, we\'ll shortly be CANCELLING your application.\n\n' +
                        'More importantly, this means you will LOSE OUT on the UK Pension opportunity which is worth many thousands to you.\n\n' +
                        'Next steps are explained in this short video:https://xpen.uk/approve\n\n' +
                        'Thanks\n\n' +
                        'John Ring, Head of Operations\n\n' +
                        'XtraPension Ltd\n' +
                        '+353 (0)91 335 583';
                    if (this.posted2Envs) {
                        this.options1.map( item => {
                            if(item.value == this.posted2Envs) {
                                item.isSelected = true;
                            }
                        })
                    } else {
                        this.options1.map( item => {
                            if(item.label == 'None') {
                                item.isSelected = true;
                            }
                        })
                    }
                    if (this.postedEnvA) {
                        this.options2.map( item => {
                            if(item.value == this.postedEnvA) {
                                item.isSelected = true;
                            }
                        })
                    } else {
                        this.options2.map( item => {
                            if(item.label == 'None') {
                                item.isSelected = true;
                            }
                        })
                    }
                    if (this.postedEnvB) {
                        this.options3.map( item => {
                            if(item.value == this.postedEnvB) {
                                item.isSelected = true;
                            }
                        })
                    } else {
                        this.options3.map( item => {
                            if(item.label == 'None') {
                                item.isSelected = true;
                            }
                        })
                    }
                    if (this.envA) {
                        this.options4.map( item => {
                            if(item.value == this.envA) {
                                item.isSelected = true;
                            }
                        })
                    } else {
                        this.options4.map( item => {
                            if(item.label == 'None') {
                                item.isSelected = true;
                            }
                        })
                    }
                    if (this.envB) {
                        this.options5.map( item => {
                            if(item.value == this.envA) {
                                item.isSelected = true;
                            }
                        })
                    } else {
                        this.options5.map( item => {
                            if(item.label == 'None') {
                                item.isSelected = true;
                            }
                        })
                    }

                } else this.error = data?.errorMessage;
            }
        ).catch(
            error => console.log('Error message ==== ', error)
        )
    }

    handleClick() {
        this.isMainPage = !this.isMainPage;
    }

    handleSave() {
        this.showSpinner = !this.showSpinner;
        let newData = {
            applicationId: this.recordId,
            posted2Envs: this.posted2Envs,
            envelopA: this.envA,
            envelopB: this.envB,
            postedEnvelopA: this.postedEnvA,
            postedEnvelopB: this.postedEnvB,
            dateEnvelopA: this.dateEnvA,
            dateEnvelopB: this.dateEnvB
        }
        saveNINOEnvelopsData({
            data: newData
        }).then(data=> {
            this.showSpinner = !this.showSpinner;
            this.showToastMessage(
                'Success',
                'You\'ve saved Get NINO for Client data!',
                'success'
            );
            window.location.reload();
        }).catch(error=> {
            console.log(error);
            this.showSpinner = !this.showSpinner;
            this.showToastMessage(
                'Error',
                'Error message is ' + error.body.message,
                'error'
            );
            window.location.reload();
        })

    }

    handleChangePosted2Env(event) {
        this.posted2Envs = event.target.value;
    }

    handleChangeEnvA(event) {
        this.envA = event.target.value;
    }

    handleChangeEnvB(event) {
        this.envB = event.target.value;
    }

    handleChangePostedEnvA(event) {
        this.postedEnvA = event.target.value;
    }

    handleChangePostedEnvB(event) {
        this.postedEnvB = event.target.value;
    }

    handleChangeDateEnvA(event) {
        this.dateEnvA = event.target.value;
    }

    handleChangeDateEnvB(event) {
        this.dateEnvB = event.target.value;
    }

    showToastMessage(titleData, messageInfo, toastVariant) {
        this.dispatchEvent(new ShowToastEvent({
            title: titleData,
            message: messageInfo,
            variant: toastVariant,
        }));
    }

    handleCopy() {
        this.copyInfo(this.copyData);
    }

    handleGetNINO() {
        this.copyInfo(this.getNINOData);
    }

    handleFollowUpAgentCall() {
        this.copyInfo(this.getFollowUpAgentCallMessage);
    }

    handleUrgentDocApproval() {
        this.copyInfo(this.getUrgentDocApprovalMessage);
    }

    handleGenerate() {
        this.showSpinner = !this.showSpinner;
        generateNINOFile({
            applicationId: this.recordId
        }).then( result => {
            if (result.isSuccess) {
                this.showToastMessage(
                    'Success',
                    'You\'ve successfully generated file to get NINO',
                    'success'
                );
            } else {
                this.showToastMessage(
                    'Error',
                    result.errorMessage,
                    'error'
                );
            }
            this.showSpinner = !this.showSpinner;
        }).catch(error=> {
            this.showSpinner = !this.showSpinner;
            this.showToastMessage(
                'Error',
                'You have error when generated files: ' + error.body.message,
                'error'
            );
        });
    }

    copyInfo(dataOfCopy) {
        const input = document.createElement("textarea");
        document.body.appendChild(input);
        input.select();
        if(navigator.clipboard){
            copy(dataOfCopy);
            this.showToastMessage(
                'Success',
                'You copied the data',
                'success'
            );
        } else {
            this.showToastMessage(
                'Error',
                'You didn\'t copy the data',
                'error'
            );
        }
        document.body.removeChild(input);
    }
}

export const copy = async textToCopy =>
    await navigator.clipboard.writeText(textToCopy)
                             .catch(err =>
                                console.error(JSON.stringify(err)),
                                err => console.error(JSON.stringify(err)
                                )
                            );
/* eslint-disable guard-for-in */
/* eslint-disable no-new */
/* eslint-disable no-return-await */
import { LightningElement, track, api} from 'lwc';
import getApplications from '@salesforce/apex/HMRCStatusCheckController.getRepeatedApps';
import updateCurrentApplication from '@salesforce/apex/HMRCStatusCheckController.updateCurrentApplication';
import { NavigationMixin } from "lightning/navigation";
import APPLICATION_OBJECT from '@salesforce/schema/Application__c';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import ChartJs from '@salesforce/resourceUrl/ChartJs';
import { loadScript } from 'c/resourceLoader';

export default class HmrcStatusCheck extends NavigationMixin(LightningElement) {
    apps = [];
    @api repeatType = [];
    @api amount = [];
    @track isChartJsInitialized = false;

    connectedCallback() {
        this.getRecords();
    }

    renderedCallback() {

    }

    async getRecords() {
        await getApplications()
        .then(result => {
            this.apps = JSON.parse(JSON.stringify(result?.repeatedApps));
            this.totalSummary = JSON.parse(JSON.stringify(result?.totalData));
            for (let i in result?.totalData) {
                this.repeatType.push(i);
                this.amount.push(result?.totalData[i]);
            }

            if (this.isChartJsInitialized) {
                return;
            }
            this.isChartJsInitialized = true;
            Promise.all([
                loadScript(this, ChartJs)
            ]).then(() => {
            // Chart.js library loaded
                this.initializePieChart();
            })
            .catch(error => {
                console.log('Error loading Chart.js');
                console.error(error);
            });
        }).catch(error => {
            console.error(error);
        })
    }

    navigateToRecord(event) {
        let appId = event.currentTarget.getAttribute("value");
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId:appId,
                objectApiName: APPLICATION_OBJECT.Application__c,
                actionName: 'view'
            }
        });
    }

    get options() {
        return [
            { label: 'Client', value: 'Client' },
            { label: 'Agent', value: 'Agent' },
            { label: 'Both', value: 'Both' },
        ];
    }

    copyClient(event) {
        let copyButtonType = event.target.dataset.id;
        let appRecordId = event.target.closest("tr").dataset.id;
        let currApp = this.apps.find(app => app.Id === appRecordId);
        let messageBody;
        if (copyButtonType === 'CopyClient') {
            messageBody = 'Hi - did you receive a CF83 for our client and did you send a reply to us? Client' +
                           (currApp.National_Insurance_Number__c ? ' NINO = ' + currApp.National_Insurance_Number__c : '') +
                           (currApp.Date_Of_Birth__c ? ' DOB = ' + currApp.Date_Of_Birth__c : '') +
                          ' Name = ' + currApp.First_Name__c + ' ' + currApp.Second_Name__c +
                          ' Addr = ' +  currApp.Full_Current_Address_Abroad__c.replaceAll('<br>', ' ') +
                          ' Tel = ' +  currApp.Related_Contact_Phone__c;
        } else if (copyButtonType === 'CopyAgent') {
            messageBody = 'Agent = JGBA Ltd, Suite 2/11 Pure Offices, 1 Ainslie Road, Hillington, Glasgow G52 4RU - Tel 0141 301 1480 (Previous address Suite 1/31 Pure Offices)';
        }
        if (messageBody) this.copyInfo(messageBody);
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

    showToastMessage(titleData, messageInfo, toastVariant) {
        this.dispatchEvent(new ShowToastEvent({
            title: titleData,
            message: messageInfo,
            variant: toastVariant,
        }));
    }

    handleCheckboxClick(event) {
        event.preventDefault();
        let fieldName = event.target.dataset.id;
        let appRecordId = event.target.closest("tr").dataset.id;
        let currValue = event.target.checked;
        this.updateApplication({
            "fieldName" : fieldName,
            "newFieldValue" : currValue,
            "appId" : appRecordId
        });
    }

    async updateApplication(dataForUpdate) {
        await updateCurrentApplication({
            inputData : dataForUpdate
        }).then(result => {
            if (result.isError) {
                this.showToastMessage(
                    'Error',
                    result.errorMessage,
                    'error'
                );
            } else if (result.isSuccess) {
                this.showToastMessage(
                    'Success',
                    'Applicaitons was updated',
                    'success'
                );
            }
        }).catch(error => {
            this.showToastMessage(
                'Error',
                error.body.message,
                'error'
            );
        })
    }

    handleClick(event) {
        event.preventDefault();
        let fieldName = event.target.dataset.id;
        let appRecordId = event.target.closest("tr").dataset.id;
        let currValue = event.target.value;
        this.updateApplication({
            "fieldName" : fieldName,
            "newFieldValue" : currValue,
            "appId" : appRecordId
        });
    }

    initializePieChart() {
        const ctx = this.template.querySelector('canvas').getContext('2d');
        new window.Chart(ctx, {
            type: 'horizontalBar',
            data: {
                labels: this.repeatType,
                datasets: [{
                    data: this.amount,
                    fill: false,
                    backgroundColor: this.generateRandomColors(this.repeatType)
                }]
            },
            options: {
                legend: {
                    display: false
                },
                responsive: true,
                maintainAspectRatio: false,
            },
        });
    }

    generateRandomColors(names) {
        let randomBackgroundColor = [];
        let usedColors = new Set();

        let dynamicColors = function() {
            let r = Math.floor(Math.random() * 255);
            let g = Math.floor(Math.random() * 255);
            let b = Math.floor(Math.random() * 255);
            let color = "rgb(" + r + "," + g + "," + b + ")";

            if (!usedColors.has(color)) {
                usedColors.add(color);
                return color;
            } else {
                return dynamicColors();
            }
        };

        for (let i in names) {
            randomBackgroundColor.push(dynamicColors());
        }
        return randomBackgroundColor;
    }
}

export const copy = async textToCopy =>
    await navigator.clipboard.writeText(textToCopy)
                             .catch(err =>
                                console.error(JSON.stringify(err)),
                                err => console.error(JSON.stringify(err)
                                )
                            );
import { LightningElement, track, api } from 'lwc';
import ChartJs from '@salesforce/resourceUrl/ChartJs';
import { loadScript } from 'c/resourceLoader';

export default class PieChart extends LightningElement {
    @track isChartJsInitialized = false;
    @api saleData;

    renderedCallback() {
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
    }

    initializePieChart() {

        let dayName = [];
        let dayAmount = [];
        this.saleData.map(dateInfo => {
            dayName.push(dateInfo.dateName);
            dayAmount.push(dateInfo.amount);
        });
        const ctx = this.template.querySelector('canvas').getContext('2d');
        new window.Chart(ctx, {
            type: 'bar',
            data: {
                labels: dayName,
                datasets: [{
                    data: dayAmount,
                    backgroundColor: this.generateRandomColors(dayName)
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
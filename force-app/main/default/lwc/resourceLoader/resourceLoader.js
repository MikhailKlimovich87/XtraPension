import { LightningElement } from 'lwc';

export default class ResourceLoader extends LightningElement {
}

export function loadScript(ctx, url) {
    return new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = url;
        script.charset = 'utf-8';
        script.type = 'text/javascript';
        document.head.appendChild(script);
        script.addEventListener('load', resolve);
        script.addEventListener('error', reject);
    });
}
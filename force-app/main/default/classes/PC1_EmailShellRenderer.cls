/**
 * PC1_EmailShellRenderer — wraps rendered "Simple" content in the XtraPension
 * HTML email shell (PC1_Email_Shell static resource).
 *
 * Pipeline for Content_Mode__c = Simple:
 *   1. Render {{Token}} merges against Content_Text__c (dispatcher-side).
 *   2. simpleToHtml(): escape HTML, convert **bold** → <strong>, blank lines
 *      → paragraph breaks (<p>).
 *   3. Load PC1_Email_Shell body from StaticResource cache, replace the
 *      literal placeholder `{{__CONTENT__}}` with the HTML from step 2, and
 *      resolve footer tokens ({{XPPhone}}, {{XPEmail}}, {{XPWhatsApp}},
 *      {{XPOffice}}) from PC1_Config__c.
 *
 * Kept as a thin static helper so PC1_MessageDispatcher can call it inline
 * without any additional SOQL contention (StaticResource read is one SOQL
 * per queueable run — cached in memory across templates in the same run).
 */
public with sharing class PC1_EmailShellRenderer {

    public static final String SHELL_RESOURCE_NAME = 'PC1_Email_Shell';
    public static final String CONTENT_PLACEHOLDER = '{{__CONTENT__}}';

    // Fallback constants — used when PC1_Config__c org-default row is missing
    // fields. Kept in sync with the values Fernando published on the marketing
    // site so at least a placeholder shows, never a raw {{XPPhone}} token.
    private static final String FALLBACK_PHONE    = '+353 1 254 4116';
    private static final String FALLBACK_EMAIL    = 'clients@xtrapension.com';
    private static final String FALLBACK_WHATSAPP = '+353 87 123 4567';
    private static final String FALLBACK_OFFICE   = 'Cork, Ireland';

    // In-memory cache of the shell body so a single dispatcher run over N
    // templates only pays one StaticResource SOQL.
    private static String cachedShell;

    /**
     * Take already-merged simple text and produce the full XtraPension HTML
     * email ready for Messaging.SingleEmailMessage.setHtmlBody.
     */
    public static String wrap(String mergedContentText) {
        String content = simpleToHtml(mergedContentText == null ? '' : mergedContentText);
        String shell = loadShell();
        if (String.isBlank(shell)) {
            // Belt-and-suspenders: shell missing → return the content with a
            // minimal wrapper so the message still delivers.
            return '<html><body style="font-family:Helvetica,Arial,sans-serif;padding:16px;">'
                 + content + '</body></html>';
        }
        String out = shell.replace(CONTENT_PLACEHOLDER, content);
        Map<String, String> footer = footerValues();
        for (String key : footer.keySet()) {
            out = out.replace('{{' + key + '}}', footer.get(key));
        }
        return out;
    }

    /**
     * Public so PC1_MessageTemplateController.getMergeSchema-fed preview can
     * show admins the *exact* transformation before save.
     *
     * 2026-08-25 (Fernando): auto-detect HTML vs legacy markdown so the
     * pc1MessageTemplates LWC can move from `<textarea>` (plain text with
     * **bold** markdown syntax) to `<lightning-input-rich-text>` (WYSIWYG
     * that emits HTML directly). Detection heuristic: any occurrence of an
     * HTML tag (opening tag with alpha name) means the content is already
     * rendered rich text. In that case we ONLY strip the outer <p> that
     * lightning-input-rich-text always wraps content in (so callers pasting
     * unwrapped rich text OR wrapped rich text both work) — no escape, no
     * markdown pass. Merge tokens (&#123;&#123;FirstName&#125;&#125;) render
     * intact either way; the dispatcher's `resolve()` call did that already
     * before we get here.
     *
     * Backward compat: existing Content_Text__c rows without HTML tags still
     * fall through the escape + `**bold**` → `<strong>` + paragraph pipeline
     * exactly as before. No data migration needed.
     */
    public static String simpleToHtml(String src) {
        if (String.isBlank(src)) return '';
        String s = src.replace('\r\n', '\n').replace('\r', '\n');

        if (looksLikeHtml(s)) {
            // Already-rich content from the LWC's lightning-input-rich-text.
            // No escape, no markdown replacement — trust the widget's output
            // and just hand it back for the shell wrapper. We DO however
            // strip zero-width-space runs that Quill (the widget's engine)
            // sometimes inserts in empty paragraphs, and strip inline
            // background/color styles that pasting from Word leaks in.
            String out = s;
            out = out.replaceAll('style="[^"]*background[^"]*"', '');
            out = out.replaceAll('style="[^"]*color[^"]*"', '');
            out = out.replaceAll('​', '');
            return out;
        }

        // Legacy path — treat as plain text with **bold** markdown.
        // HTML-escape first so **bold** markers don't accidentally straddle
        // an escaped entity.
        s = s.replace('&', '&amp;')
             .replace('<', '&lt;')
             .replace('>', '&gt;');

        // **bold** → <strong>bold</strong> (non-greedy, single-line matches).
        Pattern boldP = Pattern.compile('\\*\\*([^*\\n]+)\\*\\*');
        Matcher bm = boldP.matcher(s);
        String woven = '';
        Integer last = 0;
        while (bm.find()) {
            woven += s.substring(last, bm.start());
            woven += '<strong>' + bm.group(1) + '</strong>';
            last = bm.end();
        }
        woven += s.substring(last);
        s = woven;

        // Split into paragraphs on 2+ newlines. Within a paragraph, single
        // newlines become <br/> so bullet-list-style text visually survives.
        List<String> paras = new List<String>();
        for (String block : s.split('\\n{2,}')) {
            String trimmed = block.trim();
            if (String.isBlank(trimmed)) continue;
            paras.add('<p style="margin:0 0 12px 0;">' + trimmed.replace('\n', '<br/>') + '</p>');
        }
        return String.join(paras, '');
    }

    /**
     * True when the string contains at least one HTML opening tag with an
     * alphabetic tag name. Loose on purpose — we're distinguishing rich text
     * from markdown, not sanitising, so `<p>` `<b>` `<div>` `<ul>` all count.
     * A merge token `{{FirstName}}` doesn't match. A stray `<` in plain text
     * (rare) will misclassify, but the widget always wraps content in `<p>`
     * or similar so real rich text is unambiguous.
     */
    @TestVisible
    private static Boolean looksLikeHtml(String s) {
        if (String.isBlank(s)) return false;
        return Pattern.compile('<[a-zA-Z][a-zA-Z0-9]*[\\s/>]').matcher(s).find();
    }

    // ── helpers ─────────────────────────────────────────────────────

    private static String loadShell() {
        if (cachedShell != null) return cachedShell;
        for (StaticResource sr : [
            SELECT Body FROM StaticResource
             WHERE Name = :SHELL_RESOURCE_NAME LIMIT 1
        ]) {
            cachedShell = sr.Body != null ? sr.Body.toString() : '';
            return cachedShell;
        }
        cachedShell = '';
        return cachedShell;
    }

    private static Map<String, String> footerValues() {
        Map<String, String> m = new Map<String, String>();
        PC1_Config__c cfg = PC1_Config__c.getOrgDefaults();
        m.put('XPPhone',    coalesce(cfg == null ? null : cfg.XP_Phone__c,    FALLBACK_PHONE));
        m.put('XPEmail',    coalesce(cfg == null ? null : cfg.XP_Email__c,    FALLBACK_EMAIL));
        m.put('XPWhatsApp', coalesce(cfg == null ? null : cfg.XP_WhatsApp__c, FALLBACK_WHATSAPP));
        m.put('XPOffice',   coalesce(cfg == null ? null : cfg.XP_Office__c,   FALLBACK_OFFICE));
        return m;
    }

    private static String coalesce(String v, String fallback) {
        return String.isBlank(v) ? fallback : v;
    }
}
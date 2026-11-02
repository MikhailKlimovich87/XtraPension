import { LightningElement, track } from 'lwc';

// Flat emoji list with keywords for search. Categorised via a second array
// so category tabs still work. Curated to Unicode ≤ 12 (Windows Segoe UI
// Emoji reliable).
const EMOJIS = [
    // Smileys
    { c:'😀', k:'grin smile happy face', cat:0 }, { c:'😃', k:'smile happy grin face', cat:0 }, { c:'😄', k:'smile happy grin joy face', cat:0 },
    { c:'😁', k:'grin beam happy', cat:0 }, { c:'😆', k:'laugh haha happy', cat:0 }, { c:'😅', k:'sweat laugh happy', cat:0 },
    { c:'😂', k:'laugh cry tears joy funny', cat:0 }, { c:'🤣', k:'rofl laugh floor funny', cat:0 }, { c:'😊', k:'smile blush happy', cat:0 },
    { c:'☺️', k:'smile relaxed', cat:0 }, { c:'🙂', k:'smile slight face', cat:0 }, { c:'🙃', k:'upside down smile', cat:0 },
    { c:'😉', k:'wink smile flirt', cat:0 }, { c:'😌', k:'relieved calm smile', cat:0 }, { c:'😍', k:'love hearts heart eyes', cat:0 },
    { c:'😘', k:'kiss blow', cat:0 }, { c:'😗', k:'kiss face', cat:0 }, { c:'😙', k:'kiss smile', cat:0 }, { c:'😚', k:'kiss closed', cat:0 },
    { c:'😋', k:'yum tasty tongue', cat:0 }, { c:'😛', k:'tongue', cat:0 }, { c:'😝', k:'tongue closed eyes', cat:0 }, { c:'😜', k:'tongue wink', cat:0 },
    { c:'🤪', k:'crazy zany silly', cat:0 }, { c:'🤨', k:'raised eyebrow suspicious', cat:0 }, { c:'🧐', k:'monocle inspect', cat:0 },
    { c:'🤓', k:'nerd glasses', cat:0 }, { c:'😎', k:'cool sunglasses', cat:0 }, { c:'😏', k:'smirk sly', cat:0 },
    { c:'😒', k:'unamused annoyed', cat:0 }, { c:'😞', k:'sad disappointed', cat:0 }, { c:'😔', k:'sad pensive', cat:0 },
    { c:'😟', k:'worried', cat:0 }, { c:'😕', k:'confused', cat:0 }, { c:'🙁', k:'frown sad', cat:0 }, { c:'☹️', k:'frown very sad', cat:0 },
    { c:'😣', k:'persevere struggle', cat:0 }, { c:'😖', k:'confounded', cat:0 }, { c:'😫', k:'tired', cat:0 }, { c:'😩', k:'weary tired', cat:0 },
    { c:'😢', k:'cry tear sad', cat:0 }, { c:'😭', k:'loud cry sob', cat:0 }, { c:'😤', k:'huff steam nose', cat:0 },
    { c:'😠', k:'angry mad', cat:0 }, { c:'😡', k:'pout rage angry', cat:0 }, { c:'🤬', k:'swear cursing angry', cat:0 },
    { c:'🤯', k:'shocked mind blown', cat:0 }, { c:'😳', k:'flushed embarrassed', cat:0 }, { c:'😱', k:'scream shock scared', cat:0 },
    { c:'😨', k:'fear scared', cat:0 }, { c:'😰', k:'sweat anxious', cat:0 }, { c:'😥', k:'sad disappointed relieved', cat:0 },
    { c:'😓', k:'sweat downcast', cat:0 }, { c:'🤗', k:'hug hugging', cat:0 }, { c:'🤔', k:'thinking hmm think', cat:0 },
    { c:'🤭', k:'shh giggle hand mouth', cat:0 }, { c:'🤫', k:'shh quiet silence', cat:0 }, { c:'🤥', k:'lying pinocchio', cat:0 },
    { c:'😶', k:'no mouth silent', cat:0 }, { c:'😐', k:'neutral face', cat:0 }, { c:'😑', k:'expressionless', cat:0 },
    { c:'😬', k:'grimace teeth', cat:0 }, { c:'🙄', k:'eye roll', cat:0 }, { c:'😴', k:'sleep zzz', cat:0 },
    { c:'😪', k:'sleepy tired', cat:0 }, { c:'😵', k:'dizzy', cat:0 }, { c:'🤤', k:'drool', cat:0 },
    { c:'🤢', k:'nauseated sick', cat:0 }, { c:'🤮', k:'vomit sick', cat:0 }, { c:'🤧', k:'sneeze sick', cat:0 },
    { c:'😷', k:'mask sick face', cat:0 }, { c:'🤒', k:'sick thermometer fever', cat:0 }, { c:'🤕', k:'hurt injured', cat:0 },
    { c:'🤑', k:'money mouth', cat:0 }, { c:'🤠', k:'cowboy', cat:0 }, { c:'👻', k:'ghost boo', cat:0 },
    { c:'💀', k:'skull death', cat:0 }, { c:'👽', k:'alien', cat:0 }, { c:'🤖', k:'robot bot', cat:0 },
    // Gestures / people
    { c:'👍', k:'thumbs up like ok good yes', cat:1 }, { c:'👎', k:'thumbs down dislike bad no', cat:1 },
    { c:'👌', k:'ok hand perfect', cat:1 }, { c:'✌️', k:'peace victory', cat:1 }, { c:'🤞', k:'fingers crossed', cat:1 },
    { c:'🤟', k:'love you sign', cat:1 }, { c:'🤘', k:'rock horns', cat:1 }, { c:'🤙', k:'call me hang loose', cat:1 },
    { c:'👈', k:'point left', cat:1 }, { c:'👉', k:'point right', cat:1 }, { c:'👆', k:'point up', cat:1 }, { c:'👇', k:'point down', cat:1 },
    { c:'☝️', k:'index finger one', cat:1 }, { c:'✋', k:'raised hand stop high five', cat:1 }, { c:'🤚', k:'back of hand', cat:1 },
    { c:'🖐️', k:'hand five', cat:1 }, { c:'🖖', k:'vulcan spock', cat:1 }, { c:'👋', k:'wave hello hi bye', cat:1 },
    { c:'🤝', k:'handshake deal', cat:1 }, { c:'👏', k:'clap applause', cat:1 }, { c:'🙌', k:'raised hands celebrate', cat:1 },
    { c:'🙏', k:'pray thanks please', cat:1 }, { c:'💪', k:'muscle strong flex', cat:1 },
    { c:'👀', k:'eyes look see', cat:1 }, { c:'👶', k:'baby', cat:1 }, { c:'👦', k:'boy', cat:1 }, { c:'👧', k:'girl', cat:1 },
    { c:'👨', k:'man', cat:1 }, { c:'👩', k:'woman', cat:1 }, { c:'🧑', k:'person', cat:1 },
    { c:'👴', k:'old man', cat:1 }, { c:'👵', k:'old woman grandma', cat:1 },
    // Hearts
    { c:'❤️', k:'heart love red', cat:2 }, { c:'🧡', k:'orange heart', cat:2 }, { c:'💛', k:'yellow heart', cat:2 },
    { c:'💚', k:'green heart', cat:2 }, { c:'💙', k:'blue heart', cat:2 }, { c:'💜', k:'purple heart', cat:2 },
    { c:'🖤', k:'black heart', cat:2 }, { c:'🤍', k:'white heart', cat:2 }, { c:'🤎', k:'brown heart', cat:2 },
    { c:'💔', k:'broken heart', cat:2 }, { c:'❣️', k:'heart exclamation', cat:2 }, { c:'💕', k:'two hearts', cat:2 },
    { c:'💞', k:'revolving hearts', cat:2 }, { c:'💓', k:'beating heart', cat:2 }, { c:'💗', k:'growing heart', cat:2 },
    { c:'💖', k:'sparkling heart', cat:2 }, { c:'💘', k:'cupid arrow heart', cat:2 }, { c:'💝', k:'heart ribbon gift', cat:2 },
    { c:'💌', k:'love letter', cat:2 },
    // Objects
    { c:'📞', k:'phone call', cat:3 }, { c:'📱', k:'mobile phone cell', cat:3 }, { c:'💻', k:'laptop computer', cat:3 },
    { c:'⌨️', k:'keyboard', cat:3 }, { c:'🖥️', k:'desktop computer', cat:3 }, { c:'🖨️', k:'printer', cat:3 },
    { c:'📷', k:'camera', cat:3 }, { c:'📸', k:'camera flash', cat:3 }, { c:'📹', k:'video camera', cat:3 },
    { c:'📺', k:'tv television', cat:3 }, { c:'☎️', k:'telephone', cat:3 },
    { c:'⏰', k:'alarm clock time', cat:3 }, { c:'⌚', k:'watch time', cat:3 },
    { c:'📅', k:'calendar date', cat:3 }, { c:'📆', k:'calendar', cat:3 }, { c:'🗓️', k:'calendar spiral', cat:3 },
    { c:'📎', k:'paperclip attach file', cat:3 }, { c:'📌', k:'pushpin pin', cat:3 }, { c:'📍', k:'location pin', cat:3 },
    { c:'✂️', k:'scissors cut', cat:3 }, { c:'🔒', k:'lock closed', cat:3 }, { c:'🔓', k:'lock open', cat:3 }, { c:'🔑', k:'key', cat:3 },
    { c:'🔧', k:'wrench tool fix', cat:3 }, { c:'🔨', k:'hammer tool', cat:3 }, { c:'⚙️', k:'gear settings', cat:3 },
    { c:'⚡', k:'lightning bolt', cat:3 }, { c:'💡', k:'lightbulb idea', cat:3 }, { c:'🔋', k:'battery', cat:3 }, { c:'🔌', k:'plug electric', cat:3 },
    { c:'💸', k:'money flying', cat:3 }, { c:'💰', k:'money bag cash', cat:3 }, { c:'💳', k:'credit card', cat:3 },
    { c:'🧾', k:'receipt', cat:3 }, { c:'📝', k:'memo note write', cat:3 }, { c:'✏️', k:'pencil write edit', cat:3 },
    { c:'📁', k:'folder file', cat:3 }, { c:'📂', k:'folder open', cat:3 },
    { c:'📄', k:'document page paper', cat:3 }, { c:'📃', k:'page curl', cat:3 }, { c:'📑', k:'bookmark tabs', cat:3 },
    { c:'📊', k:'bar chart', cat:3 }, { c:'📈', k:'chart up increase', cat:3 }, { c:'📉', k:'chart down decrease', cat:3 },
    { c:'📚', k:'books', cat:3 }, { c:'📖', k:'book open', cat:3 },
    { c:'🎁', k:'gift present', cat:3 }, { c:'🎉', k:'party popper celebrate', cat:3 }, { c:'🎊', k:'confetti party', cat:3 },
    // Signs
    { c:'✅', k:'check mark yes done', cat:4 }, { c:'❌', k:'cross no wrong', cat:4 }, { c:'❗', k:'exclamation important', cat:4 },
    { c:'❓', k:'question', cat:4 }, { c:'⚠️', k:'warning caution', cat:4 }, { c:'🚫', k:'prohibited banned', cat:4 },
    { c:'🔴', k:'red circle', cat:4 }, { c:'🟠', k:'orange circle', cat:4 }, { c:'🟡', k:'yellow circle', cat:4 },
    { c:'🟢', k:'green circle', cat:4 }, { c:'🔵', k:'blue circle', cat:4 },
    { c:'⭐', k:'star', cat:4 }, { c:'🌟', k:'glowing star', cat:4 }, { c:'💯', k:'100 hundred perfect', cat:4 },
    { c:'✔️', k:'checkmark', cat:4 }, { c:'✖️', k:'multiply x', cat:4 },
    { c:'🔔', k:'bell notification', cat:4 }, { c:'🔕', k:'bell mute', cat:4 },
    // Nature
    { c:'🌞', k:'sun face', cat:5 }, { c:'🌝', k:'full moon face', cat:5 },
    { c:'☀️', k:'sun sunny', cat:5 }, { c:'🌤️', k:'sun small cloud', cat:5 }, { c:'⛅', k:'sun cloud', cat:5 },
    { c:'🌧️', k:'rain cloud', cat:5 }, { c:'⛈️', k:'thunderstorm rain', cat:5 }, { c:'❄️', k:'snowflake cold', cat:5 },
    { c:'☃️', k:'snowman', cat:5 }, { c:'⛄', k:'snowman no snow', cat:5 },
    { c:'🌈', k:'rainbow', cat:5 }, { c:'☔', k:'umbrella rain', cat:5 }, { c:'💧', k:'water droplet', cat:5 },
    { c:'🌊', k:'wave ocean water', cat:5 }, { c:'🔥', k:'fire hot flame', cat:5 }, { c:'✨', k:'sparkles', cat:5 },
    { c:'🌸', k:'cherry blossom flower', cat:5 }, { c:'🌺', k:'hibiscus flower', cat:5 }, { c:'🌻', k:'sunflower flower', cat:5 },
    { c:'🌷', k:'tulip flower', cat:5 }, { c:'🌹', k:'rose flower', cat:5 }, { c:'🍀', k:'four leaf clover lucky', cat:5 },
    // Food
    { c:'🍎', k:'apple red fruit', cat:6 }, { c:'🍐', k:'pear fruit', cat:6 }, { c:'🍊', k:'orange fruit', cat:6 },
    { c:'🍋', k:'lemon fruit', cat:6 }, { c:'🍌', k:'banana fruit', cat:6 }, { c:'🍉', k:'watermelon fruit', cat:6 },
    { c:'🍇', k:'grapes fruit', cat:6 }, { c:'🍓', k:'strawberry fruit', cat:6 }, { c:'🍒', k:'cherry fruit', cat:6 },
    { c:'🍑', k:'peach fruit', cat:6 }, { c:'🥝', k:'kiwi fruit', cat:6 }, { c:'🍅', k:'tomato', cat:6 },
    { c:'🥑', k:'avocado', cat:6 }, { c:'🥕', k:'carrot', cat:6 }, { c:'🍞', k:'bread loaf', cat:6 },
    { c:'🧀', k:'cheese', cat:6 }, { c:'🥚', k:'egg', cat:6 }, { c:'🍔', k:'hamburger burger', cat:6 },
    { c:'🍟', k:'fries french', cat:6 }, { c:'🍕', k:'pizza', cat:6 }, { c:'🌭', k:'hot dog', cat:6 },
    { c:'🍿', k:'popcorn', cat:6 }, { c:'🍦', k:'ice cream soft', cat:6 }, { c:'🍩', k:'donut doughnut', cat:6 },
    { c:'🍪', k:'cookie biscuit', cat:6 }, { c:'🎂', k:'birthday cake', cat:6 }, { c:'🍰', k:'cake slice', cat:6 },
    { c:'🍫', k:'chocolate bar', cat:6 }, { c:'☕', k:'coffee hot drink', cat:6 }, { c:'🍵', k:'tea', cat:6 },
    { c:'🍺', k:'beer', cat:6 }, { c:'🍷', k:'wine glass', cat:6 }, { c:'🥂', k:'champagne cheers', cat:6 },
];
const CATEGORIES = [
    { icon: '😀', label: 'Smileys' },
    { icon: '👋', label: 'People' },
    { icon: '❤️', label: 'Hearts' },
    { icon: '📎', label: 'Objects' },
    { icon: '✅', label: 'Signs' },
    { icon: '🌤️', label: 'Nature' },
    { icon: '🍕', label: 'Food' },
];

export default class AaEmojiPicker extends LightningElement {
    @track activeIdx = 0;
    @track query = '';

    get categories() {
        return CATEGORIES.map((c, i) => ({
            key: c.label,
            icon: c.icon,
            label: c.label,
            btnCls: 'aa-ep__cat' + (i === this.activeIdx && !this.query ? ' is-active' : ''),
            i,
        }));
    }
    get visibleEmojis() {
        if (this.query) {
            const q = this.query.trim().toLowerCase();
            if (!q) return [];
            return EMOJIS.filter(e => e.k.includes(q)).map((e, i) => ({ key: `q-${i}`, char: e.c }));
        }
        return EMOJIS.filter(e => e.cat === this.activeIdx).map((e, i) => ({ key: `${this.activeIdx}-${i}`, char: e.c }));
    }
    get hasResults() { return this.visibleEmojis.length > 0; }
    handleCat(e) {
        this.activeIdx = Number(e.currentTarget.dataset.i);
        this.query = '';
    }
    handleSearch(e) { this.query = e.target.value; }
    handlePick(e) {
        const char = e.currentTarget.dataset.char;
        this.dispatchEvent(new CustomEvent('pick', { detail: { char } }));
    }
    handleClose() { this.dispatchEvent(new CustomEvent('close')); }
    connectedCallback() {
        this._esc = (e) => { if (e.key === 'Escape') this.handleClose(); };
        window.addEventListener('keydown', this._esc);
    }
    disconnectedCallback() {
        if (this._esc) window.removeEventListener('keydown', this._esc);
    }
}
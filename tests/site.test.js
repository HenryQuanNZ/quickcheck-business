const fs = require('fs');
const path = require('path');
const { JSDOM, VirtualConsole } = require('jsdom');

const html = fs.readFileSync(path.join(__dirname, '..', 'site', 'index.html'), 'utf8');

let navigationAttempted = false;
const vc = new VirtualConsole();
vc.on('jsdomError', (e) => {
  if (String(e.message).includes('navigation')) navigationAttempted = true;
});

const dom = new JSDOM(html, {
  runScripts: 'dangerously', pretendToBeVisual: true, virtualConsole: vc,
  beforeParse(window) {
    window.matchMedia = (q) => ({ matches: false, media: q, addListener(){}, removeListener(){} });
    Object.defineProperty(window.navigator, 'clipboard', {
      value: { writeText: (t) => { window.__clipboard = t; return Promise.resolve(); } }
    });
  }
});
const { window } = dom;
const { document } = window;

let pass = 0, fail = 0;
function check(name, cond, extra) {
  if (cond) { pass++; console.log('PASS  ' + name); }
  else { fail++; console.log('FAIL  ' + name + (extra ? ' — ' + extra : '')); }
}
const hasCJK = s => /[\u4e00-\u9fff]/.test(s);

/* ---------- regression: anchors ---------- */
[...document.querySelectorAll('a[href^="#"]')]
  .filter(a => a.getAttribute('href') !== '#')
  .forEach(a => {
    const id = a.getAttribute('href').slice(1);
    check(`anchor -> #${id} target exists`, !!document.getElementById(id));
  });
check('direct email link is mailto:', document.getElementById('emailLink').href.startsWith('mailto:'));

/* ---------- i18n: key parity (no element left untranslated) ---------- */
const qc = window.__quickcheck;
['en','zh'].forEach(lang => {
  qc.applyLang(lang);
  const empty = [...document.querySelectorAll('[data-i18n]')]
    .filter(el => el.innerHTML.trim() === '')
    .map(el => el.getAttribute('data-i18n'));
  check(`[${lang}] every data-i18n element has content`, empty.length === 0, 'missing: ' + empty.join(','));
  const emptyPh = [...document.querySelectorAll('[data-i18n-ph]')]
    .filter(el => !el.getAttribute('placeholder'))
    .map(el => el.getAttribute('data-i18n-ph'));
  check(`[${lang}] every placeholder is set`, emptyPh.length === 0, 'missing: ' + emptyPh.join(','));
});

/* ---------- i18n: toggle button behaviour ---------- */
qc.applyLang('en');
const langBtn = document.getElementById('langBtn');
const svcH2 = document.querySelector('#services h2');
check('initial language is English', qc.getLang() === 'en' && !hasCJK(svcH2.textContent));
check('toggle button offers 中文 when in English', langBtn.textContent === '中文');

langBtn.click();
check('clicking toggle switches to Chinese', qc.getLang() === 'zh');
check('html lang attribute updates to zh', document.documentElement.getAttribute('lang') === 'zh');
check('section heading renders in Chinese', hasCJK(svcH2.textContent), `got "${svcH2.textContent}"`);
check('toggle button offers EN when in Chinese', langBtn.textContent === 'EN');
check('page title switches to Chinese', hasCJK(document.title));

langBtn.click();
check('clicking toggle again restores English', qc.getLang() === 'en' && !hasCJK(svcH2.textContent));

/* ---------- regression: tier buttons (values now language-independent) ---------- */
const sel = document.getElementById('f-tier');
[...document.querySelectorAll('[data-tier]')].forEach(btn => {
  sel.value = 'Not sure — recommend one for me'; // reset to avoid false pass
  btn.click();
  const want = btn.getAttribute('data-tier');
  check(`tier button "${want}" sets dropdown`, sel.value === want, `dropdown="${sel.value}"`);
});

/* ---------- tier value stays English even in Chinese UI ---------- */
qc.applyLang('zh');
sel.value = 'Deep Check ($15)';
check('dropdown option labels show Chinese', hasCJK(sel.options[sel.selectedIndex].text));
check('dropdown VALUE stays English (stable for email)', sel.value === 'Deep Check ($15)');

/* ---------- buildBody in both languages ---------- */
document.getElementById('f-url').value = 'https://example.co.nz';
document.getElementById('f-focus').value = '手机端支付有问题';
document.getElementById('f-name').value = '王太太';
const zhBody = qc.buildBody();
check('zh request body uses Chinese template', zhBody.includes('我想预约一次网站检测'));
check('zh request body keeps English service value', zhBody.includes('Deep Check ($15)'));
check('zh request body includes user inputs', zhBody.includes('https://example.co.nz') && zhBody.includes('王太太'));

qc.applyLang('en');
const enBody = qc.buildBody();
check('en request body uses English template', enBody.includes('request a website check'));
check('empty-field fallbacks still work', (() => {
  document.getElementById('f-url').value = '';
  const b = qc.buildBody();
  document.getElementById('f-url').value = 'https://example.co.nz';
  return b.includes('(no URL given)');
})());

/* ---------- FAQ ---------- */
const faqs = [...document.querySelectorAll('.faq-item')];
check('FAQ has 6 items', faqs.length === 6, `found ${faqs.length}`);
faqs.forEach((d, i) => {
  const q = d.querySelector('summary').textContent.trim();
  const a = d.querySelector('.faq-a').textContent.trim();
  check(`FAQ ${i+1} has question + answer`, q.length > 5 && a.length > 20);
});
const first = faqs[0];
check('FAQ items start collapsed', !first.open);
first.open = true;
check('FAQ item can open', first.open === true);
qc.applyLang('zh');
check('FAQ translates to Chinese', hasCJK(faqs[0].querySelector('summary').textContent));
qc.applyLang('en');

/* ---------- service terms ---------- */
const terms = [...document.querySelectorAll('.terms-list li')];
check('terms section exists', !!document.getElementById('terms'));
check('terms has 6 clauses', terms.length === 6, `found ${terms.length}`);
terms.forEach((li, i) => {
  const h = li.querySelector('strong').textContent.trim();
  const p = li.querySelector('span').textContent.trim();
  check(`term ${i+1} has heading + body`, h.length > 5 && p.length > 30);
});
check('terms ownership note present', document.querySelector('.terms-note').textContent.trim().length > 20);
qc.applyLang('zh');
check('terms translate to Chinese', hasCJK(terms[0].querySelector('strong').textContent));
qc.applyLang('en');
check('footer links to terms', !!document.querySelector('footer a[href="#terms"]'));

/* ---------- send + copy buttons ---------- */
document.getElementById('sendBtn').click();
check('send button triggers mailto navigation', navigationAttempted);
check('email placeholder still flagged for replacement', qc.email === 'hello@quickcheckqa.nz');

document.getElementById('copyBtn').click();
setTimeout(() => {
  check('copy button wrote to clipboard', typeof window.__clipboard === 'string');
  check('copied confirmation becomes visible', document.getElementById('copied').style.display === 'inline');

  setTimeout(() => {
    check('copied confirmation auto-hides', document.getElementById('copied').style.display === 'none');
    const checksEls = [...document.querySelectorAll('#testrunBody .check')];
    check('all 5 test-run lines animate in', checksEls.length === 5 && checksEls.every(c => c.classList.contains('show')));
    check('verdict line animates in', document.querySelector('.testrun-verdict').classList.contains('show'));
    console.log(`\n${pass} passed, ${fail} failed`);
    process.exit(fail ? 1 : 0);
  }, 4000);
}, 100);

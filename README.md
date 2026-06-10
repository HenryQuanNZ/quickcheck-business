# QuickCheck QA

Micro website-testing service run by a senior QA engineer in Wellington, NZ —
**and the quality pipeline that tests the business itself.**

Bilingual (EN/中文) landing page, an automated test suite covering every
interactive element on it, a pre-gig URL safety screener, and a CI/CD pipeline
that refuses to deploy the site unless its own tests pass. A testing business
should hold itself to its own standard.

## Repository structure

```
site/        index.html — single-file bilingual landing page (no build step)
tests/       site.test.js — 63-check jsdom suite (i18n parity, forms, FAQ, terms, animation)
tools/       precheck.sh — pre-gig URL safety screener (red flags, whois, TLS, VirusTotal, GSB)
docs/        接单前检查清单.md — full pre-gig operational checklist (Chinese)
.github/     ci.yml — test on every push/PR; deploy to GitHub Pages from main when green
```

## Local development

```bash
npm ci          # install jsdom (only dev dependency)
npm test        # run the 63-check suite against site/index.html
open site/index.html   # preview in a browser
```

The site is a single HTML file with zero runtime dependencies — edit, test, push.

### Test suite highlights

- **i18n key parity**: every `data-i18n` element must have content in *both*
  languages — add a string in one language and forget the other, CI fails and
  names the missing key.
- **Behavioural checks**: language toggle, tier buttons preselecting the form,
  mailto/clipboard request builders, FAQ accordion, terms section, empty-field
  fallbacks, hero animation timing.
- Dropdown *labels* are translated but *values* stay English, so incoming
  request emails have a stable format regardless of customer language —
  asserted by a dedicated test.

## Pre-gig screener

```bash
./tools/precheck.sh https://client-website.co.nz
```

Five stages: red-flag patterns (raw IPs, URL shorteners, punycode lookalikes),
whois domain age, TLS certificate, HTTP reachability/redirect-domain check,
and VirusTotal + Google Safe Browsing reputation. Exit codes: `0` clean,
`1` warnings (review manually), `2` failures (decline the gig).

Optional API keys (the script degrades to manual-check links without them):

```bash
export VT_API_KEY=...    # https://www.virustotal.com/gui/my-apikey (free)
export GSB_API_KEY=...   # https://developers.google.com/safe-browsing
```

Full operating procedure: [`docs/接单前检查清单.md`](docs/接单前检查清单.md).

## Deploying (first time)

1. Create an empty GitHub repository, then from this folder:
   ```bash
   git init && git add . && git commit -m "QuickCheck QA v1.0"
   git branch -M main
   git remote add origin git@github.com:<your-username>/quickcheck-business.git
   git push -u origin main
   ```
2. In the repo: **Settings → Pages → Source → GitHub Actions**.
3. Push to `main` (or re-run the workflow). Tests run first; the site deploys
   only if all 63 pass.
4. Before going live, replace the placeholder email `hello@quickcheckqa.nz`
   in `site/index.html` (it appears twice) with your real address.

## Before first customer — TODO

- [ ] Replace placeholder email in `site/index.html`
- [ ] Register domain and point it at GitHub Pages (Settings → Pages → Custom domain)
- [ ] Set up email forwarding for the public address
- [ ] Get a free VirusTotal API key for `precheck.sh`
- [ ] Post the offer somewhere with traffic (the site converts interest; it doesn't generate it)

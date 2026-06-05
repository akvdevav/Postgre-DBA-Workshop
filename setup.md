npm install && npm run build

> pev2@1.20.2 prepare
> husky


added 493 packages, and audited 494 packages in 5s

124 packages are looking for funding
  run `npm fund` for details

4 vulnerabilities (1 moderate, 3 high)

To address all issues, run:
  npm audit fix

Run `npm audit` for details.

> pev2@1.20.2 build
> vue-tsc --noEmit && vite build

vite v6.4.1 building for production...
✓ 1059 modules transformed.
rendering chunks (1)...

Inlining: index-DAJ_258u.js
Inlining: style-DiBVywKn.css
dist-app/index.html  1,303.76 kB │ gzip: 307.96 kB
✓ built in 2.49s
(base) avannala@Q2HWTCX6H4 pev2 %  cp -r dist-app/* ../pev-spring/src/main/resources/static/pev2/
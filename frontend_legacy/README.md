# LocalIQ — Frontend

Next.js 16 (App Router) + Tailwind CSS 4 + TypeScript.

See the root [`README.md`](../README.md) for setup and [`PLAN.md`](../PLAN.md) for the roadmap.

## Commands

```bash
npm install     # install dependencies
npm run dev     # start dev server on http://localhost:3000
npm run build   # production build
npm run start   # run the production build
npm run lint    # eslint
npm run typecheck
```

## Source layout

```
src/
├── app/          # routes, layout, global styles
├── components/   # UI (forms, results, experience, layout)
├── hooks/        # shared React hooks
├── lib/api/      # API client
├── store/        # client state
└── types/        # shared TypeScript types
```

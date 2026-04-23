---
paths: ["src/web/**", "src/components/**", "app/**", "**/*.tsx", "**/*.jsx"]
---
# Frontend rules

## Stack
- Framework: <React 19 / Next.js 15 / SvelteKit / …>
- Styling: <Tailwind / CSS modules / vanilla-extract>
- State: <TanStack Query + local state / Zustand / Redux Toolkit>
- Testing: <Vitest + Testing Library / Playwright>

## Patterns
- Components are function components with explicit props interfaces.
- No default exports for components — named exports only. Exception: page files.
- Hooks go in `src/hooks/`. One hook per file; name matches file.
- No business logic inside JSX. Extract to helpers or hooks.
- Client components explicit: top-of-file `"use client"` when needed.
- Accessibility: every interactive element needs a label. Use semantic HTML first.

## Don'ts
- No `any`. Use `unknown` + narrow, or define a proper type.
- No inline styles except dynamic values.
- No `useEffect` for deriving state from props — derive it in render.

## Where to look
- Shared UI primitives: `src/components/ui/`
- Shared hooks: `src/hooks/`
- Design tokens: `src/styles/tokens.ts`

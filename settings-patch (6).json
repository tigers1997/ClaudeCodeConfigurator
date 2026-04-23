---
paths: ["**/*.test.ts", "**/*.test.tsx", "**/*.spec.ts", "**/*.spec.tsx", "tests/**", "**/*_test.py", "test_*.py"]
---
# Testing rules

## Philosophy
- Tests describe behavior, not implementation. Assert outcomes, not internals.
- One assertion per test when practical. Group related ones with descriptive names.
- Tests run fast: < 1s each by default. Slow tests are marked and segregated.

## Structure
- Arrange / Act / Assert, separated by blank lines.
- Use data factories, not shared fixtures that mutate state.
- No sleeps. Use fake timers or explicit waits on conditions.

## Naming
- Test file sits next to the file it tests: `foo.ts` + `foo.test.ts`.
- Top-level `describe` matches the subject. Nested describes match the scenario.
- Test names read as sentences: `it("rejects requests without an auth token")`.

## Coverage
- Public API: 100%.
- Internal helpers: best-effort.
- Don't chase coverage numbers. Chase risk.

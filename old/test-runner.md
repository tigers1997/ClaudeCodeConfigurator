---
paths: ["src/api/**", "src/server/**", "**/*.controller.ts", "**/*.service.ts"]
---
# Backend rules

## Stack
- Runtime: <Node 20 / Python 3.12 / Go 1.22>
- Framework: <Fastify / Express / FastAPI / Gin>
- ORM / DB driver: <Prisma / Drizzle / SQLAlchemy / pgx>

## Structure
- Route handlers are thin: parse input → call service → shape response.
- All business logic in `services/`. Services are pure where possible.
- DB access only through `repositories/`. No raw SQL in handlers.
- Schemas / validation: <Zod / Pydantic> at every boundary (request, DB, external API).

## Error handling
- Never swallow errors. Log with structured context, rethrow or map to a typed error.
- User-facing errors go through a single `AppError` hierarchy.
- No stack traces in production response bodies.

## Security
- Never log request bodies or headers that may contain secrets.
- Rate-limit auth endpoints.
- Parameterized queries only.

## Testing
- Every service has unit tests with the DB mocked.
- Every endpoint has a contract test against a real DB (testcontainers or in-memory).

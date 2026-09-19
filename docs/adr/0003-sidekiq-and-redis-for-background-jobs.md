# 0003. Sidekiq and Redis for background jobs

- Status: Accepted
- Date: 2026-09-19
- Supersedes: ADR 0002

## Context

Facet needs background generation that survives an SSE disconnect, later memory
extraction, thread summarization, maintenance, and initiative scheduling. These
workloads benefit from an independently scalable worker pool, explicit queues,
retry/backoff, and mature operational tooling.

ADR 0002 selected PostgreSQL-backed Solid Queue to avoid another stateful
service. We are deliberately changing that decision before queue infrastructure
has been implemented: background jobs will use Sidekiq, which requires Redis.

## Decision

Application code uses Active Job as its job API and Sidekiq as the queue
adapter. Docker Compose and production run separate `web`, `worker`, and
`redis` services.

Redis has a deliberately narrow role:

- it stores Sidekiq queue, retry, schedule, and process coordination data;
- it is not the source of truth for messages, generation state, memories,
  usage, spending limits, OTP, authorization, or unread state;
- application caching, rate limiting, and SSE pub/sub are not enabled merely
  because Redis is present; each requires a measured need and its own policy;
- production Redis uses authentication and transport security where supported,
  a non-evicting memory policy, persistence appropriate for queued work, and
  monitoring for memory, latency, queue depth, retries, and dead jobs.

PostgreSQL remains authoritative. Generation progress is periodically persisted
to `Message` and `GenerationRun`; SSE reads that persisted progress so a
reconnect does not depend on transient Redis pub/sub messages.

Sidekiq provides at-least-once delivery, so every job must be idempotent.
Database constraints, run-state transitions, and locks prevent duplicate model
calls and writes. Jobs are enqueued only after the owning database transaction
commits. Where losing the interval between PostgreSQL commit and Redis enqueue
is unacceptable, the transaction writes a database outbox record and an
idempotent dispatcher publishes it to Sidekiq.

## Consequences

- Background work can scale separately from web and does not consume PostgreSQL
  connections for queue polling.
- Redis becomes required infrastructure in development, test integration,
  staging, and production.
- Operations must monitor and back up two stateful systems, although domain
  recovery continues to center on PostgreSQL.
- A Redis outage delays jobs but must not corrupt domain state. Pending runs and
  outbox records remain discoverable and can be dispatched after recovery.
- Graceful deploys must stop accepting new work and allow Sidekiq workers to
  finish or safely retry interrupted jobs.
- Regular tests use the Active Job test adapter or deterministic fakes; separate
  integration tests verify Sidekiq configuration without contacting AI APIs.

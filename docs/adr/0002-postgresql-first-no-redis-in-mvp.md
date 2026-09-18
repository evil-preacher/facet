# 0002. PostgreSQL first; no Redis in the MVP

- Status: Accepted
- Date: 2026-09-18

## Context

Facet needs durable jobs, scheduled initiative, idempotency, spending limits,
OTP throttling, SSE streaming, and eventually some caching. Redis could provide
queues, pub/sub, rate limiting, and a cache, but it would also introduce another
stateful service and failure mode before the workload is known.

## Decision

Redis is not part of the MVP. PostgreSQL remains the source of truth and is used
for transactions, uniqueness, row/advisory locks, and persisted generation
state. When background processing is introduced, it will use PostgreSQL-backed
Solid Queue. SSE sends the active response directly; `GenerationRun` and
`Message` persist enough state to recover after a reconnect.

Caching follows these rules:

- use provider prompt caching from the first AI release and record cached input
  tokens and actual cost;
- let Propshaft and browsers cache fingerprinted static assets;
- do not introduce a general application-data cache before profiling;
- never depend on an ephemeral cache for authorization, OTP validation, hard
  budget checks, messages, memories, usage, or generation state;
- cache only reconstructible derived data with a versioned tenant-aware key,
  an owner for invalidation, a TTL where appropriate, and stale-data tests;
- do not cache complete personalized prompts or responses without a separate
  privacy decision.

Potential later candidates include immutable personality-version compilation,
token counts for immutable prompt fragments, short-lived retrieval results, and
usage dashboard aggregates. Budget enforcement continues to read authoritative
records and active reservations.

## Consequences

- Docker Compose and production have fewer moving parts.
- Backup, restore, and correctness center on PostgreSQL.
- Database load and queue contention must be measured as the product grows.
- Solid Cache or a small in-process cache may be evaluated for a measured use
  case, but neither is added by default.

## Revisit criteria

Reconsider Redis only with measurements showing one or more of the following:

- Solid Queue creates unacceptable PostgreSQL contention or misses throughput
  or latency targets;
- many concurrent SSE connections require low-latency cross-process pub/sub;
- reconnect polling creates material database load;
- distributed rate limiting becomes a high-frequency hot path;
- an application cache demonstrates a valuable hit rate that justifies a
  separate in-memory datastore.

Adding Redis requires a new ADR with the measured problem, ownership, failure
behavior, persistence expectations, and a migration/rollback plan.

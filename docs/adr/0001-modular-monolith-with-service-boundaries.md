# 0001. Modular monolith with service-oriented boundaries

- Status: Accepted
- Date: 2026-09-18

## Context

Facet will contain several domains: identity, personalities, conversations, AI
integration, memories, usage, and initiative. These workflows need explicit
boundaries, but the product is at an early stage and benefits from simple
transactions, deployment, testing, and local development.

Splitting the system into networked microservices now would add distributed
transactions, API versioning, operational overhead, and slower tests before
independent scaling requirements are known.

## Decision

Facet is one deployable Rails application backed by PostgreSQL. We apply SOA
inside this modular monolith:

- domain code is grouped into `Identity`, `Personalities`, `Conversations`,
  `Ai`, `Memories`, `Usage`, and `Initiative` namespaces as those areas
  appear;
- controllers handle HTTP and delegate a use case to an application service;
- jobs handle delivery and retries and invoke the same application services;
- Active Record models own persistence and local invariants, not cross-domain
  workflows hidden in callbacks;
- services expose explicit inputs and result/error contracts and own transaction
  boundaries;
- external providers are accessed through ports such as `Ai::Gateway`;
- asynchronous workflows are idempotent and use transactional enqueue or a
  database outbox where enqueue-after-commit could lose work;
- dependencies between domains remain explicit and acyclic.

New behavior is developed with TDD in short red-green-refactor cycles. We start
from an observable feature or request spec, add focused service/model contract
tests, implement the smallest behavior, and then refactor. Bugs receive a
failing regression test before the fix. External AI calls are replaced by fakes
in the regular suite and exercised only by opt-in smoke tests.

Existing authentication code does not need a speculative rewrite. It adopts
these boundaries when a workflow is extended or its current shape causes pain.

## Consequences

- Cross-domain behavior has a named, testable entry point.
- Most tests remain fast and deterministic without network calls.
- Database transactions can cover a complete use case.
- The application avoids a generic `ServiceObject` base class; service names
  describe business actions such as `Personalities::Create`.
- A domain may become a separate service only after independent scaling,
  isolation, or lifecycle requirements are demonstrated.

# Facet

Rails application with passwordless email authentication, running entirely in
Docker Compose. Local Ruby and PostgreSQL installations are not required.

## Start

The checked-in development defaults work without additional configuration.
To override database credentials, mail settings, or the container user, copy
the environment template first:

```sh
cp .env.example .env
```

Set `MISTRAL_API_KEY` in `.env` before making real model calls. Conversation and
utility model roles default to `mistral-large-2512` and `mistral-small-latest`; override them with
`MISTRAL_CONVERSATION_MODEL` and `MISTRAL_UTILITY_MODEL`. `MISTRAL_BASE_URL`
defaults to Mistral's global API endpoint. Credentials, prompts,
character bibles, and message content are filtered from Rails parameter logs.

```sh
docker compose up --build
```

- Application: <http://localhost:3000>
- Development mailbox (Mailpit): <http://localhost:8025>
- Development object storage (MinIO API): <http://localhost:9000>
- MinIO console: <http://localhost:9001>

The interface and authentication emails are available in Russian and English.
The language switcher stores the selection in the encrypted session cookie.

Tailwind CSS is rebuilt automatically by the `css` service. Development emails
are delivered over SMTP to Mailpit; no external email account is needed.
Docker Compose also starts a private S3-compatible MinIO bucket named
`facet-development`. The `minio-init` service creates it idempotently before the
web and worker services start. Local credentials and endpoints can be overridden
with the `S3_*` variables documented in `.env.example`.

## Authentication flow

The home page contains the login form. The registration form is loaded into the
same card through a Hotwire Turbo Frame and also works as a standalone page.


- Registration sends a single-use email confirmation link valid for 24 hours.
- Login sends a six-digit one-time code valid for 10 minutes.
- A code permits five attempts and becomes invalid after successful use.
- After confirmation, the user fills in a separate profile.

## Personalities

After completing a profile, a user creates their first private AI personality.
The guided form captures character, conversational style, preferences,
relationship context, permissions, and behavioral boundaries. Facet compiles
these fields into an editable Markdown character bible.

Each personality belongs to its user. Its initial bible is stored as version 1;
every save appends a new immutable record with its author, timestamp, and an
optional change note. The version-history UI supports line-by-line comparisons
and restores an earlier bible by creating another version rather than rewriting
history. Archiving preserves the personality and every version.

## Conversations

Each personality can have multiple conversation threads. A thread starts with
its first user message, which also provides a temporary title. Messages are
stored in a stable order against the exact personality version used at send
time, and idempotency tokens prevent repeated submissions from creating
duplicates. The composer responds with Turbo Streams while retaining a plain
HTML fallback.

`GenerationRun` records and UI states for pending, running, failed, stopped,
and retry are in place. Archived personalities and threads remain readable but
cannot accept new messages or retries.

## AI gateway and usage

All provider calls cross a provider-neutral `Ai::Gateway`. The Mistral adapter
uses Mistral's OpenAI-compatible Chat Completions endpoint through the typed Ruby
OpenAI transport for buffered and streaming calls;
ordinary tests use a deterministic fake adapter and never access the network.

Image generation calls Black Forest Labs directly through `Ai::BflImageAdapter`.
The default is the pinned `flux-2-klein-9b` endpoint at 768x1024 (3:4),
with `safety_tolerance=5`. BFL returns an asynchronous polling URL; completed
images are downloaded immediately and copied into the private S3 bucket.

Explicit photo requests in a conversation create a pending image placeholder.
After the character replies, the utility text model decides whether the
character actually chose to send a photo and extracts the exact visible scene
into a compact specification. Refusals never call BFL. Accepted specifications
are placed before character context in the BFL prompt, while the personality
avatar is supplied as the facial reference image.

Every request creates a `ModelCall` audit record with provider request ID,
latency, input/cached/output token usage, and integer `cost_microusd`. Pricing is
effective-dated in `ModelPrice`; `db:seed` installs the verified Mistral Large 3
and Mistral Small 4 text-token rates current on 2026-09-19, while retaining the
historical OpenAI rates. Failed calls store stable,
sanitized error codes and preserve partial usage when the provider supplies it.
Generation runs claim work under a database lock so duplicate workers cannot
issue a second request for an already running or completed run.

### AI request diagnostics

Every completed `ModelCall` stores both the requested model alias and the actual
`response.model` returned by Mistral. Set `AI_DEBUG_UI=true` to show the actual
model snapshot and input/output token counts below assistant messages. Existing
records created before this field was added fall back to the requested alias.

Set `AI_DEBUG_PAYLOADS=true` only during local development to log text-model
payloads and BFL image request/status metadata. BFL reference-image Base64 is always
redacted from logs. The payload does
not contain the API key, but it does contain the private character bible and
conversation text. This opt-in payload entry is emitted at `INFO` so it is visible
in Sidekiq's default logs. Restart the `web` and `worker` services after changing
either flag, then inspect generation calls with `docker compose logs -f worker`.

## Prompt assembly

`Ai::PromptBuilder` assembles provider-neutral response input in a stable
order: application rules, the pinned provider-specific platform correction,
the immutable character bible version, relationship
state, relevant memories, thread summary, recent messages, and the current user message. When a
summary checkpoint exists, messages covered by it are excluded from recent history. The
response-language rule lives in Application rules so the current user message remains the final
input item. The stable rules and bible prefix is reused with a conversation-thread cache key that
also identifies the provider, personality version, platform-prompt revision, and summary
checkpoint. This keeps each thread’s growing prefix isolated while invalidating the cache when a
stable prompt component changes.

Platform corrections are administrative, versioned records and never become
part of a personality version or user-authored conversation history. Publish a
new active revision from a UTF-8 text file with:

```sh
docker compose exec -T web bin/rails ai:platform_prompts:publish \
  PROVIDER=mistral PURPOSE=conversation FILE=/app/config/prompts/mistral.txt
```

New generation runs pin the active revision so retries remain reproducible.
Set `AI_PLATFORM_PROMPT_REQUIRED=true` to reject new generations when the
configured provider has no active conversation correction.

Each section has an explicit context budget. On overflow, the oldest recent
messages are removed first, then memories and other optional context; application
rules, the platform correction, and the character bible are never shortened. Budget estimates use one
Unicode character as one deterministic unit, while provider-reported token usage
remains authoritative for billing.

Every build stores a diagnostic manifest on the `GenerationRun` with context
record IDs, section estimates, truncation flags, detected language, and the cache
key. It deliberately does not persist a duplicate of the private assembled
prompt.

## Managed memory

Every completed conversation turn can enqueue an idempotent extraction on the
`memory` queue through the database outbox. The personality's utility model
returns candidates through Mistral JSON Schema structured output; the server
then validates the schema, tenant ownership, source message IDs, memory IDs, and
content limits before writing anything.

Memories retain links to their source messages and are scoped to one personality.
Exact normalized duplicates add provenance instead of creating another record,
while corrections create a new record and mark the previous one as superseded.
Sensitive candidates are stored as active memories with a `sensitive` classification, while credentials or likely
authentication/payment secrets are discarded.

The personality Memory page supports type filters, user-authored corrections,
approval, deletion, and an automatic-memory toggle. Deletion removes a memory
from the current/retrievable scope immediately while retaining the historical
record for the future retention workflow.

Before every reply, PostgreSQL ranks active memories from the same personality by
text relevance, importance, recency, and memory kind. The result count and token
budget are bounded; pending, superseded, deleted, and foreign memories never enter
the prompt. The generation manifest records scores and ranking reasons without
duplicating memory content, and successful use updates `last_recalled_at`.

Completed replies also enqueue relationship-state maintenance and periodic thread
summarization through the outbox. Thread summaries advance an explicit
`summary_through_message_id` checkpoint and retain immutable, grounded versions.
Relationship state is shared by every thread of a personality, has immutable
revisions, and supports rollback by creating a new revision. Both utility-model
flows require structured source-message provenance and reject unknown sources.

## Background streaming

User messages atomically create an assistant placeholder and a `GenerationRun`.
After the database transaction commits, `Ai::GenerateReplyJob` is enqueued on
Sidekiq's `conversation` queue. A separate worker streams the provider response
and periodically persists accumulated text, so generation continues if the
browser disconnects.

The authenticated SSE endpoint reads persisted progress and emits `delta`,
`usage`, `done`, and `error` events. Its character cursor supports
`Last-Event-ID` reconnects, while heartbeat comments keep idle connections
alive. The Stimulus controller updates the assistant message and reconnects
independently of the Sidekiq job.

Stop is cooperative between provider chunks. Retry preserves the failed or
stopped attempt and creates a new assistant message, generation run, and job.
Redis is used for Sidekiq queue state only; PostgreSQL remains authoritative for
messages, runs, and usage.

## Background reliability

Sidekiq polls four weighted queues: `conversation`, `memory`, `maintenance`, and
`initiative`. Temporary provider failures use bounded polynomial backoff;
validation and budget failures are terminal, and an exhausted generation is
persisted as failed rather than left running.

Critical generation enqueue goes through the PostgreSQL `outbox_events` table.
The dedicated `outbox` process retries Redis delivery, including after a Redis
restart. Duplicate delivery is safe because generation runs are claimed under a
database lock and terminal runs never issue another provider call.

Redis uses AOF persistence with `appendfsync everysec` and `noeviction` in the
development Compose stack. Sidekiq concurrency and shutdown timeout are
configurable separately from the web process.

`GET /operations/health` reports database/Redis health, Sidekiq process and
queue depth/latency, retry/dead counts, and pending outbox work. It returns 404
unless `OPERATIONS_USERNAME` and `OPERATIONS_PASSWORD` are configured, and then
requires HTTP Basic authentication; it must not be exposed publicly.

## Tests

The suite uses RSpec, Factory Bot, FFaker, Shoulda Matchers, Database Cleaner,
and Capybara. Feature specs cover registration, email confirmation, profile
completion, OTP login, logout, and locale switching through the UI.

Development follows TDD and keeps domain workflows behind service-oriented
boundaries inside the Rails monolith. Architectural decisions are recorded in
[`docs/adr`](docs/adr).

## Useful commands

```sh
docker compose run --rm web bin/rails console
docker compose run --rm web bin/rails db:migrate
docker compose run --rm -e RAILS_ENV=test web bin/rails db:prepare
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec
docker compose run --rm --no-deps web bin/rubocop
```

Stop the application with `docker compose down`. To also remove the local
database volume, run `docker compose down --volumes`.

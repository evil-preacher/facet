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

Set `OPENAI_API_KEY` in `.env` before making real model calls. Conversation and
utility model roles default to `gpt-4o` and `gpt-4o-mini`; override them with
`OPENAI_CONVERSATION_MODEL` and `OPENAI_UTILITY_MODEL`. Credentials, prompts,
character bibles, and message content are filtered from Rails parameter logs.

```sh
docker compose up --build
```

- Application: <http://localhost:3000>
- Development mailbox (Mailpit): <http://localhost:8025>

The interface and authentication emails are available in Russian and English.
The language switcher stores the selection in the encrypted session cookie.

Tailwind CSS is rebuilt automatically by the `css` service. Development emails
are delivered over SMTP to Mailpit; no external email account is needed.

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

All provider calls cross a provider-neutral `Ai::Gateway`. The OpenAI adapter
uses the official Ruby SDK and Responses API for buffered and streaming calls;
ordinary tests use a deterministic fake adapter and never access the network.

Every request creates a `ModelCall` audit record with provider request ID,
latency, input/cached/output token usage, and integer `cost_microusd`. Pricing is
effective-dated in `ModelPrice`; `db:seed` installs the verified GPT-4o and
GPT-4o mini text-token rates current on 2026-09-19. Failed calls store stable,
sanitized error codes and preserve partial usage when the provider supplies it.
Generation runs claim work under a database lock so duplicate workers cannot
issue a second request for an already running or completed run.

## Prompt assembly

`Ai::PromptBuilder` assembles provider-neutral response input in a stable
order: application rules, the immutable character bible version, relationship
state, relevant memories, thread summary, recent messages, the current user
message, and the response-language instruction. The stable rules and bible
prefix is reused with a personality-version cache key for provider prompt
caching.

Each section has an explicit context budget. On overflow, the oldest recent
messages are removed first, then memories and other optional context; application
rules and the character bible are never shortened. Budget estimates use one
Unicode character as one deterministic unit, while provider-reported token usage
remains authoritative for billing.

Every build stores a diagnostic manifest on the `GenerationRun` with context
record IDs, section estimates, truncation flags, detected language, and the cache
key. It deliberately does not persist a duplicate of the private assembled
prompt. Connecting this input to persisted streaming assistant messages belongs
to the next implementation stage, so the chat UI does not call the provider yet.

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

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
and retry are in place; actual AI responses are intentionally deferred to the
model gateway stage. Archived personalities and threads remain readable but
cannot accept new messages or retries.

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

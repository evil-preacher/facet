# Production operations

Facet's `compose.production.yml` runs only the Rails web process, Sidekiq worker,
and PostgreSQL outbox dispatcher. Provide managed PostgreSQL, Redis, S3-compatible
storage, SMTP, and an HTTPS reverse proxy. The Compose file binds Puma only to
`127.0.0.1:3000`.

## Environment checklist

- Set `SECRET_KEY_BASE` to a long random value and keep it stable across restarts.
- Set `DATABASE_URL` to the production PostgreSQL database and `REDIS_URL` to
  persistent Redis. Redis must not evict Sidekiq data.
- Set `APP_HOST` to the public hostname without scheme or port. Forward HTTPS
  requests to Puma and preserve the original host and scheme.
- Set `SMTP_ADDRESS`, `SMTP_PORT`, `MAILER_FROM`, and SMTP credentials when the
  server requires authentication. Test confirmation, login, and opt-in initiative
  emails. Optional `SMTP_OPEN_TIMEOUT` and `SMTP_READ_TIMEOUT` default to 5 and
  10 seconds so disabling email is not held behind an unbounded SMTP call.
- Set `S3_ENDPOINT`, `S3_PUBLIC_ENDPOINT`, `S3_REGION`, `S3_BUCKET`,
  `S3_ACCESS_KEY_ID`, and `S3_SECRET_ACCESS_KEY`. The public endpoint must be
  reachable by users because it appears in short-lived image URLs.
- Set the selected `AI_PROVIDER` API key, `BFL_API_KEY` for image generation,
  and review model prices and `AI_GLOBAL_MONTHLY_LIMIT_MICROUSD`.
- Set strong `OPERATIONS_USERNAME` and `OPERATIONS_PASSWORD`. Restrict
  `/operations/*` to the operations network at the reverse proxy as well.
- Keep `AI_DEBUG_PAYLOADS=false`. Structured events contain IDs, status,
  provider/model, token counts, latency, cost, and error codes, never prompts or
  message text.
- Back up the database and object bucket. Test a restore into an isolated
  environment before accepting production traffic.

Store these values in a secret manager or a root-owned environment file outside
the repository. Compose interpolation requires them at startup; the application
image contains no production credentials.

## Build and release

```sh
docker compose -f compose.production.yml build web
docker compose -f compose.production.yml run --rm --no-deps web bin/rails db:migrate
docker compose -f compose.production.yml run --rm --no-deps \
  -v /absolute/private/prompts:/prompt-import:ro web \
  bin/rails ai:prompts:import DIRECTORY=/prompt-import
docker compose -f compose.production.yml up -d web worker outbox
```

The prompt import needs one private `<key>.txt` file per key in
`Ai::PromptCatalog::KEYS`. It creates missing active revisions and leaves existing
revisions untouched. Keep the source directory out of the repository and back up
the database before deployment; a fresh database has no bundled prompt text.

Build uses `Dockerfile.production`, which installs production gems and compiles
assets. The Sidekiq timeout is 25 seconds by default and Compose gives the
worker 35 seconds to stop. SSE responses reconnect after at most 25 seconds;
web receives 35 seconds to stop. The outbox dispatcher handles `TERM` and
finishes its current dispatch pass before exit.

Check `GET /up` from the proxy and inspect authenticated
`GET /operations/health`, `/operations/metrics`, and `/operations/diagnostics`.
Metrics use a rolling 24-hour window. Diagnostics list stalled record IDs and
timestamps only. An operator may re-enqueue a pending generation older than
five minutes with `POST /operations/diagnostics/runs/:id/retry`; running runs
cannot be retried through this endpoint. Model-call reservation and generation
claim guards prevent duplicate billing when a queued job is delivered twice.

## PostgreSQL backup and restore

Run a logical backup from a host with access to the database and PostgreSQL
client tools. Set `DATABASE_URL` in that shell without printing it:

```sh
pg_dump --format=custom --no-owner --file=facet.dump "$DATABASE_URL"
```

Store the dump encrypted and record its date, database version, and matching
object bucket snapshot. Restore only into an empty, isolated database first:

```sh
createdb facet_restore
pg_restore --dbname=facet_restore --no-owner --exit-on-error facet.dump
```

Point a test deployment at the restored database and matching bucket; run
`bin/rails db:migrate`, then test login, conversation history, object URLs,
and operational health. For a real disaster recovery, stop web, worker, and
outbox before restoring, restore the bucket snapshot, switch `DATABASE_URL` to
the restored database, and start the services. Never restore over a live
database while background workers are running.

Redis holds Sidekiq queue state. Its persistence and backup policy must be
configured alongside PostgreSQL. The database outbox can redeliver critical
generation work after a Redis loss, but Redis backups preserve scheduled,
retry, and other non-outbox jobs.

## Verification record

On 2026-10-05, the production image built with precompiled assets and passed
`bin/rails zeitwerk:check`. A temporary development account ran a two-message
RU→EN conversation through Mistral in one thread. The prompt detected each
message's language and the model responded in the corresponding language.
The temporary account was deleted after the check.

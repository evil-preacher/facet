# Facet

Rails application running entirely in Docker Compose. Local Ruby and
PostgreSQL installations are not required.

## Start

```sh
docker compose up --build
```

The application is available at <http://localhost:3000>.

## Useful commands

```sh
docker compose run --rm web bin/rails console
docker compose run --rm web bin/rails db:migrate
docker compose run --rm -e RAILS_ENV=test web bin/rails db:prepare
docker compose run --rm -e RAILS_ENV=test web bundle exec rspec
```

Stop the application with `docker compose down`. To also remove the local
database volume, run `docker compose down --volumes`.

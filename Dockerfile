# syntax=docker/dockerfile:1

FROM ruby:3.4.10-slim

ENV BUNDLE_PATH=/usr/local/bundle

RUN apt-get update -qq \
    && apt-get install -y --no-install-recommends \
      build-essential \
      libpq-dev \
      postgresql-client \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile* ./
RUN bundle install

COPY . .

ENTRYPOINT ["/app/bin/docker-entrypoint"]

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]

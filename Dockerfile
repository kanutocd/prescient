# syntax=docker/dockerfile:1

FROM ruby:3.3-alpine AS builder

WORKDIR /app

RUN apk add --no-cache build-base git

ENV BUNDLE_WITH=rack_example \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_PATH=/usr/local/bundle

COPY Gemfile prescient.gemspec ./
COPY lib ./lib

RUN bundle install --jobs 4 --retry 3

FROM ruby:3.3-alpine

WORKDIR /app

RUN apk add --no-cache curl tzdata && \
    addgroup -S -g 1000 prescient && \
    adduser -S -u 1000 -G prescient prescient

ENV BUNDLE_WITH=rack_example \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_PATH=/usr/local/bundle \
    GEM_HOME=/usr/local/bundle/ruby/3.3.0 \
    GEM_PATH=/usr/local/bundle/ruby/3.3.0 \
    PATH=/usr/local/bundle/ruby/3.3.0/bin:/usr/local/bundle/bin:$PATH \
    RACK_ENV=production

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --chown=prescient:prescient lib ./lib
COPY --chown=prescient:prescient examples/rest_api.ru ./examples/rest_api.ru

USER prescient

EXPOSE 9292

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1:9292/healthz || exit 1

CMD ["rackup", "-s", "puma", "-o", "0.0.0.0", "-p", "9292", "/app/examples/rest_api.ru"]

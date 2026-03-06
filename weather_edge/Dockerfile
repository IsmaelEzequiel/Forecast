# === Builder Stage ===
FROM hexpm/elixir:1.17.3-erlang-27.1.2-debian-bookworm-20241016-slim AS builder

RUN apt-get update -y && apt-get install -y build-essential git curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config
COPY config/config.exs config/prod.exs config/runtime.exs config/
RUN mix deps.compile

COPY lib lib
COPY priv priv
COPY assets assets

RUN mix assets.deploy
RUN mix compile

RUN mix release

# === Runner Stage ===
FROM debian:bookworm-slim AS runner

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

RUN useradd --create-home app

COPY --from=builder --chown=app:app /app/_build/prod/rel/weather_edge ./
COPY --from=builder --chown=app:app /app/entrypoint.sh ./

USER app

ENV PHX_SERVER=true

ENTRYPOINT ["bash", "entrypoint.sh"]

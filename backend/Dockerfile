# syntax=docker/dockerfile:1
FROM rust:1-slim-bookworm AS build
WORKDIR /src
ENV SQLX_OFFLINE=true
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    cargo build --release --locked && cp target/release/humannet-api /humannet-api

# Imagem final sem shell nem gerenciador de pacotes, rodando como não-root.
FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=build /humannet-api /usr/local/bin/humannet-api
ENV BIND_ADDR=0.0.0.0:8080 LOG_FORMAT=json
EXPOSE 8080
USER nonroot
ENTRYPOINT ["/usr/local/bin/humannet-api"]
CMD ["serve"]

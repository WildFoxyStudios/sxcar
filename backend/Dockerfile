FROM rust:1-slim@sha256:6abf73f05806f36362d0ff2722f2250c6153398831edd0455e0e0baa1f78ecc7 AS builder
WORKDIR /app
# Compila contra la cache .sqlx (sin DB en build) de forma explícita y reproducible.
ENV SQLX_OFFLINE=true
# Usa el toolchain ya instalado en la imagen (1.96.0) e IGNORA rust-toolchain.toml,
# que pide componentes rustfmt/clippy innecesarios para `build` (evita descargas frágiles).
ENV RUSTUP_TOOLCHAIN=1.96.0
COPY . .
RUN cargo build --release --bin api

FROM debian:bookworm-slim@sha256:60eac759739651111db372c07be67863818726f754804b8707c90979bda511df AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/target/release/api /usr/local/bin/api
ENV BIND_ADDR=0.0.0.0:8080
EXPOSE 8080
RUN useradd -u 10001 -m appuser
USER 10001
CMD ["api"]

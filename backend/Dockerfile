FROM rust:1-slim AS builder
WORKDIR /app
COPY . .
RUN cargo build --release --bin api

FROM debian:bookworm-slim AS runtime
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/target/release/api /usr/local/bin/api
ENV BIND_ADDR=0.0.0.0:8080
EXPOSE 8080
CMD ["api"]

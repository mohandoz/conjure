---
name: messaging
description: "Kafka / RabbitMQ / ActiveMQ / SQS topics & queues, consumers, producers, DLQ flow. Invoke when user asks about events, message handling, or async workflows."
---

# messaging

Transports in use: `<Kafka | RabbitMQ | ActiveMQ | SQS | NATS | ...>`.

## Configuration files

| Concern | File |
| --- | --- |
| Broker config | `<file:line>` |
| Consumer factory | `<file:line>` |
| Producer template | `<file:line>` |
| Error handler / DLQ | `<file:line>` |

## Topic / queue catalog

| Class | Destination | Payload DTO | Purpose |
| --- | --- | --- | --- |

## Conventions

- Topic/queue names externalized via `<config key pattern>`.
- All consumers MUST be idempotent (DLQ replay is common).
- Producer DTO versioning: `<strategy>`.
- DLQ inspection: `<script path>`.
- Schema registry: `<yes/no, location>`.

## Adding a new consumer

1. Define payload DTO under `<path>`.
2. Add consumer class under `<path>` annotated `<@KafkaListener | @JmsListener | ...>`.
3. Externalize topic name into `<config file>`.
4. Add DLQ behavior — see `<file:line>`.
5. Add integration test using `<embedded broker / testcontainers>`.

## Gotchas

- <thing that bit us, with file:line>

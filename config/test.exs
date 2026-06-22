import Config

config :logger, level: :none

config :tower_db, :buffer,
  batch_size: 5,
  flush_interval: 100,
  backpressure_retry: 50

config :tower_db, :circuit_breaker,
  failure_threshold: 3,
  recovery_timeout: 500,
  queue_retry_interval: 10,
  max_queue_size: 10

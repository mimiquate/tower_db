import Config

config :tower_db, :circuit_breaker,
  failure_threshold: 3,
  recovery_timeout: 50,
  queue_retry_interval: 10,
  max_queue_size: 10

require "sidekiq/api"

redis_config = {
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  network_timeout: ENV.fetch("REDIS_NETWORK_TIMEOUT", "5").to_f,
  pool_timeout: ENV.fetch("REDIS_POOL_TIMEOUT", "5").to_f
}

Sidekiq.configure_server do |config|
  config.redis = redis_config
end

Sidekiq.configure_client do |config|
  config.redis = redis_config
end

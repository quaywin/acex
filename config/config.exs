import Config

config :acex_gateway,
  port: 8686

import_config "#{config_env()}.exs"

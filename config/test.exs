import Config

# In test, port 0 lets OS assign an ephemeral unused port to prevent collisions
config :acex_gateway,
  port: 0,
  channels_file: "tmp/test_channels.json",
  groups_file: "tmp/test_groups.json",
  settings_file: "tmp/test_settings.json",
  skip_upstream_fetch: true

config :logger, level: :warning

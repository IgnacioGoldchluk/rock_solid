import Config

config :rock_solid, client_options: [plug: {Req.Test, RockSolid.Client}, retry: false]
config :logger, :default_handler, false

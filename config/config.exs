import Config

config :pythonx, :uv_init,
  pyproject_toml: """
  [project]
  name = "project"
  version = "0.0.0"
  requires-python = "==3.13.*"
  dependencies = [
    "greenery>=4.2.2"
  ]
  """

import_config "#{config_env()}.exs"

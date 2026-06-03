defmodule RockSolid.Types do
  @moduledoc false
  # Common types between schemas, validation and simplification
  @type schema :: map() | boolean()
  @type value :: map() | list() | String.t() | number() | boolean() | nil

  @type error_list :: list(Zoi.Errors.t())
end

defmodule RockSolid do
  @moduledoc """
  Data generation from JSON schema
  """
  alias RockSolid.Strategy

  alias RockSolid.Resolution.Resolvers.DummyResolver

  @opts_schema [resolver: [type: :mod_arg, required: true]]

  @doc """
  Generates data based on the input JSON schema

  ## Options

    - `:resolver` - Either a module or a tuple {module, args} that implements the
    `RockSolid.Resolution.Resolver` behaviour. Defaults to [`DummyResolver`](`RockSolid.Resolution.Resolvers.DummyResolver`).
  """
  def from_schema(json_schema, opts \\ []) do
    opts = opts |> parse_resolver() |> NimbleOptions.validate!(@opts_schema)
    Strategy.from_schema(json_schema, opts)
  end

  defp parse_resolver(opts) do
    # This allows the user to pass just the module without arguments
    Keyword.update(opts, :resolver, {DummyResolver, []}, fn
      {_mod, _args} = mod_arg -> mod_arg
      val when is_atom(val) -> {val, []}
    end)
  end
end

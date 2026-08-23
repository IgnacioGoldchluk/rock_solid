defmodule RockSolid do
  @moduledoc """
  Builds `StreamData` generators from JSON Schemas.

  Use `from_schema/2` when a test, fixture, or sample payload should follow the
  same schema as the system boundary it exercises. Pass schemas as decoded JSON
  maps with string keys; generated values are JSON-compatible Elixir terms.

  RockSolid is a generator, not a validator. It attempts to produce values that
  satisfy the schema after resolving references and normalizing supported JSON
  Schema drafts into its internal representation.

  ## Choosing Schemas

  Generation works best when schemas describe the value space directly: include
  explicit `"type"` fields, keep branches narrow, and prefer positive
  constraints over broad exclusions. Use a custom `:resolver` when schemas
  contain references that cannot be handled by the default dummy resolver.

  See `from_schema/2` for options and the README for installation, examples,
  and broader guidance.
  """
  alias RockSolid.Strategy

  alias RockSolid.Resolution.Resolvers.DummyResolver

  @opts_schema [
    resolver: [type: :mod_arg, required: true],
    string_kind: [type: :atom, default: nil]
  ]

  @doc """
  Generates data based on the input JSON schema

  ## Options

  - `:resolver` - Either a module or a tuple {module, args} that implements the
  `RockSolid.Resolution.Resolver` behaviour. Defaults to [`DummyResolver`](`RockSolid.Resolution.Resolvers.DummyResolver`).
  - `:string_kind` - The kind of strings to generate. See `StreamData.string/2`. Defaults to
  generating `:utf8` strings
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

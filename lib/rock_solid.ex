defmodule RockSolid do
  @moduledoc """
  Data generation from JSON schema.

  `RockSolid` exposes a single function: `from_schema/2`.

  You can use it inside a [`property`](`ExUnitProperties.property/3`) test
  ```elixir
  defmodule MyTest do
    use ExUnit.Case
    use ExUnitProperties

    property "generates valid user profiles" do
      schema = %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "birthDate" => %{"type" => "string", "format" => "date"},
          "name" => %{"type" => "string", "pattern" => "^[A-Z][a-z]+$"},
          "email" => %{"type" => "string", "format" => "email"}
        },
        "required" => ["birthDate", "name", "email"]
      }

      check all user_data <- RockSolid.from_schema(schema) do
        assert Regex.match?(~r/^[A-Z][a-z]+$/, user_data["name"])
        assert %Date{} = Date.from_iso8601!(user_data["birthDate"])
        assert String.split(user_data["email"], "@") |> length() == 2
      end
    end
  end
  ```

  or as a generator, since `RockSolid.from_schema/2` returns elements of type `t:StreamData.t/1`

  ```elixir
  iex(1)> specs = %{
  "type" => "object",
  "properties" => %{
    "serverIPs" => %{
      "type" => "array",
      "items" => %{"type" => "string", "format" => "ipv4"},
      "uniqueItems" => true,
      "minItems" => 1
    },
    "serverName" => %{"pattern" => "^[a-z][a-z_0-9]{2,255}$", "type" => "string"},
  },
  "required" => ["serverIPs", "serverName"],
  "additionalProperties" => false
  }

  iex(2)> specs |> RockSolid.from_schema() |> Enum.take(3)
  [
    %{"serverIPs" => ["148.50.92.205"], "serverName" => "a5l"},
    %{"serverIPs" => ["230.26.166.121"], "serverName" => "y_w"},
    %{
      "serverIPs" => ["144.154.111.248", "155.134.134.38"],
      "serverName" => "v2_5"
    }
  ]
  ```
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

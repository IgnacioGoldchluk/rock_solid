defmodule RockSolid.Schemas.Null do
  @moduledoc """
  Null type
  """
  alias RockSolid.Schemas.Schema

  @schema Zoi.map(
            Map.merge(Schema.common_keywords(), %{
              "type" => Zoi.literal("null") |> Zoi.default("null")
            })
          )
  def new(attrs), do: Zoi.parse(schema(), attrs)
  def schema, do: @schema
end

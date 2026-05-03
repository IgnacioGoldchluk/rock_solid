defmodule RockSolid.Schemas.Boolean do
  @moduledoc """
  Boolean type
  """
  alias RockSolid.Schemas.Schema

  @schema Zoi.map(
            Map.merge(Schema.common_keywords(), %{
              "type" => Zoi.literal("boolean") |> Zoi.default("boolean")
            })
          )

  def new(attrs), do: Zoi.parse(schema(), attrs)

  def schema, do: @schema
end

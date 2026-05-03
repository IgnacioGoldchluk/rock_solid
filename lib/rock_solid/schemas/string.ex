defmodule RockSolid.Schemas.String do
  @moduledoc """
  Represents a string type
  """
  alias RockSolid.Schemas.{Refinements, Schema}

  @string_format [
    "char",
    "email",
    "idn-email",
    "uuid",
    "ipv4",
    "ipv6",
    "http-date",
    "hostname",
    "idn-hostname",
    "iri",
    "uri",
    "sf-string",
    "sf-token",
    "sf-boolean",
    "sf-binary",
    "json-pointer",
    "password",
    "time",
    "time-local",
    "date",
    "date-time",
    "date-time-local",
    "duration",
    "html",
    "regex",
    "commonmark",
    "uri-template",
    "uri-reference",
    "iri-reference",
    "media-range",
    "relative-json-pointer"
  ]

  @specific_keywords %{
    "type" => Zoi.literal("string") |> Zoi.default("string"),
    "minLength" => Zoi.integer(gte: 0) |> Zoi.optional(),
    "maxLength" => Zoi.integer(gte: 0) |> Zoi.optional(),
    "pattern" => Zoi.string() |> Zoi.refine(&Refinements.compile_regex/1) |> Zoi.optional(),
    "format" => Zoi.enum(@string_format) |> Zoi.optional()
  }

  @schema Zoi.map(Map.merge(Schema.common_keywords(), @specific_keywords))

  def new(attrs), do: Zoi.parse(schema(), attrs)

  def schema do
    Enum.reduce(extra_validations(), @schema, fn fun, schema -> Zoi.refine(schema, fun) end)
  end

  defp extra_validations, do: [&validate_length/1]

  defp validate_length(%{"minLength" => min, "maxLength" => max}) when min > max do
    {:error, "minLength > maxLength"}
  end

  defp validate_length(_), do: :ok
end

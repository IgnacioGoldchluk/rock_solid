defmodule RockSolid.Strategy do
  @moduledoc """
  Data generation based on JSON schema
  """

  alias RockSolid.Context
  alias RockSolid.Migration
  alias RockSolid.Schemas
  alias RockSolid.Strategy.UUID
  alias RockSolid.Transformation

  @doc """
  Generates values based on JSON the schema
  """
  @spec from_schema(map(), Keyword.t()) :: StreamData.t()
  def from_schema(schema, opts) do
    {:ok, migrated} = Migration.migrate(schema, Keyword.fetch!(opts, :resolver))

    migrated |> Transformation.simplify() |> from_json_schema()
  end

  defp from_json_schema(schema) when is_map(schema) or schema == true do
    schema |> gen() |> filter_not(schema)
  end

  defp gen(true), do: json()
  defp gen(%{"$ref" => pointer}), do: Context.get_ref(pointer) |> from_json_schema()
  defp gen(%{"const" => value}), do: StreamData.constant(value)
  defp gen(%{"enum" => values}) when is_list(values), do: StreamData.member_of(values)

  defp gen(%{"type" => "boolean"}), do: StreamData.boolean()
  defp gen(%{"type" => "null"}), do: StreamData.constant(nil)

  defp gen(%{"multipleOf" => multiple_of} = schema) do
    schema
    |> Map.delete("multipleOf")
    |> Map.put("type", "integer")
    |> Map.update("minimum", nil, &trunc(&1 / multiple_of))
    |> Map.update("maximum", nil, &trunc(&1 / multiple_of))
    |> gen()
    |> StreamData.map(fn generated ->
      if is_integer(multiple_of) do
        generated * multiple_of
      else
        [_, decimals] = multiple_of |> to_string() |> String.split(".")
        Float.round(generated * multiple_of, String.length(decimals))
      end
    end)
  end

  defp gen(%{"type" => "integer"} = schema) do
    [min: Schemas.Number.min_value(schema), max: Schemas.Number.max_value(schema)]
    |> Keyword.filter(fn {_, v} -> not is_nil(v) end)
    |> MoreStreamData.more_integer()
    |> filter_value(schema["exclusiveMinimum"])
    |> filter_value(schema["exclusiveMaximum"])
  end

  defp gen(%{"type" => "number"} = schema) do
    [
      min: Schemas.Number.min_value(schema),
      max: Schemas.Number.max_value(schema),
      exclude_min?: Map.has_key?(schema, "exclusiveMinimum"),
      exclude_max?: Map.has_key?(schema, "exclusiveMaximum")
    ]
    |> MoreStreamData.more_float()
  end

  # pattern always takes priority above format, because format is not stanarized
  # in the newer drafts.
  defp gen(%{"type" => "string", "pattern" => pattern} = schema) do
    pattern
    |> MoreStreamData.from_regex(character_set: :printable)
    |> filter_min_length(schema["minLength"])
    |> filter_max_length(schema["maxLength"])
  end

  defp gen(%{"type" => "string", "format" => "email"} = schema) do
    # Handle separately because `email` supports `maxLength`
    MoreStreamData.email(to_keyword(schema, max_length: "maxLength"))
  end

  defp gen(%{"type" => "string", "format" => format} = schema) do
    format
    |> from_format()
    |> filter_min_length(schema["minLength"])
    |> filter_max_length(schema["maxLength"])
  end

  defp gen(%{"type" => "string"} = schema) do
    StreamData.string(
      :printable,
      to_keyword(schema, min_length: "minLength", max_length: "maxLength")
    )
    |> filter_min_length(schema["minLength"])
  end

  defp gen(%{"anyOf" => schemas}) when is_list(schemas) do
    StreamData.one_of(Enum.map(schemas, &from_json_schema/1))
  end

  defp gen(%{"type" => "array"} = schema), do: array_gen(schema)
  defp gen(%{"type" => "object"} = schema), do: object_gen(schema)

  defp filter_value(generator, nil), do: generator
  defp filter_value(generator, value), do: StreamData.filter(generator, &(&1 != value))

  defp filter_not(generator, %{"not" => clauses}) do
    not_schema = Context.build!(%{"not" => clauses})
    StreamData.filter(generator, &match?({:ok, _}, JSV.validate(&1, not_schema)))
  end

  defp filter_not(generator, _schema), do: generator

  def to_keyword(schema, mappings) do
    mappings
    |> Keyword.new(fn {keyword, map_key} -> {keyword, schema[map_key]} end)
    |> Keyword.filter(fn {_k, v} -> not is_nil(v) end)
  end

  # String generation
  defp filter_min_length(generator, nil), do: generator

  defp filter_min_length(generator, min_length) when is_integer(min_length) do
    StreamData.filter(generator, fn val -> String.length(val) >= min_length end)
  end

  defp filter_max_length(generator, nil), do: generator

  defp filter_max_length(generator, max_length) when is_integer(max_length) do
    StreamData.filter(generator, fn val -> String.length(val) <= max_length end)
  end

  defp from_format("char"), do: StreamData.codepoint() |> StreamData.map(&<<&1>>)
  defp from_format("email"), do: MoreStreamData.email()
  defp from_format("idn-email"), do: from_format("email")

  defp from_format("uuid"), do: StreamData.repeatedly(&UUID.generate/0)

  defp from_format("ipv4"), do: MoreStreamData.ip_address(version: 4)
  defp from_format("ipv6"), do: MoreStreamData.ip_address(version: 6)

  defp from_format("http-date") do
    MoreStreamData.datetime()
    |> StreamData.map(fn dt ->
      {{dt.year, dt.month, dt.day}, {dt.hour, dt.minute, dt.second}}
      |> :httpd_util.rfc1123_date()
      |> to_string()
    end)
  end

  defp from_format("hostname") do
    MoreStreamData.from_regex(
      "^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9]))*$"
    )
  end

  defp from_format("idn-hostname"), do: from_format("hostname")
  defp from_format("date"), do: StreamData.date() |> StreamData.map(&to_string/1)
  defp from_format("date-time"), do: MoreStreamData.datetime() |> StreamData.map(&to_string/1)
  defp from_format("time"), do: MoreStreamData.time() |> StreamData.map(&to_string/1)

  defp from_format("duration"),
    do: MoreStreamData.duration() |> StreamData.map(&Duration.to_iso8601/1)

  defp from_format("uri"), do: MoreStreamData.url()
  defp from_format("uri-reference"), do: from_format("uri")
  # Default to URI for now
  defp from_format("iri"), do: from_format("uri")

  defp from_format("relative-uri") do
    StreamData.map(from_format("uri"), fn url ->
      url
      |> URI.parse()
      |> Map.take([:path, :query, :fragment])
      |> then(&struct(URI, &1))
      |> to_string()
    end)
  end

  # Temporal until we can generate real regexes
  defp from_format("regex"), do: StreamData.constant("^[A-Z]_[a-z]+$")

  defp array_gen(%{"prefixItems" => prefix_items} = schema) do
    lpf = length(prefix_items)

    StreamData.tuple({
      StreamData.fixed_list(Enum.map(prefix_items, &from_json_schema/1)),
      from_json_schema(
        schema
        |> Map.delete("prefixItems")
        |> Map.update("minItems", nil, &max(0, &1 - lpf))
        |> Map.update("maxItems", nil, &max(0, &1 - lpf))
      )
    })
    |> StreamData.map(fn {prefix_items, items} -> prefix_items ++ items end)
  end

  defp array_gen(%{"items" => false}), do: StreamData.constant([])

  defp array_gen(%{"items" => %{"enum" => values}, "uniqueItems" => true} = array) do
    MoreStreamData.sample(
      values,
      to_keyword(array, min_length: "minItems", max_length: "maxItems")
    )
  end

  defp array_gen(%{"items" => items, "uniqueItems" => true} = array) do
    if Map.has_key?(array, "minItems") and array["minItems"] > 0 do
      length_opts = to_keyword(array, min_length: "minItems", max_length: "maxItems")

      StreamData.uniq_list_of(from_json_schema(items), length_opts)
      |> scale_log(length_opts)
    else
      # This is to avoid the "TooManyDuplicatesError" from StreamData.
      # If there is no `minItems` constraint then create a list and then
      # keep only the unique ones
      StreamData.list_of(from_json_schema(items), to_keyword(array, max_length: "maxItems"))
      |> scale_log()
      |> StreamData.map(&Enum.uniq/1)
    end
  end

  defp array_gen(%{"items" => items} = array) do
    length_opts = to_keyword(array, min_length: "minItems", max_length: "maxItems")

    StreamData.list_of(from_json_schema(items), length_opts)
    |> scale_log(length_opts)
  end

  # No items, default to random integers for now
  defp array_gen(array), do: gen(Map.put(array, "items", true))

  defp can_generate_props?(s) do
    s["additionalProperties"] != false or s["patternProperties"] not in [nil, %{}, false]
  end

  defp object_gen(schema) do
    possible_properties = Schemas.Object.possible_properties(schema)

    properties =
      Map.get(schema, "properties", %{}) |> Map.filter(fn {k, _v} -> k in possible_properties end)

    required = Map.get(schema, "required", [])
    optional = Enum.reject(possible_properties, &(&1 in required))

    min_props = Map.get(schema, "minProperties", 0)
    min_optionals = if(can_generate_props?(schema), do: 0, else: min_props)

    max_optionals =
      case schema["maxProperties"] do
        nil -> length(optional)
        other -> max(length(optional), other)
      end

    StreamData.tuple(
      {StreamData.integer(min_optionals..max_optionals), StreamData.shuffle(optional)}
    )
    |> StreamData.bind(fn {to_take, optional_props} ->
      {_, optionals} = Enum.split(optional_props, to_take)

      properties
      |> Map.new(fn {name, subschema} -> {name, from_json_schema(subschema)} end)
      |> StreamData.optional_map(optionals)
    end)
    |> StreamData.bind(fn current_map -> pattern_properties(schema, current_map) end)
    |> StreamData.bind(fn current_map -> additional_properties(schema, current_map) end)
    |> StreamData.map(fn current_map ->
      conform_dependent_required(current_map, schema["dependentRequired"])
    end)
  end

  defp conform_dependent_required(gen_value, nil), do: gen_value

  defp conform_dependent_required(gen_value, dependent_required) do
    Enum.reduce(dependent_required, gen_value, fn {prop, deps}, acc ->
      if Enum.any?(deps, &(not Map.has_key?(acc, &1))) do
        Map.delete(acc, prop)
      else
        acc
      end
    end)
  end

  defp pattern_properties(%{"patternProperties" => pattern_props} = schema, current_gen) do
    defined_properties = Map.get(schema, "properties", %{}) |> Map.keys()

    opts = pattern_properties_length(schema, map_size(current_gen))

    Enum.map(pattern_props, fn {pattern, subschema} ->
      key_gen =
        MoreStreamData.from_regex(pattern, character_set: :printable)
        |> StreamData.filter(&(&1 not in defined_properties))

      value_gen = from_json_schema(subschema)

      StreamData.tuple({key_gen, value_gen})
    end)
    |> StreamData.one_of()
    |> then(fn pattern_props_gen ->
      if opts[:min_length] == 0 do
        # Duplicate keys don't matter, will be discarded when we create the map
        StreamData.list_of(pattern_props_gen)
      else
        opts_with_uniq_fun = Keyword.put(opts, :uniq_fun, fn {key, _val} -> key end)
        StreamData.uniq_list_of(pattern_props_gen, opts_with_uniq_fun)
      end
    end)
    |> scale_log(opts)
    |> StreamData.map(fn key_value_pairs -> Map.merge(Map.new(key_value_pairs), current_gen) end)
  end

  defp pattern_properties(_, current_gen), do: StreamData.constant(current_gen)

  defp pattern_properties_length(schema, current_length) do
    additional_props = schema["additionalProperties"]
    min_props = Map.get(schema, "minProperties", 0)
    max_props = schema["maxProperties"]

    min_length =
      if additional_props == false do
        max(0, min_props - current_length)
      else
        0
      end

    max_length =
      case max_props do
        nil -> nil
        limit when is_integer(limit) -> max(0, limit - current_length)
      end

    if is_nil(max_length) do
      [min_length: min_length]
    else
      [min_length: min_length, max_length: max_length]
    end
  end

  defp additional_properties(%{"additionalProperties" => false}, current_gen) do
    StreamData.constant(current_gen)
  end

  defp additional_properties(schema, current_gen) do
    current_length = map_size(current_gen)

    min_length =
      case schema["minProperties"] do
        nil -> 0
        val when is_integer(val) -> max(0, val - current_length)
      end

    max_length =
      case schema["maxProperties"] do
        nil -> nil
        val when is_integer(val) -> max(0, val - current_length)
      end

    length_opts =
      case {min_length, max_length} do
        {x, x} -> [length: x]
        {x, nil} -> [min_length: x]
        {x, y} -> [min_length: x, max_length: y]
      end

    cond do
      length_opts[:length] == 0 ->
        StreamData.constant(current_gen)

      length_opts[:min_length] == 0 ->
        additional_properties_no_min(schema, current_gen, length_opts)

      true ->
        additional_properties_with_min(schema, current_gen, length_opts)
    end
  end

  defp additional_properties_with_min(schema, current_gen, length_opts) do
    additional_props = Map.get(schema, "additionalProperties", true)

    pattern_properties =
      Map.get(schema, "patternProperties", %{}) |> Map.keys() |> Enum.map(&Regex.compile!/1)

    property_names =
      Map.get(schema, "propertyNames", Map.new()) |> Map.put_new("type", "string")

    existing_keys =
      Enum.uniq(Map.keys(Map.get(schema, "properties", %{})) ++ Map.keys(current_gen))

    StreamData.map_of(
      from_json_schema(property_names)
      |> StreamData.filter(fn name ->
        not (name in existing_keys or matches_any_regex?(name, pattern_properties))
      end),
      from_json_schema(additional_props),
      length_opts
    )
    |> scale_log(length_opts)
    |> StreamData.map(fn additional_props -> Map.merge(additional_props, current_gen) end)
  end

  defp additional_properties_no_min(schema, current_gen, length_opts) do
    additional_props = Map.get(schema, "additionalProperties", true)

    pattern_properties =
      schema |> Map.get("patternProperties", %{}) |> Map.keys() |> Enum.map(&Regex.compile!/1)

    existing_keys =
      Enum.uniq(Map.keys(Map.get(schema, "properties", %{})) ++ Map.keys(current_gen))

    property_names =
      Map.get(schema, "propertyNames", Map.new()) |> Map.put_new("type", "string")

    {from_json_schema(property_names), from_json_schema(additional_props)}
    |> StreamData.tuple()
    |> StreamData.list_of(length_opts)
    |> scale_log()
    |> StreamData.map(fn key_value_pairs ->
      key_value_pairs
      |> Enum.reject(fn {k, _} ->
        k in existing_keys or matches_any_regex?(k, pattern_properties)
      end)
      |> Map.new()
      |> Map.merge(current_gen)
    end)
  end

  defp matches_any_regex?(key, regexes), do: Enum.any?(regexes, &Regex.match?(&1, key))

  defp json do
    scalar_generator =
      StreamData.one_of([
        StreamData.integer(),
        StreamData.boolean(),
        StreamData.string(:ascii),
        nil
      ])

    StreamData.tree(scalar_generator, fn nested_generator ->
      StreamData.one_of([
        StreamData.list_of(nested_generator),
        StreamData.map_of(StreamData.string(:ascii, min_length: 1), nested_generator)
      ])
    end)
    |> StreamData.resize(2)
  end

  defp scale_log(gen, length_opts \\ []) do
    min_length = Keyword.get(length_opts, :min_length, 0)
    max_length = Keyword.get(length_opts, :max_length, nil)

    StreamData.scale(gen, fn size ->
      case {size, min_length, max_length} do
        {0, min, nil} -> min
        {size, min, nil} -> ceil(:math.log(size)) + min
        {size, min, max} -> min(ceil(:math.log(size)) + min, max)
      end
    end)
  end
end

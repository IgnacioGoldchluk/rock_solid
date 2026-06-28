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
    schema
    |> Migration.migrate(Keyword.fetch!(opts, :resolver))
    |> Transformation.simplify()
    |> from_json_schema(opts)
  end

  defp from_json_schema(true, _), do: json()

  defp from_json_schema(schema, opts) when is_map(schema) do
    {not_clause, schema_without_not} = Map.pop(schema, "not", nil)
    schema_without_not |> gen(opts) |> filter_not(not_clause)
  end

  defp gen(true, _), do: json()
  defp gen(s, _) when map_size(s) == 0, do: json()
  defp gen(%{"$ref" => pointer}, opts), do: Context.get_ref(pointer) |> from_json_schema(opts)
  defp gen(%{"const" => value}, _), do: StreamData.constant(value)
  defp gen(%{"enum" => values}, _) when is_list(values), do: StreamData.member_of(values)

  defp gen(%{"type" => "boolean"}, _), do: StreamData.boolean()
  defp gen(%{"type" => "null"}, _), do: StreamData.constant(nil)

  defp gen(%{"multipleOf" => multiple_of} = schema, opts) when is_number(multiple_of) do
    schema
    |> Map.delete("multipleOf")
    |> Map.put("type", "integer")
    |> scale_limit("minimum", multiple_of)
    |> scale_limit("maximum", multiple_of)
    |> gen(opts)
    |> StreamData.map(fn generated ->
      if is_integer(multiple_of) do
        generated * multiple_of
      else
        [_, decimals] = multiple_of |> to_string() |> String.split(".")
        Float.round(generated * multiple_of, String.length(decimals))
      end
    end)
  end

  defp gen(%{"type" => "integer"} = schema, _) do
    StreamData.frequency([
      {90, regular_integer(schema)},
      {5, close_to_max(schema)},
      {5, close_to_min(schema)}
    ])
    |> filter_value(schema["exclusiveMinimum"])
    |> filter_value(schema["exclusiveMaximum"])
  end

  defp gen(%{"type" => "number"} = schema, opts) do
    StreamData.frequency([
      {50, gen(float_to_int(schema), opts)},
      {50, gen_float(schema)}
    ])
  end

  # pattern always takes priority above format, because format is not stanarized
  # in the newer drafts.
  defp gen(%{"type" => "string", "pattern" => pattern} = schema, _) do
    opts = to_keyword(schema, max_length: "maxLength") |> Keyword.put(:character_set, :printable)
    pattern |> MoreStreamData.from_regex(opts) |> filter_min_length(schema["minLength"])
  end

  defp gen(%{"type" => "string", "format" => "email"} = schema, _) do
    # Handle separately because `email` supports `maxLength`
    MoreStreamData.email(to_keyword(schema, max_length: "maxLength"))
  end

  defp gen(%{"type" => "string", "format" => format} = schema, _) do
    format
    |> from_format()
    |> filter_min_length(schema["minLength"])
    |> filter_max_length(schema["maxLength"])
  end

  defp gen(%{"type" => "string"} = schema, opts) do
    string_opts = to_keyword(schema, min_length: "minLength", max_length: "maxLength")

    case Keyword.fetch!(opts, :string_kind) do
      nil ->
        [:utf8, :printable, :ascii]
        |> Enum.map(fn codepoints -> {1, StreamData.string(codepoints, string_opts)} end)
        |> StreamData.frequency()

      kind ->
        StreamData.string(kind, string_opts)
    end
    |> filter_min_length(schema["minLength"])
  end

  defp gen(%{"anyOf" => schemas}, opts) when is_list(schemas) do
    StreamData.one_of(Enum.map(schemas, &from_json_schema(&1, opts)))
  end

  defp gen(%{"type" => "array"} = schema, opts), do: array_gen(schema, opts)
  defp gen(%{"type" => "object"} = schema, opts), do: object_gen(schema, opts)

  defp filter_value(generator, nil), do: generator
  defp filter_value(generator, value), do: StreamData.filter(generator, &(&1 != value))

  defp filter_not(generator, nil), do: generator

  defp filter_not(generator, clauses) do
    not_schema = Context.build!(%{"not" => clauses})
    StreamData.filter(generator, &match?({:ok, _}, JSV.validate(&1, not_schema)))
  end

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

  defp gen_array_length(schema) do
    schema
    |> Map.put_new("minItems", 0)
    |> to_keyword(min: "minItems", max: "maxItems")
    |> Keyword.reject(fn {_k, v} -> is_nil(v) end)
    |> MoreStreamData.more_integer()
  end

  defp array_gen(%{"prefixItems" => prefix_items} = schema, opts) do
    # Decide the length in advance. This forces schemas using prefixItems
    # to be more explicit if they actually expect all prefixItems to be present
    schema
    |> gen_array_length()
    |> StreamData.bind(fn array_length ->
      if array_length <= length(prefix_items) do
        prefix_items
        |> Enum.take(array_length)
        |> Enum.map(&from_json_schema(&1, opts))
        |> StreamData.fixed_list()
      else
        prefix_items
        |> Enum.map(&from_json_schema(&1, opts))
        |> StreamData.fixed_list()
        |> StreamData.bind(fn prefix_items_gen ->
          items_length = array_length - length(prefix_items)

          schema
          |> Map.delete("prefixItems")
          |> Map.put("minItems", items_length)
          |> Map.put("maxItems", items_length)
          |> from_json_schema(opts)
          |> StreamData.map(fn items -> prefix_items_gen ++ items end)
        end)
      end
    end)
  end

  defp array_gen(%{"items" => false}, _), do: StreamData.constant([])

  defp array_gen(%{"items" => %{"enum" => values}, "uniqueItems" => true} = array, _) do
    MoreStreamData.sample(
      values,
      to_keyword(array, min_length: "minItems", max_length: "maxItems")
    )
  end

  defp array_gen(%{"items" => items, "uniqueItems" => true} = array, opts) do
    if Map.has_key?(array, "minItems") and array["minItems"] > 0 do
      length_opts = to_keyword(array, min_length: "minItems", max_length: "maxItems")

      StreamData.uniq_list_of(from_json_schema(items, opts), length_opts)
      |> scale_log(length_opts)
    else
      # This is to avoid the "TooManyDuplicatesError" from StreamData.
      # If there is no `minItems` constraint then create a list and then
      # keep only the unique ones
      StreamData.list_of(from_json_schema(items, opts), to_keyword(array, max_length: "maxItems"))
      |> scale_log()
      |> StreamData.map(&Enum.uniq/1)
    end
  end

  defp array_gen(%{"items" => items} = array, opts) do
    length_opts = to_keyword(array, min_length: "minItems", max_length: "maxItems")

    StreamData.list_of(from_json_schema(items, opts), length_opts)
    |> scale_log(length_opts)
  end

  # No items, default to random integers for now
  defp array_gen(array, opts), do: gen(Map.put(array, "items", true), opts)

  defp can_generate_props?(s) do
    s["additionalProperties"] != false or s["patternProperties"] not in [nil, %{}, false]
  end

  defp object_gen(schema, opts) do
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
        max_props -> min(length(optional), max_props - length(required))
      end

    MoreStreamData.sample(optional, min_length: min_optionals, max_length: max_optionals)
    |> StreamData.bind(fn optionals_chosen ->
      (required ++ optionals_chosen)
      |> Map.new(fn name -> {name, from_json_schema(properties[name], opts)} end)
      |> StreamData.fixed_map()
    end)
    |> StreamData.bind(fn current_map -> pattern_properties(schema, current_map, opts) end)
    |> StreamData.bind(fn current_map -> additional_properties(schema, current_map, opts) end)
    |> StreamData.map(fn current_map ->
      pop_dependent_required(current_map, Map.get(schema, "dependentRequired", %{}))
    end)
  end

  defp pop_dependent_required(gen_value, dependent_required) do
    pop_dependent_required(gen_value, dependent_required, Map.keys(dependent_required))
  end

  defp pop_dependent_required(gen_value, _, []), do: gen_value

  defp pop_dependent_required(gen_value, dependent_required, [dep | rest]) do
    if Enum.all?(Map.get(dependent_required, dep, []), &Map.has_key?(gen_value, &1)) do
      pop_dependent_required(gen_value, dependent_required, rest)
    else
      # Search all the dependent_required that contain the key we just deleted, or nothing
      # if we didn't delete anything
      to_check =
        if Map.has_key?(gen_value, dep) do
          Enum.filter(dependent_required, fn {prop, deps} -> dep in deps and prop != dep end)
          |> Enum.map(fn {prop, _} -> prop end)
        else
          []
        end

      pop_dependent_required(
        Map.delete(gen_value, dep),
        dependent_required,
        Enum.uniq(rest ++ to_check)
      )
    end
  end

  defp pattern_properties(%{"patternProperties" => pattern_props} = schema, current_gen, opts) do
    defined_properties = Map.get(schema, "properties", %{}) |> Map.keys()

    pattern_properties_opts = pattern_properties_length(schema, map_size(current_gen))

    Enum.map(pattern_props, fn {pattern, subschema} ->
      key_gen =
        MoreStreamData.from_regex(pattern, character_set: :printable)
        |> StreamData.filter(&(&1 not in defined_properties))

      value_gen = from_json_schema(subschema, opts)

      StreamData.tuple({key_gen, value_gen})
    end)
    |> StreamData.one_of()
    |> then(fn pattern_props_gen ->
      if pattern_properties_opts[:min_length] == 0 do
        # Duplicate keys don't matter, will be discarded when we create the map
        StreamData.list_of(pattern_props_gen)
      else
        opts_with_uniq_fun =
          Keyword.put(pattern_properties_opts, :uniq_fun, fn {key, _val} -> key end)

        StreamData.uniq_list_of(pattern_props_gen, opts_with_uniq_fun)
      end
    end)
    |> scale_log(pattern_properties_opts)
    |> StreamData.map(fn key_value_pairs -> Map.merge(Map.new(key_value_pairs), current_gen) end)
  end

  defp pattern_properties(_, current_gen, _), do: StreamData.constant(current_gen)

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

  defp additional_properties(%{"additionalProperties" => false}, current_gen, _) do
    StreamData.constant(current_gen)
  end

  defp additional_properties(schema, current_gen, opts) do
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
        additional_properties_no_min(schema, current_gen, length_opts, opts)

      true ->
        additional_properties_with_min(schema, current_gen, length_opts, opts)
    end
  end

  defp additional_properties_with_min(schema, current_gen, length_opts, opts) do
    additional_props = Map.get(schema, "additionalProperties", true)

    pattern_properties =
      Map.get(schema, "patternProperties", %{}) |> Map.keys() |> Enum.map(&Regex.compile!/1)

    property_names =
      Map.get(schema, "propertyNames", Map.new()) |> Map.put_new("type", "string")

    existing_keys =
      Enum.uniq(Map.keys(Map.get(schema, "properties", %{})) ++ Map.keys(current_gen))

    StreamData.map_of(
      from_json_schema(property_names, opts)
      |> StreamData.filter(fn name ->
        not (name in existing_keys or matches_any_regex?(name, pattern_properties))
      end),
      from_json_schema(additional_props, opts),
      length_opts
    )
    |> scale_log(length_opts)
    |> StreamData.map(fn additional_props -> Map.merge(additional_props, current_gen) end)
  end

  defp additional_properties_no_min(schema, current_gen, length_opts, opts) do
    additional_props = Map.get(schema, "additionalProperties", true)

    pattern_properties =
      schema |> Map.get("patternProperties", %{}) |> Map.keys() |> Enum.map(&Regex.compile!/1)

    existing_keys =
      Enum.uniq(Map.keys(Map.get(schema, "properties", %{})) ++ Map.keys(current_gen))

    property_names =
      Map.get(schema, "propertyNames", Map.new()) |> Map.put_new("type", "string")

    {from_json_schema(property_names, opts), from_json_schema(additional_props, opts)}
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

  defp scale_limit(schema, key, multiple_of) do
    case Map.get(schema, key) do
      val when is_number(val) -> Map.put(schema, key, trunc(val / multiple_of))
      nil -> schema
    end
  end

  defp scale_log(gen, length_opts \\ []) do
    min_length = Keyword.get(length_opts, :min_length, 0)
    max_length = Keyword.get(length_opts, :max_length, nil)

    StreamData.scale(gen, fn size ->
      case {size, min_length, max_length} do
        {0, min, _max} -> min
        {size, min, nil} -> ceil(:math.log(size)) + min
        {size, min, max} -> min(ceil(:math.log(size)) + min, max)
      end
    end)
  end

  defp regular_integer(schema) do
    [min: Schemas.Number.min_value(schema), max: Schemas.Number.max_value(schema)]
    |> Keyword.filter(fn {_, v} -> not is_nil(v) end)
    |> MoreStreamData.more_integer()
  end

  defp close_to_max(schema) do
    max = Schemas.Number.max_value(schema) || 2_147_483_647
    min = Schemas.Number.min_value(schema) || -2_147_483_648

    StreamData.integer(0..(max - min))
    |> StreamData.map(fn val -> max - val end)
  end

  defp close_to_min(schema) do
    max = Schemas.Number.max_value(schema) || 2_147_483_647
    min = Schemas.Number.min_value(schema) || -2_147_483_648

    StreamData.integer(0..(max - min))
    |> StreamData.map(fn val -> val + min end)
  end

  defp gen_float(schema) do
    StreamData.frequency([
      {90, regular_float(schema)},
      {5, close_to_max_float(schema)},
      {5, close_to_min_float(schema)}
    ])
  end

  defp regular_float(schema) do
    [
      min: Schemas.Number.min_value(schema),
      max: Schemas.Number.max_value(schema),
      exclude_min?: Map.has_key?(schema, "exclusiveMinimum"),
      exclude_max?: Map.has_key?(schema, "exclusiveMaximum")
    ]
    |> MoreStreamData.more_float()
  end

  defp close_to_max_float(schema) do
    max = Schemas.Number.max_value(schema) || 8.94e307
    min = Schemas.Number.min_value(schema) || -8.94e307

    StreamData.float(min: 0, max: max - min)
    |> StreamData.map(fn val -> max - val end)
  end

  defp close_to_min_float(schema) do
    max = Schemas.Number.max_value(schema) || 8.94e307
    min = Schemas.Number.min_value(schema) || -8.94e307

    StreamData.float(min: 0, max: max - min)
    |> StreamData.map(fn val -> val + min end)
  end

  defp float_to_int(%{"type" => "number"} = schema) do
    ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"]
    |> Enum.reduce(Map.put(schema, "type", "integer"), fn key, acc_schema ->
      if Map.has_key?(acc_schema, key) do
        Map.update!(acc_schema, key, &trunc/1)
      else
        acc_schema
      end
    end)
  end
end

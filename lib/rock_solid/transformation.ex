defmodule RockSolid.Transformation do
  @moduledoc false
  alias RockSolid.Combinatorics
  alias RockSolid.Context
  alias RockSolid.Exceptions.InvalidSchema
  alias RockSolid.Intersection
  alias RockSolid.Schemas
  alias RockSolid.Schemas.Schema

  import RockSolid.Traversal, only: [property?: 1, is_atomic: 1]

  require Logger

  @reasonable_combinations 12

  @doc """
  Simplifies a JSON schema to a canonical format
  """
  def simplify(%{"$id" => uri} = schema) do
    Context.put_schema(schema)

    schema
    |> simplify(_root = ["#"])
    |> tap(&Context.put_simplified(uri, &1))
  end

  def simplify(schema, rev_path) do
    cond do
      property?(rev_path) or hd(rev_path) in ["$defs", "dependentSchemas"] ->
        Map.new(schema, fn {k, v} -> {k, simplify(v, [k | rev_path])} end)

      is_atomic(schema) ->
        schema

      hd(rev_path) in ["dependentRequired", "required"] and not property?(tl(rev_path)) ->
        schema

      is_list(schema) ->
        for {val, idx} <- Enum.with_index(schema), do: simplify(val, [to_string(idx) | rev_path])

      Map.has_key?(schema, "$ref") ->
        simplify_ref(schema, rev_path)

      Map.has_key?(schema, "const") ->
        {:ok, enums} = enums_matching_all([schema["const"]], [schema])
        drop_non_keywords(enums)

      Map.has_key?(schema, "enum") ->
        {:ok, enums} = enums_matching_all(schema["enum"], [schema])
        drop_non_keywords(enums)

      schema == %{"not" => true} ->
        false

      true ->
        schema |> drop_non_keywords() |> postorder_simplify(rev_path)
    end
  end

  def drop_non_keywords(schema) do
    schema |> Map.drop(non_keywords()) |> Map.reject(&custom_key_value_pair?/1)
  end

  defp non_keywords do
    ["description", "example", "examples", "title", "default"]
  end

  defp custom_key_value_pair?({"x-" <> _, _}), do: true
  defp custom_key_value_pair?(_), do: false

  defp postorder_simplify(schema, rev_path) do
    simplified = Map.new(schema, fn {k, v} -> {k, simplify(v, [k | rev_path])} end)

    simplify_funcs()
    |> Enum.reduce_while([simplified], fn func, accs ->
      case Enum.flat_map(accs, func) |> Enum.reject(&(&1 == false)) do
        [] -> {:halt, []}
        other when is_list(other) -> {:cont, other}
      end
    end)
    # This is a bit inefficient because we are generating a bunch of extra schemas.
    # The problem comes because `$ref` are expanded to every possible type. Instead
    # what we should do is extract them into a "$ref" type and perform intersection
    # with `"$ref"` types. The problem is that `common_types` might be empty in
    # `all_of_to_any_of` and we have to consider it. Refine the algorithm later.
    # So far this will take longer and might generate additional redundant `anyOf`
    # if enums are merged out of order. For example:
    # %{"anyOf" => [%{"enum" => [1, 2]}, %{"enum" => [2,1]}]}
    |> Enum.uniq()
    |> case do
      [] -> raise InvalidSchema, reason: :empty_simplification, schema: schema
      [one_schema] -> one_schema
      schemas when is_list(schemas) -> %{"anyOf" => schemas}
    end
  end

  defp simplify_funcs do
    [
      &to_schemas_by_types/1,
      &expand_dependent_schemas/1,
      &expand_case_schema/1,
      &expand_if_then_else/1,
      &merge_boolean_schemas/1
    ]
  end

  @doc """
  Converts a schema that indirectly supports muliple types to an equivalent `anyOf`
  schema
  """
  @spec to_any_of(Schema.t()) :: Schema.t()
  def to_any_of(schema) when is_map(schema) do
    schema
    |> split_by_types()
    |> Map.values()
    |> case do
      [single_type] -> single_type
      many_types when length(many_types) > 1 -> %{"anyOf" => many_types}
    end
  end

  def to_any_of(schema) when is_boolean(schema), do: schema

  defp to_schemas_by_types(schema), do: Map.values(split_by_types(schema))

  @spec split_by_types(Schema.t()) :: %{String.t() => Schema.t()}
  defp split_by_types(true) do
    Map.new(Schema.base_types(), fn type -> {type, %{"type" => type}} end)
  end

  defp split_by_types(false), do: %{}

  defp split_by_types(schema) when is_map(schema) do
    Enum.reduce(schema, Map.new(), fn {key, value}, acc ->
      Enum.reduce(types(key, value), acc, fn type, acc ->
        new_acc = Map.put_new(acc, type, default(type))

        case key do
          # Do not override "type" key, otherwise we can end up
          # with %{"type" => ["number", "array"]} again because
          # the value overwrites the default inserted by `put_new`
          "type" ->
            # The only edge case is if we have "integer" in types but not
            # "number", in that case we have to replace it. If we have
            # ["number", "integer"] then "number" wins
            if value == "integer" or
                 (is_list(value) and "integer" in value and "number" not in value) do
              # Because we might reach this part before 'number' type is parsed
              # we had to add an extra `Map.put_new` just in case
              new_acc
              |> Map.put_new("number", %{"type" => "integer"})
              |> put_in(["number", "type"], "integer")
            else
              new_acc
            end

          # In case of enum we have to append if the value already exists
          # We might not need `enum` and `const` at all if we always convert
          # from schema with `enum` or `const` to single enum list
          "enum" ->
            # Fix this later, we are traversing everything multiple times for each
            # enum
            insert_enums(new_acc, value)

          # Other regular keys are simply inserted
          other ->
            put_in(new_acc, [type, other], value)
        end
      end)
    end)
    |> add_unspecified_types()
    |> keep_explicit_types(Map.take(schema, ["const", "type", "enum"]))
  end

  defp insert_enums(schemas_by_type, enums) do
    Enum.reduce(enums, schemas_by_type, fn enum, acc ->
      [type] = types("const", enum)

      acc
      |> Map.put_new(type, default(type))
      |> update_in([type, "enum"], fn
        nil -> [enum]
        values when is_list(values) -> Enum.uniq(values ++ [enum])
      end)
    end)
  end

  # These are not part of the schemas validation module, handle separately
  defp types("dependentSchemas", _), do: ["object"]
  defp types("type", "integer"), do: ["number"]
  defp types("type", type) when is_binary(type), do: [type]
  defp types("type", types) when is_list(types), do: Enum.flat_map(types, &types("type", &1))

  defp types("const", val), do: [enum_type(val)]
  defp types("enum", values), do: values |> Enum.map(&enum_type/1) |> Enum.uniq()

  defp types("format", format) do
    Enum.find_value(all_schemas(), fn {type, module} ->
      if Enum.member?(Schema.formats(module), format) do
        type
      end
    end)
    |> case do
      nil -> []
      type -> [type]
    end
  end

  defp types(key, _value) do
    Enum.reduce(all_schemas(), MapSet.new(), fn {type, module}, acc ->
      if key in Schema.fields(module), do: MapSet.put(acc, type), else: acc
    end)
  end

  defp all_schemas do
    [
      {"boolean", Schemas.Boolean},
      {"null", Schemas.Null},
      {"number", Schemas.Number},
      {"array", Schemas.Array},
      {"string", Schemas.String},
      {"object", Schemas.Object}
    ]
  end

  defp enum_type(t) when is_boolean(t), do: "boolean"
  defp enum_type(t) when is_number(t), do: "number"
  defp enum_type(t) when is_list(t), do: "array"
  defp enum_type(t) when is_binary(t), do: "string"
  defp enum_type(t) when is_map(t), do: "object"
  defp enum_type(nil), do: "null"

  defp default(type), do: %{"type" => type}

  # If `const`, `enum` or `types` was specified then the types are explicit, keep
  # only the possible types.
  #
  # Validate if `const` is present then the value matches the original schema
  # If `enum` is present (and `const` isn't) then keep only the values that match
  # the schema.
  # We should do this before in the pre-simplification step
  defp keep_explicit_types(types_map, %{"const" => c}), do: Map.take(types_map, types("const", c))
  defp keep_explicit_types(types_map, %{"enum" => e}), do: Map.take(types_map, types("enum", e))
  defp keep_explicit_types(types_map, %{"type" => t}), do: Map.take(types_map, types("type", t))
  defp keep_explicit_types(types_map, _), do: types_map

  defp add_unspecified_types(types_map) do
    Enum.reduce(Schema.base_types(), types_map, fn type, acc ->
      Map.put_new(acc, type, default(type))
    end)
  end

  @doc """
  Converts an `allOf` list of schemas to the equivalent `anyOf`
  """
  @spec all_of_to_any_of(list(Schema.t())) :: {:ok, Schema.t()} | {:error, any()}
  def all_of_to_any_of(schemas) when is_list(schemas) do
    case collect_enums(schemas) do
      [] -> all_of_to_any_of_schemas(schemas)
      enums -> enums_matching_all(enums, schemas)
    end
  end

  defp collect_enums(schemas) when is_list(schemas) do
    schemas
    |> Enum.flat_map(fn schema ->
      case schema do
        %{"const" => const} -> [const]
        %{"enum" => enums} -> enums
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp enums_matching_all(enums, schemas) when is_list(enums) and is_list(schemas) do
    j_schemas = Enum.map(schemas, &Context.build!/1)

    enums
    |> Enum.filter(fn enum ->
      Enum.all?(j_schemas, fn j_schema -> match?({:ok, _}, JSV.validate(enum, j_schema)) end)
    end)
    |> case do
      [] -> {:error, "no enum in #{inspect(enums)} matches schemas: #{inspect(schemas)}"}
      other when is_list(other) -> {:ok, %{"enum" => other}}
    end
  end

  defp all_of_to_any_of_schemas(schemas) when is_list(schemas) do
    by_types = Enum.map(schemas, &split_by_types/1)

    common_types =
      by_types
      |> Enum.map(&Map.keys/1)
      |> Enum.reduce(fn k1, k2 -> MapSet.intersection(MapSet.new(k1), MapSet.new(k2)) end)
      |> Enum.to_list()

    by_types
    |> Enum.map(&Map.take(&1, common_types))
    |> Enum.reduce(fn map1, map2 ->
      Map.merge(map1, map2, fn _k, v1, v2 -> Intersection.safe_intersection(v1, v2) end)
    end)
    |> Map.values()
    |> discard_impossible_intersections()
    |> case do
      [] -> {:error, "empty anyOf"}
      [value] -> {:ok, value}
      values when is_list(values) -> {:ok, %{"anyOf" => values}}
    end
  end

  @doc """
  Converts a list of `oneOf` to the equivalent `anyOf`
  """
  @spec one_of_to_any_of(list(Schema.t())) :: {:ok, Schema.t()} | {:error, any()}
  def one_of_to_any_of(schemas) when is_list(schemas) do
    num_clauses = length(schemas)

    if num_clauses > @reasonable_combinations do
      Logger.warning("""
      Too many 'oneOf' clauses provided (#{num_clauses}). Generation might timeout if
      the clauses are not mutually exclusive. Consider replacing by an 'anyOf' clause
      with mutually exclusive subschemas.
      """)
    end

    schemas
    |> Enum.with_index()
    |> Enum.map(fn {schema, i} -> to_mutually_exclusive(schema, List.delete_at(schemas, i)) end)
    |> Enum.reject(&Intersection.impossible?/1)
    |> case do
      [] -> {:error, "impossible oneOf condition"}
      [value] -> {:ok, value}
      values when is_list(values) -> {:ok, %{"anyOf" => values}}
    end
  end

  def one_of_to_any_of(%{"oneOf" => schemas}), do: one_of_to_any_of(schemas)
  def one_of_to_any_of(schema) when is_map(schema), do: {:ok, true}

  defp to_mutually_exclusive(schema, others) do
    intersections =
      others
      |> Enum.map(&Intersection.safe_intersection(&1, schema))
      |> Enum.reject(&(&1 == false))

    Intersection.Not.add_clauses(schema, intersections)
  end

  @doc """
  Expands an `if/then/else` clause into multiple clauses and returns a list
  of possible schemas
  """
  @spec expand_if_then_else(Schema.t()) :: list(Schema.t())
  def expand_if_then_else(%{"if" => if_, "then" => then_} = schema) do
    else_ = Map.get(schema, "else", true)
    schema = Map.drop(schema, ["if", "then", "else"])

    case Intersection.safe_intersection(schema, if_) do
      # Consider special case where if never matches, no need to add the `not` clause
      # to the else case
      false ->
        [Intersection.safe_post_intersection(schema, else_)]

      if_intersection ->
        [
          Intersection.safe_post_intersection(if_intersection, then_),
          schema |> Intersection.Not.add_clause(if_) |> Intersection.safe_post_intersection(else_)
        ]
    end
    |> discard_impossible_intersections()
  end

  def expand_if_then_else(schema), do: [schema]

  @doc """
  Converts a schema with `anyOf`, `oneOf` and/or `allOf` into a list of `anyOf` schemas
  """
  @spec merge_boolean_schemas(list(Schema.t())) :: list(Schema.t())
  def merge_boolean_schemas(schema) when is_map(schema) do
    {bools, schema} = Map.split(schema, ["anyOf", "oneOf", "allOf"])

    schema = if(map_size(schema) == 0, do: true, else: schema)
    any_of = if(Map.has_key?(bools, "anyOf"), do: Map.take(bools, ["anyOf"]), else: true)

    with {:ok, all_of} <- all_of_to_any_of(Map.get(bools, "allOf", [true])),
         {:ok, one_of} <- one_of_to_any_of(bools) do
      case Enum.reduce([schema, any_of, one_of, all_of], &Intersection.safe_intersection(&1, &2)) do
        %{"anyOf" => values} -> values
        false -> []
        value -> [value]
      end
    else
      {:error, _} -> []
    end
  end

  @doc """
  Expands a schema with `dependentSchemas` to a list of all the combinations
  of properties. Impossible cases are discarded
  """
  @spec expand_dependent_schemas(Schema.t()) :: [Schema.t()]
  def expand_dependent_schemas(%{"dependentSchemas" => _} = schema) do
    dependent_schemas = schema |> Map.fetch!("dependentSchemas") |> Map.keys()

    num_props = length(dependent_schemas)

    if num_props > @reasonable_combinations do
      Logger.warning("""
      Too many 'dependentSchemas'/'dependencies' clauses #{num_props} found.
      Generation might timeout
      """)
    end

    dependent_schemas
    |> Combinatorics.power_set()
    |> Enum.map(fn req_props -> intersect_dependent_schemas(schema, req_props) end)
    |> discard_impossible_intersections()
  end

  def expand_dependent_schemas(schema), do: [schema]

  defp intersect_dependent_schemas(schema, properties) do
    forbidden_props =
      schema |> Map.get("dependentSchemas", %{}) |> Map.keys() |> Enum.reject(&(&1 in properties))

    new_schema =
      schema
      |> Map.update("required", properties, fn req -> Enum.uniq(req ++ properties) end)
      |> add_forbidden_properties(forbidden_props)
      |> Map.delete("dependentSchemas")

    Enum.reduce(properties, new_schema, fn prop, acc ->
      Intersection.safe_intersection(acc, schema["dependentSchemas"][prop])
    end)
  end

  @doc """
  Adds a list of banned properties to the schema, that should never be added
  because they conflict with a previous intersection. Returns the updated schema,
  or false if one of the banned properties is required
  """
  def add_forbidden_properties(schema, []), do: schema

  def add_forbidden_properties(schema, forbidden_properties) when is_list(forbidden_properties) do
    if Enum.any?(Map.get(schema, "required") || [], &(&1 in forbidden_properties)) do
      false
    else
      no_props = Map.from_keys(forbidden_properties, false)
      Map.update(schema, "properties", no_props, &Map.merge(&1, no_props))
    end
  end

  @doc """
  Expands a case schema into a list of mutually exclusive schemas. A case
  schema is written as an %{"allOf": [%{"if" => ..., "else" => ...}, %{"if" => ...}]}
  """
  def expand_case_schema(schema) do
    if(case_schema?(schema), do: do_expand_case_schema(schema), else: [schema])
  end

  defp do_expand_case_schema(schema) do
    {all_of, base_schema} = Map.pop(schema, "allOf")
    {if_cases, rest} = split_if_then_clauses(all_of)

    base_schema = Enum.reduce(rest, base_schema, &Intersection.safe_intersection/2)

    Enum.reduce(if_cases, [base_schema], fn if_case, schemas ->
      Enum.flat_map(schemas, fn schema ->
        schema
        |> Map.merge(Map.take(if_case, ["if", "then", "else"]))
        |> expand_if_then_else()
      end)
    end)
    |> discard_impossible_intersections()
  end

  defp case_schema?(%{"allOf" => all_of}), do: Enum.any?(all_of, &if_then_case?/1)
  defp case_schema?(_), do: false

  defp split_if_then_clauses(clauses), do: Enum.split_with(clauses, &if_then_case?/1)

  defp if_then_case?(%{"if" => _, "then" => _}), do: true
  defp if_then_case?(_), do: false

  defp discard_impossible_intersections(schemas), do: Enum.reject(schemas, &(&1 == false))

  @doc """
  Simplifies "required" and "dependentRequired" by including in "required" all
  the properties that depend on another "required" property and removes them
  from dependentRequired list.

  For example an object containing
  ```elixir
  %{
    "required" => ["name"],
    "dependentRequired" => %{"name" => ["age"], "birthDate" => ["passportNumber"]}
  }
  ```
  is converted to
  ```elixir
  %{
    "required" => ["name", "age"],
    "dependentRequired" => %{"birthDate" => ["passportNumber"]}
  }
  ```
  """
  def simplify_dependent_required(%{"required" => req, "dependentRequired" => dep_req} = schema) do
    {required, dependent_required} =
      simplify_dependent_required(:queue.from_list(req), dep_req, MapSet.new())

    schema = Map.put(schema, "required", required)

    if map_size(dependent_required) == 0 do
      Map.delete(schema, "dependentRequired")
    else
      Map.put(schema, "dependentRequired", dependent_required)
    end
  end

  def simplify_dependent_required(schema), do: schema

  defp simplify_dependent_required(queue, dependent_required, required) do
    case :queue.out(queue) do
      {:empty, _} ->
        {
          MapSet.to_list(required),
          Map.filter(dependent_required, fn {_k, v} -> not Enum.empty?(v) end)
        }

      {{:value, property_name}, updated_queue} ->
        if MapSet.member?(required, property_name) do
          simplify_dependent_required(updated_queue, dependent_required, required)
        else
          {deps, new_dependent_required} = Map.pop(dependent_required, property_name, [])

          new_dependent_required =
            Map.new(new_dependent_required, fn {prop_name, deps} ->
              {prop_name, Enum.reject(deps, &(&1 == property_name))}
            end)

          new_required = MapSet.put(required, property_name)
          new_queue = :queue.join(updated_queue, :queue.from_list(deps))
          simplify_dependent_required(new_queue, new_dependent_required, new_required)
        end
    end
  end

  defp simplify_ref(%{"$ref" => ref_ptr, "x-rocksolid-refbehaviour" => "ignore"}, _) do
    %{"$ref" => ref_ptr}
  end

  defp simplify_ref(%{"$ref" => _, "x-rocksolid-refbehaviour" => "merge"} = ref_schema, rev_path) do
    {ref, rest} = Map.split(ref_schema, ["$ref"])
    rest = drop_non_keywords(rest)
    {ref_value, rest} = extract_additional_properties(ref, rest)

    if rest == %{} do
      ref_value
    else
      {:ok, intersection} = Intersection.intersection(ref_value, simplify(rest, rev_path))
      intersection
    end
  end

  # Edge case. `additionalProperties` is excluded if `$ref` already contains it, otherwise
  # it's put inside `$ref`
  defp extract_additional_properties(%{"$ref" => ref_ptr}, %{"additionalProperties" => _} = rest) do
    {additional_props, rest_no_props} = Map.pop!(rest, "additionalProperties")
    ref_val = Context.get_ref(ref_ptr)

    {Map.put_new(ref_val, "additionalProperties", additional_props), rest_no_props}
  end

  defp extract_additional_properties(ref, rest), do: {ref, rest}
end

defmodule RockSolid.Migration do
  @moduledoc """
  Migration from older schema versions to latest 2020-12 draft
  """

  import RockSolid.Traversal

  alias RockSolid.Context
  alias RockSolid.Exceptions.InvalidKeyword
  alias RockSolid.Resolution
  alias RockSolid.Schemas.Vocabulary

  @type path_rename() :: {RockSolid.Traversal.path_t(), RockSolid.Traversal.path_t()}
  @type paths_rename() :: list(path_rename())

  @root_path ["#"]

  @doc """
  Migrates a schema to latest 2020-12 draft.

  All the changes implemented are as follows:
  - `"id"` -> `"$id"`
  - `"items"` and `"additionalItems"` -> `"prefixItems"` and `"items"`. Only when `"items"`
  is an array
  - `"dependencies"` -> `"dependentRequired"` and `"dependentSchemas"`
  - `"$schema"` is set to draft 2020
  - `"definitions"` -> `"$defs"`
  - `"exclusiveMinimum"` and `"minimum"` -> "`exclusiveMinimum"`. Only when `"exclusiveMinimum"`
  is a boolean. Same applies for `"exclusiveMaximum"`
  - empty schema object is replaced by `true`, except in `"properties"` and "patternProperties"
  where empty means no properties defined
  - All `$ref` are also updated accordingly to the new paths. For example a reference
  pointing to `#/definitions/person` is converted to `#/$defs/person`.

  Additionally, the function checks that no unsupported keywords or patterns are present.
  """
  def migrate(schema, resolver) when is_map(schema) do
    all_schemas = Resolution.fetch_all!(schema, resolver)
    check_unsupported_keywords(Map.values(all_schemas))

    {schemas, path_changes} =
      all_schemas
      |> Enum.map(&put_id/1)
      |> Enum.map(&put_ref_behaviour/1)
      |> Enum.reduce({[], []}, fn schema, {schemas, path_changes} ->
        {new_schema, new_path_changes} = migrate(schema, @root_path, migrations(schema))
        {[new_schema | schemas], [{Resolution.id(new_schema), new_path_changes} | path_changes]}
      end)

    schemas =
      schemas
      |> Enum.map(&update_refs(&1, path_changes))
      |> anchors_to_pointers()
      |> relative_refs_to_absolute()

    :ok = Enum.each(schemas, &Context.put_schema/1)

    # Return the schema that contains the `$id` of the original, or with the default value
    root = Enum.find(schemas, &(Resolution.id(&1) == Resolution.id(schema)))

    if is_nil(root), do: raise("root not found")
    root
  end

  defp migrate(s, ["$schema" | _] = path, _funcs) when is_binary(s) do
    if(property?(path) or definition?(path), do: {s, []}, else: {Vocabulary.draft2020_12(), []})
  end

  defp migrate(schema, path, funcs) when is_list(schema) do
    schema
    |> Enum.with_index()
    |> Enum.reduce({[], []}, fn {s, idx}, {new_s, modified} ->
      {new_val, new_modified} = migrate(s, [to_string(idx) | path], funcs)
      {new_s ++ [new_val], new_modified ++ modified}
    end)
  end

  # Special case for empty map
  # properties and patternProperties are converted to false, the rest are true
  defp migrate(schema, [last | rest] = path, _funcs)
       when is_map(schema) and map_size(schema) == 0 do
    cond do
      literal?(path) -> {schema, []}
      last in ["properties", "patternProperties"] and not property?(rest) -> {schema, []}
      true -> {true, []}
    end
  end

  defp migrate(schema, path, funcs) when is_map(schema) do
    if literal?(path) do
      # Reached an `enum`, `const`, `default` or `examples`, do early return
      # because everything past this should be treated as literal, we don't want
      # to accidentally migrate `"const": {"id": "foo"} to {"$id": "foo"}`
      {schema, []}
    else
      {new_schema, path_changes} =
        cond do
          property?(path) ->
            {schema, []}

          definition?(path) ->
            {schema, []}

          dependencies?(path) ->
            {schema, []}

          true ->
            Enum.reduce(funcs, {schema, []}, fn func, {schema, path_changes} ->
              {new_schema, new_path_changes} = func.(schema, path)
              {new_schema, Enum.concat(new_path_changes, path_changes)}
            end)
        end

      Enum.reduce(new_schema, {%{}, path_changes}, fn {k, v}, {s, p} ->
        {new_val, changes} = migrate(v, [k | path], funcs)

        {Map.put(s, k, new_val), changes ++ p}
      end)
    end
  end

  defp migrate(schema, _path, _funcs), do: {schema, []}

  defp migrations(schema) do
    [
      &rename_id/2,
      &to_prefix_items/2,
      &to_dependent_required_and_dependent_schemas/2,
      &rename_definitions/2,
      &rename_exclusive_maximum/2,
      &rename_exclusive_minimum/2,
      &ignore_redundant_ids/2,
      &ignore_empty_defs/2,
      &unevaluated_to_additional_properties/2,
      fn subschema, path -> remove_self_remote(subschema, path, Resolution.id(schema)) end
    ]
  end

  defp to_prefix_items(%{"items" => items} = schema, path) when is_list(items) do
    new_schema =
      Map.put(schema, "prefixItems", items)
      |> Map.put("items", Map.get(schema, "additionalItems", true))
      |> Map.delete("additionalItems")

    modified = [
      path_change(path, "additionalItems", "items"),
      path_change(path, "items", "prefixItems")
    ]

    {new_schema, modified}
  end

  defp to_prefix_items(schema, _), do: {schema, []}

  defp to_dependent_required_and_dependent_schemas(%{"dependencies" => deps} = schema, path) do
    {dep_req, dep_schemas} = Enum.split_with(deps, fn {_k, v} -> is_list(v) end)
    {dep_req, dep_schemas} = {Map.new(dep_req), Map.new(dep_schemas)}

    # This makes things a bit faster
    dep_schemas =
      Map.new(dep_schemas, fn {dep_property, value} ->
        {dep_property, Map.put_new(value, "type", "object")}
      end)

    new_schema =
      [{"dependentRequired", dep_req}, {"dependentSchemas", dep_schemas}]
      |> Enum.reduce(Map.delete(schema, "dependencies"), fn {dep_key, val}, new_schema ->
        if Enum.empty?(val), do: new_schema, else: Map.put(new_schema, dep_key, val)
      end)

    modified_dep_req =
      dep_req
      |> Map.keys()
      |> Enum.map(fn k -> {[k, "dependencies" | path], [k, "dependentRequired" | path]} end)

    modified_dep_schemas =
      dep_schemas
      |> Map.keys()
      |> Enum.map(fn k -> {[k, "dependencies" | path], [k, "dependentSchemas" | path]} end)

    {new_schema, modified_dep_req ++ modified_dep_schemas}
  end

  defp to_dependent_required_and_dependent_schemas(schema, _), do: {schema, []}

  defp remove_self_remote(%{"$ref" => pointer} = schema, path, uri) do
    if literal?(path) or definition?(path) or property?(path) or dependencies?(path) do
      {schema, []}
    else
      {Map.put(schema, "$ref", String.trim_leading(pointer, uri)), []}
    end
  end

  defp remove_self_remote(schema, _, _), do: {schema, []}

  defp rename_id(schema, path), do: rename(schema, path, "id", "$id")
  defp rename_definitions(schema, path), do: rename(schema, path, "definitions", "$defs")

  defp rename_exclusive_minimum(%{"exclusiveMinimum" => true, "minimum" => min} = schema, path) do
    {
      Map.put(schema, "exclusiveMinimum", min) |> Map.delete("minimum"),
      [path_change(path, "minimum", "exclusiveMinimum")]
    }
  end

  defp rename_exclusive_minimum(schema, _), do: {schema, []}

  defp rename_exclusive_maximum(%{"exclusiveMaximum" => true, "maximum" => max} = schema, path) do
    {
      Map.put(schema, "exclusiveMaximum", max) |> Map.delete("maximum"),
      [path_change(path, "maximum", "exclusiveMaximum")]
    }
  end

  defp rename_exclusive_maximum(schema, _), do: {schema, []}

  @spec rename(map(), RockSolid.Traversal.path_t(), String.t(), String.t()) ::
          {map(), paths_rename()}
  defp rename(schema, path, old, new) do
    if Map.has_key?(schema, old) do
      {Map.put(schema, new, schema[old]) |> Map.delete(old), [path_change(path, old, new)]}
    else
      {schema, []}
    end
  end

  defp ignore_redundant_ids(%{"$id" => "#/" <> _} = schema, _),
    do: {Map.delete(schema, "$id"), []}

  defp ignore_redundant_ids(schema, _), do: {schema, []}

  defp ignore_empty_defs(schema, _) do
    keys = Enum.filter(["$defs", "definitions"], &(Map.get(schema, &1) == %{}))
    {Map.drop(schema, keys), []}
  end

  defp unevaluated_to_additional_properties(%{"unevaluatedProperties" => false} = schema, _) do
    {Map.put_new(schema, "additionalProperties", false), []}
  end

  defp unevaluated_to_additional_properties(schema, _), do: {schema, []}

  defp path_change(path, old, new) when is_list(path) and is_binary(old) and is_binary(new) do
    {[old | path], [new | path]}
  end

  @doc """
  Updates all old "$ref" paths by the new paths. Returns a new schema with the new "$ref"
  """
  @spec update_refs({term(), list({list(String.t()), list(String.t())})}) :: term()
  def update_refs({schema, path_changes}) do
    # Updates all the paths in "$ref" by the new path based on the changes
    # made to the schema.
    path_changes
    |> Enum.reverse()
    |> Enum.map(fn {old, new} -> {to_pointer(old), to_pointer(new)} end)
    |> do_update_refs(schema, @root_path)
  end

  @doc """
  Updates all old "$ref" paths by the new paths. Returns a new schema with the new "$ref"
  """
  def update_refs(schema, all_path_changes) do
    Enum.reduce(all_path_changes, schema, fn {id, path_changes}, schema ->
      path_changes
      |> Enum.reverse()
      |> Enum.map(fn {old, new} ->
        # If id doesn't match then the path changes are from a different schema. We have to add
        # the id (URI) such that pointers to remote schemas are also updated.
        prefix = if Resolution.id(schema) == id, do: "", else: id
        {prefix <> to_pointer(old), prefix <> to_pointer(new)}
      end)
      |> do_update_refs(schema, @root_path)
    end)
  end

  defp do_update_refs(changes, schema, path) when is_list(schema) do
    schema
    |> Enum.with_index()
    |> Enum.map(fn {s, i} -> do_update_refs(changes, s, [to_string(i) | path]) end)
  end

  defp do_update_refs(changes, schema, path) when is_map(schema) do
    if literal?(path) do
      schema
    else
      cond do
        property?(path) -> schema
        definition?(path) -> schema
        dependencies?(path) -> schema
        Map.has_key?(schema, "$ref") -> Map.update!(schema, "$ref", &update_ref(&1, changes))
        true -> schema
      end
      |> Map.new(fn {k, v} -> {k, do_update_refs(changes, v, [k | path])} end)
    end
  end

  defp do_update_refs(_changes, schema, _path), do: schema

  defp update_ref(ref, changes) when is_binary(ref) and is_list(changes) do
    Enum.reduce(changes, ref, fn {old, new}, acc -> String.replace_leading(acc, old, new) end)
  end

  # Converts all "$ref" to anchors to "$ref" to path instead.
  defp anchors_to_pointers(schemas) do
    references_map =
      Map.new(schemas, fn schema -> {Resolution.id(schema), references(schema)} end)

    # Reverse the anchors map so that we get %{"person" => ["#", "path", "to", "anchor"]}
    anchors_paths =
      Map.new(references_map, fn {schema_uri, references} ->
        anchors_map = Map.get(references, "$anchor", %{})
        {schema_uri, Map.new(anchors_map, fn {ptr, name} -> {name, ptr} end)}
      end)

    # For each schema, iterate over all the `$ref`, keep only the anchor ones by
    # rejecting "" (root) and anything that starts with "/" because it's a path.
    # The anchor name is the fragment of the URI, and from there we can get the
    # path, convert that to a pointer, update the fragment part and then set
    # the ref_path ++ ["$ref"] to the new value.

    Enum.map(schemas, fn schema ->
      references_map
      |> ref_to_anchors(schema)
      |> Enum.reduce(schema, fn {ref_rev_path, pointer_with_anchor}, schema ->
        id =
          case Resolution.base_id(pointer_with_anchor) do
            "" -> Resolution.id(schema)
            other -> other
          end

        {base, fragment} = Resolution.base_fragment(pointer_with_anchor)
        anchor_path = anchors_paths[id][fragment]
        "#" <> pointer = to_pointer(anchor_path)
        new_full_path = base <> "#" <> pointer
        ["#" | map_path] = ref_rev_path

        put_in_schema!(schema, map_path ++ ["$ref"], to_string(new_full_path))
      end)
    end)
  end

  defp relative_refs_to_absolute(schemas) when is_list(schemas) do
    Enum.map(schemas, &relative_refs_to_absolute/1)
  end

  defp relative_refs_to_absolute(%{"$id" => uri} = schema) do
    base_id = Resolution.base_id(uri)

    schema
    |> references()
    |> Map.get("$ref", %{})
    |> Map.filter(fn {_k, v} -> Resolution.base_id(v) == "" end)
    |> Enum.reduce(schema, fn {ref_path, relative_ptr}, schema ->
      full_path = ref_path ++ ["$ref"]

      {_base, fragment} = Resolution.base_fragment(relative_ptr)
      full_ref = base_id <> "#" <> fragment
      put_in_schema!(schema, full_path, full_ref)
    end)
  end

  defp ref_to_anchors(all_references_map, schema) do
    all_references_map
    |> Map.fetch!(Resolution.id(schema))
    |> Map.get("$ref", %{})
    |> Map.reject(fn {_path, value} ->
      {_base, fragment} = Resolution.base_fragment(value)

      fragment in [nil, ""] or String.starts_with?(fragment, "/")
    end)
  end

  defp check_unsupported_keywords(schemas) when is_list(schemas) do
    Enum.each(schemas, &check_unsupported_keywords/1)
  end

  defp check_unsupported_keywords(schema) when is_map(schema) do
    do_check_unsupported_keywords(schema, ["#"])
  end

  defp do_check_unsupported_keywords(schema, _) when is_atomic(schema), do: :ok

  defp do_check_unsupported_keywords(schema, rev_path) when is_list(schema) do
    schema
    |> Enum.with_index()
    |> Enum.each(fn {elem, idx} ->
      do_check_unsupported_keywords(elem, [to_string(idx) | rev_path])
    end)
  end

  defp do_check_unsupported_keywords(schema, rev_path) when is_map(schema) do
    if property?(rev_path) or hd(rev_path) == "$defs" do
      schema
      |> Enum.each(fn {k, v} -> do_check_unsupported_keywords(v, [k | rev_path]) end)
    else
      pointer = to_pointer(rev_path)
      keys = Map.keys(schema)

      Enum.each(unsupported_keywords(), fn
        kw when is_binary(kw) ->
          if kw in keys do
            raise InvalidKeyword, keyword: kw, path: pointer
          end

        {kw, check} when is_binary(kw) and is_function(check) ->
          if kw in keys and not check.(Map.fetch!(schema, kw)) do
            val = Map.fetch!(schema, kw)
            raise InvalidKeyword, keyword: kw, value: val, path: pointer
          end
      end)

      Enum.each(schema, fn {k, v} -> do_check_unsupported_keywords(v, [k | rev_path]) end)
    end
  end

  defp unsupported_keywords do
    [
      "$dynamicAnchor",
      "$dynamicRef",
      "minContains",
      "maxContains",
      {"unevaluatedProperties", fn val -> val == false end},
      {"unevaluatedItems", fn val -> val == false end}
    ]
  end

  # Sets the `x-rocksolid-refbehaviour`.
  # For draft-04, draft-06 and draft-07 `$ref` overrides everything else
  # and other keywords don't apply.
  # For draft-2019-09 and draft-2020-12 the extra keywords are applied after
  # `$ref` validates. Which is basically an intersection, with some exceptions
  # - if `$ref` contains `additionalProperties` then `additionalProperties` does not apply
  # otherwise they are inserted directly.
  # - if there is a `oneOf` they apply separately, they do not concatenate. Be careful
  # with this one.
  defp put_ref_behaviour(schema) when is_map(schema) do
    key = ref_behaviour_key()

    schema
    |> references()
    |> Map.get("$ref", %{})
    |> Map.keys()
    |> Enum.reduce(schema, fn path, new_schema ->
      # We have to try to find the $schema key, or until no schema exists and we default to 2020-12
      put_in_schema!(new_schema, path ++ [key], ref_behaviour(schema, path))
    end)
  end

  def ref_behaviour_key, do: "x-rocksolid-refbehaviour"

  defp ref_behaviour(_schema, []), do: "merge"

  defp ref_behaviour(schema, path) do
    reversed_path = Enum.reverse(path)

    if property?(reversed_path) or definition?(reversed_path) do
      ref_behaviour(schema, reversed_path |> tl() |> Enum.reverse())
    else
      case fetch_in_schema!(schema, path) do
        %{"$schema" => value} -> ref_behaviour(Vocabulary.vocabulary(value))
        _ -> ref_behaviour(schema, remove_last(path))
      end
    end
  end

  defp ref_behaviour(draft) when draft in [:draft04, :draft06, :draft07], do: "ignore"
  defp ref_behaviour(draft) when draft in [:draft2020_12, :draft2019_09], do: "merge"

  defp remove_last(l) when is_list(l), do: l |> Enum.reverse() |> tl() |> Enum.reverse()

  defp put_id({uri, %{"id" => uri} = schema}), do: schema
  defp put_id({uri, %{"$id" => uri} = schema}), do: schema
  defp put_id({uri, schema}), do: Map.put(schema, "$id", Resolution.base_id(uri))
end

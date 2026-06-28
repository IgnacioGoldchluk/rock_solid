# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

## 0.0.12 [2026-06-28]
- Generate better extreme cases for "number", "integer" and "string" types

## 0.0.11 [2026-06-26]
- Add `:string_kind` option to `RockSolid.from_schema/2`

## 0.0.10 [2026-06-17]
- Rename `Traversal.get_in_schema/2` to `Traversal.fetch_in_schema!/2` and add safe `Traversal.fetch_in_schema/2`

## 0.0.9 [2026-06-15]
- Fix regex intersection timeouts by replacing `greenery`/`pythonx` with rustler precompiled `regex_solver`

## 0.0.8 [2026-06-11]
- Fix bug where properties named `"required"` and `"dependentRequired"` weren't being simplified

## 0.0.7 [2026-06-07]
- Rename `RockSolid.Traversal.update_in_schema/3` to `RockSolid.Traversal.put_in_schema!/3` and also implement `RockSolid.Traversal.put_in_schema/3`

## 0.0.6 [2026-06-07]
- Support JSON Pointers starting without "#" in `RockSolid.Traversal.to_path/1`
- Fix `RockSolid.Traversal.update_in_schema/3` when last element in path is a list

## 0.0.5 [2026-05-12]
- Fix `contains` not being generated
- Generate only a sublist of `prefixItems` when `minItems` is not specified, or is smaller than `prefixItems` length
- Improve `pattern` with `maxLength` generations

## 0.0.4 [2026-05-11]
Implements all possible unrecoverable exceptions and adds improved error messages.

## 0.0.3 [2026-05-07]
This version contains several bug fixes and optimisations, mainly for handling of `object` types.

### Fixes
- Fix `patternProperties` ignoring `propertyNames` pattern
- Fix `dependentSchemas` being ignored
- Fix `dependentRequired` algorithm behaving incorrectly when properties depended on each other
- Return empty value when a required property is no longer valid after adding a `not` clause
- Fix edge case when "catch all" `patternProperties` is the same subschema as the other `patternProperties`
- Fix `additionalProperties` in `if/then/else`clauses having the same priority as the base schema
- Fix edge cases of `properties`, `definitions`, `dependencies`, `dependentSchemas` and `dependentRequired` being used as keys in `dependencies`, `dependentSchemas` and `dependentRequired`. For example, when a property called `dependencies` used as a key inside `dependentRequired` it was being treated as the keyword `dependencies` instead of the literal key.

### Internal/enhancements
- Optimise `oneOf` by computing the intersection of the subschema and the negation of the remaining clauses when possible
- Optimise adding `not` clauses for the common case of object type + present/absent properties
- Avoid expanding `$ref` when the other element to intersect is the "any" value

## 0.0.2 [2026-05-03]
- Fix generation not considering `minItems`, `minProperties`, `maxItems`, `maxProperties` when scaling

## 0.0.1 [2026-05-03]
- Initial demo release

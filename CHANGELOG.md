# Changelog

All notable changes to this project will be documented in this file.

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
# Roadmap
This document describes the features and fixes that must be implemented before releasing a stable version.

## Recursive $ref
The current implementation only considers recursive `$ref` reachable from a single path. When the same `$ref` is reached during a recursive intersection the algorithm assumes it has already been simplified and the code raises a `"Placeholder ${VALUE} not found"` error. The algorithm must be rewritten to support multiple branches and paths.

## pattern and length
When generating data, if we have `pattern` + `minLength`/`maxLength` we generate based on `pattern` and then apply filtering. This approach often throws a `StreamData.FilterTooNarrowError`. Instead we should add support for generating strings based on regular expressions + length options. This change should likely be implemented in [MoreStreamData](https://github.com/IgnacioGoldchluk/more_stream_data)

## pattern intersection
To compute the intersection between two `pattern` we are using [greenery](https://github.com/qntm/greenery) which is a Python package, forcing us to include Pythonx as dependency. Additionally, `greenery` is quite slow and buggy. If there is no alternative in a faster language that can be included via NIF then we might have to develop an alternative in Elixir. It does not matter that the final regex is "ugly" because it gets passed to `MoreStreamData` and tokenized anyway.

## contains keyword
The current solution is a hack that places the `contains` value on the first available `prefixItems`, which returns empty intersection errors when the schema must be intersected with another one that contains incompatible prefix items. Instead we should keep the `contains` keyword in the array object as use it in the data generation step.

## error messages
We are currently raising and letting the code throw a `MatchError` without much context. We should standarize the type of errors (`EmptyIntersection`, `EmptyAnyOf`, etc.) and provide context.

## dependentSchemas
Find an alternative to calculating the powerset and creating potentially thousands of schemas.
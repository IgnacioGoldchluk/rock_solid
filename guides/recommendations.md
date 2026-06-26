# Recommendations
The following are a list of recommendations for reducing ambiguity and improving the performance of data generation. `RockSolid` tries to simplify the input schema as much as possible before generating data, and passing schemas defined using "bad practices" can result in timeouts or failure to generate valid data.

If your schema follows all of the suggestion and still times out then create an issue.

## Boolean operations

### oneOf
Prefer `anyOf` over `oneOf`. Many tools that automatically generate JSON schema documents make heavy use of `oneOf`, but the keyword does not work as one expects: `oneOf` passes if the input data is valid against **exactly one** of the subschemas. This means that validation must be performed against all of the subschemas, even when one subschema already matched the data.

Internally `RockSolid` has to convert `oneOf` to an `anyOf`, checking that the subschemas are mutually exclusive. When the schemas are not mutually exclusive an additional `not` clause is added. This slows down the generation process significantly.

If your subschemas are mutually exclusive, you can replace `oneOf` by `anyOf`.

For example, the following schema can be converted to `anyOf`
```json
{"oneOf": [{"type": "string"}, {"type": "number"}]}
```

Whereas the following schema requires a `not` clause, because the intersection of the regular expressions is not empty
```json
{
    "oneOf": [
        {"type": "string", "pattern": "^[a-z]+$"},
        {"type": "string", "pattern": "^[A-Za-z]+$"}
    ]
}
```

### not
Avoid `not` clauses that overlap with most of the common cases for the data. In some cases, `RockSolid` can transform `not` clauses into their positive equivalent, but in other cases it has to carry the `not` clause until the data generation step.

An example of a `not` clause with low overlap
```json
{"type": "number", "not": {"multipleOf": 10}}
```

An example of a `not` clause with high overlap
```json
{"type": "number", "not": {"maximum": 0}}
```

### allOf
Prefer a single clause instead of multiple `allOf` whenever possible. For the same reason as [oneOf](#oneof), `RockSolid` has to convert the clause to an equivalent `anyOf`, and providing many subschemas may result in a timeout.

For example, instead of
```json
{
    "allOf": [
        {"type": "string"},
        {"pattern": "^foo"},
        {"pattern": "bar$"}
    ]
}
```
do
```json
{"type": "string", "pattern": "^foo.*bar$"}
```

## "type" keyword
Specify the `"type"` keyword whenever possible, otherwise `RockSolid` has to assume every type is valid and might need to perform exponentially more checks and validations.

For example, in the following schema
```json
{"properties": {"foo": {"minimum": 0}}}
```
while the user might have implied that the data must be an object where the key `foo` is a non-negative integer, the JSON Schema standard works differently. Every type is valid unless the `"type"` keyword is specified, therefore the schema can match any type, and `foo` can also be of any type. The only limitation imposed by the schema is that if the data is an object that contains the key `foo` and `foo` is a number, then it cannot be negative.

Prefer specifying `"type"`
```json
{"type": "object", "properties": {"foo": {"type": "number", "minimum": 0}}}
```

## patternProperties
Prefer to define as few `patternProperties` as possible, and use the `^` and `$` anchors, since the regular expressions are not anchored by default.

Keep in mind `patternProperties` apply to every property, including those defined in `properties` keyword. Consider the following example
```json
{
  "type": "object",
  "properties": {
    "fooqux": {"type": "boolean"},
  },
  "patternProperties": {
    "foo.*": {"type": "string"},
    "bar.*": {"type": "number"}
  }
}
```
The schema requires `fooqux` to be a `boolean`, but there is a matching `patternProperties` key `foo.*` that requires a `string`. Therefore the `fooqux` property cannot exist.

Similarly, `patternProperties` are not exclusive to each other. A property `foobar` cannot exist (or any property containing both `foo` and `bar` as substring) because `patternProperties` requires that they are both `string` and `number`.

## additionalProperties
If you don't expect any extra properties in addition to the defined ones then set `additionalProperties` to `false`. By default JSON Schema allows for additional properties unless explicitly stated. For example the following schema
```json
{"type": "object", "properties": {"foo": {"type": "number"}}}
```
matches all of the following
- `{"foo": 1}`
- `{"foo": 1, "bar": "baz"}`
- `{"foo": 1, "bar": "baz", "qux": {"a nested": "object"}}`
which is not what you intended (I hope)

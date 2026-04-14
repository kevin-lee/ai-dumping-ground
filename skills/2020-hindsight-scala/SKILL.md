---
name: 2020-hindsight-scala
description: >
  Refactor Scala code and apply good practices from 2020 Hindsight Scala (https://2020-hindsight-scala.kevinly.dev/docs/).
  Use this skill whenever writing new Scala code, reviewing Scala code, or refactoring existing Scala code.
  Also trigger when the user mentions Scala best practices, ADTs, type safety, Option/Either usage,
  or asks to clean up / improve Scala code quality. This skill applies even if the user doesn't
  explicitly mention "2020 hindsight" — any Scala code writing or refactoring should follow these practices.
---

# 2020 Hindsight Scala — Good Practices

Apply these practices when writing new Scala code or refactoring existing Scala code.
Reference: https://2020-hindsight-scala.kevinly.dev/docs/

For detailed rules and examples for each practice, read `references/practices.md` in this skill directory.

## Quick Reference — The Rules

### 1. ADT: Place Data in Companion Objects
Put ADT case classes/objects inside the sealed trait's companion object to avoid naming conflicts and provide a clear namespace. For Scala 3, use `enum` instead of `sealed trait` with `case class` / `case object` in a companion object.

### 2. ADT: Use Constructor Methods
Define constructor methods in the companion object that return the sealed trait type — not the case class type. This fixes type inference issues (e.g. `List[Product with MyTrait with Serializable]` instead of `List[MyTrait]`).

### 3. Type-safe Equality
Use `===` / `!==` (from Cats `Eq` or a custom extension) instead of `==` / `!=`. Scala's universal equality is not type-safe — `"a" == 1` compiles but is always `false`.

### 4. Option: Use `.some` / `none[A]`
Use `1.some` and `none[Int]` (from Cats) instead of `Some(1)` and `None`. Direct `Some()` produces `Some[Int]` not `Option[Int]`, causing type inference issues in collections and generic contexts (invariant type parameters). For conditional `Option` creation (Scala 2.13+), use `Option.when(condition)(value)` instead of `if (condition) value.some else none`. **Testing exception:** In test code, `Some(value)` and `None` are allowed on the expected side of assertions (e.g. `actual ==== Some(expectedValue)`, `actual ==== None`) because these express exactly what is expected.

### 5. Option: Never Use `.get`
`Option.get` throws `NoSuchElementException` on `None`. Use pattern matching, `fold`, `getOrElse`, `map`, or `flatMap` instead.

### 6. Either: Use `.asRight` / `.asLeft`
Use `1.asRight[String]` and `"error".asLeft[Int]` (Cats) instead of `Right()` / `Left()`. Direct constructors produce `Right[Nothing, Int]` / `Left[String, Nothing]`, causing type inference problems. For conditional `Either` creation, use `Either.cond(condition, rightValue, leftValue)` instead of `if (condition) rightValue.asRight else leftValue.asLeft`. **Testing exception:** In test code, `Right(value)` and `Left(value)` are allowed on the expected side of assertions (e.g. `actual ==== Right(expectedValue)`, `actual ==== Left(expectedError)`) because these express exactly what is expected.

### 7. More Types: Avoid Stringly-Typed Code
Wrap primitive types in value classes (`extends AnyVal`), newtypes (`@newtype` / `@newsubtype`), opaque types (Scala 3), or refined4s. This catches argument-ordering bugs at compile time and makes code self-documenting.

### 8. More Types: Use ADTs Instead of Boolean
Replace `Boolean` fields with sealed trait ADTs when the meaning of `true`/`false` is ambiguous. For example, use `AccountStatus.Enabled` / `AccountStatus.Disabled` instead of `enabled: Boolean`.

### 9. Error Handling: Total Functions over Partial Functions
Never throw exceptions from pure functions. Use `Option` for single-failure lookups and `Either` (with an ADT error type on the Left) for multiple failure cases. This makes failure modes explicit in the type signature.

### 10. Always `final case class`
Always declare case classes as `final`. Non-final case classes can be extended by regular classes, breaking `equals`, `hashCode`, `toString`, and pattern matching. Exceptions: `@newtype` annotations (not real case classes) and `case object` (already implicitly final).

### 11. For-Comprehension
Use for-comprehension instead of nested `flatMap`/`map` chains for readability. But avoid for-comprehension with a single generator — just use `map` or `flatMap` directly, as the for-comprehension adds no readability benefit.

### 12. Formatting: Follow `.scalafmt.conf`
If a `.scalafmt.conf` file exists in the project, follow its formatting rules when writing or modifying code.

### 13. Follow `.scalafix.conf` Rules
If a `.scalafix.conf` file exists in the project, follow its rules when writing or modifying code.

### 14. Scala 3: Use Brace Syntax, Not Significant Indentation
For Scala 3 code, always use brace syntax instead of significant indentation (braceless) syntax. Exception: single-line `if (then)`/`else` expressions may omit braces. If either branch of an `if`/`else` has more than one line, use braces for both branches.

### 15. `if` Should Always Have `else`
Every `if` expression should have a corresponding `else` branch. This makes the logic explicit and avoids subtle bugs from missing cases.

### 16. Don't Use `var`
Avoid `var` unless it is absolutely required (e.g. for Java interop or performance-critical mutable state with no functional alternative). Prefer `val`, immutable data structures, and functional patterns.

### 17. Naming: No ALL-CAPITAL Acronyms
Never use all-capital letters for acronyms or short words in identifiers — they are hard to read. Use PascalCase for acronyms/abbreviations. For example: `VpnIdHttpPinUuid` not `VPNIDHTTPPINUUID`, `HttpClient` not `HTTPClient`, `JsonParser` not `JSONParser`.

### 18. Separate Operations from Data in Case Classes
Do not put methods in a case class body. Instead, define them as extension methods in the companion object. Case classes should be pure data carriers — separating operations from data follows the core FP principle of defining data types and functions over them independently. This improves composability, makes serialization cleaner, and avoids conflating data definition with behavior.

### 19. Do Not Use Default Parameters
Avoid default parameter values. They hide semantics at the call site, smuggle policy into APIs, make changes risky (changing a default silently changes behavior in all callers with no compile-time signal), create ambiguous APIs (especially with multiple optional or boolean parameters), encourage oversized functions, and interact badly with overloading, named arguments, and versioning (especially in Scala 2). They also complicate higher-order usage since defaults are lost during eta-expansion. Instead, require all parameters explicitly, use a configuration case class, or provide distinct method names for distinct behaviors.

### 20. Tuple: Use Pattern Matching Instead of `_._1`, `_._2`
Never access tuple elements by positional accessors (`_._1`, `_._2`, etc.). Use pattern matching to destructure tuples into named bindings instead. Positional accessors are meaningless and convey no intent. Pattern matching gives each element a descriptive name, making the code self-documenting. For example: `nameValuePairs.map { case (name, _) => name }` instead of `nameValuePairs.map(_._1)`, and `priceAndQuantityPairs.map(x => x._1 * x._2)` becomes `priceAndQuantityPairs.map { case (price, quantity) => price * quantity }`.

### 21. Pattern Matching on ADTs: Prefer Explicit Constructors over Wildcard
When pattern matching on an ADT, prefer explicit data constructor matches over the wildcard pattern (`_`) — even when the remaining cases are handled identically. Use `|` (alternative patterns) to combine them. This makes the compiler's exhaustiveness check work for you: when a new variant is added to the ADT, the compiler warns about the non-exhaustive match instead of silently routing the new case through the wildcard. Example — given the ADT:

```scala
// Scala 2
sealed trait Foobar
object Foobar {
  case object Foo extends Foobar
  final case class Bar(n: Int) extends Foobar
  case object Baz extends Foobar
  final case class Qux(s: String) extends Foobar
}

// Scala 3
enum Foobar {
  case Foo
  case Bar(n: Int)
  case Baz
  case Qux(s: String)
}
```

Prefer:
```scala
foobar match {
  case Foo         => println("It's Foo!")
  case Bar(n)      => println(s"The bar value is $n")
  case Baz | Qux(_) => println("Neither Foo nor Bar")
}
```

Instead of:
```scala
foobar match {
  case Foo    => println("It's Foo!")
  case Bar(n) => println(s"The bar value is $n")
  case _      => println("Neither Foo nor Bar")
}
```

## How to Apply

When **writing new Scala code**: follow all rules above from the start.

When **refactoring existing Scala code**: scan for violations of the rules above and fix them. Common things to look for:
- Non-final case classes
- ADT variants defined outside companion objects
- ADT variants without constructor methods
- `Some()` / `None` / `Right()` / `Left()` used directly (except in test assertions on the expected side)
- `if (cond) value.some else none` instead of `Option.when(cond)(value)` (Scala 2.13+)
- `if (cond) b.asRight else a.asLeft` instead of `Either.cond(cond, b, a)`
- `Option.get` calls
- `==` / `!=` used for equality
- Primitive types used where a value class / newtype would be more expressive
- Boolean fields that would be clearer as ADTs
- Exception throwing instead of returning `Option` / `Either`
- Nested `flatMap`/`map` that could be a for-comprehension (or single-generator for-comprehension that should just be `map`/`flatMap`)
- Code formatting inconsistent with `.scalafmt.conf`
- Code violating `.scalafix.conf` rules
- Scala 3 code using significant indentation (braceless) syntax instead of braces
- `if` expressions missing an `else` branch
- Use of `var` where `val` or immutable patterns would suffice
- ALL-CAPITAL acronyms in identifiers (e.g. `HTTPClient` instead of `HttpClient`)
- Methods defined directly in case class bodies instead of as extension methods in companion objects
- Default parameter values hiding semantics, smuggling policy, or encouraging oversized function signatures
- Tuple element access via `_._1`, `_._2` instead of pattern matching (e.g. `{ case (name, _) => name }`)
- Wildcard (`_`) pattern used when matching on an ADT — replace with explicit constructors combined via `|` so exhaustiveness checking catches new variants

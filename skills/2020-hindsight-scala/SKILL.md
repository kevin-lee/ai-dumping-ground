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
Put ADT case classes/objects inside the sealed trait's companion object to avoid naming conflicts and provide a clear namespace.

### 2. ADT: Use Constructor Methods
Define constructor methods in the companion object that return the sealed trait type — not the case class type. This fixes type inference issues (e.g. `List[Product with MyTrait with Serializable]` instead of `List[MyTrait]`).

### 3. Type-safe Equality
Use `===` / `!==` (from Cats `Eq` or a custom extension) instead of `==` / `!=`. Scala's universal equality is not type-safe — `"a" == 1` compiles but is always `false`.

### 4. Option: Use `.some` / `none[A]`
Use `1.some` and `none[Int]` (from Cats) instead of `Some(1)` and `None`. Direct `Some()` produces `Some[Int]` not `Option[Int]`, causing type inference issues in collections and generic contexts (invariant type parameters).

### 5. Option: Never Use `.get`
`Option.get` throws `NoSuchElementException` on `None`. Use pattern matching, `fold`, `getOrElse`, `map`, or `flatMap` instead.

### 6. Either: Use `.asRight` / `.asLeft`
Use `1.asRight[String]` and `"error".asLeft[Int]` (Cats) instead of `Right()` / `Left()`. Direct constructors produce `Right[Nothing, Int]` / `Left[String, Nothing]`, causing type inference problems.

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

## How to Apply

When **writing new Scala code**: follow all rules above from the start.

When **refactoring existing Scala code**: scan for violations of the rules above and fix them. Common things to look for:
- Non-final case classes
- ADT variants defined outside companion objects
- ADT variants without constructor methods
- `Some()` / `None` / `Right()` / `Left()` used directly
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

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
Use `===` / `!==` (from Cats `Eq` or Scalaz `Equal`, or a custom extension) instead of `==` / `!=`. Scala's universal equality is not type-safe — `"a" == 1` compiles but is always `false`.

### 4. Option: Use `.some` / `none[A]`
Use `1.some` and `none[Int]` (from Cats or Scalaz) instead of `Some(1)` and `None`. Direct `Some()` produces `Some[Int]` not `Option[Int]`, causing type inference issues in collections and generic contexts (invariant type parameters).

### 5. Option: Never Use `.get`
`Option.get` throws `NoSuchElementException` on `None`. Use pattern matching, `fold`, `getOrElse`, `map`, or `flatMap` instead.

### 6. Either: Use `.asRight` / `.asLeft`
Use `1.asRight[String]` and `"error".asLeft[Int]` (Cats) or `.right` / `.left` (Scalaz) instead of `Right()` / `Left()`. Direct constructors produce `Right[Nothing, Int]` / `Left[String, Nothing]`, causing type inference problems.

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

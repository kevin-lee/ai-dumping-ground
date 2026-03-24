# 2020 Hindsight Scala — Detailed Practices & Examples

Reference: https://2020-hindsight-scala.kevinly.dev/docs/

## Table of Contents
1. [ADT: Place Data in Companion Objects](#1-adt-place-data-in-companion-objects)
2. [ADT: Use Constructor Methods](#2-adt-use-constructor-methods)
3. [Type-safe Equality](#3-type-safe-equality)
4. [Option: Use .some / none](#4-option-use-some--nonea)
5. [Option: Never Use .get](#5-option-never-use-get)
6. [Either: Use .asRight / .asLeft](#6-either-use-asright--asleft)
7. [More Types: Avoid Stringly-Typed Code](#7-more-types-avoid-stringly-typed-code)
8. [More Types: ADTs Instead of Boolean](#8-more-types-adts-instead-of-boolean)
9. [Error Handling: Total over Partial Functions](#9-error-handling-total-over-partial-functions)
10. [Always final case class](#10-always-final-case-class)
11. [For-Comprehension](#11-for-comprehension)
12. [Formatting: Follow .scalafmt.conf](#12-formatting-follow-scalafmtconf)
13. [Follow .scalafix.conf Rules](#13-follow-scalafixconf-rules)
14. [Scala 3: Use Brace Syntax](#14-scala-3-use-brace-syntax-not-significant-indentation)
15. [if Should Always Have else](#15-if-should-always-have-else)
16. [Don't Use var](#16-dont-use-var)
17. [Naming: No ALL-CAPITAL Acronyms](#17-naming-no-all-capital-acronyms)
18. [Separate Operations from Data in Case Classes](#18-separate-operations-from-data-in-case-classes)

---

## 1. ADT: Place Data in Companion Objects

Place ADT case classes/objects inside the sealed trait's companion object.

**Bad:**
```scala
sealed trait MyNumber
final case class SomeNumber(n: Int) extends MyNumber
case object NoNumber extends MyNumber
```

**Good:**
```scala
sealed trait MyNumber
object MyNumber {
  final case class SomeNumber(n: Int) extends MyNumber
  case object NoNumber extends MyNumber
}
```

This avoids naming conflicts when multiple ADTs have similar constructor names and provides a clear namespace:
```scala
sealed trait ValidationError
object ValidationError {
  final case class MissingField(name: String) extends ValidationError
  final case class InvalidId(id: Long) extends ValidationError
}
// Usage: ValidationError.MissingField("email") — no need for "MissingFieldError"
```

---

## 2. ADT: Use Constructor Methods

Define constructor methods in the companion object that return the sealed trait type.

**Why?** Direct case class constructors return the specific subtype, causing type inference problems:
```scala
// BAD: inferred as List[MyNumber.SomeNumber], not List[MyNumber]
val ns = List(MyNumber.SomeNumber(1), MyNumber.SomeNumber(5))

// BAD: inferred as List[Product with MyNumber with Serializable]
val ns2 = List(MyNumber.SomeNumber(1), MyNumber.AnotherNumber(5))
```

**Good — define constructor methods:**
```scala
sealed trait MyNumber
object MyNumber {
  final case class SomeNumber(n: Int) extends MyNumber
  final case class AnotherNumber(n: Int) extends MyNumber
  case object NoNumber extends MyNumber

  def someNumber(n: Int): MyNumber = SomeNumber(n)
  def anotherNumber(n: Int): MyNumber = AnotherNumber(n)
  def noNumber: MyNumber = NoNumber
}

// Now correctly inferred as List[MyNumber]
val ns3 = List(MyNumber.someNumber(1), MyNumber.someNumber(5), MyNumber.noNumber)
```

**Exception:** For `Option` and `Either`, use the library-provided constructors (`.some`, `none[A]`, `.asRight`, `.asLeft`) instead of writing your own.

---

## 3. Type-safe Equality

Scala's `==` is not type-safe: `"a" == 1` compiles but is always `false`.

**Solution — Cats `Eq`:**
```scala
import cats.syntax.eq._

1 === 1        // true
"a" === 1      // compile-time error: type mismatch

// For case classes, derive Eq:
final case class Person(id: Long, name: String)
object Person {
  implicit val eq: Eq[Person] = Eq.fromUniversalEquals
}
Person(1L, "Kevin") === Person(1L, "Kevin") // true
```

**Solution — Custom extension (if not using Cats):**
```scala
implicit final class AnyEquals[A](val self: A) extends AnyVal {
  def ===(other: A): Boolean = self == other
  def !==(other: A): Boolean = self != other
}
```

---

## 4. Option: Use `.some` / `none[A]`

**Bad:**
```scala
Some(1)           // Some[Int], not Option[Int]
None              // None.type

// Type inference problem in collections:
List(Some(1), Some(2))  // List[Some[Int]], not List[Option[Int]]
```

**Good — Cats:**
```scala
import cats.syntax.option._

1.some            // Option[Int] = Some(1)
none[Int]         // Option[Int] = None

List(1.some, 2.some)  // List[Option[Int]]
```

This is important in generic/invariant contexts where `F[Some[Int]]` won't match `F[Option[Int]]`.

**Conditional construction:**
```scala
Option.when(num > 0)(num)  // Some(num) if true, None if false
```

---

## 5. Option: Never Use `.get`

`Option.get` throws `NoSuchElementException` on `None`. Always use safe alternatives:

**Pattern matching:**
```scala
maybeNum match {
  case Some(n) => n + 1
  case None    => 0
}
```

**`fold` (catamorphism):**
```scala
maybeNum.fold(0)(n => n + 1)
// equivalent to: maybeNum.map(n => n + 1).getOrElse(0)
```

**`getOrElse`:**
```scala
maybeNum.getOrElse(0)
```

**Other safe operations:** `map`, `flatMap`, `filter`, `exists`, `contains`, `collect`.

---

## 6. Either: Use `.asRight` / `.asLeft`

**Bad:**
```scala
Right(1)            // Right[Nothing, Int], not Either[String, Int]
Left("error")       // Left[String, Nothing], not Either[String, Int]
```

**Good — Cats:**
```scala
import cats.syntax.either._

1.asRight[String]           // Either[String, Int] = Right(1)
"error".asLeft[Int]         // Either[String, Int] = Left("error")

List(1.asRight[String], 2.asRight[String])  // List[Either[String, Int]]
```

**Conditional construction:**
```scala
Either.cond(num > 0, num, "must be positive")
```

**Safe extraction** — use pattern matching, `fold`, or `getOrElse`:
```scala
result.fold(err => handleError(err), value => handleSuccess(value))
```

---

## 7. More Types: Avoid Stringly-Typed Code

Wrapping primitives in types catches argument-ordering bugs at compile time.

**Bad:**
```scala
final case class User(id: Long, firstName: String, lastName: String, email: String)
// Nothing stops: User(id, email, firstName, lastName) — compiles, wrong at runtime
```

**Good — Value classes:**
```scala
final case class User(
  id: User.Id,
  firstName: User.FirstName,
  lastName: User.LastName,
  email: User.Email
)
object User {
  final case class Id(id: Long) extends AnyVal
  final case class FirstName(firstName: String) extends AnyVal
  final case class LastName(lastName: String) extends AnyVal
  final case class Email(email: String) extends AnyVal
}
// User(id, email, firstName, lastName) — compile error!
```

**Better — Scala 2 newtype:**
```scala
import io.estatico.newtype.macros.newtype

@newtype case class Name(name: String)
// At runtime: java.lang.String (zero overhead)
```

**Better — Scala 3 opaque types:**
```scala
object Types {
  type Name = Name.Name
  object Name {
    opaque type Name = String
    def apply(name: String): Name = name
    extension (name: Name) {
      def value: String = name
    }
  }
}
```

**Better — Scala 3 refined4s:**
```scala
import refined4s.*

object Types {
  type Name = Name.Type
  object Name extends Newtype[String]
}
```

---

## 8. More Types: ADTs Instead of Boolean

**Bad:**
```scala
final case class User(/* ... */, enabled: Boolean)
// What does `true` mean? If renamed to `disabled`, all true/false values flip silently.
```

**Good:**
```scala
sealed trait AccountStatus
object AccountStatus {
  case object Enabled extends AccountStatus
  case object Disabled extends AccountStatus
  def enabled: AccountStatus = Enabled
  def disabled: AccountStatus = Disabled
}

final case class User(/* ... */, accountStatus: User.AccountStatus)
```

---

## 9. Error Handling: Total over Partial Functions

A **total function** is defined for all inputs. A **partial function** throws exceptions for some inputs. Prefer total functions.

**Bad — throwing exceptions:**
```scala
def foo(n: Int): Int =
  if (n < 0) throw InvalidInputException(s"Invalid: $n")
  else n * 2
```

**Good — use Option for single-failure lookups:**
```scala
def findUser(userId: User.Id): Option[User] = // ...
```

**Good — use Either with ADT errors for multiple failure cases:**
```scala
sealed trait ValidationError
object ValidationError {
  case object EmptyUsername extends ValidationError
  final case class UsernameTooShort(username: String, min: Int) extends ValidationError
  final case class UsernameTooLong(username: String, max: Int) extends ValidationError
  final case class InvalidUsername(username: String, invalidChars: List[Char]) extends ValidationError

  // constructor methods...
}

def createUsername(username: String): Either[ValidationError, Username] = {
  if (username.isEmpty)
    ValidationError.emptyUsername.asLeft[Username]
  else if (username.length < 4)
    ValidationError.usernameTooShort(username, 4).asLeft[Username]
  else
    Username(username).asRight[ValidationError]
}
```

---

## 10. Always `final case class`

Non-final case classes can be extended by regular classes, breaking `equals`, `hashCode`, `toString`, and pattern matching.

**Bad:**
```scala
case class WithNumber(num: Int)
class Item(num: Int, name: String) extends WithNumber(num)

new Item(1, "ABC") == new Item(1, "XYZ")  // true — WRONG!
Set(new Item(1, "A"), new Item(1, "B"))    // Set with only 1 element!
```

**Good:**
```scala
final case class WithNumber(num: Int)  // Cannot be extended
```

**Exceptions:**
- `@newtype` annotations — not real case classes at runtime
- `case object` — already implicitly final

---

## 11. For-Comprehension

Use for-comprehension instead of nested `flatMap`/`map` for readability.

**Translation rules:**
- All `<-` except the last one become `flatMap`
- The last `<-` becomes `map`

```scala
// Nested flatMap/map (hard to read):
foo(a).flatMap { b => bar(b).flatMap { c => baz(c).map { d => b + c + d } } }

// For-comprehension (clear):
for {
  b <- foo(a)
  c <- bar(b)
  d <- baz(c)
} yield b + c + d
```

**Single generator — don't use for-comprehension:**
```scala
// Bad — unnecessary for-comprehension:
for { b <- foo(a) } yield b          // just use foo(a)
for { b <- foo(a) } yield bar(b)     // just use foo(a).map(bar) or foo(a).flatMap(bar)

// Good:
foo(a)
foo(a).map(bar)
```

---

## 12. Formatting: Follow `.scalafmt.conf`

If a `.scalafmt.conf` file exists in the project, follow its formatting rules when writing or modifying code. Read the config to understand the project's formatting conventions (e.g. max line length, alignment, indent style) and apply them consistently.

---

## 13. Follow `.scalafix.conf` Rules

If a `.scalafix.conf` file exists in the project, follow its rules when writing or modifying code. This includes any enabled linting rules, rewrites, or code organization rules defined in the config.

---

## 14. Scala 3: Use Brace Syntax, Not Significant Indentation

For Scala 3 code, always use brace syntax instead of significant indentation (braceless) syntax.

**Bad — significant indentation:**
```scala
object MyApp:
  def foo(x: Int): String =
    val y = x + 1
    y.toString

  enum Color:
    case Red, Green, Blue
```

**Good — brace syntax:**
```scala
object MyApp {
  def foo(x: Int): String = {
    val y = x + 1
    y.toString
  }

  enum Color {
    case Red, Green, Blue
  }
}
```

**Exception — single-line `if (then)`/`else`** (braces may be omitted):
```scala
// OK — single line per branch:
if a then
  doSomething
else
  doSomethingElse

// Multi-line branches MUST use braces:
if a then {
  doSomething
  doSomethingMore
} else {
  doSomethingElse
  doSomethingElseMore
}
```

---

## 15. `if` Should Always Have `else`

Every `if` expression should have a corresponding `else` branch. This makes the logic explicit and avoids subtle bugs from missing cases.

**Bad:**
```scala
if (x > 0)
  doSomething(x)
```

**Good:**
```scala
if (x > 0)
  doSomething(x)
else
  doDefault()
```

**Good — Scala 3:**
```scala
if x > 0 then
  doSomething(x)
else
  doDefault()
```

---

## 16. Don't Use `var`

Avoid `var` unless it is absolutely required. Prefer `val`, immutable data structures, and functional patterns.

**Bad:**
```scala
var total = 0
for (x <- xs) {
  total += x
}
```

**Good:**
```scala
val total = xs.sum
// or
val total = xs.foldLeft(0)(_ + _)
```

**Bad:**
```scala
var result: Option[Int] = None
if (condition) {
  result = Some(42)
}
```

**Good:**
```scala
val result: Option[Int] =
  if condition then 42.some
  else none[Int]
```

**Exception:** `var` may be acceptable for Java interop or performance-critical mutable state where no functional alternative exists.

---

## 17. Naming: No ALL-CAPITAL Acronyms

Never use all-capital letters for acronyms or short words in identifiers. They are hard to read, especially when multiple acronyms appear together.

**Bad:**
```scala
// Hard to read — where do the word boundaries fall?
val VPNIDHTTPPINUUID = ???
class HTTPSURLConnection
trait JSONAPIResponse
def getHTTPURLConnection(): HTTPURLConnection
```

**Good:**
```scala
// PascalCase for acronyms — clear word boundaries
val vpnIdHttpPinUuid = ???
class HttpsUrlConnection
trait JsonApiResponse
def getHttpUrlConnection(): HttpUrlConnection
```

**More examples:**

| Bad | Good |
|-----|------|
| `HTTPClient` | `HttpClient` |
| `JSONParser` | `JsonParser` |
| `XMLHTTPRequest` | `XmlHttpRequest` |
| `getUserByID` | `getUserById` |
| `parseJSON` | `parseJson` |
| `AWSS3URL` | `AwsS3Url` |

This applies to all identifier types: classes, traits, objects, methods, variables, and type aliases.

---

## 18. Separate Operations from Data in Case Classes

Do not put methods in a case class body. Define them as extension methods in the companion object instead. Case classes should be pure data carriers (product types).

**Why?**
- **Separation of concerns (data vs. behavior)**: In FP, data types and functions over them are defined independently. This is the standard approach in Haskell, ML, and idiomatic Scala FP. Mixing methods into case classes conflates data definition with behavior.
- **Composability**: When operations are separate from data, they can be composed, overridden, and tested independently. Data types remain simple and reusable across different contexts.
- **Serialization friendliness**: Case classes used purely as data map cleanly to/from JSON, Protobuf, Avro, etc. Methods on case classes don't participate in serialization but can mislead readers into thinking the class has richer behavior than what survives a round-trip.
- **Extensibility (Expression Problem)**: New operations can be added in new companion objects or in separate files without modifying the data type. This avoids reopening the data definition every time a new behavior is needed.
- **Typeclass coherence**: When behavior is defined via extension methods (or typeclasses), it's clear that the behavior is attached externally, making it easier to swap implementations or provide different behaviors in different contexts.

**Bad — methods inside the case class:**
```scala
final case class Order(items: List[Item], discount: Discount) {
  def totalPrice: BigDecimal =
    items.map(_.price).sum

  def discountedPrice: BigDecimal =
    Discount.applyDiscount(discount, totalPrice)

  def isEmpty: Boolean =
    items.isEmpty
}
```

**Good — Scala 2 (extension via implicit value class):**
```scala
final case class Order(items: List[Item], discount: Discount)
object Order {
  implicit final class OrderOps(private val order: Order) extends AnyVal {
    def totalPrice: BigDecimal =
      order.items.map(_.price).sum

    def discountedPrice: BigDecimal =
      Discount.applyDiscount(order.discount, totalPrice)

    def isEmpty: Boolean =
      order.items.isEmpty
  }
}
```

**Good — Scala 3 (extension methods):**
```scala
final case class Order(items: List[Item], discount: Discount)
object Order {
  extension (order: Order) {
    def totalPrice: BigDecimal =
      order.items.map(_.price).sum

    def discountedPrice: BigDecimal =
      Discount.applyDiscount(order.discount, totalPrice)

    def isEmpty: Boolean =
      order.items.isEmpty
  }
}
```

**Note:** This rule applies to *operations* (computed values, transformations, business logic). It does **not** apply to overriding standard methods like `toString` when there is a specific reason to do so — though in practice, prefer typeclass instances (e.g. Cats `Show`) over `toString` overrides.

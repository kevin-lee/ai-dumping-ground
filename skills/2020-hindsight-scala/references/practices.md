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

**Solution — Scalaz `Equal`:**
```scala
import scalaz._, Scalaz._

1 === 1        // true
"a" === 1      // compile-time error

final case class Person(id: Long, name: String)
object Person {
  implicit val equal: Equal[Person] = Equal.equalA
}
```

**Solution — Custom extension (if not using Cats/Scalaz):**
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

**Good — Scalaz:**
```scala
import scalaz._, Scalaz._

1.some            // Option[Int]
none[Int]         // Option[Int]
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

**Good — Scalaz:**
```scala
import scalaz._, Scalaz._

1.right[String]             // String \/ Int = \/-(1)
"error".left[Int]           // String \/ Int = -\/("error")
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

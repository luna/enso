package org.enso.languageserver.runtime

import org.enso.polyglot.Suggestion

/** Suggestion instances used in tests. */
object Suggestions {

  val atom: Suggestion.Atom =
    Suggestion.Atom(
      module        = "Test.Main",
      name          = "MyType",
      arguments     = Vector(Suggestion.Argument("a", "Any", false, false, None)),
      returnType    = "MyAtom",
      documentation = None
    )

  val method: Suggestion.Method =
    Suggestion.Method(
      module = "Test.Main",
      name   = "foo",
      arguments = Vector(
        Suggestion.Argument("this", "MyType", false, false, None),
        Suggestion.Argument("foo", "Number", false, true, Some("42"))
      ),
      selfType      = "MyType",
      returnType    = "Number",
      documentation = Some("Lovely")
    )

  val function: Suggestion.Function =
    Suggestion.Function(
      module     = "Test.Main",
      name       = "print",
      arguments  = Vector(),
      returnType = "IO",
      scope =
        Suggestion.Scope(Suggestion.Position(1, 9), Suggestion.Position(1, 22))
    )

  val local: Suggestion.Local =
    Suggestion.Local(
      module     = "Test.Main",
      name       = "x",
      returnType = "Number",
      scope =
        Suggestion.Scope(Suggestion.Position(21, 0), Suggestion.Position(89, 0))
    )

  val all = Seq(atom, method, function, local)
}

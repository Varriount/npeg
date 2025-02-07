
#
# Copyright (c) 2019 Ico Doornekamp
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# This parser implementation is based on the following papers:
#
# - A Text Pattern-Matching Tool based on Parsing Expression Grammars
#   (Roberto Ierusalimschy)
#
# - An efficient parsing machine for PEGs
#   (Jos Craaijo)
#

## Note: This document is rather terse, for the complete NPeg manual please refer
## to the README.md or the git project page at https://github.com/zevv/npeg
##   
## NPeg is a pure Nim pattern matching library. It provides macros to compile
## patterns and grammars (PEGs) to Nim procedures which will parse a string and
## collect selected parts of the input. PEGs are not unlike regular
## expressions, but offer more power and flexibility, and have less ambiguities.
##
## Here is a simple example showing the power of NPeg: The macro `peg` compiles a
## grammar definition into a `parser` object, which is used to match a string and
## place the key-value pairs into the Nim table `words`:

runnableExamples:

  import npeg, strutils, tables

  var words = initTable[string, int]()

  let parser = peg "pairs":
    pairs <- pair * *(',' * pair) * !1
    word <- +Alpha
    number <- +Digit
    pair <- >word * '=' * >number:
      words[$1] = parseInt($2)

  doAssert parser.match("one=1,two=2,three=3,four=4").ok


import tables
import macros
import json
import strutils
import npeg/[common,codegen,capture,parsepatt,grammar,dot]

export NPegException, Parser, ASTNode, MatchResult, contains, items, `[]`

# Create a parser for a PEG grammar

proc pegAux(name: string, userDataType: NimNode, userDataId: string, n: NimNode): NimNode =
  var dot = newDot(name)
  var grammar = parseGrammar(n, dot)
  let code = grammar.link(name, dot).genCode(userDataType, ident(userDataId))
  dot.dump()
  code

macro peg*(name: untyped, n: untyped): untyped =
  ## Construct a parser from the given PEG grammar. `name` is the initial
  ## grammar rule where parsing starts. This macro returns a `Parser` type
  ## which can later be used for matching subjects with the `match()` proc
  let userDataType = bindSym("bool")
  pegAux(name.strVal, userDataType, "userdata", n)


macro peg*(name: untyped, userData: untyped, n: untyped): untyped =
  ## Construct a typed parser from the given PEG grammar. `name` is the initial
  ## grammar rule where parsing starts. The `userdata` takes a colon expression
  ## with an identifier and a type, this identifier is available in code block
  ## captions during parsing.
  ##
  ## This macro returns a `Parser` type which can later be used for matching
  ## subjects with the `match()` proc
  expectKind(userData, nnkExprColonExpr)
  pegAux name.strVal, userData[1], userData[0].strVal, n


template patt*(n: untyped): untyped =
  ## Construct a parser from a single PEG rule. This is similar to the regular
  ## `peg()` macro, but useful for short regexp-like parsers that do not need a
  ## complete grammar.
  peg anonymous:
    anonymous <- n

template patt*(n: untyped, code: untyped): untyped =
  ## Construct a parser from a single PEG rule. This is similar to the regular
  ## `peg()` macro, but useful for short regexp-like parsers that do not need a
  ## complete grammar. This variant takes a code block which will be used as
  ## code block capture for the anonymous rule.
  peg anonymous:
    anonymous <- n:
      code

macro grammar*(libNameNode: untyped, n: untyped) =
  ## This macro defines a collection of rules to be stored in NPeg's global
  ## grammar library.
  let libName = libNameNode.strval
  let grammar = parseGrammar(n, dumpRailroad = libname != "")
  libStore(libName, grammar)


proc match*[T](p: Parser, s: Subject, userData: var T): MatchResult =
  ## Match a subject string with the given generic parser. The returned
  ## `MatchResult` contains the result of the match and can be used to query
  ## any captures.
  var ms = initMatchState()
  p.fn(ms, s, userData)


proc match*(p: Parser, s: Subject): MatchResult =
  ## Match a subject string with the given parser. The returned `MatchResult`
  ## contains the result of the match and can be used to query any captures.
  var userData: bool # dummy if user does not provide a type
  p.match(s, userData)


# Match a file

when defined(windows) or defined(posix):
  import memfiles
  proc matchFile*[T](p: Parser, fname: string, userData: var T): MatchResult =
    var m = memfiles.open(fname)
    var a: ptr UncheckedArray[char] = cast[ptr UncheckedArray[char]](m.mem)
    var ms = initMatchState()
    result = p.fn(ms, toOpenArray(a, 0, m.size-1), userData)
    m.close()
  
  proc matchFile*(p: Parser, fname: string): MatchResult =
    var userData: bool # dummy if user does not provide a type
    matchFile(p, fname, userData)


proc captures*(mr: MatchResult): seq[string] =
  ## Return all plain string captures from the match result
  for cap in collectCaptures(mr.cs):
    result.add cap.s

proc capturesJson*(mr: MatchResult): JsonNode {.deprecated.} =
  ## Return the tree with JSON captures from the match result
  collectCapturesJson(mr.cs)


proc capturesAST*(mr: MatchResult): ASTNode {.deprecated.} =
  ## Return the tree with AST captures from the match result
  collectCapturesAST(mr.cs)


import npeg/lib/core


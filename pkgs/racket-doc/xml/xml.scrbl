#lang scribble/doc
@(require scribble/manual
          scribble/bnf
          scribble/eval
          (for-label racket/base
                     racket/contract
                     racket/list
                     xml
                     xml/plist))

@(define xml-eval (make-base-eval))
@(define plist-eval (make-base-eval))
@interaction-eval[#:eval xml-eval (require xml)]
@interaction-eval[#:eval xml-eval (require racket/list)]
@interaction-eval[#:eval plist-eval (require xml/plist)]

@title{XML: Parsing and Writing}

@author["Paul Graunke and Jay McCarthy"]

@defmodule[xml #:use-sources (xml/private/xexpr-core)]

The @racketmodname[xml] library provides functions for parsing and
generating XML. XML can be represented as an instance of the
@racket[document] structure type, or as a kind of S-expression that is
called an @deftech{X-expression}.

The @racketmodname[xml] library does not provide Document Type
Declaration (DTD) processing, including preservation of DTDs in read documents, or validation.
It also does not expand user-defined entities or read user-defined entities in attributes.
It does not interpret namespaces either.

@margin-note{In addition to the library described by this document, there is another
 @racket[sxml] library based on work by Oleg Kiselyov
 which users may find faster in processing large documents. It is
 available through racket's package server.}

@; ----------------------------------------------------------------------

@section{Datatypes}

@defstruct[location ([line (or/c false/c exact-nonnegative-integer?)]
                     [char (or/c false/c exact-nonnegative-integer?)]
                     [offset exact-nonnegative-integer?])]{

Represents a location in an input stream. The offset is a character offset unless @racket[xml-count-bytes] is @racket[#t], in which case it is a byte offset.}

@defthing[location/c contract?]{
 Equivalent to @racket[(or/c location? symbol? false/c)].
}

@defstruct[source ([start location/c]
                   [stop location/c])]{

Represents a source location. Other structure types extend
@racket[source].

When XML is generated from an input stream by @racket[read-xml],
locations are represented by @racket[location] instances. When XML
structures are generated by @racket[xexpr->xml], then locations are
symbols.}

@deftogether[(
@defstruct[external-dtd ([system string?])]
@defstruct[(external-dtd/public external-dtd) ([public string?])]
@defstruct[(external-dtd/system external-dtd) ()]
)]{

Represents an externally defined DTD.}

@defstruct[document-type ([name symbol?]
                          [external external-dtd?]
                          [inlined false/c])]{

Represents a document type.}

@defstruct[comment ([text string?])]{

Represents a comment.}

@defstruct[(p-i source) ([target-name symbol?]
                         [instruction string?])]{

Represents a processing instruction.}

@defthing[misc/c contract?]{
 Equivalent to @racket[(or/c comment? p-i?)]
}

@defstruct[prolog ([misc (listof misc/c)]
                   [dtd (or/c document-type false/c)]
                   [misc2 (listof misc/c)])]{
Represents a document prolog. 
}

@defstruct[document ([prolog prolog?]
                     [element element?]
                     [misc (listof misc/c)])]{
Represents a document.}

@defstruct[(element source) ([name symbol?]
                             [attributes (listof attribute?)]
                             [content (listof content/c)])]{
Represents an element.}

@defstruct[(attribute source) ([name symbol?] [value (or/c string? permissive/c)])]{

Represents an attribute within an element.}

@defthing[content/c contract?]{
 Equivalent to @racket[(or/c pcdata? element? entity? comment? cdata? p-i? permissive/c)].
}

@defthing[permissive/c contract?]{
 If @racket[(permissive-xexprs)] is @racket[#t], then equivalent to @racket[any/c], otherwise equivalent to @racket[(make-none/c 'permissive)]}

@defproc[(valid-char? [x any/c]) boolean?]{
 Returns true if @racket[x] is an exact-nonnegative-integer whose character interpretation under UTF-8 is from the set ([#x1-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]), in accordance with section 2.2 of the XML 1.1 spec.
}

@defstruct[(entity source) ([text (or/c symbol? valid-char?)])]{

Represents a symbolic or numerical entity.}

@defstruct[(pcdata source) ([string string?])]{

Represents PCDATA content.}

@defstruct[(cdata source) ([string string?])]{

Represents CDATA content.

The @racket[string] field is assumed to be of the form
@litchar{<![CDATA[}@nonterm{content}@litchar{]]>} with proper quoting
of @nonterm{content}. Otherwise, @racket[write-xml] generates
incorrect output.}

@defstruct[(exn:invalid-xexpr exn:fail) ([code any/c])]{

Raised by @racket[validate-xexpr] when passed an invalid
@tech{X-expression}. The @racket[code] fields contains an invalid part
of the input to @racket[validate-xexpr].}

@defstruct[(exn:xml exn:fail:read) ()]{
 Raised by @racket[read-xml] when an error in the XML input is found.
}

@defproc[(xexpr? [v any/c]) boolean?]{

Returns @racket[#t] if @racket[v] is a @tech{X-expression}, @racket[#f] otherwise.

The following grammar describes expressions that create @tech{X-expressions}:

@racketgrammar[
#:literals (cons list valid-char?)
xexpr string
      (list symbol (list (list symbol string) ...) xexpr ...)
      (cons symbol (list xexpr ...))
      symbol
      valid-char?
      cdata
      misc
]

A @racket[_string] is literal data. When converted to an XML stream,
the characters of the data will be escaped as necessary.

A pair represents an element, optionally with attributes. Each
attribute's name is represented by a symbol, and its value is
represented by a string.

A @racket[_symbol] represents a symbolic entity. For example,
@racket['nbsp] represents @litchar{&nbsp;}.

An @racket[valid-char?] represents a numeric entity. For example,
@racketvalfont{#x20} represents @litchar{&#x20;}.

A @racket[_cdata] is an instance of the @racket[cdata] structure type,
and a @racket[_misc] is an instance of the @racket[comment] or
@racket[p-i] structure types.}

@defthing[xexpr/c contract?]{
 A contract that is like @racket[xexpr?] except produces a better error
 message when the value is not an @tech{X-expression}.
}

@; ----------------------------------------------------------------------

@section{X-expression Predicate and Contract}

@defmodule[xml/xexpr]

The @racketmodname[xml/xexpr] library provides just @racket[xexpr/c],
@racket[xexpr?], @racket[correct-xexpr?], and @racket[validate-xexpr]
from @racketmodname[xml] with minimal dependencies.

@; ----------------------------------------------------------------------

@section{Reading and Writing XML}

@defproc[(read-xml [in input-port? (current-input-port)]) document?]{

Reads in an XML document from the given or current input port XML
documents contain exactly one element, raising @racket[xml-read:error]
if the input stream has zero elements or more than one element.
       
Malformed xml is reported with source locations in the form
@nonterm{l}@litchar{.}@nonterm{c}@litchar{/}@nonterm{o}, where
@nonterm{l}, @nonterm{c}, and @nonterm{o} are the line number, column
number, and next port position, respectively as returned by
@racket[port-next-location].

Any non-characters other than @racket[eof] read from the input-port
appear in the document content.  Such special values may appear only
where XML content may.  See @racket[make-input-port] for information
about creating ports that return non-character values.

@examples[
#:eval xml-eval
(xml->xexpr (document-element 
             (read-xml (open-input-string 
                        "<doc><bold>hi</bold> there!</doc>"))))
]}

@defproc[(read-xml/document [in input-port? (current-input-port)]) document?]{

Like @racket[read-xml], except that the reader stops after the single element, rather than attempting to read "miscellaneous" XML content after the element. The document returned by @racket[read-xml/document] always has an empty @racket[document-misc].}

@defproc[(read-xml/element [in input-port? (current-input-port)]) element?]{

Reads a single XML element from the port.  The next non-whitespace
character read must start an XML element, but the input port can
contain other data after the element.}

@defproc[(syntax:read-xml [in input-port? (current-input-port)]
                          [#:src source-name any/c (object-name in)])
         syntax?]{

Reads in an XML document and produces a syntax object version (like
@racket[read-syntax]) of an @tech{X-expression}.}

@defproc[(syntax:read-xml/element [in input-port? (current-input-port)]
                                  [#:src source-name any/c (object-name in)])
         syntax?]{

Like @racket[syntax:real-xml], but it reads an XML element like
@racket[read-xml/element].}

@defproc[(write-xml [doc document?] [out output-port? (current-output-port)])
         void?]{

Writes a document to the given output port, currently ignoring
everything except the document's root element.}

@defproc[(write-xml/content [content content/c] [out output-port? (current-output-port)])
         void?]{

Writes document content to the given output port.}

@defproc[(display-xml [doc document?] [out output-port? (current-output-port)])
         void?]{

Like @racket[write-xml], but newlines and indentation make the output
more readable, though less technically correct when whitespace is
significant.}

@defproc[(display-xml/content [content content/c] [out output-port? (current-output-port)])
         void?]{

Like @racket[write-xml/content], but with indentation and newlines
like @racket[display-xml].}
               

@defproc[(write-xexpr [xe xexpr/c] [out output-port? (current-output-port)]
                      [#:insert-newlines? insert-newlines? any/c #f])
         void?]{

Writes an X-expression to the given output port, without using an intermediate
XML document.

If @racket[insert-newlines?] is true, the X-expression is written with newlines
before the closing angle bracket of a tag.}


@; ----------------------------------------------------------------------

@section{XML and X-expression Conversions}

@defboolparam[permissive-xexprs v]{
 If this is set to non-false, then @racket[xml->xexpr] will allow
 non-XML objects, such as other structs, in the content of the converted XML
 and leave them in place in the resulting ``@tech{X-expression}''.
}

@defproc[(xml->xexpr [content content/c]) xexpr/c]{

Converts document content into an @tech{X-expression}, using
@racket[permissive-xexprs] to determine if foreign objects are allowed.}

@defproc[(xexpr->xml [xexpr xexpr/c]) content/c]{

Converts an @tech{X-expression} into XML content.}

@defproc[(xexpr->string [xexpr xexpr/c]) string?]{

Converts an @tech{X-expression} into a string containing XML.}

@defproc[(string->xexpr [str string?]) xexpr/c]{

Converts XML represented with a string into an @tech{X-expression}.}

@defproc[(xml-attribute-encode [str string?]) string?]{

Escapes a string as required for XML attributes.

The escaping performed for attribute strings is slightly
different from that performed for body strings, in that
double-quotes must be escaped, as they would otherwise
terminate the enclosing string.

Note that this conversion is performed automatically in attribute
positions by @racket[xexpr->string], and you are therefore unlikely to
need this function unless you are using @racket[include-template] to
insert strings directly into attribute positions of HTML.

@history[#:added "6.6.0.7"]
}

@defproc[((eliminate-whitespace [tags (listof symbol?) empty]
                                [choose (boolean? . -> . boolean?) (λ (x) x)])
          [elem element?])
         element?]{

Some elements should not contain any text, only other tags, except
they often contain whitespace for formating purposes.  Given a list of
tag names as @racket[tag]s and the identity function as
@racket[choose], @racket[eliminate-whitespace] produces a function
that filters out PCDATA consisting solely of whitespace from those
elements, and it raises an error if any non-whitespace text appears.
Passing in @racket[not] as @racket[choose] filters all elements which
are not named in the @racket[tags] list.  Using @racket[(lambda (x) #t)] as
@racket[choose] filters all elements regardless of the @racket[tags]
list.}

@defproc[(validate-xexpr [v any/c]) #t]{

If @racket[v] is an @tech{X-expression}, the result is
@racket[#t]. Otherwise, @racket[exn:invalid-xexpr]s is raised, with
a message of the form ``Expected @nonterm{something}, given
@nonterm{something-else}''. The @racket[code] field of the exception
is the part of @racket[v] that caused the exception.

@examples[#:eval xml-eval
  (validate-xexpr '(doc () "over " (em () "9000") "!"))
  (validate-xexpr #\newline)
]
}

@defproc[(correct-xexpr? [v any/c]
                         [success-k (-> any/c)]
                         [fail-k (exn:invalid-xexpr? . -> . any/c)])
         any/c]{

Like @racket[validate-xexpr], except that @racket[success-k] is called
on each valid leaf, and @racket[fail-k] is called on invalid leaves;
the @racket[fail-k] may return a value instead of raising an exception
or otherwise escaping. Results from the leaves are combined with
@racket[and] to arrive at the final result.}

@; ----------------------------------------------------------------------

@section{Parameters}

@defparam[empty-tag-shorthand shorthand (or/c (one-of/c 'always 'never) (listof symbol?))]{

A parameter that determines whether output functions should use the
@litchar{<}@nonterm{tag}@litchar{/>} tag notation instead of
@litchar{<}@nonterm{tag}@litchar{>}@litchar{</}@nonterm{tag}@litchar{>}
for elements that have no content.

When the parameter is set to @racket['always], the abbreviated
notation is always used. When set of @racket['never], the abbreviated
notation is never generated.  when set to a list of symbols is
provided, tags with names in the list are abbreviated.

The abbreviated form is the preferred XML notation.  However, most
browsers designed for HTML will only properly render XHTML if the
document uses a mixture of the two formats. The
@racket[html-empty-tags] constant contains the W3 consortium's
recommended list of XHTML tags that should use the shorthand. This
list is the default value of @racket[empty-tag-shorthand].}

@defthing[html-empty-tags (listof symbol?)]{

See @racket[empty-tag-shorthand].

@examples[
#:eval xml-eval
(parameterize ([empty-tag-shorthand html-empty-tags])
  (write-xml/content (xexpr->xml `(html 
                                    (body ((bgcolor "red"))
                                      "Hi!" (br) "Bye!")))))
]}

@defboolparam[collapse-whitespace collapse?]{

A parameter that controls whether consecutive whitespace is replaced
by a single space.  CDATA sections are not affected. The default is
@racket[#f].}

@defboolparam[read-comments preserve?]{

A parameter that determines whether comments are preserved or
discarded when reading XML.  The default is @racket[#f], which
discards comments.}

@defboolparam[xml-count-bytes count-bytes?]{

A parameter that determines whether @racket[read-xml] counts
characters or bytes in its location tracking. The default is
@racket[#f], which counts characters.

You may want to use @racket[#t] if, for example, you will be
communicating these offsets to a C program that can more easily deal
with byte offsets into the character stream, as opposed to UTF-8
character offsets.}

@defboolparam[xexpr-drop-empty-attributes drop?]{

Controls whether @racket[xml->xexpr] drops or preserves attribute
sections for an element that has no attributes. The default is
@racket[#f], which means that all generated @tech{X-expression}
elements have an attributes list (even if it's empty).}

@; ----------------------------------------------------------------------

@section{PList Library}

@defmodule[xml/plist]

The @racketmodname[xml/plist] library provides the ability to read and
write XML documents that conform to the @defterm{plist} DTD, which is
used to store dictionaries of string--value associations.  This format
is used by Mac OS (both the operating system and its applications)
to store all kinds of data.

A @deftech{plist value} is a value that could be created by an
expression matching the following @racket[_pl-expr] grammar, where a
value created by a @racket[_dict-expr] is a @deftech{plist dictionary}:

@racketgrammar*[
#:literals (list quote)
[pl-expr string
          (list 'true)
          (list 'false)
          (list 'integer integer)
          (list 'real real)
          (list 'data string)
          (list 'date string)
          dict-expr
          (list 'array pl-expr ...)]
[dict-expr (list 'dict assoc-pair ...)]
[assoc-pair (list 'assoc-pair string pl-expr)]
]

@defproc[(plist-value? [any/c v]) boolean?]{

Returns @racket[#t] if @racket[v] is a @tech{plist value},
@racket[#f] otherwise.}

@defproc[(plist-dict? [any/c v]) boolean?]{

Returns @racket[#t] if @racket[v] is a @tech{plist dictionary},
@racket[#f] otherwise.}

@defproc[(read-plist [in input-port?]) plist-value?]{

Reads a plist from a port, and produces a @tech{plist value}.}

@defproc[(write-plist [dict plist-value?] [out output-port?]) void?]{

Write a @tech{plist value} to the given port.}

@examples[
#:eval plist-eval
(define my-dict
  `(dict (assoc-pair "first-key"
                     "just a string with some  whitespace")
         (assoc-pair "second-key"
                     (false))
         (assoc-pair "third-key"
                     (dict ))
         (assoc-pair "fourth-key"
                     (dict (assoc-pair "inner-key"
                                       (real 3.432))))
         (assoc-pair "fifth-key"
                     (array (integer 14)
                            "another string"
                            (true)))
         (assoc-pair "sixth-key"
                     (array))
         (assoc-pair "seventh-key"
                     (data "some data"))
         (assoc-pair "eighth-key"
                     (date "2013-05-10T20:29:55Z"))))
(define-values (in out) (make-pipe))
(write-plist my-dict out)
(close-output-port out)
(define new-dict (read-plist in))
(equal? my-dict new-dict)
]

The XML generated by @racket[write-plist] in the above example looks
like the following, if re-formatted by hand to have newlines and
indentation:

@verbatim[#:indent 2]|{
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist SYSTEM 
 "file://localhost/System/Library/DTDs/PropertyList.dtd">
<plist version="0.9">
  <dict>
    <key>first-key</key>
    <string>just a string with some  whitespace</string>
    <key>second-key</key>
    <false />
    <key>third-key</key>
    <dict />
    <key>fourth-key</key>
    <dict>
      <key>inner-key</key>
      <real>3.432</real>
    </dict>
    <key>fifth-key</key>
    <array>
      <integer>14</integer>
      <string>another string</string>
      <true />
    </array>
    <key>sixth-key</key>
    <array />
    <key>seventh-key</key>
    <data>some data</data>
    <key>eighth-key</key>
    <date>2013-05-10T20:29:55Z</date>
  </dict>
</plist>
}|

@; ----------------------------------------------------------------------

@section{Simple X-expression Path Queries}

@(require (for-label xml/path))
@defmodule[xml/path]

This library provides a simple path query library for X-expressions.

@defthing[se-path? contract?]{
 A sequence of symbols followed by an optional keyword.

 The prefix of symbols specifies a path of tags from the leaves with an implicit any sequence to the root. The final, optional keyword specifies an attribute. 
}

@defproc[(se-path*/list [p se-path?] [xe xexpr?])
         (listof any/c)]{
 Returns a list of all values specified by the path @racket[p] in the X-expression @racket[xe].         
}

@defproc[(se-path* [p se-path?] [xe xexpr?])
         any/c]{
 Returns the first answer from @racket[(se-path*/list p xe)].
}

@(define path-eval (make-base-eval))
@interaction-eval[#:eval path-eval (require xml/path)]
@examples[
#:eval path-eval
       (define some-page 
         '(html (body (p ([class "awesome"]) "Hey") (p "Bar"))))
       (se-path*/list '(p) some-page)
       (se-path* '(p) some-page)
       (se-path* '(p #:class) some-page)                 
       (se-path*/list '(body) some-page)
       (se-path*/list '() some-page)
]

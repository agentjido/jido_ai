Definitions.

FLOAT_END = [0-9]+\.[0-9]*
FLOAT_START = [0-9]*\.[0-9]+
INTEGER = [0-9]+
P_OPEN = \(
P_CLOSE = \)
B_OPEN = \[
B_CLOSE = \]
C_OPEN = \{
C_CLOSE = \}
WORD = [a-zA-Zä-üßÄ-Ü_][a-zA-Zä-üßÄ-Ü0-9_\-]*

PLUS = \+
MINUS = \-
DIVIDE = \/
MULTIPLY = \*
POWER = \^

NEWLINE = \n

FACTORIAL = !

COMMA = ,
DOT = \.

SIGN = (\-|\+)

WHITESPACE = [\s\t\n\r]

STRING = "([^\\"]+|\\"|\\)*"

Rules.
% reserved words appear up here so they're not eaten by {WORD}
not : {token, {'not', TokenLine}}.
null : {token, {nil, TokenLine}}.
false : {token, {false, TokenLine}}.
true : {token, {true, TokenLine}}.

{INTEGER}    : {token, {number, TokenLine, list_to_integer(TokenChars)}}.
{FLOAT_END}      : {token, {number, TokenLine, list_to_float(TokenChars)}}.
{FLOAT_START}      : {token, {number, TokenLine, list_to_float([48 | TokenChars])}}.
{P_OPEN}    : {token, {'(', TokenLine}}.
{P_CLOSE}   : {token, {')', TokenLine}}.
{C_OPEN}    : {token, {'{', TokenLine}}.
{C_CLOSE}   : {token, {'}', TokenLine}}.
{PLUS}   : {token, {'+', TokenLine}}.
{MINUS}  : {token, {'-', TokenLine}}.
{DIVIDE} : {token, {'/', TokenLine}}.
{MULTIPLY} : {token, {'*', TokenLine}}.
{POWER} : {token, {'^', TokenLine}}.
{FACTORIAL} : {token, {'!', TokenLine}}.
{STRING} : {token, {string, TokenLine, parse_string(TokenChars)}}.
{WORD}  : {token, {word, TokenLine, unicode:characters_to_binary(TokenChars)}}.
{B_OPEN} : {token, {'[', TokenLine}}.
{B_CLOSE} : {token, {']', TokenLine}}.
{DOT} : {token, {'.', TokenLine}}.
& : {token, {'&', TokenLine}}.
\|\^ : {token, {'|^', TokenLine}}.
\| : {token, {'|', TokenLine}}.
>> : {token, {'>>', TokenLine}}.
<< : {token, {'<<', TokenLine}}.
~ : {token, {'~', TokenLine}}.
&& : {token, {'and', TokenLine}}.
\|\| : {token, {'or', TokenLine}}.

\? : {token, {'?', TokenLine}}.
: : {token, {':', TokenLine}}.
!= : {token, {'!=', TokenLine}}.
== : {token, {'==', TokenLine}}.
<= : {token, {'<=', TokenLine}}.
>= : {token, {'>=', TokenLine}}.
<  : {token, {'<', TokenLine}}.
>  : {token, {'>', TokenLine}}.
=> : {token, {'=>', TokenLine}}.

% {NEWLINE} : {token, {newline, TokenLine}}.
{WHITESPACE}+ : skip_token.
{COMMA} : {token, {',', TokenLine}}.

Erlang code.
parse_string(Chars) -> 
  'Elixir.Abacus.Runtime.Helpers':unescape_string(Chars).
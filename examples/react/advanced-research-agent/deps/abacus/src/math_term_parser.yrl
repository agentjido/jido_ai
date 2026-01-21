Terminals '(' ')'
  '+' '/' '*' '-' '^'
  word ',' number
  '!'
  '.' '[' ']'
  '~' '&' '|' '|^' '<<' '>>'
  'and' 'or' 'not' '?' ':'
  '==' '!=' '<=' '>=' '<' '>' nil true false string.
Nonterminals expr argument arguments function variable variables signed_number.
Rootsymbol expr.
Unary 1000 '!'.
Right 900 '^'.
Unary 850 'not'.
Unary 800 '~'.
Left 750 '*' '/'.
Left 700 '+' '-'.
Left 600 '<<' '>>'.
Left 590 '==' '!=' '<=' '<' '>=' '>'.
Left 580 '&'.
Left 550 '|^'.
Left 520 '|'.
Left 480 'and'.
Left 420 'or'.
Right 300 '?' ':'.


Unary 100 function.
Unary 0 variable.

% boolean stuff
expr -> nil : nil.
expr -> true : true.
expr -> false : false.

expr -> expr '==' expr : {eq, '$1', '$3'}.
expr -> expr '!=' expr : {neq, '$1', '$3'}.
expr -> expr '>=' expr : {gte, '$1', '$3'}.
expr -> expr '<=' expr : {lte, '$1', '$3'}.
expr -> expr '<' expr : {lt, '$1', '$3'}.
expr -> expr '>' expr : {gt, '$1', '$3'}.

expr -> expr 'and' expr : {logical_and, '$1', '$3'}.
expr -> expr 'or' expr : {logical_or, '$1', '$3'}.
expr -> 'not' expr : {logical_not, '$2'}.

expr -> expr '?' expr ':' expr : {ternary_if, '$1', '$3', '$5'}.

% Binary stuff
expr -> '~' expr : {'not', '$2'}.
expr -> expr '&' expr : {'and', '$1', '$3'}.
expr -> expr '|' expr : {'or', '$1', '$3'}.
expr -> expr '|^' expr : {'xor', '$1', '$3'}.
expr -> expr '<<' expr : {shift_left, '$1', '$3'}.
expr -> expr '>>' expr : {shift_right, '$1', '$3'}.

% Math stuff
expr -> expr '^' expr : {power, '$1', '$3'}.
expr -> expr '+' expr : {add, '$1', '$3'}.
expr -> expr '-' expr : {subtract, '$1', '$3'}.
expr -> expr '/' expr : {divide, '$1', '$3'}.
expr -> expr '*' expr : {multiply, '$1', '$3'}.
expr -> expr '!' : {factorial, '$1'}.

% Grouping
expr -> '(' expr ')' : '$2'.

% What is an expression
expr -> number : extract_token('$1').
expr -> function : '$1'.
expr -> variables : '$1'.
expr -> signed_number : '$1'.

% Support signed numbers
signed_number -> '+' number : extract_token('$2').
signed_number -> '-' number : -extract_token('$2').

% Access
variable -> word : {variable, extract_token('$1')}.

variables -> variable : {access, ['$1']}.
variables -> variables '.' variable : {access, concat([extract('$1'), ['$3']])}.
variables -> variables '[' expr ']' : {access, concat([extract('$1'), [{index, '$3'}]])}.

% Functions
argument -> expr : '$1'.
arguments -> argument : ['$1'].
arguments -> argument ',' arguments : ['$1' | '$3'].

function -> word '(' ')' : {function, extract_token('$1'), []}.
function -> word '(' arguments ')' : {function, extract_token('$1'), '$3'}.

% Strings
expr -> string : extract_token('$1').

Erlang code.
extract_token({_Token, _Line, Value}) -> Value.
extract({access, Value}) -> Value.
concat(List) -> lists:concat(List).

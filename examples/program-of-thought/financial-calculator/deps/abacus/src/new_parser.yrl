Terminals '(' ')' '{' '}' newline
  '+' '/' '*' '-' '^'
  word ',' number
  '!' '=>'
  '.' '[' ']'
  '~' '&' '|' '|^' '<<' '>>'
  'and' 'or' 'not' '?' ':'
  '==' '!=' '<=' '>=' '<' '>' nil true false string.
Nonterminals expr statement statements argument arguments function variable variables signed_number lambda block.
Rootsymbol expr.
Left 1200 '(' ')'.
Right 1100 '=>'.
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
Unary 20 argument.
Unary 0 variable.

% boolean stuff
expr -> nil : nil.
expr -> true : true.
expr -> false : false.

expr -> expr '==' expr : {'==', [], ['$1', '$3']}.
expr -> expr '!=' expr : {'!=', [], ['$1', '$3']}.
expr -> expr '>=' expr : {'>=', [], ['$1', '$3']}.
expr -> expr '<=' expr : {'<=', [], ['$1', '$3']}.
expr -> expr '<' expr : {'<', [], ['$1', '$3']}.
expr -> expr '>' expr : {'>', [], ['$1', '$3']}.

expr -> expr 'and' expr : {'&&', [], ['$1', '$3']}.
expr -> expr 'or' expr : {'||', [], ['$1', '$3']}.
expr -> 'not' expr : {'not', [], ['$2']}.

% ternary if op
expr -> expr '?' expr ':' expr : {'if', [{import, 'Elixir.Kernel'}], [
    '$1', 
    [
      {'do', '$3'}, 
      {'else', '$5'}
    ]
  ]
}.

% Binary stuff
expr -> '~' expr : {'~~~', [], ['$2']}.
expr -> expr '&' expr : {'&&&', [], ['$1', '$3']}.
expr -> expr '|' expr : {'|||', [], ['$1', '$3']}.
expr -> expr '|^' expr : {'^^^', [], ['$1', '$3']}.
expr -> expr '<<' expr : {'<<<', [], ['$1', '$3']}.
expr -> expr '>>' expr : {'>>>', [], ['$1', '$3']}.

% Math stuff
expr -> expr '^' expr : {'^', [], ['$1', '$3']}.
expr -> expr '+' expr : {'+', [], ['$1', '$3']}.
expr -> expr '-' expr : {'-', [], ['$1', '$3']}.
expr -> expr '/' expr : {'/', [], ['$1', '$3']}.
expr -> expr '*' expr : {'*', [], ['$1', '$3']}.
expr -> expr '!' : {'!', [], ['$1']}.

% Grouping
expr -> '(' expr ')' : '$2'.

% What is an expression
expr -> number : extract_token('$1').
expr -> signed_number : '$1'.

% Support signed numbers
signed_number -> '+' number : extract_token('$2').
signed_number -> '-' number : -extract_token('$2').

% Functions
expr -> function : '$1'.

argument -> expr : '$1'.
arguments -> argument : ['$1'].
arguments -> argument ',' arguments : ['$1' | '$3'].

function -> expr '(' arguments ')' : {'$1', [], '$3'}.
function -> expr '(' ')' : {'$1', [], []}.

% Strings
expr -> string : extract_token('$1').

% Access
expr -> variables : '$1'.

variable -> word : {variable, extract_token('$1')}.

variables -> variable : var('$1').
variables -> variables '.' variable : {'.', [], ['$1', '$3']}.
variables -> variables '[' expr ']' : {'.', [], ['$1', '$3']}.

Erlang code. 

extract_token({_Token, _Line, Value}) -> Value.

var({variable, Name}) -> 
  Variables = 'Elixir.Process':get(variables, maps:new()),
  Symbol = case maps:get(Name, Variables, nil) of
    nil -> 
      Len = maps:size(Variables),
      LenS = integer_to_binary(Len),
      SymbolGen = binary_to_atom(<<"var", LenS/binary>>, utf8),
      UpdatedVariables = maps:put(Name, SymbolGen, Variables),
      'Elixir.Process':put(variables, UpdatedVariables),
      SymbolGen;
    S -> S
  end,
  {Symbol, [], 'nil'}.

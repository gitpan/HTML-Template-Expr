package HTML::Template::Expr;

use strict;
use vars qw($VERSION);

$VERSION = '0.01';

use HTML::Template 2.4;
use Carp qw(croak confess);
use Parse::RecDescent;
# use Data::Dumper;

use base 'HTML::Template';

use vars qw($GRAMMAR);
$GRAMMAR = <<END;
<autotree>

expression    : subexpression /^\$/  { \$return = \$item[1]; } 

subexpression : '(' comparison ')'
              | '(' math ')'
              | '(' logic ')'
              | '(' subexpression ')' { \$item{subexpression} }
              | function_call
              | thing
              | <error>

comparison    : thing comparison_op thing
              { [ \$item{comparison_op}{__VALUE__}, \$item[1], \$item[3] ] }
              | thing comparison_op subexpression
              { [ \$item{comparison_op}{__VALUE__}, \$item[1], \$item[3] ] }
              | subexpression comparison_op thing
              { [ \$item{comparison_op}{__VALUE__}, \$item[1], \$item[3] ] }
              | subexpression comparison_op subexpression
              { [ \$item{comparison_op}{__VALUE__}, \$item[1], \$item[3] ] }

comparison_op : '>=' | '<=' | '==' | '!=' | '<'  | '>'  
              | 'le' | 'ge' | 'eq' | 'ne' | 'lt' | 'gt'

math          : thing math_op thing
              { [ \$item{math_op}{__VALUE__}, \$item[1], \$item[3] ] }
              | thing math_op subexpression
              { [ \$item{math_op}{__VALUE__}, \$item[1], \$item[3] ] }
              | subexpression math_op thing
              { [ \$item{math_op}{__VALUE__}, \$item[1], \$item[3] ] }
              | subexpression math_op subexpression
              { [ \$item{math_op}{__VALUE__}, \$item[1], \$item[3] ] }

math_op       : '+' | '-' | '*' | '/' | '%'

logic         : thing logic_op thing
              { [ \$item{logic_op}{__VALUE__}, \$item[1], \$item[3] ] }
              | thing logic_op subexpression
              { [ \$item{logic_op}{__VALUE__}, \$item[1], \$item[3] ] }
              | subexpression logic_op thing
              { [ \$item{logic_op}{__VALUE__}, \$item[1], \$item[3] ] }
              | subexpression logic_op subexpression
              { [ \$item{logic_op}{__VALUE__}, \$item[1], \$item[3] ] }

logic_op      : '||' | 'or' | '&&' | 'and'

function_call : function_name '(' args ')' | function_name '(' ')'

function_name : /[A-Za-z_][A-Za-z0-9_]*/

args          : arg_list | subexpression

arg_list      : <leftop: subexpression ',' subexpression>
                { \@item[1 .. \$#item]; }

thing         : var    { \$item{var};  }
              | float  { \$item{float}{__VALUE__}  }
              | int    { \$item{int}{__VALUE__}    }
              | string { \$item{string}{__DIRECTIVE1__}[2] }


var           : /[A-Za-z_][A-Za-z0-9_]*/
float         : /\\d*\\.\\d+/
int           : /\\d+/
string        : <perl_quotelike>

END

# create global parser
use vars qw($PARSER);
$PARSER = Parse::RecDescent->new($GRAMMAR);

# initialize preset function table
use vars qw(%FUNC);
%FUNC = 
  (
   'sprintf' => sub { sprintf(@_); },
   'substr'  => sub { 
     return substr($_[0], $_[1]) if @_ == 2; 
     return substr($_[0], $_[1], $_[2]);
   },
   'lc'      => sub { lc($_[0]); },
   'lcfirst' => sub { lcfirst($_[0]); },
   'uc'      => sub { uc($_[0]); },
   'ucfirst' => sub { ucfirst($_[0]); },
   'length'  => sub { length($_[0]); },
   'defined' => sub { defined($_[0]); },
   'abs'     => sub { abs($_[0]); },
   'atan2'   => sub { atan2($_[0], $_[1]); },
   'cos'     => sub { cos(@_); },
   'exp'     => sub { exp(@_); },
   'hex'     => sub { hex(@_); },
   'int'     => sub { int(@_); },
   'log'     => sub { log(@_); },
   'oct'     => sub { oct(@_); },
   'rand'    => sub { rand(@_); },
   'sin'     => sub { sin(@_); },
   'sqrt'    => sub { sqrt(@_); },
   'srand'   => sub { srand(@_); },
  );

sub new { 
  my $pkg = shift;
  my $self;

  # check hashworthyness
  croak("HTML::Template::Expr->new() called with odd number of option parameters - should be of the form option => value")
    if (@_ % 2);
  my %options = @_;

  # check for unsupported options file_cache and shared_cache
  croak("HTML::Template::Expr->new() : sorry, this module won't work with file_cache or shared_cache modes.  This will hopefully be fixed in an upcoming version.")
    if ($options{file_cache} or $options{shared_cache});

  # push on our filter, one way or another.  Why did I allow so many
  # different ways to say the same thing?  Was I smoking crack?
  my @expr;
  if (exists $options{filter}) {
    # CODE => ARRAY
    $options{filter} = [ { 'sub'    => $options{filter},
                           'format' => 'scalar'         } ]
      if ref($options{filter}) eq 'CODE';

    # HASH => ARRAY
    $options{filter} = [ $options{filter} ]
      if ref($options{filter}) eq 'HASH';

    # push onto ARRAY
    if (ref($options{filter}) eq 'ARRAY') {
      push(@{$options{filter}}, { 'sub'    => sub { _expr_filter(\@expr, @_); },
                                  'format' => 'scalar' });
    } else {
      # unrecognized
      croak("HTML::Template::Expr->new() : bad format for filter argument.  Please check the HTML::Template docs for the allowed forms.");      
    }
  } else {
    # new filter
    $options{filter} = [ { 'sub'    => sub { _expr_filter(\@expr, @_) },
                           'format' => 'scalar'                    
                         } ];
  }  

  # force global_vars on
  $options{global_vars} = 1;

  # create an HTML::Template object, catch the results to keep error
  # message line-numbers helpful
  eval {
    $self = HTML::Template->new(%options);
  };
  croak("HTML::Template::Expr->new() : Error creating HTML::Template object : $@") if $@;

  # stow expr
  $self->{expr} = \@expr;

  # get functions
  if ($options{functions}) {
    $self->{expr_func} = $options{functions};
  } else {
    $self->{expr_func} = {};
  }

  # doubly blessed and sent into the world
  return bless($self, $pkg);

}

sub _expr_filter {
  my $expr = shift;
  my $text = shift;

  # print STDERR "\n\nTEXT IN:\n $$text\n";  

  # find expressions and create parse trees
  my ($ref, $tree, $expr_text, $vars, $which, $out);
  $$text =~ s/<[Tt][Mm][Pp][Ll]_([Ii][Ff]|[Uu][Nn][Ll][Ee][Ss][Ss]|[Vv][Aa][Rr])\s+[Ee][Xx][Pp][Rr]="(.*?)"\s*>
             /
               $which = $1;
               $expr_text = $2;  

               # add enclosing parens to keep grammar simple
               $expr_text = "($expr_text)";

               # parse the expression
               eval {
                 $tree = $PARSER->expression($expr_text);
               };
               croak("HTML::Template::Expr : Unable to parse expression: $expr_text")
                  if $@ or not $tree;

               # stub out variables needed by the expression
               $out = "<tmpl_if __expr_unused__>";
               foreach my $var (_expr_vars($tree)) {
                 next unless defined $var;
                 $out .= "<tmpl_var name=\"$var\">";
               }

               # save parse tree for later
               push(@$expr, $tree);
               
               # add the expression placeholder and replace
               $out . "<\/tmpl_if><tmpl_$which __expr_" . $#{$expr} . "__>";
             /xeg;

  # print STDERR "\n\nTEXT OUT:\n $$text\n";
  return;
}

# find all variables in a parse tree
sub _expr_vars {
  my $tree = shift;

  return unless ref $tree;

  if (ref($tree) eq 'var') {
    return ($tree->{__VALUE__});
  } elsif ($tree->{thing}) {
    return _expr_vars($tree->{thing});
  } elsif ($tree->{expression}) {
    return _expr_vars($tree->{expression});
  } elsif ($tree->{subexpression}) {
    return _expr_vars($tree->{subexpression});
  } elsif ($tree->{comparison}) {
    return (_expr_vars($tree->{comparison}[0]), 
            _expr_vars($tree->{comparison}[1]));
  } elsif ($tree->{math}) {
    return (_expr_vars($tree->{math}[0]), 
            _expr_vars($tree->{math}[1]));
  } elsif ($tree->{logic}) {
    return (_expr_vars($tree->{logic}[0]), 
            _expr_vars($tree->{logic}[1]));
  } elsif ($tree->{function_call}) {
    if ($tree->{function_call}{args}) {
      if ($tree->{function_call}{args}{arg_list}) {
        return map { _expr_vars($_) } @{$tree->{function_call}{args}{arg_list}};
      } else {
        return _expr_vars($tree->{function_call}{args});
      }
    } else {
      return;
    }
  }


    
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Purity = 0;
    local $Data::Dumper::Deepcopy = 1;
    print STDERR Data::Dumper->Dump([\$tree],['$tree']);

  
  confess("HTML::Template::_expr_vars fell off the edge!");
}


sub output {
  my $self = shift;
  my $expr = $self->{expr};

  # setup expression evaluators
  my %param;
  for (my $x = 0; $x < @$expr; $x++) {
    my $node = $expr->[$x];
    $param{"__expr_" . $x . "__"} = sub { _expr_evaluate($node, @_) };
  }
  $self->param(\%param);

  # setup %FUNC 
  local %FUNC = (%FUNC, %{$self->{expr_func}});

  return HTML::Template::output($self, @_);
}

sub _expr_evaluate {
  my ($tree, $template) = @_;
  # print STDERR Data::Dumper->Dump([$tree],['$tree']);

  # get at subexpressions, if we're at the top
  $tree = $tree->[0] if ref($tree) eq 'ARRAY';
  
  # return scalars up
  return $tree unless ref $tree;
  
  # lookup var
  return $template->param($tree->{__VALUE__}) if ref($tree) eq 'var';

  # handle expressions
  my ($op, $lhs, $rhs);
  if (ref $tree eq 'subexpression') {
    if ($tree->{thing}) {
      return _expr_evaluate($tree->{thing}, $template);
    } elsif ($tree->{comparison}) {
      ($op, $lhs, $rhs) = @{$tree->{comparison}};

      # recurse and resolve subexpressions
      $lhs = _expr_evaluate($lhs, $template) if ref($lhs);
      $rhs = _expr_evaluate($rhs, $template) if ref($rhs);

      # do the op
      $op eq '>=' and return $lhs >= $rhs;
      $op eq '<=' and return $lhs <= $rhs;
      $op eq '==' and return $lhs == $rhs;
      $op eq '!=' and return $lhs != $rhs;
      $op eq '>'  and return $lhs >  $rhs;
      $op eq '<'  and return $lhs <  $rhs;
      $op eq 'le' and return $lhs le $rhs;
      $op eq 'ge' and return $lhs ge $rhs;
      $op eq 'eq' and return $lhs eq $rhs;
      $op eq 'ne' and return $lhs ne $rhs;
      $op eq 'lt' and return $lhs lt $rhs;
      $op eq 'gt' and return $lhs gt $rhs;

      confess("HTML::Template::Expr : unknown op: $op");

    } elsif ($tree->{math}) {
      ($op, $lhs, $rhs) = @{$tree->{math}};
      
      # recurse and resolve subexpressions
      $lhs = _expr_evaluate($lhs, $template) if ref $lhs;
      $rhs = _expr_evaluate($rhs, $template) if ref $rhs;
      
      # do the op
      $op eq '+' and return $lhs + $rhs;
      $op eq '-' and return $lhs - $rhs;
      $op eq '/' and return $lhs / $rhs;
      $op eq '*' and return $lhs * $rhs;
      $op eq '%' and return $lhs %  $rhs;

      confess("HTML::Template::Expr : unknown op: $op");
      
    } elsif ($tree->{logic}) {
      ($op, $lhs, $rhs) = @{$tree->{logic}};

      if ($op eq 'or' or $op eq '||') {
        # short circuit or
        $lhs = _expr_evaluate($lhs, $template) if ref $lhs;
        return 1 if $lhs;
        $rhs = _expr_evaluate($rhs, $template) if ref $rhs;
        return 1 if $rhs;
        return 0;
      } else {
        # short circuit and
        $lhs = _expr_evaluate($lhs, $template) if ref $lhs;
        return 0 unless $lhs;
        $rhs = _expr_evaluate($rhs, $template) if ref $rhs;
        return 0 unless $rhs;

        return 1;
      }
    } elsif ($tree->{function_call}) {
      my $func_name = $tree->{function_call}{function_name}{__VALUE__};
      my $func;
      if (exists($FUNC{$func_name})) {
        $func = $FUNC{$func_name};
      } else {
        croak("HTML::Template::Expr : found unknown subroutine call : $func_name\n");
      }

      if ($tree->{function_call}{args}) {
        if ($tree->{function_call}{args}{arg_list}) {
          my @args = map { _expr_evaluate($_, $template) } @{$tree->{function_call}{args}{arg_list}};
          my $result = $func->(@args);
          return $result;
        } else {
          return $func->(_expr_evaluate($tree->{function_call}{args}, $template));
        }
      } else {
        return $func->();
      }
        
    } else {
       # empty expression, recurse
       return _expr_evaluate($tree->{subexpression}, $template);
    }
  }

  croak("HTML::Template::Expr : fell off the edge of _expr_evaluate()!  This is a bug - please report it to the author.");
}


1;
__END__
=pod

=head1 NAME

HTML::Template::Expr - HTML::Template extension adding expression support

=head1 SYNOPSIS

  use HTML::Template::Expr;

  my $template = HTML::Template::Expr->new(filename => 'foo.tmpl');
  $template->param(banana_count => 10);
  print $template->output();

=head1 DESCRIPTION

This module provides an extension to HTML::Template which allows
expressions in the template syntax.  This is purely an addition - all
the normal HTML::Template options, syntax and behaviors will still
work.  See L<HTML::Template> for details.

Expression support includes comparisons, math operations, string
operations and a mechanism to allow you add your own functions at
runtime.  The basic syntax is:

   <TMPL_IF EXPR="banana_count > 10">
     I've got a lot of bananas.
   </TMPL_IF>

This will output "I've got a lot of bananas" if you call:

   $template->param(banana_count => 100);

In your script.  <TMPL_VAR>s also work with expressions:

   I'd like to have <TMPL_VAR EXPR="banana_count * 2"> bananas.

This will output "I'd like to have 200 bananas." with the same param()
call as above.

=head1 MOTIVATION

Some of you may wonder if I've been replaced by a pod person.  Just
for the record, I still think this sort of thing should be avoided.
However, I realize that there are some situations where allowing the
template author some programatic leeway can be invaluable.

If you don't like it, don't use this module.  Keep using plain ol'
HTML::Template - I know I will!  However, if you find yourself needing
a little programming in your template, for whatever reason, then this
module may just save you from HTML::Mason.

=head1 BASIC SYNTAX

Variables are unquoted alphanumeric strings with the same restrictions
as variable names in HTML::Template.  Their values are set through
param(), just like normal HTML::Template variables.  For example,
these two lines are equivalent:

   <TMPL_VAR EXPR="foo">
  
   <TMPL_VAR NAME="foo">

Numbers are unquoted strings of numbers and may have a single "." to
indicate a floating point number.  For example:

   <TMPL_VAR EXPR="10 + 20.5">

String constants must be enclosed in quotes, single or double.  For example:

   <TMPL_VAR EXPR="sprintf('%d', foo)">

The parser is currently rather simple, so all compound expressions
must be parenthesized.  Examples:

   <TMPL_VAR EXPR="(10 + foo) / bar">

   <TMPL_IF EXPR="(foo % 10) > (bar + 1)">

If you don't like this rule please feel free to contribute a patch
to improve the parser's grammar.

=head1 COMPARISON

Here's a list of supported comparison operators:

=over 4

=item * Numeric Comparisons

=over 4

=item * E<lt>

=item * E<gt>

=item * ==

=item * !=

=item * E<gt>=

=item * E<lt>=

=item * E<lt>=E<gt>

=back 4

=item * String Comparisons

=over 4

=item * gt

=item * lt

=item * eq

=item * ne

=item * ge

=item * le

=item * cmp

=back 4

=back 4

=head1 MATHEMATICS

The basic operators are supported:

=over 4

=item * +

=item * -

=item * *

=item * /

=item * %

=back 4

There are also some mathy functions.  See the FUNCTIONS section below.

=head1 LOGIC

Boolean logic is available:

=over 4

=item * && (synonym: and)

=item * || (synonym: or)

=back 4

=head1 FUNCTIONS

The following functions are available to be used in expressions.  See
perldoc perlfunc for details.

=over 4

=item * sprintf

=item * substr (2 and 3 arg versions only)

=item * lc

=item * lcfirst

=item * uc

=item * ucfirst

=item * length

=item * defined

=item * abs

=item * atan2

=item * cos

=item * exp

=item * hex

=item * int

=item * log

=item * oct

=item * rand

=item * sin

=item * sqrt

=item * srand

=back 4

All functions must be called using full parenthesis.  For example,
this is a syntax error:

   <TMPL_IF expr="defined foo">

But this is good:

   <TMPL_IF expr="defined(foo)">

=head1 DEFINING NEW FUNCTIONS

To defined a new function, pass a C<functions> option to new:

  $t = HTML::Template::Expr->new(filename => 'foo.tmpl',
                                 functions => 
                                   { func_name => \&func_handler });

You provide a subroutine reference that will be called during output.
It will recieve as arguments the parameters specified in the template.
For example, here's a function that checks if a directory exists:

  sub directory_exists {
    my $dir_name = shift;
    return 1 if -d $dir_name;
    return 0;
  }

If you call HTML::Template::Expr->new() with a C<functions> arg:

  $t = HTML::Template::Expr->new(filename => 'foo.tmpl',
                                 functions => {
                                    directory_exists => \&directory_exists
                                 });

Then you can use it in your template:

  <tmpl_if expr="directory_exists('/home/sam')">

This can be abused in ways that make my teeth hurt.

=head1 CAVEATS

Currently the module forces the HTML::Template global_vars option to
be set.  This will hopefully go away in a future version, so if you
need global_vars in your templates then you should set it explicitely.

The module won't work with HTML::Template's file_cache or shared_cache
modes, but normal memory caching should work.  I hope to address this
is a future version.

The module is inefficient, both in parsing and evaluation.  I'll be
working on this for future versions and patches are always welcome.

=head1 BUGS

When you find a bug, join the mailing list and tell us about it
(htmltmpl@lists.vm.com).  You can join the HTML::Template mailing-list
by sending a blank email to htmltmpl-subscribe@lists.vm.com.  Of
course, you can still email me directly (sam@tregar.com) with bugs,
but I reserve the right to forward bug reports to the mailing list.

When submitting bug reports, be sure to include full details,
including the VERSION of the module, a test script and a test template
demonstrating the problem!

=head1 AUTHOR

Sam Tregar <sam@tregar.com>

=head1 LICENSE

HTML::Template::Expr : HTML::Template extension adding expression support

Copyright (C) 2001 Sam Tregar (sam@tregar.com)

This module is free software; you can redistribute it and/or modify it
under the terms of either:

a) the GNU General Public License as published by the Free Software
Foundation; either version 1, or (at your option) any later version,
or

b) the "Artistic License" which comes with this module.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either
the GNU General Public License or the Artistic License for more details.

You should have received a copy of the Artistic License with this
module, in the file ARTISTIC.  If not, I'll be glad to provide one.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
USA

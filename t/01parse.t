use Test::More tests => 14;
use HTML::Template::Expr;
use Parse::RecDescent;
use Data::Dumper;

use constant DEBUG => 0;

# test grammar directly
$::RD_HINT = 1 if DEBUG;
my @tests = (
             "(foo > 10)",
             "((foo < 10) != (bar > 10))",
             "('foo' eq 'bar')",
             "((foo + 10.1) > 100)",
             "(((foo > 10) || (200 < bar)) + 10.5)",
             "(call(foo, 10))",
             "(call(foo, 10) > 10)",
             "(first( foo, 10 ))",
             "(call(foo, \"baz\", 10) eq 'string val')", 
             "((foo < 10) != (bar > 10))",
             "(((call(foo, 10) + 100) > 10) || (foo eq \"barf\"))",
             "((foo > bar))",
	     "call(call2(call3()))",
	     "call(foo > bar)"
	    );

foreach my $test (@tests) {
 my $tree = $HTML::Template::Expr::PARSER->expression($test);
 ok($tree, "parsing \"$test\"");
 if (DEBUG) {
   local $Data::Dumper::Indent = 1;
   local $Data::Dumper::Purity = 0;
   local $Data::Dumper::Deepcopy = 1;
   print STDERR Data::Dumper->Dump([\$tree],['$tree']);
   print STDERR "vars: ", join(',', HTML::Template::Expr::_expr_vars($tree)), "\n\n";
 }
}

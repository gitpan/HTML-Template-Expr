use Test;
BEGIN { plan tests => 1 };
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
           );
foreach my $test (@tests) {
 my $tree = $HTML::Template::Expr::PARSER->expression($test);
 ok($tree);
 if (DEBUG) {
   local $Data::Dumper::Indent = 1;
   local $Data::Dumper::Purity = 0;
   local $Data::Dumper::Deepcopy = 1;
   print STDERR Data::Dumper->Dump([\$tree],['$tree']);
 }
}

my ($template, $output);

$template = HTML::Template::Expr->new(path => ['templates'],
                                      filename => 'foo.tmpl');
$template->param(foo => 100);
$output = $template->output();
ok($output =~ /greater than/i);

$template->param(foo => 10);
$output = $template->output();
ok($output =~ /less than/i);

                                       
$template = HTML::Template::Expr->new(path => ['templates'],
                                      filename => 'complex.tmpl',
                                     );
$template->param(foo => 11,
                 bar => 0,
                 fname => 'president',
                 lname => 'clinton');
$output = $template->output();
ok($output =~ /Foo is greater than 10/i);
ok($output !~ /Bar and Foo/i);
ok($output =~ /Bar or Foo/i);
ok($output =~ /Bar - Foo = -11/i);
ok($output =~ /Math Works, Alright/i);
ok($output =~ /My name is President Clinton/);
ok($output =~ /Resident Alien is phat/);
ok($output =~ /Resident has 8 letters, which is less than 10 and greater than 5/);

$template = HTML::Template::Expr->new(path => ['templates'],
                                      filename => 'loop.tmpl',
                                     );
$template->param(simple => [
                            { foo => 10 },
                            { foo => 100 },
                            { foo => 1000 }
                           ]);
$template->param(color => 'blue');
$template->param(complex => [ 
                             { 
                              fname => 'Yasunari',
                              lname => 'Kawabata',
                              inner => [
                                        { stat_name => style, 
                                          stat_value => 100 ,
                                        },
                                        { stat_name => shock,
                                          stat_value => 1,
                                        },
                                        { stat_name => poetry,
                                          stat_value => 100
                                        },
                                        { stat_name => machismo,
                                          stat_value => 50
                                        },
                                       ],
                             },
                             { 
                              fname => 'Yukio',
                              lname => 'Mishima',
                              inner => [
                                        { stat_name => style, 
                                          stat_value => 50,
                                        },
                                        { stat_name => shock,
                                          stat_value => 100,
                                        },
                                        { stat_name => poetry,
                                          stat_value => 1
                                        },
                                        { stat_name => machismo,
                                          stat_value => 100
                                        },
                                       ],
                             },
                            ]);

$output = $template->output();
ok($output =~ /Foo is less than 10.\s+Foo is greater than 10.\s+Foo is greater than 10./);


# test user-defined functions
my $repeat = sub { $_[0] x $_[1] };

$template = HTML::Template::Expr->new(path => ['templates'],
                                      filename => 'func.tmpl',
                                      functions => {
                                                    repeat => $repeat,
                                                   },
                                     );
$template->param(repeat_me => 'foo ');
$output = $template->output();
ok($output =~ /foo foo foo foo/);
ok($output =~ /FOO FOO FOO FOO/);


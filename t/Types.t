use strict;
use warnings;

BEGIN { unshift @INC, './lib'; }

use Test::More tests => 5;
use Igor::Types;
use Type::Coercion;
use Types::Standard qw(ArrayRef Dict);
use Test::Exception;

my $type = $Igor::Types::PathTiny;

# Basic Coercion
my $val = $type->assert_coerce(".");
ok(ref($val) eq 'Path::Tiny', "Basic coercion");

# Invalid coercion
dies_ok {
	$type->assert_coerce({ a => 1, b => 2});
} "Invalid coercion";

# Nested coercion
my $dict = Dict [ a => $Igor::Types::PathTiny
				, b => ArrayRef[$Igor::Types::PathTiny]
			    ];
my $hash = {
	a => ".",
	b => [".", "."],
};
my $data = $dict->assert_coerce($hash);
ok(ref($data->{a})    eq "Path::Tiny", "First level coerce");
ok(ref($data->{b}[0]) eq "Path::Tiny", "Array coerce: 1");
ok(ref($data->{b}[1]) eq "Path::Tiny", "Array coerce: 2");

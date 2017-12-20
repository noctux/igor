use strict;
use warnings;

BEGIN { unshift @INC, './lib'; }

use Test::More tests => 5;

# Test: Require works
use Igor::Merge;

{ # Test: Empty hashes
	my $merger = Igor::Merge->new();

	my $res = $merger->merge({}, {});
	is_deeply($res, {}, "Empty hashes");
}

{ # Test: Basic overlays
	my $merger = Igor::Merge->new();

	my $res = $merger->merge({a => 1,}, {a => 2});
	is($res->{a}, 2, "Basic overlaystructure");
}

{ # Test: Complex recursive merging
	my $merger = Igor::Merge->new();

	my $h1 = {
		scalar => 1,
		arrayref => [1],
		hashref  => {
			val => 1,
			ex1 => 1, # only in one
		},
		ex1 => 1,
	};

	my $h2 = {
		scalar => 2,
		arrayref => [2],
		hashref  => {
			val => 2,
			ex2 => 2, # only in one
		},
		ex2 => 2,
	};

	my $res = $merger->merge($h1, $h2);

	my $res_ok = {
		scalar => 2,
		arrayref => [2],
		hashref  => {
			val => 2,
			ex1 => 1,
			ex2 => 2,
		},
		ex1 => 1,
		ex2 => 2,
	};

	is_deeply($res, $res_ok, "Complex overlay mechanism");
}

{ # Test: Cloning
	my $merger = Igor::Merge->new(clone => 1);

	my $a = { a => 1};
	my $b = { a => 2};

	my $m = $merger->merge($a, $b);

	is($a->{a}, 1, "Clone");
}

{ # Test: Custom mergers
	my $merger = Igor::Merge->new(
		mergers => {
			arrayref     => \&Igor::Merge::list_concat,
			arrayrefex1  => \&Igor::Merge::list_concat,
			arrayrefex2  => \&Igor::Merge::list_concat,
			scalar       => sub {
				my ($a, $b) = @_; return $a + $b;
			},
			arrayrefuniq => \&Igor::Merge::uniq_list_merge,
			nested       => {
				val => sub {
					my ($a, $b) = @_; return $a + $b;
				},
			},
		},
	);

	my $h1 = {
		scalar       => 1,
		arrayref     => [1, 2],
		arrayrefuniq => [1, 2],
		arrayrefex1  => [1],
		nested       => {
			val => 1,
		},
	};

	my $h2 = {
		scalar       => 2,
		arrayref     => [2, 3],
		arrayrefuniq => [2, 3],
		arrayrefex2  => [2],
		nested       => {
			val => 2,
		},
	};

	my $res = $merger->merge($h1, $h2);

	my $res_ok = {
		scalar       => 3,
		arrayref     => [1, 2, 2, 3],
		arrayrefuniq => [1, 2, 3],
		arrayrefex1  => [1],
		arrayrefex2  => [2],
		nested       => {
			val => 3,
		},
	};

	is_deeply($res, $res_ok, "Custom mergers");
}

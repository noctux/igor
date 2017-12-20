use strict;
use warnings;

BEGIN { unshift @INC, './lib'; }

use Test::More tests => 5;
use File::Temp;
use IO::Handle;
use Test::MockModule;
use Test::Exception;

use Igor::Util;

{ # Test read_toml

	my $fh = File::Temp->new(UNLINK => 1);
	# Based on https://github.com/toml-lang/toml
	print $fh <<'EOF';
# This is a TOML document.

title = "TOML Example"

[owner]
name = "Tom Preston-Werner"
dob = 1979-05-27T07:32:00-08:00 # First class dates

[database]
server = "192.168.1.1"
ports = [ 8001, 8001, 8002 ]
connection_max = 5000
enabled = true
false   = false

[servers]

  # Indentation (tabs and/or spaces) is allowed but not required
  [servers.alpha]
  ip = "10.0.0.1"
  dc = "eqdc10"

  [servers.beta]
  ip = "10.0.0.2"
  dc = "eqdc10"

[clients]
data = [ ["gamma", "delta"], [1, 2] ]

# Line breaks are OK when inside arrays
hosts = [
  "alpha",
  "omega"
]
EOF
	$fh->flush();
	my $res = Igor::Util::read_toml($fh->filename);

	my $expected = {
		title => "TOML Example",
		owner => {
			name => "Tom Preston-Werner",
			dob  => "1979-05-27T07:32:00-08:00",
		},
		database => {
			server         => "192.168.1.1",
			ports          => [8001, 8001, 8002],
			connection_max => 5000,
			enabled        => \1,
			false          => \0,
		},
		servers => {
			alpha => {
				ip => "10.0.0.1",
				dc => "eqdc10",
			},
			beta  => {
				ip => "10.0.0.2",
				dc => "eqdc10",
			},
		},
		clients => {
			data => [["gamma", "delta"], [1, 2]],
			hosts => ["alpha", "omega"],
		},
	};

	is_deeply($res, $expected, "read_toml");
}

sub arrayrefeq {
	my ($a, $b) = @_;
	return 0 unless scalar(@{$a}) == scalar(@{$b});
	for my $i (0..(scalar(@$a) - 1)){
		return 0 unless $a->[$i] eq $b->[$i];
	}
	return 1;
}

{ # Test toposort_dependencies: order
	my $graph = {
		a => {deps => [qw(b c)]},
		b => {deps => ['d']},
		c => {deps => ['d']},
	};
	my @order = Igor::Util::toposort_dependencies($graph, 'a', sub { return $_[0]->{deps}; });


	ok(   arrayrefeq(\@order, [qw(a b c d)])
	   or arrayrefeq(\@order, [qw(a c b d)]), "toposort_dependencies: order");
}

{ # Test toposort_dependencies: cyclic input
	# We expect toposort_dependencies to die on cyclic input
	my $graph = {
		a => {deps => [qw(b c)]},
		b => {deps => ['d', 'a']},
		c => {deps => ['d']},
	};

	;
	dies_ok {
		Igor::Util::toposort_dependencies($graph, 'a', sub { return $_[0]->{deps}; });
	} "toposort_dependencies: die on cyclic input";
}

{ # Test guess_identifier: fallbacks
	my $net_domain   = Test::MockModule->new('Net::Domain');
	$net_domain->redefine('hostfqdn', sub { return 'fqdn'; });

	my $sys_hostname = Test::MockModule->new('Sys::Hostname');
	$sys_hostname->redefine('hostname', sub { return 'sys'; });

	# Fqdn has priority over the pure hostname
	my $identifier = Igor::Util::guess_identifier();

	ok($identifier eq "fqdn", "guess_identifier: fqdn has priority");
}

{
	# Now test the fallback
	my $net_domain   = Test::MockModule->new('Net::Domain');
	$net_domain->redefine('hostfqdn', sub { return undef; });

	my $sys_hostname = Test::MockModule->new('Sys::Hostname');
	$sys_hostname->redefine('hostname', sub { return 'sys'; });

	my $identifier = Igor::Util::guess_identifier();
	ok($identifier eq "sys", "guess_identifier: fallback");
}

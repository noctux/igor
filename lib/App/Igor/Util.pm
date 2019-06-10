package App::Igor::Util;
use Exporter 'import';
@EXPORT_OK = qw(colored);

use strict;
use warnings;
use feature 'state';

use Data::Diver qw(DiveRef);
use Data::Dumper;
use File::Glob ':bsd_glob';
use Graph;
use Graph::Directed;
use Log::ger;
use Net::Domain;
use Path::Tiny;
use Scalar::Util qw(reftype);
use Sys::Hostname;
use Term::ANSIColor ();
use TOML;
use TOML::Parser;

sub read_toml {
	my ($filepath) = @_;

	state $parser = TOML::Parser->new(
		inflate_boolean => sub { $_[0] eq 'true' ? \1 : \0 },
	);
	my ($conf, $err) = $parser->parse_file($filepath);
	unless ($conf) {
		log_error "Parsing of $filepath failed: $err";
		die $err;
	}

	return $conf;
}

sub build_graph {
	my ($hash, $lambda_deps) = @_;

	# Build the graph
	my $g = Graph::Directed->new;

	for my $key (sort keys %$hash) {
		$g->add_vertex($key);
		my $deps = $lambda_deps->($hash->{$key});
		next unless defined($deps);
		for my $child (@$deps) {
			$g->add_edge($key, $child);
		}
	}

	return $g;
}

sub toposort_dependencies {
	my ($hash, $root, $lambda_deps) = @_;

	my $g = build_graph($hash, $lambda_deps);
	$g->add_vertex($root);

	log_trace "Dependency graph: $g\n";

	# Do a topological sort
	my @ts = $g->topological_sort;

	# Now restrict that to the nodes reachable from the root
	my %r = ($root => 1);
	$r{$_}=1 for ($g->all_reachable($root));

	my @order = grep { $r{$_} } @ts;
	return @order;
}

# Tries to determine an identifier for the current computer from the following sources:
#    - fully qualified domain name (via Net::Domain)
#    - hostname (via Sys::Hostname)
# In the following order, this sources are probed, the first successful entry is returned
sub guess_identifier {
	# Try fqdn
	my $fqdn = Net::Domain::hostfqdn;
	return $fqdn if defined $fqdn;

	# Try hostname
	return Sys::Hostname::hostname; # Croaks on error
}

sub colored {
	if (-t STDOUT) { # outputting to terminal
		return Term::ANSIColor::colored(@_);
	} else {
		# Colored has two calling modes:
		#   colored(STRING, ATTR[, ATTR ...])
		#   colored(ATTR-REF, STRING[, STRING...])

		unless (ref($_[0])) { # Called as option one
			return $_;
		} else { # Called as option two
			shift;
			return @_;
		}
	}
}

{ no warnings 'redefine';
	sub glob {
		my ($pattern) = @_;

		return bsd_glob($pattern, GLOB_BRACE | GLOB_MARK | GLOB_NOSORT | GLOB_QUOTE | GLOB_TILDE);
	}
}

# Read a file (as Path::Tiny instances) containing a sub and return the correspoding coderef
sub file_to_coderef {
	my ($path) = @_;
	my $source = $path->slurp;
	log_trace "Executing @{[$path]}:\n$source";
	my $coderef = eval { eval($source) };
	die "Failure while evaluating the coderef at @{[$path]}: $@\n" if not defined $coderef;
	return $coderef;
}

# Traversal for HASH of HASH of HASH ... calls the callback with the value and current list of breadcrumbs
# i.e.: [key1, innerkey2, innermostkey3]
sub traverse_nested_hash {
	my ($hash, $cb) = @_;

	my @worklist = ({
		breadcrumbs => [],
		data => $hash,
	});

	my %result;

	while(@worklist) {
		my $ctx = pop @worklist;
		my @breadcrumbs = @{$ctx->{breadcrumbs}};
		my $d = $ctx->{data};
		if (reftype($d) // '' eq 'HASH') {
			for my $k (keys %$d) {
				my $bc = [@breadcrumbs, $k];
				push @worklist, { breadcrumbs => $bc, data => $d->{$k}};
			}
		} else {
			my $ref = DiveRef(\%result, @breadcrumbs);
			$$ref = $cb->($d, \@breadcrumbs);
		}
	}

	return \%result;
}

1;

__END__

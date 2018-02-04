package Igor::Config;
use strict;
use warnings;

use Class::Tiny qw(file configurations), {
   	defaults     => {},
   	repositories => {},
	packagedb    => undef,
};

use Data::Dumper;
use Data::Diver;
use Graph;
use Igor::Merge;
use Igor::Repository;
use Igor::Util;
use List::Util qw(reduce);
use Log::ger;
use Path::Tiny;
use Try::Tiny;
use Types::Standard qw(Any ArrayRef Dict HashRef Optional Str);
use Storable qw(dclone);

# Config file Schemata for TOML validation
my $packageschema = Str;
# TODO: Integrate filesystem permissions here
my $collectionschema = Dict[
	destination => Str,
	merger      => Optional[Str],
	perm        => Optional[Str],
];
my $repositoryschema = Dict[
	path => Str,
];
my $configurationschema = Dict[
	dependencies => Optional[ArrayRef[Str]],
	packages     => Optional[ArrayRef[$packageschema]],
	repositories => Optional[HashRef[$repositoryschema]],
	facts        => Optional[Any],
	collections  => Optional[HashRef[$collectionschema]],
	pattern      => Optional[Str],
];
my $configschema = Dict[
	defaults       => Optional[$configurationschema],
	configurations => HashRef[$configurationschema],
];

sub BUILD {
	my ($self, $args) = @_;

	# Build Path::Tiny objects
	for my $cfg (values %{$args->{configurations}}, $args->{defaults}) {
		#my $cfg = $args->{configurations}->{$cfgkey};
		$cfg //= {};
		$cfg->{repositories} //= {};
		for my $repokey (keys %{$cfg->{repositories}}) {
			my $repo = $cfg->{repositories}->{$repokey};
			if (exists $repo->{path}) {
				my $path = path($repo->{path});
				if ($path->is_relative) {
					# Resolve relative paths in relation to the config file
					$path = path("@{[$args->{file}->parent]}/$path");
				}
				$repo->{path} = $path;
			}
		}
		$cfg->{collections} //= {};
		for my $collkey (keys %{$cfg->{collections}}) {
			my $coll = $cfg->{collections}->{$collkey};
			$coll->{destination} = path($coll->{destination}) if exists $coll->{destination};
		}
	}
}

sub from_file {
	my ($filepath) = @_;

	# Parse and read the config file
	my $conf = Igor::Util::read_toml($filepath);

	try {
		# Validate the config
		$configschema->($conf);
	} catch {
		die "Validating $filepath failed:\n$_";
	};

	return Igor::Config->new(file => path($filepath), %{$conf});
}

sub expand_dependencies {
	my ($cfgs, $root) = @_;

	# Expand the configuration dependencies by depth first search
	return Igor::Util::toposort_dependencies($cfgs, $root, sub { $_[0]->{dependencies} });
}

sub determine_effective_configuration {
	my ($self, $root) = @_;

	die "No such configuration: $root" unless defined $self->configurations->{$root};

	my @cfgnames = expand_dependencies($self->configurations, $root);
	log_debug "Topological sort of dependencies: @cfgnames";

	# Merge in reverse topological order
	my @cfgs     = map {
		my $cfg = $self->configurations->{$_};
		die "No such configuration: $_" unless defined ($cfg);
		$cfg;
	} reverse @cfgnames;

	my $merger = Igor::Merge->new(
		mergers => {
			packages     => \&Igor::Merge::uniq_list_merge,
			dependencies => \&Igor::Merge::uniq_list_merge,
			# repositories and collections use the default hash merger, same for facts
		},
	);

	# Prepend the defaults to the cfg list
	unshift @cfgs, $self->defaults;

	# Now merge the configurations, with entries of the later ones overlaying old values
	my $effective = reduce { $merger->merge($a, $b) } @cfgs;
	log_trace "Merged configuration: " . Dumper($effective);

	return $effective;
}

sub resolve_package {
	my ($packagename, $repositories, $packagedb) = @_;

	# Packagenames can optionally be qualified "repo/packagename" or
	# unqualified "packagename" Unqualified packagenames have to be unique
	# among all repositories

	# Step one: determine $repo and $pkgname
	my ($reponame, $pkgname);

	my @fragments = split /\//,$packagename,2;
	if (@fragments == 2) {
		# Qualified name, resolve repo -> package
		my ($parent, $packagename) = @fragments;
		$reponame = $parent;
		$pkgname  = $packagename;
	} elsif (@fragments == 1) {
		# Unqualified name: search packagedb
		my $alternatives = $packagedb->{$packagename};

		# Do we have at least one packages?
		die "No repository provides a package '$packagename': "
		  . "Searched repositories: @{[sort keys %$repositories]}"
		  unless defined($alternatives) &&  (@$alternatives);

		# Do we have more than one alternative -> Qualification needed
		die "Ambiguous packagename '$packagename': Instances include @$alternatives"
			unless (@$alternatives == 1);

		# We have exactly one instance for the package
		$reponame = $alternatives->[0];
		$pkgname  = $packagename;
	} else {
		# This should be unreachable
		die "Internal: Invalid packagename $packagename\n";
	}

	# Actually lookup the package
	my $repo = $repositories->{$reponame};
	die "Unable to resolve qualified packagename '$packagename':"
	  . " No such repository: $reponame" unless defined $repo;

	return  $repo->resolve_package($pkgname);
}

# Given a list of packages and a list repositories, first resolve all
# packages in the given repositories and build the dependency-graph
#
# Returns all packages that need to be installed
sub expand_packages {
	my ($self, $repositories, $packages) = @_;

	# This sets $self->repositories and $self->packagedb
	$self->build_package_db($repositories);

	# Resolve all packages to qnames
	my @resolved = map {
			resolve_package( $_
						   , $self->repositories
						   , $self->packagedb)->qname
		} @$packages;

	# Now build the dependency graph
	my $g = Graph::Directed->new;
	for my $reponame (sort keys %{$self->repositories}) {
		my $repo = $self->repositories->{$reponame};
		# Subgraph for the repo
		my $rg = $repo->dependency_graph;
		# Merge it with the global graph, prefixing all vertexes
		$g->add_vertex($_) for map { "$reponame/$_" } @{[$rg->vertices]};
		for my $edge (@{[$rg->edges]}) {
			my ($x,$y) = @{$edge};
			$g->add_edge("$reponame/$x", "$reponame/$y");
		}
	}

	# Now add a virtual 'start' and link it to all requested packages
	$g->add_vertex("start");
	for my $res (@resolved) {
		$g->add_edge('start', $res);
	}

	my @packages = sort $g->all_reachable("start");
	return map {
		resolve_package( $_
		               , $self->repositories
		               , $self->packagedb)
		} @packages;
}


sub build_package_db {
	my ($self, $repositories) = @_;

	log_debug "Building packagedb";

	my %repos     = ();
	my %packagedb = ();

	for my $name (sort keys %$repositories) {
		my $repo = Igor::Repository->new(id => $name, directory => $repositories->{$name}->{path});
		$repos{$name} = $repo;

		for my $pkg (keys %{$repo->packagedb}) {
			push(@{$packagedb{$pkg}}, $name);
		}
	}

	$self->repositories(\%repos);
	$self->packagedb(\%packagedb);

	return \%packagedb;
}

sub build_collection_context {
	my ($self, $collections) = @_;

	my @transactions;
	my $ctx = { collections => {} };

	for my $coll (keys %$collections) {
		$ctx->{collections}->{$coll} = {};
		my $pkg = Igor::Package->new(basedir => $self->file, repository => undef, id => "collection_$coll");
		push @transactions, Igor::Operation::EmitCollection->new(
			collection => $coll,
			merger => sub { my $hash = shift;
				my @keys = sort { $a cmp $b } keys %$hash;
				join('', map {$hash->{$_}} @keys)
			},
			sink => Igor::Sink::File->new( path => $collections->{$coll}->{destination}
				                         , id => $pkg
				                         , perm => $collections->{$coll}->{perm}
									     ),
			package => $pkg,
			order   => 50,
		);
	}

	return ($ctx, \@transactions);
}

1;

__END__

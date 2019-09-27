package App::Igor::Config;
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
use App::Igor::Merge;
use App::Igor::Repository;
use App::Igor::Util;
use List::Util qw(reduce);
use Log::ger;
use Path::Tiny;
use Try::Tiny;
use Types::Standard qw(Any ArrayRef Bool Dict HashRef Map Optional Str);
use Storable qw(dclone);

# Config file Schemata for TOML validation
my $packageschema = Str;
my $collectionschema = Dict[
	destination => Str,
	merger      => Optional[Str],
	perm        => Optional[Str],
];
my $repositoryschema = Dict[
	path => Str,
];
my $factorschema = Dict [
	path => Str,
	type => Optional[Str],
];
my $vaultschema = Dict [
	path      => Str,
	command   => Str,
	cacheable => Optional[Bool],
	type      => Optional[Str],
];
my $mergers = Map[Str, Str];
my $configurationschema = Dict[
	mergers        => Optional[$mergers],
	mergeconfig    => Optional[HashRef],
	dependencies   => Optional[ArrayRef[Str]],
	packages       => Optional[ArrayRef[$packageschema]],
	repositories   => Optional[HashRef[$repositoryschema]],
	facts          => Optional[Any],
	factors        => Optional[ArrayRef[$factorschema]],
	vaults         => Optional[ArrayRef[$vaultschema]],
	collections    => Optional[HashRef[$collectionschema]],
	pattern        => Optional[Str],
	cachedirectory => Optional[Str],
];
my $configschema = Dict[
	defaults       => Optional[$configurationschema],
	configurations => HashRef[$configurationschema],
];

sub BUILD {
	my ($self, $args) = @_;

	# Merge configurations can only be applied configured in the defaults configuration
	for my $key (keys %{$args->{configurations}}) {
		if (exists($args->{configurations}->{$key}->{mergeconfig})) {
			die "Syntax error for configuration $key: mergeconfigs may only be applied in the defaults section";
		}
	}

	$args->{defaults} //= {};
	$args->{defaults}->{cachedirectory} //= "./.cache";

	# Build Path::Tiny objects
	for my $cfg (values %{$args->{configurations}}, $args->{defaults}) {
		$cfg //= {};
		$cfg->{repositories} //= {};
		my $base = $args->{file}->parent;
		my $make_abs = sub {
			my $path = path($_[0]);
			if ($path->is_relative) {
				# Resolve relative paths in relation to the config file
				$path = path("$base/$path");
			}
			$path
		};
		if (exists $cfg->{cachedirectory}) {
			$cfg->{cachedirectory} = $make_abs->($cfg->{cachedirectory});
		}
		for my $factor (@{$cfg->{factors}}) {
			if (exists $factor->{path}) {
				$factor->{path} = $make_abs->($factor->{path});
			}
		}
		for my $vault (@{$cfg->{vaults}}) {
			if (exists $vault->{path}) {
				$vault->{path} = $make_abs->($vault->{path});
			}
		}
		for my $repokey (keys %{$cfg->{repositories}}) {
			my $repo = $cfg->{repositories}->{$repokey};
			if (exists $repo->{path}) {
				$repo->{path} = $make_abs->($repo->{path});
			}
		}
		$cfg->{collections} //= {};
		for my $collkey (keys %{$cfg->{collections}}) {
			my $coll = $cfg->{collections}->{$collkey};
			$coll->{destination} = path($coll->{destination}) if exists $coll->{destination};
		}
		$cfg->{mergers} //= {};
		for my $merger (keys %{$cfg->{mergers}}) {
			$cfg->{mergers}->{$merger} = $make_abs->($cfg->{mergers}->{$merger});
		}
	}
}

sub from_file {
	my ($filepath) = @_;

	# Parse and read the config file
	my $conf = App::Igor::Util::read_toml($filepath);
	log_debug "Parsed configuration at '$filepath':\n" . Dumper($conf);

	try {
		# Validate the config
		$configschema->($conf);
	} catch {
		die "Validating $filepath failed:\n$_";
	};

	return App::Igor::Config->new(file => path($filepath), %{$conf});
}

sub expand_dependencies {
	my ($cfgs, $root) = @_;

	# Expand the configuration dependencies by depth first search
	return App::Igor::Util::toposort_dependencies($cfgs, $root, sub { $_[0]->{dependencies} });
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

	my $configmergers = {
		factors      => \&App::Igor::Merge::list_concat,
		packages     => \&App::Igor::Merge::uniq_list_merge,
		dependencies => \&App::Igor::Merge::uniq_list_merge,
		# repositories and collections use the default hash merger, same for facts
	};
	my $mergers = $self->defaults->{mergers} // {};
	my $cm = App::Igor::Util::traverse_nested_hash($self->defaults->{mergeconfig} // {}, sub {
			my ($name, $bc) = @_;
			unless(exists $mergers->{$name}) {
				die "Configured merger '$name' for path @{$bc} is not defined";
			}
			App::Igor::Util::file_to_coderef($mergers->{$name});
		});
	$configmergers->{$_} = $cm->{$_} for (keys %$cm);

	my $merger = App::Igor::Merge->new(
		mergers => $configmergers,
	);

	# Prepend the defaults to the cfg list
	unshift @cfgs, $self->defaults;

	# Now merge the configurations, with entries of the later ones overlaying old values
	my $effective = reduce { $merger->merge($a, $b) } @cfgs;
	log_trace "Merged configuration: " . Dumper($effective);

	# Store the merger within the effective configuration for later use
	$effective->{merger} = $merger;

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
	my ($self, $repositories, $packages, $config) = @_;

	# This sets $self->repositories and $self->packagedb
	$self->build_package_db($repositories, $config);

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

# Given a list of packages (as App::Igor::Package) get all inactive packages
sub complement_packages {
	my ($self, $packages) = @_;

	my %blacklist;
	$blacklist{$_->id} = 1 for (@$packages);

	my @complement;
	my $packagedb = $self->packagedb;
	my $repos     = $self->repositories;
	for my $name (keys %$packagedb) {
		next if $blacklist{$name};
		for my $repo (@{$packagedb->{$name}}) {
			$repo = $repos->{$repo};

			push @complement, $repo->resolve_package($name);
		}
	}

	return @complement;
}

sub build_package_db {
	my ($self, $repositories, $config) = @_;

	log_debug "Building packagedb";

	my %repos     = ();
	my %packagedb = ();

	for my $name (sort keys %$repositories) {
		my $repo = App::Igor::Repository->new(id => $name, directory => $repositories->{$name}->{path}, config => $config);
		$repos{$name} = $repo;

		for my $pkg (keys %{$repo->packagedb}) {
			push(@{$packagedb{$pkg}}, $name);
		}
	}

	log_trace "Build packagedb:\n" . Dumper(\%packagedb);

	$self->repositories(\%repos);
	$self->packagedb(\%packagedb);

	return \%packagedb;
}

sub build_collection_context {
	my ($self, $configuration) = @_;
	my $collections = $configuration->{collections};

	my @transactions;
	my $ctx = { collections => {} };

	for my $coll (keys %$collections) {
		$ctx->{collections}->{$coll} = {};
		my $pkg = App::Igor::Package->new(basedir => $self->file, repository => undef, id => "collection_$coll");
		my $merger;
		if (defined $collections->{$coll}->{merger}) {
			my $mergerid   = $collections->{$coll}->{merger};
			my $mergerfile = $configuration->{mergers}->{$mergerid};
			die "No such merger defined: $mergerid" unless defined $mergerfile;
			try {
				$merger = App::Igor::Util::file_to_coderef($mergerfile);
			} catch {
				die "Error while processing collection '$coll': cannot create merger from $mergerfile: $_";
			}
		} else {
			$merger = sub { my $hash = shift;
				my @keys = sort { $a cmp $b } keys %$hash;
				join('', map {$hash->{$_}} @keys)
			};
		}
		push @transactions, App::Igor::Operation::EmitCollection->new(
			collection => $coll,
			merger => $merger,
			sink => App::Igor::Sink::File->new( path => $collections->{$coll}->{destination}
				                         , id => $pkg
				                         , perm => $collections->{$coll}->{perm}
									     ),
			package => $pkg,
			order   => 50,
		);
	}

	return ($ctx, \@transactions);
}

sub build_factor_transactions {
	my ($self, $factors) = @_;

	my @transactions;
	for my $factor (@$factors) {
		push @transactions, App::Igor::Operation::RunFactor->new(%$factor, order => 1);
	}

	return \@transactions;
}


sub build_vault_transactions {
	my ($self, $vaults, $merger, $cachedirectory) = @_;

	my @transactions;
	for my $vault (@$vaults) {
		push @transactions, App::Igor::Operation::UnlockVault->new(%$vault, order => 1, merger => $merger, cachedirectory => $cachedirectory);
	}

	return \@transactions;
}

1;

__END__

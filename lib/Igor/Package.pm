package Igor::Package;
use strict;
use warnings;

use Class::Tiny qw(basedir repository id), {
	dependencies => [],
	files        => [],
	precmds      => [],
	postcmds     => [],
	templates    => [],
	artifacts    => [],
};

use Data::Dumper;
use Path::Tiny;
use Try::Tiny;
use Type::Tiny;
use Types::Standard qw(Any ArrayRef Dict HashRef Optional Str);

use Igor::Operation;
use Igor::Util;

# Config file Schemata for TOML validation
my $commandschema  = Str | ArrayRef[Str];
my $fileschema     = Dict[
	source     => Str,
	collection => Str,
] | Dict[
	source     => Str,
	dest       => Str,
	perm       => Optional[Str],
	operation  => Optional[Str]
];
# Dependencies are files with a special preprocessingstep...
my $templatedelimiter = Dict[
	open  => Str,
	close => Str,
];
my $templateschema = Dict[
	source     => Str,
	collection => Str,
	delimiters => Optional[$templatedelimiter],
] | Dict[
	source     => Str,
	dest       => Str,
	delimiters => Optional[$templatedelimiter],
	perm       => Optional[Str],
];
my $dependencyschema = Str;
my $globschema = Str;

my $packageschema = Dict[
	dependencies => Optional[ArrayRef[$dependencyschema]],
	files        => Optional[ArrayRef[$fileschema]],
	templates    => Optional[ArrayRef[$templateschema]],
	precmds      => Optional[ArrayRef[$commandschema]],
	postcmds     => Optional[ArrayRef[$commandschema]],
	artifacts    => Optional[ArrayRef[$globschema]],
];

sub BUILD {
	my ($self, $args) = @_;

	# Build Path::Tiny objects for all filepaths
	for my $ent (@{$args->{templates}}, @{$args->{files}}) {
		for my $key (qw(source dest)) {
			$ent->{$key} = path($ent->{$key}) if exists $ent->{$key};
		}
	}
}

sub from_file {
	my ($filepath, $repository) = @_;

	# Parse and read the config file
	my $conf = Igor::Util::read_toml($filepath);
	my $packagedir = path($filepath)->parent;

	return from_hash($conf, $packagedir, $repository);
}

sub from_hash {
	my ($conf, $basedir, $repository) = @_;
	try {
		# Validate the config
		$packageschema->($conf);
	} catch {
		die "Validating package-configuration at $basedir failed:\n$_";
	};

	return Igor::Package->new(basedir => $basedir
		, repository => $repository
		, id => $basedir->basename
		, %{$conf});
}

sub qname {
	my ($self) = @_;

	my @segments;
	if (defined $self->repository) {
		push @segments, $self->repository->id;
	}
	push @segments, $self->id;

	return join('/', @segments);
}

sub determine_sink {
	 my ($file, $id) = @_;

	if (defined($file->{dest})) {
		return Igor::Sink::File->new(path => $file->{dest}, id => $id, perm => $file->{perm}, operation => $file->{operation});
	} elsif (defined($file->{collection})) {
		return Igor::Sink::Collection->new(collection => $file->{collection}, id => $id);
	} else {
		die "Failed to determine sink for file: " . Dumper($file);
	}
}

sub to_transactions {
	my ($self) = @_;
	my @transactions;

	# Run precommands
	for my $cmd (@{$self->precmds}) {
		push @transactions, Igor::Operation::RunCommand->new(
			package => $self,
			command => $cmd,
			basedir => $self->basedir,
			order   => 10,
		);
	}

	# Symlink and create files
	for my $file (@{$self->files}) {
		my $source = path("@{[$self->basedir]}/$file->{source}");
		# File mode bits: 07777 -> parts to copy
		$file->{perm} //= $source->stat->mode & 07777;
		push @transactions, Igor::Operation::FileTransfer->new(
			package => $self,
			source  => $source,
			sink    => determine_sink($file, $self->qname),
			order   => 20,
		);
	}

	# Run the templates
	for my $tmpl (@{$self->templates}) {
		push @transactions, Igor::Operation::Template->new(
			package    => $self,
			template   => path("@{[$self->basedir]}/$tmpl->{source}"),
			sink       => determine_sink($tmpl, $self->qname),
			delimiters => $tmpl->{delimiters},
			order      => 30,
		);
	}

	# Now run the postcommands
	for my $cmd (@{$self->postcmds}) {
		push @transactions, Igor::Operation::RunCommand->new(
			package => $self,
			command => $cmd,
			basedir => $self->basedir,
			order   => 90,
		);
	}

	@transactions;
}

sub get_files {
	my ($self) = @_;

	my @files     = map { $_->{dest} } @{$self->files}, @{$self->templates};
	return map {
		path($_)->realpath->stringify
	} grep { defined($_) } @files;
}

sub gc {
	my ($self) = @_;

	my @files     = map { $_->{dest} } @{$self->files}, @{$self->templates};
	my @artifacts = map { Igor::Util::glob($_) } @{$self->artifacts};

	return map {
		path($_)->realpath->stringify
	} grep { defined($_) } @files, @artifacts;
}

1;

__END__

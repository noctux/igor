package Igor::Package;
use strict;
use warnings;

use Class::Tiny qw(basedir repository id), {
	dependencies => [],
	files        => [],
	precmds      => [],
	postcmds     => [],
	templates    => [],
};

use Data::Dumper;
use Path::Tiny;
use Try::Tiny;
use Type::Coercion;
use Type::Tiny;
use Type::Utils qw(class_type);
use Types::Standard qw(Any ArrayRef Dict HashRef Optional Str);

use Igor::Operation;
use Igor::Types;
use Igor::Util;

# Config file Schemata for TOML validation
my $commandschema  = Str | ArrayRef[Str];
my $fileschema     = Dict[
	source     => $Igor::Types::PathTiny,
	collection => Str,
] | Dict[
	source     => $Igor::Types::PathTiny,
	dest       => $Igor::Types::PathTiny,
];
# Dependencies are files with a special preprocessingstep...
my $templatedelimiter = Dict[
	open  => Str,
	close => Str,
];
# TODO: Integrate filesystem permissions here
my $templateschema = Dict[
	source     => $Igor::Types::PathTiny,
	dest       => $Igor::Types::PathTiny,
	delimiters => Optional[$templatedelimiter],
] | Dict[
	source     => $Igor::Types::PathTiny,
	collection => Optional[Str],
	delimiters => Optional[$templatedelimiter],
];
my $dependencyschema = Str;

my $packageschema = Dict[
	dependencies => Optional[ArrayRef[$dependencyschema]],
	files        => Optional[ArrayRef[$fileschema]],
	templates    => Optional[ArrayRef[$templateschema]],
	precmds      => Optional[ArrayRef[$commandschema]],
	postcmds     => Optional[ArrayRef[$commandschema]],
];

sub from_file {
	my ($filepath, $repository) = @_;

	# Parse and read the config file
	my $conf = Igor::Util::read_toml($filepath);


	try {
		# Validate the config
		$conf = $packageschema->assert_coerce($conf);
	} catch {
		die "Validating package-configuration $filepath failed:\n$_";
	};

	my $packagedir = path($filepath)->parent;
	return Igor::Package->new(basedir => $packagedir
		, repository => $repository
		, id => $packagedir->basename
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
	 	return Igor::Sink::File->new(path => $file->{dest}, id => $id);
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
			basedir => $self->basedir
		);
	}

	# Symlink and create files
	for my $file (@{$self->files}) {
		push @transactions, Igor::Operation::FileTransfer->new(
			package => $self,
			source => path("@{[$self->basedir]}/$file->{source}"),
			sink => determine_sink($file, $self->qname)
		);
	}

	# Run the templates
	for my $tmpl (@{$self->templates}) {
		push @transactions, Igor::Operation::Template->new(
			package => $self,
			template => path("@{[$self->basedir]}/$tmpl->{source}"),
			sink => determine_sink($tmpl, $self->qname),
			delimiters => $tmpl->{delimiters},
		);
	}

	# Now run the postcommands
	for my $cmd (@{$self->postcmds}) {
		push @transactions, Igor::Operation::RunCommand->new(
			package => $self,
			command => $cmd,
			basedir => $self->basedir
		);
	}

	@transactions;
}

1;

__END__

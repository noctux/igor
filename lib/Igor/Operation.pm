package Igor::Operation;
use strict;
use warnings;

use Class::Tiny qw(package order);
use Data::Dumper;
use Igor::Sink;

sub prepare { die 'Not implemented'; }
sub check   { die 'Not implemented'; }
sub apply   { die 'Not implemented'; }
sub diff    { die 'Not implemented'; }
sub log     { die 'Not implemented'; }

sub select_backend {
	my ($self, $sink) = @_;

	for my $backend (@{$sink->requires}) {
		return $backend if grep {$_ == $backend} @{$self->backends};
	}

	die "No matching backend between @{[ref($self)]} and sink @{[ref($sink)]}";
}

sub prepare_file_for_backend {
	my ($self, $file, $backend) = @_;

	if ($backend == Igor::Pipeline::Type::FILE) {
		# File backend: Simply pass the file
		return $file->absolute;
	} elsif ($backend == Igor::Pipeline::Type::TEXT) {
		# Text backend: Pass by content
		return $file->slurp_utf8;
	}

	die "Internal: Unknown backend: $backend";
}


package Igor::Operation::Template;
use strict;
use warnings;

use Igor::Sink;

use Class::Tiny qw(template sink), {
	content  => undef,
	delimiters => undef,
	backends => [Igor::Pipeline::Type::TEXT]
};
use parent 'Igor::Operation';

use Const::Fast;
use Data::Dumper;
use Log::ger;
use Safe;
use Scalar::Util qw(reftype);
use Text::Template;

=begin
Generate variable declarations for C<Text::Template>'s C<HASH> parameter when used in
conjunction with C<use strict>.

Params:
	datahash - the HASH parameter passed to C<Text::Template>

Returns:
	Multiple C<use> declarations that predeclare the variables that will be autogenerated
	by C<Text::Template>.

	Supported Referencetypes are:
	- plain strings and numbers
	- HASH
	- ARRAY
	- SCALAR
	- REF

Exceptions:
	Dies on unknown reftypes
=cut
sub gen_template_variable_declarations {
	my ($datahash) = @_;

	# For use strict to work, we have predeclare the relevant variables
	# and therefore mangle accordingly.
	my @variables;
	for my $key (sort keys %$datahash) {
		my $value = $datahash->{$key};
		# Mangling is described in
		# https://metacpan.org/pod/Text::Template#PREPEND-feature-and-using-strict-in-templates

		if (not defined $value) {
			# "If the value is undef, then any variables named $key, @key,
			#  %key, etc., are undefined."
			push @variables, ("\$$key", "\%$key", "\@$key");
			next;
		}

		my $type = reftype($value) // '';
		if ($type eq '') {
			# If the value is a string or a number, then $key is set to
			# that value in the template. For anything else, you must pass a
			# reference."
			push @variables, "\$$key";
		} elsif ($type eq 'ARRAY') {
			# If the value is a reference to an array, then @key is set to that
			# array.
			push @variables, "\@$key";
		} elsif ($type eq 'HASH') {
			# If the value is a reference to a hash, then %key is set to that
			# hash.
			push @variables, "\%$key";
		} elsif ($type eq 'SCALAR' || $type eq 'REF') {
			# Similarly if value is any other kind of reference. This means that
			#
			#   var => "foo" and var => \"foo"
			#
			# have almost exactly the same effect. (The difference is that in
			# the former case, the value is copied, and in the latter case it is
			# aliased.)
			push @variables, "\$$key";
		} else {
			log_error "Unexpected reference type '$type' passed to template";
			die "Unexpected reference type '$type' passed to template";
		}
	}
	my $decl = join('', map { "our $_;" } @variables);
	log_trace "gen_template_variable_declaration: $decl";
	return $decl;
}

sub prepare {
	my ($self, $ctx) = @_;

	my $facts    = $ctx->{facts};
	my $packages = $ctx->{packages};
	my $srcfile  = $self->template;

	log_debug "Preparing Template: $srcfile";

	# Hash for passing gathered facts and installed packages into templates
	const my $data => {
		facts    => $facts,
		packages => $packages,
	};

	# Use stricts requires that we predeclare those variables
	my $decls = gen_template_variable_declarations($data);

	# Create a Safe compartment for evaluation, with the opcodes
	# in :default being whitelisted:
	#   https://metacpan.org/pod/Opcode#Predefined-Opcode-Tags
	my $compartment = Safe->new();

	my %templateconfig = (
		TYPE => 'FILE',
		SOURCE => $srcfile,
		PREPEND => q{use warnings; use strict;} . $decls,
		SAFE => $compartment,
		BROKEN => sub { my %data = @_;
			die "Error encountered for $srcfile:$data{lineno}: $data{error}";
		},
	);

	# Optionally enable custom delimiters
	if (defined($self->delimiters)) {
		$templateconfig{DELIMITERS} = [$self->delimiters->{open}, $self->delimiters->{close}];
	}

	# Build the actual template
	my $template = Text::Template->new(
		%templateconfig
	) or die "Couldn't create template from '$srcfile': $Text::Template::ERROR";

	log_trace "Evaluating Template: $srcfile over:\n" . Dumper($data);
	my $content = $template->fill_in(HASH => $data);
	unless (defined $content) {
		die "Error while filling in template '$srcfile': $Text::Template::ERROR";
	}
	$self->content($content);

	log_trace "Result:\n" . Dumper($self->content);

	return $self->content;
}

sub apply {
	my ($self, $ctx) = @_;

	# Write $content to outfile or collection...
	unless (defined $self->content) {
		log_warn "@{[ref($self)]}: prepare not called for template @{[$self->sourcefile]} when applying";
		# Todo: params...
		$self->prepare();
	}

	return $self->sink->emit(Igor::Pipeline::Type::TEXT, $self->content, $ctx);
}

sub log {
	my ($self) = @_;

	log_info "Applying  @{[$self->template]} to '@{[$self->sink->stringify]}'";
}

sub check {
	my ($self, $ctx) = @_;

	unless (defined $self->content) {
		log_warn "@{[ref($self)]}: prepare not called for template @{[$self->sourcefile]} when checking\n";
	}

	return $self->sink->check(Igor::Pipeline::Type::TEXT, $self->content, $ctx);
}

sub diff {
	my ($self, $ctx) = @_;

	unless (defined $self->content) {
		log_warn "@{[ref($self)]}: prepare not called for template @{[$self->sourcefile]} when diffing\n";
	}

	return $self->sink->diff(Igor::Pipeline::Type::TEXT, $self->content, $ctx);
}

package Igor::Operation::FileTransfer;
use strict;
use warnings;

use Igor::Sink;

use Class::Tiny qw(source sink), {
	backends => [Igor::Pipeline::Type::FILE, Igor::Pipeline::Type::TEXT],
	data => undef,
	backend => undef,
};
use parent 'Igor::Operation';

use Log::ger;

sub prepare {
	my ($self) = @_;

	my $backend = $self->select_backend($self->sink);
	$self->backend($backend);
	$self->data($self->prepare_file_for_backend($self->source, $backend));
}

sub check   {
	my ($self, $ctx) = @_;

	return $self->sink->check($self->backend, $self->data, $ctx);
}

sub apply   {
	my ($self, $ctx) = @_;

	my $backend = $self->backend;
	my $data    = $self->data;

	# Symlink the two files...
	return $self->sink->emit($backend, $data, $ctx);
}

sub diff {
	my ($self) = @_;

	my $backend = $self->backend;
	my $data    = $self->data;

	return $self->diff($backend, $data);
}

sub log {
	my ($self) = @_;

	log_info "Linking   '@{[$self->source]}' to '@{[$self->sink->stringify]}'";
}


package Igor::Operation::EmitCollection;
use strict;
use warnings;

use parent 'Igor::Operation';
use Class::Tiny qw(collection merger sink), {
	data => undef,
};

use Log::ger;
use Data::Dumper;

sub prepare {
	my ($self, $ctx) = @_;

	my $collection = $ctx->{collections}->{$self->collection};
	die "Unknown collection '$self->collection'" unless defined $collection;

	my $data = $self->merger->($collection, $self->collection);
	$self->data($data);

	return 1;
}

sub check   {
	my ($self, $ctx) = @_;

	return $self->sink->check(Igor::Pipeline::Type::TEXT, $self->data, $ctx);
}

sub apply   {
	my ($self, $ctx) = @_;

	return $self->sink->emit(Igor::Pipeline::Type::TEXT, $self->data, $ctx);
}

sub diff {
	my ($self) = @_;

	return $self->diff(Igor::Pipeline::Type::TEXT, $self->data);
}

sub log {
	my ($self) = @_;

	log_info "Emitting  collection '@{[$self->sink->stringify]}'";
}

package Igor::Operation::RunCommand;
use strict;
use warnings;

use Igor::Sink;

use Class::Tiny qw(command), {
	basedir  => "",
	backends => [],
};
use parent 'Igor::Operation';

use Cwd;
use Log::ger;
use File::pushd;
use File::Which;

sub prepare { 1; } # No preparation needed

sub check   {
	my ($self) = @_;

	# If we execute a proper command (vs relying on sh),
	# we can actually check whether the binary exists...
	if (ref($self->command) eq 'ARRAY') {
		my $binary = File::Which::which($self->command->[0]);
		log_debug "Resolved @{[$self->command->[0]]} to @{[$binary // 'undef']}";
		return defined($binary);
	}

	log_trace "Cannot check shell expression @{[$self->command]}";
	1;
}

sub apply {
	my ($self) = @_;

	# If possible, we run the commands from the package directory
	my $basedir = $self->basedir;
	unless ($basedir) {
		$basedir = getcwd;
	}
	my $dir = pushd($basedir);

	# Execute
	my $retval;
	if (ref($self->command) eq 'ARRAY') {
		$retval = system(@$self->command);
	} else {
		$retval = system($self->command);
	}

 	$retval == 0 or die "system $self->command failed with exitcode: $?";
	1;
}

sub log {
	my ($self) = @_;

	if (ref($self->command) eq 'ARRAY') {
		log_info "Executing (safe)   system('@{[@{$self->command}]}')"
	} else {
		log_info "Executing (unsafe) system('@{[$self->command]}')"
	}
	1;
}

sub diff {
	my ($self) = @_;

	return 1;
}

1;
__END__

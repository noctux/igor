use strict;

package Igor::Sink {
use strict;
use warnings;

use Class::Tiny;

sub requires { die "Not implemented"; }
sub check    { die "Not implemented"; }
sub emit     { die "Not implemented"; }
sub diff     { die "Not implemented"; }

}


package Igor::Pipeline::Type {
use strict;

use constant {
	TEXT => 0,
	FILE => 1,
};

use constant {
	CHANGED   => 0,
	UNCHANGED => 1,
};
}

package Igor::Sink::File {
use strict;
use warnings;

use parent 'Igor::Sink';
use Class::Tiny qw(path), {
	perm => undef,
	operation => undef,
};

use Const::Fast;
use Data::Dumper;
use Log::ger;
use Igor::Diff ();
use Try::Tiny;
use Fcntl ':mode';

const my @REQUIRES => (Igor::Pipeline::Type::FILE, Igor::Pipeline::Type::TEXT);

sub BUILD {
	my ($self, $args) = @_;
	$args->{operation} //= 'symlink';

	unless (grep { /^\Q$args->{operation}\E$/ } qw(symlink copy)) {
		die "Illegal file operation specified for @{[$args->{path}]}: $args->{operation}";
	}
}

sub requires { return \@REQUIRES; }

sub prepare_for_copy {
	my ($self, $typeref, $dataref) = @_;

	if (defined $self->operation && $self->operation eq "copy") {
		$$typeref = Igor::Pipeline::Type::TEXT;
		# Text backend: Pass by content
		die "@{[$$dataref->stringify]}: Is no regular file\n" .
		    "Only operation 'symlink' with regular file targets (no collections) are supported for directories" unless -f $$dataref;
		$$dataref = $$dataref->slurp_utf8();
	}
}

sub check {
	my ($self, $type, $data) = @_;

	my $changeneeded = 0;

	prepare_for_copy($self, \$type, \$data);

	if ($type == Igor::Pipeline::Type::TEXT) {
		try {
			$changeneeded = $self->path->slurp_utf8() ne $data;
		} catch {
			$changeneeded = 1;
		}
	} elsif ($type == Igor::Pipeline::Type::FILE) {
		try {
			$changeneeded = not (S_ISLNK($self->path->lstat->mode) && ($self->path->realpath eq $data->realpath));
		} catch {
			$changeneeded = 1;
		}
	} else {
		die "Unsupported type \"$type\" at \"@{[ __PACKAGE__ ]}\" when checking file @{[$self->path]}";
	}

	return $changeneeded;
}

sub emit {
	my ($self, $type, $data) = @_;

	return Igor::Pipeline::Type::UNCHANGED unless $self->check($type, $data);

	prepare_for_copy($self, \$type, \$data);

	# Create directory if the target directory does not exist
	unless ($self->path->parent->is_dir) {
		$self->path->parent->mkpath;
	}

	if ($type == Igor::Pipeline::Type::TEXT) {
		log_trace "spew(@{[$self->path]}, " . Dumper($data) . ")";

		# write the data
		$self->path->spew_utf8($data);

		# Fix permissions if requested
		if (defined $self->perm) {
			$self->path->chmod($self->perm);
		}
	} elsif ($type == Igor::Pipeline::Type::FILE) {
		my $dest = $self->path->absolute;

		# Remove the link if it exists
		unlink $dest if -l $dest;

		# symlink
		symlink $data,$dest or die "Failed to symlink: $dest -> $data: $!";
	} else {
		die "Unsupported type \"$type\" at \"" . __PACKAGE__ . "\" when emitting file @{[$self->path]}";
	}

	return Igor::Pipeline::Type::CHANGED;
}

sub diff {
	my ($self, $type, $data, undef, %opts) = @_;

	prepare_for_copy($self, \$type, \$data);

	my $diff;
	if ($type == Igor::Pipeline::Type::TEXT) {
		try {
			$diff = Igor::Diff::diff \$data, $self->path->stringify, \%opts;
		} catch {
			$diff = $_;
		}
	} elsif ($type == Igor::Pipeline::Type::FILE) {
		try {
			$diff = Igor::Diff::diff $data->stringify, $self->path->stringify, \%opts;
		} catch {
			$diff = $_;
		}
	} else {
		die "Unsupported type \"$type\" at \"" . __PACKAGE__ . "\" when checking file $self->path";
	}

	return $diff;
}

sub stringify {
	my ($self) = @_;

	my $name = $self->path->stringify;
	if(defined $self->perm) {
		my $perm = sprintf("%o", $self->perm);
		$name .= " (chmod $perm)";
	}

	return $name;
}
}

package Igor::Sink::Collection {
use strict;
use warnings;

# Collection sinks are a bit of a hack: They simply export to a context, which
# will later be used to fuse the collection. Therefore check, emit and diff
# are subs, only crating a suitable ctx for the actual ops.

use parent 'Igor::Sink';
use Class::Tiny qw(collection id), {
	checked => 0,
};

use Const::Fast;
use Data::Dumper;
use Log::ger;
use Text::Diff ();

const my @REQUIRES => (Igor::Pipeline::Type::TEXT);

sub requires { \@REQUIRES }

sub check {
	my ($self, $type, $data, $ctx) = @_;

	# Only build the context once
	return 1 if $self->checked;

	# Sanity-check: Input type
	die   "Unsupported type \"$type\" at \"@{[__PACKAGE__]}\" "
	    . "when emitting to collection @{[$self->collection]} for @{[$self->id]}" if Igor::Pipeline::Type::TEXT != $type;

	# Ensure that collection exists
	die "Unknown collection '@{[$self->collection]}' for package '@{[$self->id]}'"
		unless exists $ctx->{collections}->{$self->collection};
	my $collection = $ctx->{collections}->{$self->collection};

	# Ensure that a package only writes to the context once
	die "Duplicate entry for @{[$self->id]} in collection @{[$self->collection]}" if (exists $collection->{$self->id});

	# Write to the context
	$collection->{$self->id} = $data;

	# Check has run
	$self->checked(1);

	return 1;
}

sub emit {
	my ($self, $type, $data, $ctx) = @_;

	# Sets $ctx
	$self->check($type, $data, $ctx);

	return Igor::Pipeline::Type::UNCHANGED;
}

sub diff {
	my ($self, $type, $data, $ctx) = @_;

	# Diff happens in a dedicated operation, based on $ctx
	# Sets $ctx
	$self->check($type, $data, $ctx);

	return '';
}

sub stringify {
	my ($self) = @_;

	my $name = "collection(@{[$self->collection]})";
	return $name;
}
}

1;

__END__

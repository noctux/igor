use strict;

package Igor::Sink {
use strict;
use warnings;

use Class::Tiny;

sub requires { die "Not implemented"; }
sub check    { die "Not implemented"; }
sub emit     { die "Not implemented"; }

sub diffstyle {
	return { STYLE => "Unified" };
}
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
};

use Const::Fast;
use Data::Dumper;
use Log::ger;
use Text::Diff ();
use Try::Tiny;
use Fcntl ':mode';

const my @REQUIRES => (Igor::Pipeline::Type::FILE, Igor::Pipeline::Type::TEXT);

sub requires { return \@REQUIRES; }

sub check {
	my ($self, $type, $data) = @_;

	my $changeneeded = 0;

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
		die "Unsupported type \"$type\" at \"" . __PACKAGE__ . "\" when checking file $self->path";
	}

	return $changeneeded;
}

sub emit {
	my ($self, $type, $data) = @_;

	return Igor::Pipeline::Type::UNCHANGED unless check();

	if ($type == Igor::Pipeline::Type::TEXT) {
		log_trace "spew($self->path, " . Dumper($data) . ")";

		# Create directory if the target directory does not exist
		unless ($self->path->parent->is_dir) {
			$self->path->parent->mkpath;
		}

		# write the data
		$self->path->spew_utf8($data);

		# Fix permissions if requested
		if (defined $self->perm) {
			$self->path->chmod($self->perm);
		}
	} elsif ($type == Igor::Pipeline::Type::FILE) {
		my $dest = $self->path->absolute;

		# symlink
		symlink $data,$dest or die "Failed to symlink: $dest -> $data: $!";
	} else {
		die "Unsupported type \"$type\" at \"" . __PACKAGE__ . "\" when emitting file $self->path";
	}

	return Igor::Pipeline::Type::CHANGED;
}

sub diff {
	my ($self, $type, $data) = @_;

	my $diff;
	if ($type == Igor::Pipeline::Type::TEXT) {
		try {
			$diff = Text::Diff::diff \$data, $self->path->stringify, $self->diffstyle;
		} catch {
			$diff = $_;
		}
	} elsif ($type == Igor::Pipeline::Type::FILE) {
		try {
			$diff = Text::Diff::diff $data, $self->path->stringify, $self->diffstyle;
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
	$name .= " (chmod $self->perm)" if defined $self->perm;

	return $name;
}
}

package Igor::Sink::Collection {
use strict;
use warnings;

# Collection sinks are a bit of a hack They simply export to a context, which
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

	return 1 if $self->checked;

	# Sanity-check:
	die "Unsupported type \"$type\" at \"" . __PACKAGE__ . "\" when emitting to collection $self->collection for $self->id" if Igor::Pipeline::Type::TEXT != $type;

	die "Unknown collection '@{[$self->collection]}' for package '@{[$self->id]}'"
		unless exists $ctx->{collections}->{$self->collection};
	my $collection = $ctx->{collections}->{$self->collection};

	die "Duplicate entry for $self->id in collection $self->collection" if (exists $collection->{$self->id});
	$collection->{$self->id} = $data;

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

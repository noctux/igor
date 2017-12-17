package Igor::Repository;
use strict;
use warnings;

use Class::Tiny qw(id directory), {
	packagedb => {}
};

use Igor::Package;
use Igor::Util;
use Path::Tiny;

# Collect the packages contained in this repository
# from the filesystem at C<dir>
sub collect_packages {
	my ($self, $dir) = @_;

	# Sanity check
	die "Configured Repository at $dir is not an directory" unless $dir->is_dir;

	# Visit all subdirectories, and create a package for it if there is a package.toml file
	my $packages = $dir->visit(
		sub {
			my ($path, $state) = @_;

			my $packagedesc = $path->child("package.toml");
			return unless $packagedesc->is_file;

			my $package = Igor::Package::from_file($packagedesc, $self);
			$state->{$path->basename} = $package;
		}
	);

	return $packages;
}

sub dependency_graph {
	my ($self) = @_;

	my $g = Igor::Util::build_graph($self->packagedb, sub {
			$_[0]->dependencies;
		});

	return $g;
}

sub resolve_package {
	my ($self, $package) = @_;

	my $resolved = $self->packagedb->{$package};

	die "No such package '$package' in repository '$self->id'" unless defined $resolved;

	return $resolved;
}

sub BUILD {
	my ($self, $args) = @_;

	# Make sure we've got a Path::Tiny object
	# Dynamic typing IS funny :D
	unless (ref($self->directory) eq 'Path::Tiny') {
		$self->directory(path($self->directory));
	}

	$self->packagedb($self->collect_packages($self->directory));
}

1;

__END__

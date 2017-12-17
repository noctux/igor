package Igor::Merge;
use warnings;
use strict;

use Class::Tiny {
	mergers => {},
	clone   => 1,
};

use Log::ger;
use Data::Diver qw(Dive);
use Storable qw(dclone);

sub select_merger {
	my ($self) = @_;

	my $merger = Dive($self->mergers, @{$self->{breadcrumb}});

	return undef unless ref($merger) eq 'CODE';
	return $merger;
}

# Implementation strongly influenced by Hash::Merge and Hash::Merge::Simple,
# which in turn borrowed from Catalyst::Utils... thanks!
sub _merge {
	my ($self, $left, $right) = @_;

	for my $key (keys %$right) {
		my ($er, $el) = map { exists $_->{$key} } $right, $left;

		# We only have to merge duplicate keys
		if ($er and not $el) {
			# copy keys that don't exist in $right to $left
			$left->{$key} = $right->{$key};
			next;
		} elsif (not $er) {
			# Key only in right
			next;
		}

		push @{$self->{breadcrumb}}, $key;
		my $merger = $self->select_merger;

		if (defined $merger) {
			log_trace "Running a custom merger on @{$self->{breadcrumb}}";
			# A custom merger was defined for this value
			$left->{$key} = $merger->($left->{$key}, $right->{$key}, $self->{breadcrumb});
		} else {
			my ($hr, $hl) = map { ref $_->{$key} eq 'HASH' } $right, $left;
			if ($hr and $hl) {
				log_trace "Running hash-merge on @{$self->{breadcrumb}}";
				# Both are hashes: Recurse
				$left->{$key} = $self->_merge($left->{$key}, $right->{$key});
			} else {
				log_trace "Copying $key at @{$self->{breadcrumb}}";
				# Mixed types or non HASH types: Overlay wins
				$left->{$key} = $right->{$key};
			}
		}
		pop @{$self->{breadcrumb}};
	}

	return $left;
}

sub merge {
	my ($self, $left, $right) = @_;

	# optionally deeply duplicate the hashes before merging
	if ($self->clone) {
		$left  = dclone($left);
		$right = dclone($right);
	}

	return $self->_merge($left, $right);
}

sub list_concat {
	my ($lista, $listb, $breadcrumbs) = @_;

	log_trace "Running list_concat on @{$breadcrumbs}";

	push @$lista, @$listb;

	return $lista;
}

# Merges two lists, while eliminating duplicates in the latter list
sub uniq_list_merge {
	my ($lista, $listb, $breadcrumbs) = @_;

	log_trace "Running uniq_list_merge on @{$breadcrumbs}";

	# We want to do the removal of duplicates in a stable fashion...
	my @uniqs = grep { my $v = $_; grep {$v ne $_} @$lista } @$listb;
	push @$lista, @uniqs;

	return $lista;
}

sub BUILD {
	my ($self, $args) = @_;

	$self->{breadcrumb} //= [];
}

1;

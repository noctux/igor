package Igor::Diff;
use Exporter 'import';
@EXPORT = qw(diff);

use warnings;
use strict;

{ package Igor::Colordiff;
	use warnings;
	use strict;

	use Igor::Util qw(colored);
	use Text::Diff;
	our @ISA = qw(Text::Diff::Unified);

	sub file_header {
		my $self = shift;
		colored(['bold bright_yellow'], $self->SUPER::file_header(@_));
	}

	sub hunk_header {
		my $self = shift;
		colored(['bold bright_magenta'], $self->SUPER::hunk_header(@_));
	}

	sub hunk {
		my $self = shift;
		my (undef, undef, $ops, undef) = @_;
		my @lines = split /\n/, $self->SUPER::hunk(@_), -1;
		my %ops2col = ( "+" => "bold bright_green"
		              , " " => ""
		              , "-" => "bold bright_red");
		use Data::Dumper;
		@lines = map {
			my $color = $ops2col{$ops->[$_]->[2] // " "};
			if ($color) {
				colored([$color], $lines[$_]);
			} else {
				$lines[$_];
			}
		} 0 .. $#lines;
		return join "\n", @lines;
	}
}

sub diff {
	my ($x, $y, $opts) = @_;

	# Set style, allowing overrides
	$opts->{STYLE} //= 'Igor::Colordiff';

	return Text::Diff::diff($x, $y, $opts);
}

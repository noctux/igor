use warnings;
use strict;

sub {
	my $hash = shift;

	my %copy = %$hash;
	my $vim = $copy{'main/vim'};
	delete $copy{'main/vim'};

	my @keys = sort { $a cmp $b } keys %copy;
	join('', $vim, map {$copy{$_}} @keys)

}

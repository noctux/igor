use warnings;
use strict;
use Data::Dumper;

sub {
	# Cheating, actually we simply call the default hash merging strategy... :)
	Igor::Merge::uniq_list_merge(@_)
}

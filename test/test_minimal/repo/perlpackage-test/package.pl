sub {
	my ($conf) = @_;

	use Data::Dumper;
	print "package.pl: Got @{[Dumper($conf)]}";

	return {
		files => [
			{ source => "./package.plgen"
			, dest => "~/test/package.plgen"
			}]
	};
}

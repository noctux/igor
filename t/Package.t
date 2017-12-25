use strict;
use warnings;

BEGIN { unshift @INC, './lib'; }

use Test::More tests => 4;
use File::Temp;
use IO::Handle;
use Path::Tiny;
use Test::MockModule;
use Test::MockObject;
use Test::Exception;

use Igor::Package;

{ # Test from_file

	my $fh = File::Temp->new(UNLINK => 1);
	print $fh <<'EOF';
dependencies = ["vim", "bash"]

precmds = [
	["echo", "Hello World"],
	["echo", "Hallo Welt"],
]

postcmds = [
	"echo 'Good Bye'",
]

[[templates]]
source     = "./template.tmpl"
dest       = "~/.config/template.conf"

[[templates]]
source     = "./template.tmpl"
collection = "env.sh"
delimiters = { open = 'BOF', close = 'EOF'}

[[files]]
source     = "./env.sh"
collection = "env.sh"
EOF
	$fh->flush();

	my $repo = Test::MockObject->new()
	                           ->set_always('id', 'main');

	my $res = Igor::Package::from_file($fh->filename, $repo);

	my $expected = {
		dependencies => ["vim", "bash"],
		precmds => [["echo", "Hello World"], ["echo", "Hallo Welt"]],
		postcmds => ["echo 'Good Bye'"],
		templates => [
			{
				source => path("./template.tmpl"),
				dest => path("~/.config/template.conf"),
			},
			{
				source => path("./template.tmpl"),
				collection => "env.sh",
				delimiters => { open => 'BOF', close => 'EOF'},
			},
			],
		files => [{
				source => path("./env.sh"),
				collection => "env.sh"
			}],
		basedir => path($fh->filename)->parent,
		id => path($fh->filename)->parent->basename,
		repository => $repo,
	};

	is_deeply($res, $expected, "read_toml");
}

{ # Test coercion errors
	my $repo = Test::MockObject->new()
	                           ->set_always('id', 'main');
	dies_ok {
		Igor::Package::from_hash({ invalid => 42 }, path('main/pkg1'), $repo);
	} "Coerce: invlid entry";

	dies_ok {
		Igor::Package::from_hash({ files => {source => './file'} }, path('main/pkg1'), $repo);
	} "Coerce: missing entry";
}

{ # Test qname
	my $repo = Test::MockObject->new()
	                           ->set_always('id', 'main');
	my $pkg1 = Igor::Package::from_hash({}, path('main/pkg1'), $repo);
	ok($pkg1->qname eq 'main/pkg1', "qname");
}


package App::Igor::Types;
use warnings;
use strict;

use Type::Library -base;
use Type::Utils -all;

use Path::Tiny;

BEGIN { extends "Types::Standard" };


our $PathTiny = class_type "PathTiny", { class => "Path::Tiny" };
coerce "PathTiny",
	from "Str", via { Path::Tiny->new($_) };
1;

__END__

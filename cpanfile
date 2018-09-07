requires 'common::sense';               # https://metacpan.org/pod/common::sense
requires 'Class::Tiny';                 # https://metacpan.org/pod/Class::Tiny
requires 'Const::Fast';                 # https://metacpan.org/pod/Const::Fast
requires 'Data::Diver';                 # https://metacpan.org/pod/Data::Diver
requires 'File::pushd';                 # https://metacpan.org/pod/File::pushd
requires 'File::Which';                 # https://metacpan.org/pod/File::Which
requires 'Graph';                       # https://metacpan.org/pod/Graph
requires 'Graph::Directed';             # https://metacpan.org/pod/Graph::Directed
requires 'Getopt::Long::Subcommand';    # https://metacpan.org/pod/Getopt::Long::Subcommand
requires 'Log::ger';                    # https://metacpan.org/pod/Log::ger
requires 'Log::ger::Output::Composite'; # https://metacpan.org/pod/Log::ger
requires 'Log::ger::Output::Screen';    # https://metacpan.org/pod/Log::ger
requires 'Path::Tiny';                  # https://metacpan.org/pod/Path::Tiny
requires 'String::ShellQuote';          # https://metacpan.org/pod/String::ShellQuote
requires 'TOML';                        # https://metacpan.org/pod/TOML
requires 'Text::Diff';                  # https://metacpan.org/pod/Text::Diff
requires 'Text::Template';              # https://metacpan.org/pod/Text::Template
requires 'Try::Tiny';                   # https://metacpan.org/pod/Try::Tiny
requires 'Type::Coercion';              # https://metacpan.org/pod/Type::Coercion
requires 'Types::Standard';             # https://metacpan.org/pod/Types::Standard
requires 'Type::Utils';                 # https://metacpan.org/pod/Type::Utils

# Core dependencies:
requires 'Cwd';
requires 'Data::Dumper';
requires 'List::Util';
requires 'Net::Domain';
requires 'Pod::Usage';
requires 'Safe';
requires 'Scalar::Util';
requires 'Storable';
requires 'Sys::Hostname';
requires 'Term::ANSIColor';

on 'test' => sub {
	requires 'File::Temp';
	requires 'Test::Exception';         # https://metacpan.org/pod/Test::Exception
	requires 'Test::MockModule';        # https://metacpan.org/pod/Test::MockModule
	requires 'Test::MockObject';        # https://metacpan.org/pod/Test::MockObject
	requires 'Test::More';
};

on 'build' => sub {
	requires 'App::FatPacker';          # https://metacpan.org/pod/App::FatPacker
	requires 'Perl::Strip';             # https://metacpan.org/pod/App::FatPacker
}

# requires 'Package::Alias';              # https://metacpan.org/pod/Package::Alias
# requires 'IPC::Run';                    # https://metacpan.org/pod/IPC::Run

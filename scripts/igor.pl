#!/usr/bin/env perl
#
# Igor - dotfile management for perl hackers
# Copyright (C) 2017, 2018  Simon Schuster
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use warnings;
use strict;

use version; our $VERSION = version->declare("v0.1.0");

use App::Igor::CLI;

# Simply dispatch, wuhu
App::Igor::CLI::main(@ARGV);

__END__

=encoding utf8

=head1 NAME

igor - Because nothing makes you feel so as home like a good igor

I<A humble attempt at configuration management - dotfile management for perl hackers>

=head1 SYNOPSIS

igor [general options] <subcommand> [subcommand options]

  General Options:
    --help|-h|-?   Display help
    --config|-c    Configuration file to use
    --verbose|-v   Be Verbose

  Subcommands:
    apply          Apply the specifiec configuration
    diff           Show differences between applied and stored configuration
    gc             Show obsolete files

=head1 OPTIONS

=over 8

=item B<C<--help|-h|-?>>

Print a brief help message and exits. Can be passed multiple times. Passing
twice will show the full documentation.

=item B<C<--config|-c> conffile>

Set the config file to use, instead of F<config.toml> in the current directory

=item B<C<--verbose|-v>>

Be a bit more verbose when conduction business. Can be passed multiple times.
Passing once enables the C<debug> mode most useful to debug issues with the
current configuration. C<trace> is even more verbose and logs various internal
states.

=back

=head1 SUBCOMMANDS

=head2 apply

Apply a configuration to this computer.
The default is to use the configuration specified by this computers hostname.

=over 8

=item B<C<--dry-run>>

Only list what would be done, but do not actually perform the operations.

=item B<C<--task> T>

Apply configuration C<T> instead of the default one

=back

=head2 diff

Show changes between stored and effective configuration

=head3 gc

Show obsolete files

=head1 DOCUMENTATION

=head2 FUNDAMENTALS

Igors approach to dotfile management mirrors the concept of traditional package
management. Therefore, instead of delivering all dotfiles at once, files are
grouped into L<packages|/PACKAGES> which can be enabled for individual hosts
selectively.

L<Configurations|/CONFIGURATION> describe the set of packages that igor should
activate. By providing L<facts|/facts> for the current environment, they further
allow igor to customize the packages and their templates before deployment.

=head2 PACKAGES

Igor manages individual configuration files as packages. Each package comprises
a set of files relating to a specific task or aspect of the system.  Often,
this will coincide with a program (e.g.: the C<zsh> package might contain
F<.zprofile>, F<.zshrc> and F<.zshenv>), while the can also relate to
functionality (e.g.: C<mail> comprising a F<.muttrc>, F<.mbsyncrc> and
F<.msmtprc>).

=head3 Filesystem Layout

In the filesystem, each package is represented as a directory. In the simplest
case, a package consists of the mandatory package description file (either
F<package.toml> or F<package.pl>, see below L<[1]|/"TOML">
L<[2]|/"Perl-style package description">).

In the simplest case, all actual configuration files to install for the package
reside in a flat flat folder alongside the package description file:

	vim
	├── package.toml
	├── env.sh
	├── vimrc
	├── runinstall.sh
	└── neobundle.toml.tmpl

However, you are free to reorganize them into subfolders as you see fit:

	vim
	├── files
	│   ├── env.sh
	│   └── vimrc
	├── hooks
	│   └── runinstall.sh
	├── package.toml
	└── templates
		└── neobundle.toml.tmpl

The package description file then specifies what actions should be performed on
these files.

=head3 TOML

The operations to be performed by a package are described by the
F<package.toml> file, which describes the operations to be performed
in L<TOML syntax|https://github.com/toml-lang/toml>.

Each package consists of four components:

=over

=item Files

A list of files or directories that should be deployed into the filesystem.

The most basic operation a package can perform is symlinking a file (e.g.
F<./symlink> to F<~/test/symlink>):

	[[files]]
	source     = "./symlink"
	dest       = "~/test/symlink"
	operation  = "symlink"

Specifying the operation in this example is not strictly necessary, as
C<"symlink"> actually constitutes the default. Sometimes, however, it is
necessary to actually copy the package file, which can be forced by the
C<"copy"> operation. Optionally, you can also specify the filesystem
permissions of the copied file there:

	[[files]]
	source     = "./copy"
	dest       = "~/test/copy"
	operation  = "copy"
	perm       = "0644"

However, often it is not enough to simply copy complete files. For instance,
the shell's C<.*-profile> usually comprises environment variables from several
packages. To this end, igor provides I<collections>, whose contents are collected
from all files specified in the package configuration:

	[[files]]
	source     = "./env.sh"
	collection = "profile"

Here, C<profile> specifies the name of the collection. All content from all
configured packages for said collection is collected, merged and then deployed
on the host.
The merge and deployment of named collections is configured in the
L<top level configuration file|/CONFIGURATION>.

=item Templates

Sometimes, it is useful to adapt configuration files before deployment and
provide tailored variations.

Example: On work computers, I want to set my work email address as the default
git C<user.email>.

To this end, the user can configure facts for any active configuration inside
the L<top level configuration file|/CONFIGURATION> or derive them automatically
from the environments via L<factors|/Custom factors>.

This information can then be interpolated into template files. The templating
is based on L<Text::Template|https://metacpan.org/pod/Text::Template>, which
uses perl as its templating language. The default escape characters are curly
braces C<{}>:

	# In ./gitconfig.tmpl
	[user]
	name  = Nixus Minimax
	email = { $facts{dev}->{git}->{email} }

To deploy apply templating and deploy this file, specify the destination (see
Files above for the syntax for dest/collection) in the F<package.toml> file:

	[[templates]]
	source      = "./gitconfig.tmpl"
	dest        = "~/.config/git/config"
	perm        = "..."

However, configuration files often already use C<{}> as syntactical elements.
Therefore, it is possible to use custom delimiters:

	# In package.toml
	[[templates]]
	source      = "./files/config"
	dest        = "~/.config/git/config"
	delimiters  = { open = "#BEGIN_TEMPLATE", close = "#END_TEMPLATE"}

	# In ./gitconfig.tmpl
	[user]
		name  = Nixus Minimax
	#BEGIN_TEMPLATE
	<<"EOF"
		email = $facts{dev}->{git}->{email}
	EOF
	#END_TEMPLATE
	...

=item Dependencies

Furthermore, sometimes there is interdependence between configuration files.
For instance, my C<i3> configuration spawns C<rofi> for running programs.
Therefore, whenever the package C<i3> is deployed, C<rofi>'s configuration
should be installed as well. This can be enforced by declaring the dependency
in C<i3>'s F<package.toml> file:

	# in i3/package.toml
	dependencies = [ 'rofi' ]

=item Hooks

Hooks allow to run certain commands before and after package installation.  To
this end, igor provides two lists (C<precmds> and C<postcmds>) which make it
possible to specify commands to be run before and after installation
respectively.

	precmds = [
		"mkdir -p ~/.cache/vim/",
		"echo hallo welt"
	]

	postcmds = [
		["./hooks/runinstall.sh"],
		["echo", "hallo", "welt"]
	]

The arrays can either store the commands as string, which will be executed by
the default users shell. Alternatively, the hooks can be specified as an array
of strings. In that case, the systems shell is bypassed and the command will be
invoked directly using exec, bypassing the system shell.

=back

=head4 Perl-style package description

Please see the L<section TOML|/TOML> for a full description of the individual
fields.

The TOML-style package description is the preferred way of package description.
However, in some cases, a more programmatic way of specifying package-contents
might be desired: For instance by omitting certain files or by automatically
generating a large number of file operations to cope with hundreds of
individual files inside a package.

In this case, the C<package.pl> package description format provides a mechanism
to create the relevant datastructure describing the package via perl code:

	sub {
	  my ($config) = @_; # effective configuration
	  # $config->{facts} comprises the configured facts
	  # $config->{pacakges} lists the packages being installed
	  my $package = ...; # perform calculations
	  return $package;
	}

The return type C<$package> is a perl hash with keys analogous to the
L<TOML|/TOML> components, for example:

	my $package = {
		files => [ { source => "./file", dest => "~/.myfile" }
		         , { source => "./file2", dest => "~/.myfile", operation => 'copy' }
		],
		dependencies => ['otherpackage1', 'otherpackage2'],
		template => [ { source => "...", dest => "..."}
		            , { source => "..."}, collection => "collectionname" }
		            ],
		postcmds => [ 'command arg1 arg2', [ 'cmd2', 'arg21', 'arg22'] ]
	}

=head2 CONFIGURATION

A configurations specifies which packages to install and defines parameters for
the current deployment.
The configuration is expressed in a L<TOML|https://github.com/toml-lang/toml>
configuration file.
By default, igor looks for a file named F<config.toml> in the pwd.
This default can be overwritten by passing an alternative filename to
C<-c|--config>.

The configuration file stores different configurations as TOML tables:

	[defaults]
	...

	[configurations.cfg1]
	...

	[configurations.cfg2]

=head3 Configuration format

Each configuration block describes the various attributes of the desired system
state.

=over 4

=item Repositories and Packages

Most importantly, the configuration defines which repositories to
consult when resolving package names and the list of packages to be installed:

	[configurations.config]
	repositories = {
		repository1 = { path = './repo1' }
		repository2 = { path = './repo2' }
	}
	packages = ['pkg1', 'repository1/pkg2', 'repository2/pkg2', 'repository2/pkg42']

The above snippet configures igor to search for packages in two repositories located
at F<./repo1> and F<./repo2> I<relative to the configuration file> and installs three
packages from those repositories.
Repositories are named (C<repository1> and C<repository2>).
The list of packages to be installed in specified in the C<packages> list.  By
default, igor tries to resolve packagenames in all configured repositories.
However, in case the package name is ambiguous, an error will be reported and
the execution is terminated. In that case, the packagename can be explicitly
namespaced by the repository name (e.g. C<repository1/pkg2> and C<repository2/pkg2>).

=item Facts

Templates as well as perl-style packages allow to tailor packages and package
contents to the host environment. C<facts> allow to describe attributes of the
current configuration. Examples include: the username of the current user, the
git commit email address that should be used, which development plugins for
which programming languages should be configured in the vimrc, ...

In the configuration, facts are represented as a (potentially nested) hash:

	[configurations.config.facts]
	git_email = mail@example.org
	dev = { languages = { viml = true, perl = true, haskell = false }}
	mailaccounts = [
		{ user = 'work@biz.example.org', server = 'mx.example.org' },
		{ user = 'private@example.org', server = 'hugo.example.org' },
	]
	hostname = 'luggage'

In addition to explicitly specified facts, some facts (e.g. C<hostname> above)
can be automatically gathered for all hosts using L<factors|/Custom factors>.
Inside templates, those automatic facts are stored in the hash C<%automatic>.

=item Collections

Often, certain files store configuration that relates to different system
components and as such to different packages (e.g. your shells environment
file, which might export environment variables for your editor (e.g. C<EDITOR>,
your own C<PATH>, ...)).
Collections allow to receive input from multiple packages and merge those into
a single file.

	[configurations.computer.collections]
	'env.sh' = {
		destination = '~/env.sh',  # Storage location of the merged file
		perm = "0644",             # Permissions for the generated file
	}

If no permissions (C<perm>) are specified, the default umask is used.
Inside the packages, collections can be used as a substitute to the C<dest> parameter:

	[[files]]
	source     = "./files/env.sh"
	collection = "env.sh"

By default, all entries are merged by sorting the components by packagename and
concatenating those together. As this simplistic strategy is not sufficient for
complex files (e.g.: we always need the C<env> package first, which declares
important variables like C<HOME>, C<XDG_*>, ... and are used by other
components within the generated collection file F<env.sh>). Therefore,
alternative merge strategies can be specified:

	[configurations.config]
	mergers = { envmerger = './mergers/envmerger.pl' }
	collections = {
		'env.sh' = {
			destination = '~/env.sh'
			merger = 'envmerger' # name in the mergers hash
		}
	}

For the contents of F<./mergers/envmerger.pl> see the section on
L<custom mergers|/Custom collection mergers>

=item Advanced features: C<dependencies>, C<factors>, C<mergers> and C<mergeconfigs>

For the advanced features like C<dependencies>, C<factors>, C<mergers> and
C<mergeconfigs>, see below.

=back

=head3 Cascade

However, igor does not confine itself to merely defining individual
configurations. Instead, at the core of igor is a cascading configuration
system: The basic idea is that each system's configuration actually consists of
several aspects.

For instance, all configurations share a common set of default values and basic
packages (e.g. I use a z-Shell everywhere,...) and on top of that, I have
configurations for developing Haskell, reading Mail, running graphical
environments, etc. These actually (hopefully) form a directed acyclic graph,
as displayed in the image below:

    +---------------------------------------------------------------------------+
    |                       defaults                                            |
    |    repositories = { repo1 = ... }                                         |
    |    facts = {                                                              |
    |              opt1 = false, opt2 = 'def', opt3 = 1, opt4 = { rec = true }, |
    |              opt5 = [ 1, 2, 3 ]                                           |
    |            }                                                              |
    |    packages = [ 'pkg1', 'pkg2' ]                                          |
    |                                                                           |
    +---------------------------------------------------------------------------+
              ^                          ^                            ^
              |                          |                            |
    +-------------------+       +-------------------+       +-------------------+
    |       cfg1        |       |       cfg2        |       |       cfg3        |
    | facts =           |       | facts =           |       | facts =           |
    |   {opt1 = false}  |       |  {opt1 = false,   |       |  {opt4 =          |
    +-------------------+       |   optX = 'hallo'} |       |    {rec = false}  |
              ^                 | packages =        |       |   opt3 = 42}      |
              |                 |  ['pkg2', 'pkg3'] |       +-------------------+
              |                 +-------------------+                 ^
              |                            ^      ^                   |
              |                            |      |                   |
    +-------------------+                  |      +-------------------+
    |       cfg4        |                  |      |       cfg5        |
    | facts =           |                  |      | facts =           |
    |   {opt1 = false}  |                  |      |   {opt1 = true}   |
    +-------------------+                  |      +-------------------+
                                           |               ^
                                           |               |
                                         +-------------------+
                                         |       cfg6        |
                                         | packages =        |
                                         |   [ 'pkg42' ]     |
                                         +-------------------+
                                                  ^
                                                  |
                                         active configuration

Dependencies between configurations are declared by the C<dependencies> member
inside the configuration block in F<config.toml>.

	[configurations.cfg6]
		dependencies = ['cfg2', 'cfg5']

Igor merges the set of (transitively) active configurations from top to bottom:

	defaults -> cfg2 -> cfg3 -> cfg5 -> cfg6

Therefore, the above results in the following effective configuration:

	repositories = { repo1 = ...}
	facts = {
		opt1 = true,
		opt2 = 'def',
		opt3 = 42,
		opt4 = {rec = false },
		opt5 = [1, 2, 3],
		optX = 'hallo'
	}
	packages = ['pkg1', 'pkg2', 'pkg3', 'pkg42']

C<repositories> and C<facts> are merged by the NestedHash merge strategy.
Descend into the nested hash as far as possible. As soon as something is found
that is not a hash, its value is replaced by the value of the overlay. That
way, the key C<facts.opt4.rec> will be toggled from C<true> to C<false> when
C<cfg3> is merged into C<defaults>.

The list C<packages> on the other hand is merged by concatenation of the lists
(and eliminating duplicates).

To configure such context-preserving merge strategies for individual keys
within C<facts>, custom mergers can be defined (see L</Custom fact mergers>).

=head3 Custom fact mergers

Custom fact mergers allow to specify how multiple values inside the C<facts>
section of configurations should be merged inside the cascade described in the
preceding section. The declaration consists of three components.

=over 4

=item 1.

Description of the modified merge strategy as a file (e.g.
F<./mergers/althashmerger.pl>):

	sub {
		my ($l, $r, $breadcrumbs) = @_;
		# $l : left  (= less specific) fact value
		# $r : right (= more specific) fact value
		# $breadcrumbs: arrayref describing the position in the facts hash,
		#               e.g. ['dev', 'languages'] for key 'facts.dev.languages'

		# Here, we simply take the more specific value (default behaviour)
		return $r;
	}

Of course, you can call utility functions from igors codebase where useful:

	sub {
		# Cheating, actually we simply call the default hash merging strategy... :)
		App::Igor::Merge::uniq_list_merge(@_)
	}

=item 2.

The declaration of the merger inside the main configuration file. This is the
path to a file containing the code as a perl subroutine, which we symbolically
bind to the name C<altmerger>:

	[defaults]
	mergers = { altmerger = './mergers/althashmerger.pl' }

B<Note:> As fact-mergers are used to merge configurations, they can only be
specified within the C<[defaults]> section.

=item 3.

A description to what elements this merger should be applied. This configuration
is represented as a nested hash, where the leafs name the merger that should be
used to merge the specified values inside configurations. In the example, it
registers the C<altmerger> declared above for the facts in C<recursive.hell>.

	[defaults]
	mergeconfig = { facts = { recursive = {hell = 'altmerger' } } }

B<Note:> As fact-mergers are used to merge configurations, they can only be
specified within the C<[defaults]> section.

=back

=head3 Custom collection mergers

Custom collection mergers are declared analogous to custom fact mergers by
defining the merge routine as a perl sub inside a file and symbolically naming
it insed the main config file:

	[configurations.config]
	mergers = {
		envmerger = './mergers/envmerger.pl',
	}

Contents of F<./mergers/envmerger.pl>, which ensures that the contents of the
C<main/base> package will be at the head of the merged configuration file:

	sub {
		my $hash = shift;
		# Hash of packagename -> filecontens

		# Perform a copy as we will do destructive updates below
		my %copy = %$hash;

		# Extract the contents of the "base"-packages, as we want to prepend it
		my $base = $copy{'main/base'};
		delete $copy{'main/base'};

		# Order the other artifacts in alphabetic order by package name
		my @keys = sort { $a cmp $b } keys %copy;
		join('', $base, map {$copy{$_}} @keys)
	}

Those custom mergers can then be referenced by setting the C<merger> parameter
for specified collections:

	[configurations.config]
	collections = {
		'env.sh' = {
			destination = '~/env.sh',
			merger = 'envmerger',
		}
	}

=head3 Custom factors

Some facts can be automatically obtained from the execution environment by
executing so called C<factors>, which are declared in the C<defaults.factors>
array in the main configuration file:

	[defaults]
	factors = [
		{path = './factors/executables.sh', type = 'script'},
		{path = './factors/environment.pl', type = 'perl'},
	]

There are two types of factors:

=over 4

=item C<script> factors


	[defaults]
	factors = [
		{path = './factors/executables.sh', type = 'script'},
	}

Execute scripts using C<system> und parse the scripts stdout as
L<TOML|https://github.com/toml-lang/toml>, e.g.:

	# ./factors/executables.sh
	#!/usr/bin/env sh

	# Find all executable binaries in PATH and store them in the "automatic.executables"
	# fact as an array.
	echo "executables = ["

	IFS=':';
	for i in $PATH; do
		test -d "$i" && find "$i" -maxdepth 1 -executable -type f -exec basename {} \;;
	done | sort -u | sed 's/^/\t"/g;s/$/",/g'

	echo "]"

=item C<perl> factors

	[defaults]
	factors = [
		{path = './factors/environment.pl', type = 'perl'},
	]

Execute a perl sub and use the returned perl datastructure as automatically
generated facts, e.g.:

	# ./factors/environment.pl
	sub {
		# store the environment variables as an automatic fact in "automatic.env"
		{env => \%ENV}
	}

=back

=head3 Task selection

If no task/configuration is specified at the command line using the C<--task>
command line argument, igor tries to autodetect the configuration to apply.
The first step is guessing an identifier by determining the fully qualified
domain name (FQDN) and falling back to the plain hostname if the FQDN is
unavailable.

The C<configuration.pattern> options and configuration names are matched
against this guessed identifier. If the selection is unique, this
configuration will be automatically used and applied. If multiple patterns
match, an error will be signaled instead.

=head2 EXAMPLE

Here, a more complete example showing of the different features in TOML syntax.

	[defaults]
		repositories = {
			main = { path = './repo' }
		}
		facts = {
			haskell = true,
		}
		factors = [
			{path = './factors/executables.sh', type = 'script'},
			{path = './factors/environment.pl', type = 'perl'},
		]
		mergers = { altmerger = './mergers/althashmerger.pl' }
		mergeconfig = { facts = { recursive = {hell = 'altmerger' } } }

	[configurations.interactive]
		packages = ['tmux']
		facts = {
			haskell = true,
			perl = true,
			recursive = {
				hell  = ['hades'],
				truth = 42,
			}
		}

	[configurations.computer]
		dependencies = ['interactive']
		packages = ['vim', 'file-test', 'perlpackage-test']
		facts = {
			haskell = false,
			recursive = {hell = ['hades', 'hel']},
		}
		mergers = {
			envmerger = './mergers/envmerger.pl',
		}
		collections = {
			'env.sh' = {
				destination = '~/env.sh',
				merger = 'envmerger',
			},
			'test1.collection' = {
				destination = '~/test/test1.collection',
				perm = "0644",
			},
			'test2.collection' = {
				destination = '~/test/test2.collection',
			}
		}




=head2 INSTALLATION / DISTRIBUTION

Igor is designed to be portable and not require an actual installation on
the host system (even more: it is actually designed with public systems such
as university infrastructure in mind, where the user might not possess
administrator privileges).

Instead, igor is best distributed as a single script file (fatpacked, that is
containing all dependencies) alongside your dotfiles.

To obtain the fatpacked script, either download it from the official release
page or build it yourself:

	# Install all dependencies locally to ./local using carton
	# See DEVELOPMENT SETUP below for details
	carton install
	./maint/fatpack.sh

The fatpacked script can be found in F<./igor.fatpacked.pl> and be executed
standalone.

=head2 HACKING

=head3 DESGIN/CODE STRUCTURE

C<App::Igor::CLI::main> in F<lib/Igor/CLI.pl> constitutes igor's entrypoint and
outlines the overall execution flow.

The main steps are:

=over 4

=item 1.
Command line parsing and setup

=item 2.
Parsing the config

=item 3.
Using the layering system to determine the config to apply

=item 4.
Building the package database and configuring the individual packages

=item 5.
Applying the relevant subcommand (eiter applying a configuration, diff, gc...)

=back

The last step (5.) borrows a lot of its internal structure from the layout of
compilers: Each package is deconstructed into a set of C<transactions>. These
transactions describe the operations to install the package. Available
operations include: Collecting facts (C<RunFactor>), executing commands
(C<RunCommand>), symlinking or copying files (C<FileTransfer>) and installing
templates (C<Template>) and finally merging and emitting collections
(C<EmitCollection>). Each transaction has an attribute (C<Operation::order>)
that defines the execution order of the individual transaction.

=head3 LIBRARIES

Igor uses a couple of external libraries that ease development and foster code
reuse. However, to maintain portability and the ability to fatpack igor for
distribution, B<all libraries used have to be pure perl libraries>.
All libraries used can be found in the F<cpanfile>.

The most ubiquitous libraries that you will notice when working with the code are:

=over 4

=item C<Class::Tiny>

Igor uses an object-oriented design. C<Class::Tiny> is used to ease class
construction in a lightweight fashion.

=item C<Log::ger>

Used internally for logging. Provides C<log_(trace|debug|info|warn|error)>
functions to log on different verbosity levels. C<App::Igor::Util::colored> can be
used to modify the text printed to the terminal (e.g. C<log_info colored(['bold
blue'] "Text")> will print C<Text> to stdout in bold blue).

=item C<Path::Tiny>

All variables describing filepaths are converted to C<Path::Tiny> at first
opportunity. The objects provide a wide variety of auxiliary functions for dealing
with files.

=item C<Types::Standard>

C<Types::Standard> is used to verify conformance of parsed, nested configuration
data structures with the expected format.

=back

=head3 DEVELOPMENT SETUP

=head4 Installing dependencies

Igor provides a F<cartonfile> to declare and manage its library dependencies.
Therefore L<carton|https://metacpan.org/release/carton> can be used to install
the required nonstandard libraries:

	carton install

Carton can then be used to execute C<igor> with those locally installed libs:

	carton exec -- ./scripts/igor.pl --help

=head4 Running tests

Several unittests are provided. They are written with C<Test::More> and reside
in the folder F<./t> and can be executed using C<prove> or, when using carton
by running C<carton exec prove>.

In addition, an example configuration is provided in F<./test/test_minimal> as
an integration test case.
B<WARNING:> Running the following command on your development machine might
overwrite configuration files on the host. Only execute them in a virtual
machine or container.
	./scripts/igor.pl apply -vv --dry-run -c ./test/test_minimal/config.toml --task computer

To ease development, two scripts are provided to create and manage docker
containers for igor development.
F<maint/builddocker.pl> will generate a set of dockerfiles in the folder
F<./docker> for minimal configurations of various operating systems configured
in F<maint/builddocker.pl> and builds the corresponding images.
F<maint/devup.sh> will start the archlinux-image and mount the igor-folder into
the container in read-only mode. There, new changes of igor can be tested.
Instead of using carton, you can use the fatpacked script inside the container,
which emulates the behaviour on typical hosts. (Yet, igor will prefer local
modules from the F<lib/Igor> folder to those fatpacked: that way, changes
can be tested without rerunning F<maint/fatpack.sh>).

	# On host
	# Build/Prepare
	./maint/builddocker.pl # just once
	./maint/fatpack.sh     # just once
	# Start the container
	./maint/devup.sh

	# In the container
	./igor.packed.pl --help

=head1 AUTHOR

Simon Schuster C<perl -e 'print "git . remove stuff like this . rationality.eu" =~ s/ . remove stuff like this . /@/rg'>

=head1 COPYRIGHT

Copyright 2019- Simon Schuster

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut

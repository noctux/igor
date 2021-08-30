# NAME

igor - Because nothing makes you feel so as home like a good igor

_A humble attempt at configuration management - dotfile management for perl hackers_

# SYNOPSIS

igor \[general options\] &lt;subcommand> \[subcommand options\]

    General Options:
      --help|-h|-?   Display help
      --config|-c    Configuration file to use
      --verbose|-v   Be Verbose

    Subcommands:
      apply          Apply the specifiec configuration
      diff           Show differences between applied and stored configuration
      gc             Show obsolete files

# OPTIONS

- **`--help|-h|-?`**

    Print a brief help message and exits. Can be passed multiple times. Passing
    twice will show the full documentation.

- **`--config|-c` conffile**

    Set the config file to use, instead of `config.toml` in the current directory

- **`--verbose|-v`**

    Be a bit more verbose when conduction business. Can be passed multiple times.
    Passing once enables the `debug` mode most useful to debug issues with the
    current configuration. `trace` is even more verbose and logs various internal
    states.

# SUBCOMMANDS

## apply

Apply a configuration to this computer.
The default is to use the configuration specified by this computers hostname.

- **`--dry-run`**

    Only list what would be done, but do not actually perform the operations.

- **`--task` T**

    Apply configuration `T` instead of the default one

## diff

Show changes between stored and effective configuration

### gc

Show obsolete files

# DOCUMENTATION

## FUNDAMENTALS

Igor's approach to dotfile management mirrors the concept of traditional package
management. Therefore, instead of delivering all dotfiles at once, files are
grouped into [packages](#packages) which can be enabled for individual hosts
selectively.

[Configurations](#configuration) describe the set of packages that igor should
activate. By providing [facts](#facts) for the current environment, they further
allow igor to customize the packages and their templates before deployment.

## PACKAGES

Igor manages individual configuration files as packages. Each package comprises
a set of files relating to a specific task or aspect of the system.  Often,
this will coincide with a program (e.g.: the `zsh` package might contain
`.zprofile`, `.zshrc` and `.zshenv`), while they can also relate to
functionality (e.g.: `mail` comprising a `.muttrc`, `.mbsyncrc` and
`.msmtprc`).

### Filesystem Layout

In the filesystem, each package is represented as a directory. In the simplest
case, a package consists of the mandatory package description file (either
`package.toml` or `package.pl`, see below [\[1\]](#toml)
[\[2\]](#perl-style-package-description)).

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

### TOML

The operations to be performed by a package are described by the
`package.toml` file, which describes the operations to be performed
in [TOML syntax](https://github.com/toml-lang/toml).

Each package consists of four components:

- Files

    A list of files or directories that should be deployed into the filesystem.

    The most basic operation a package can perform is symlinking a file (e.g.
    `./symlink` to `~/test/symlink`):

            [[files]]
            source     = "./symlink"
            dest       = "~/test/symlink"
            operation  = "symlink"

    Specifying the operation in this example is not strictly necessary, as
    `"symlink"` actually constitutes the default. Sometimes, however, it is
    necessary to actually copy the package file, which can be forced by the
    `"copy"` operation. Optionally, you can also specify the filesystem
    permissions of the copied file there:

            [[files]]
            source     = "./copy"
            dest       = "~/test/copy"
            operation  = "copy"
            perm       = "0644"

    However, often it is not enough to simply copy complete files. For instance,
    the shell's `.*-profile` usually comprises environment variables from several
    packages. To this end, igor provides _collections_, whose contents are collected
    from all files specified in the package configuration:

            [[files]]
            source     = "./env.sh"
            collection = "profile"

    Here, `profile` specifies the name of the collection. All content from all
    configured packages for said collection is collected, merged and then deployed
    on the host.
    The merge and deployment of named collections is configured in the
    [top level configuration file](#configuration).

- Templates

    Sometimes, it is useful to adapt configuration files before deployment and
    provide tailored variations.

    Example: On work computers, I want to set my work email address as the default
    git `user.email`.

    To this end, the user can configure facts for any active configuration inside
    the [top level configuration file](#configuration) or derive them automatically
    from the environments via [factors](#custom-factors).

    This information can then be interpolated into template files. The templating
    is based on [Text::Template](https://metacpan.org/pod/Text::Template), which
    uses perl as its templating language. The default escape characters are curly
    braces `{}`:

            # In ./gitconfig.tmpl
            [user]
            name  = Nixus Minimax
            email = { $facts{dev}->{git}->{email} }

    To deploy apply templating and deploy this file, specify the destination (see
    Files above for the syntax for dest/collection) in the `package.toml` file:

            [[templates]]
            source      = "./gitconfig.tmpl"
            dest        = "~/.config/git/config"
            perm        = "..."

    However, configuration files often already use `{}` as syntactical elements.
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

- Dependencies

    Furthermore, sometimes there is interdependence between configuration files.
    For instance, my `i3` configuration spawns `rofi` for running programs.
    Therefore, whenever the package `i3` is deployed, `rofi`'s configuration
    should be installed as well. This can be enforced by declaring the dependency
    in `i3`'s `package.toml` file:

            # in i3/package.toml
            dependencies = [ 'rofi' ]

- Hooks

    Hooks allow to run certain commands before and after package installation.  To
    this end, igor provides two lists (`precmds` and `postcmds`) which make it
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

    **Note**: Due to TOMLs parsing, be sure to add those hook arrays at the top of your
    `package.toml`, before any eventual `[[files|templates]]` tables.

#### Perl-style package description

Please see the [section TOML](#toml) for a full description of the individual
fields.

The TOML-style package description is the preferred way of package description.
However, in some cases, a more programmatic way of specifying package-contents
might be desired: For instance by omitting certain files or by automatically
generating a large number of file operations to cope with hundreds of
individual files inside a package.

In this case, the `package.pl` package description format provides a mechanism
to create the relevant datastructure describing the package via perl code:

        sub {
          my ($config) = @_; # effective configuration
          # $config->{facts} comprises the configured facts
          # $config->{pacakges} lists the packages being installed
          my $package = ...; # perform calculations
          return $package;
        }

The return type `$package` is a perl hash with keys analogous to the
[TOML](#toml) components, for example:

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

## CONFIGURATION

A configurations specifies which packages to install and defines parameters for
the current deployment.
The configuration is expressed in a [TOML](https://github.com/toml-lang/toml)
configuration file.
By default, igor looks for a file named `config.toml` in the pwd.
This default can be overwritten by passing an alternative filename to
`-c|--config`.

The configuration file stores different configurations as TOML tables:

        [defaults]
        ...

        [configurations.cfg1]
        ...

        [configurations.cfg2]

### Configuration format

Each configuration block describes the various attributes of the desired system
state.

- Repositories and Packages

    Most importantly, the configuration defines which repositories to
    consult when resolving package names and the list of packages to be installed:

            [configurations.config]
            repositories = {
                    repository1 = { path = './repo1' }
                    repository2 = { path = './repo2' }
            }
            packages = ['pkg1', 'repository1/pkg2', 'repository2/pkg2', 'repository2/pkg42']

    The above snippet configures igor to search for packages in two repositories located
    at `./repo1` and `./repo2` _relative to the configuration file_ and installs three
    packages from those repositories.
    Repositories are named (`repository1` and `repository2`).
    The list of packages to be installed is specified in the `packages` list.  By
    default, igor tries to resolve packagenames in all configured repositories.
    However, in case the package name is ambiguous, an error will be reported and
    the execution is terminated. In that case, the packagename can be explicitly
    namespaced by the repository name (e.g. `repository1/pkg2` and `repository2/pkg2`).

- Facts

    Templates as well as perl-style packages allow to tailor packages and package
    contents to the host environment. `facts` allow to describe attributes of the
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

    In addition to explicitly specified facts, some facts (e.g. `hostname` above)
    can be automatically gathered for all hosts using [factors](#custom-factors).
    Inside templates, those automatic facts are stored in the hash `%automatic`.

- Vaults

    Sometimes, credentials are required within configuration files. While
    it may be unproblematic to have these stored in plaintext on certain
    boxes (e.g. my feedreader password on my private laptop), it is often
    not desireable to have them stored in the clear on all other
    (potentially less trusted) computers igor is run on. While this
    problem can be mitigated by using multiple
    [repositories](#repositories-and-packages), it is overkill for only
    this paticular item. Vaults offer a way to store facts in an
    encrypted fashion and decrypt them automatically when required.

            [[configurations.computer.vaults]]
            path      = './vaults/newsboat.gpg'
            type      = 'shell'
            cacheable = 1
            command   = 'gpg --batch --yes -o "${IGOR_OUTFILE}" -d "${IGOR_VAULT}"'

    Each configuration can store a list of vaults that will automatically
    be unlocked when the configuration is activated on the host.

    A vault consists of a filepath to the vault and a type.  Currently,
    only the `shell` type is implemented. It allows to run a provided
    `command` to decrypt the vault. The commandline used may refer to two
    environment variables for the filepath to the vault file
    (`$IGOR_VAULT`) and the output file (`$IGOR_OUTFILE`).

    The vault itself should decrypt to a TOML-File containing the
    secrets. After decryption, the vault will be merged into the context
    and available to Perl-style packages and Templates as
    `%secrets`.

    However, it is laborous to repeatedly enter the vault password for every
    igor run being performed. So igor can cache unlocked faults for you.
    the unlocked vaults are stored in `defaults.cachedirectory` (defaulting
    to `./.cache`):

            [defaults]
            cachedirectory = './.cache'

    **IMPORTANT:** The cache is currently **not** cleared by igor
    itself. Old unlocked vaultfile-states will be cached indefinitly.
    It is the responsiblity of the user to clean the cache (by deleting
    the files within the cache directory).

    Caching has to be manually activated for the individual vaults by
    setting `cacheable` to `1`. Setting it to `0` (default) will
    disable caching.

- Collections

    Often, certain files store configuration that relates to different system
    components and as such to different packages (e.g. your shells environment
    file, which might export environment variables for your editor (e.g. `EDITOR`,
    your own `PATH`, ...)).
    Collections allow to receive input from multiple packages and merge those into
    a single file.

            [configurations.computer.collections]
            'env.sh' = {
                    destination = '~/env.sh',  # Storage location of the merged file
                    perm = "0644",             # Permissions for the generated file
            }

    If no permissions (`perm`) are specified, the default umask is used.
    Inside the packages, collections can be used as a substitute to the `dest` parameter:

            [[files]]
            source     = "./files/env.sh"
            collection = "env.sh"

    By default, all entries are merged by sorting the components by packagename and
    concatenating those together. As this simplistic strategy is not sufficient for
    complex files (e.g.: we always need the `env` package first, which declares
    important variables like `HOME`, `XDG_*`, ... and are used by other
    components within the generated collection file `env.sh`). Therefore,
    alternative merge strategies can be specified:

            [configurations.config]
            mergers = { envmerger = './mergers/envmerger.pl' }
            collections = {
                    'env.sh' = {
                            destination = '~/env.sh'
                            merger = 'envmerger' # name in the mergers hash
                    }
            }

    For the contents of `./mergers/envmerger.pl` see the section on
    [custom mergers](#custom-collection-mergers)

- Advanced features: `dependencies`, `factors`, `mergers` and `mergeconfigs`

    For the advanced features like `dependencies`, `factors`, `mergers` and
    `mergeconfigs`, see below.

### Cascade

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

Dependencies between configurations are declared by the `dependencies` member
inside the configuration block in `config.toml`.

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

`repositories` and `facts` are merged by the NestedHash merge strategy.
Descend into the nested hash as far as possible. As soon as something is found
that is not a hash, its value is replaced by the value of the overlay. That
way, the key `facts.opt4.rec` will be toggled from `true` to `false` when
`cfg3` is merged into `defaults`.

The list `packages` on the other hand is merged by concatenation of the lists
(and eliminating duplicates).

To configure such context-preserving merge strategies for individual keys
within `facts`, custom mergers can be defined (see ["Custom fact mergers"](#custom-fact-mergers)).

### Custom fact mergers

Custom fact mergers allow to specify how multiple values inside the `facts`
section of configurations should be merged inside the cascade described in the
preceding section. The declaration consists of three components.

1. Description of the modified merge strategy as a file (e.g.
`./mergers/althashmerger.pl`):

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

2. The declaration of the merger inside the main configuration file. This is the
path to a file containing the code as a perl subroutine, which we symbolically
bind to the name `altmerger`:

            [defaults]
            mergers = { altmerger = './mergers/althashmerger.pl' }

    **Note:** As fact-mergers are used to merge configurations, they can only be
    specified within the `[defaults]` section.

3. A description to what elements this merger should be applied. This configuration
is represented as a nested hash, where the leafs name the merger that should be
used to merge the specified values inside configurations. In the example, it
registers the `altmerger` declared above for the facts in `recursive.hell`.

            [defaults]
            mergeconfig = { facts = { recursive = {hell = 'altmerger' } } }

    **Note:** As fact-mergers are used to merge configurations, they can only be
    specified within the `[defaults]` section.

### Custom collection mergers

Custom collection mergers are declared analogous to custom fact mergers by
defining the merge routine as a perl sub inside a file and symbolically naming
it insed the main config file:

        [configurations.config]
        mergers = {
                envmerger = './mergers/envmerger.pl',
        }

Contents of `./mergers/envmerger.pl`, which ensures that the contents of the
`main/base` package will be at the head of the merged configuration file:

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

Those custom mergers can then be referenced by setting the `merger` parameter
for specified collections:

        [configurations.config]
        collections = {
                'env.sh' = {
                        destination = '~/env.sh',
                        merger = 'envmerger',
                }
        }

### Custom factors

Some facts can be automatically obtained from the execution environment by
executing so called `factors`, which are declared in the `defaults.factors`
array in the main configuration file:

        [defaults]
        factors = [
                {path = './factors/executables.sh', type = 'script'},
                {path = './factors/environment.pl', type = 'perl'},
        ]

There are two types of factors:

- `script` factors

            [defaults]
            factors = [
                    {path = './factors/executables.sh', type = 'script'},
            }

    Execute scripts using `system` und parse the scripts stdout as
    [TOML](https://github.com/toml-lang/toml), e.g.:

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

- `perl` factors

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

### Task selection

If no task/configuration is specified at the command line using the `--task`
command line argument, igor tries to autodetect the configuration to apply.
The first step is guessing an identifier by determining the fully qualified
domain name (FQDN) and falling back to the plain hostname if the FQDN is
unavailable.

The `configuration.pattern` options and configuration names are matched
against this guessed identifier. If the selection is unique, this
configuration will be automatically used and applied. If multiple patterns
match, an error will be signaled instead. Patterns are matched as perl-style
regexes.

## EXAMPLE

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

## INSTALLATION / DISTRIBUTION

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

The fatpacked script can be found in `./igor.packed.pl` and be executed
standalone.

## HACKING

### DESIGN/CODE STRUCTURE

`App::Igor::CLI::main` in `lib/Igor/CLI.pl` constitutes igor's entrypoint and
outlines the overall execution flow.

The main steps are:

- 1.  Command line parsing and setup
- 2.  Parsing the config
- 3.  Using the layering system to determine the config to apply
- 4.  Building the package database and configuring the individual packages
- 5.  Applying the relevant subcommand (eiter applying a configuration, diff, gc...)

The last step (5.) borrows a lot of its internal structure from the layout of
compilers: Each package is deconstructed into a set of `transactions`. These
transactions describe the operations to install the package. Available
operations include: Collecting facts (`RunFactor`), executing commands
(`RunCommand`), symlinking or copying files (`FileTransfer`) and installing
templates (`Template`) and finally merging and emitting collections
(`EmitCollection`). Each transaction has an attribute (`Operation::order`)
that defines the execution order of the individual transaction.

### LIBRARIES

Igor uses a couple of external libraries that ease development and foster code
reuse. However, to maintain portability and the ability to fatpack igor for
distribution, **all libraries used have to be pure perl libraries**.
All libraries used can be found in the `cpanfile`.

The most ubiquitous libraries that you will notice when working with the code are:

- `Class::Tiny`

    Igor uses an object-oriented design. `Class::Tiny` is used to ease class
    construction in a lightweight fashion.

- `Log::ger`

    Used internally for logging. Provides `log_(trace|debug|info|warn|error)`
    functions to log on different verbosity levels. `App::Igor::Util::colored` can be
    used to modify the text printed to the terminal (e.g. `log_info colored(['bold
    blue'] "Text")` will print `Text` to stdout in bold blue).

- `Path::Tiny`

    All variables describing filepaths are converted to `Path::Tiny` at first
    opportunity. The objects provide a wide variety of auxiliary functions for dealing
    with files.

- `Types::Standard`

    `Types::Standard` is used to verify conformance of parsed, nested configuration
    data structures with the expected format.

### DEVELOPMENT SETUP

#### Installing dependencies

Igor provides a `cartonfile` to declare and manage its library dependencies.
Therefore [carton](https://metacpan.org/release/carton) can be used to install
the required nonstandard libraries:

        carton install

Carton can then be used to execute `igor` with those locally installed libs:

        carton exec -- perl -Ilib ./scripts/igor.pl --help

#### Running tests

Several unittests are provided. They are written with `Test::More` and reside
in the folder `./t` and can be executed using `prove` or, when using carton
by running `carton exec prove`.

In addition, an example configuration is provided in `./test/test_minimal` as
an integration test case.
**WARNING:** Running the following command on your development machine might
overwrite configuration files on the host. Only execute them in a virtual
machine or container.

        ./scripts/igor.pl apply -vv --dry-run -c ./test/test_minimal/config.toml --task computer

To ease development, two scripts are provided to create and manage docker
containers for igor development.
`maint/builddocker.pl` will generate a set of dockerfiles in the folder
`./docker` for minimal configurations of various operating systems configured
in `maint/builddocker.pl` and builds the corresponding images.
`maint/devup.sh` will start the archlinux-image and mount the igor-folder into
the container in read-only mode. There, new changes of igor can be tested.
Instead of using carton, you can use the fatpacked script inside the container,
which emulates the behaviour on typical hosts. (Yet, igor will prefer local
modules from the `lib/Igor` folder to those fatpacked: that way, changes
can be tested without rerunning `maint/fatpack.sh`).

        # On host
        # Build/Prepare
        ./maint/builddocker.pl # just once
        ./maint/fatpack.sh     # just once
        # Start the container
        ./maint/devup.sh

        # In the container
        ./igor.packed.pl --help

# AUTHOR

Simon Schuster `perl -e 'print "git . remove stuff like this . rationality.eu" =~ s/ . remove stuff like this . /@/rg'`

# COPYRIGHT

Copyright 2019- Simon Schuster

# LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see &lt;http://www.gnu.org/licenses/>.

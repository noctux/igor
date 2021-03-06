package App::Igor::CLI;

use warnings;
use strict;

use Const::Fast;
use Data::Dumper;
use Getopt::Long::Subcommand;
use App::Igor::Config;
use App::Igor::Repository;
use App::Igor::Package;
use App::Igor::Util qw(colored);
use Try::Tiny;
use Pod::Usage;

use sort 'stable';

# Configure Logging
use Log::ger::Output Composite => (
	outputs => {
		Screen => [
			{
				level => ['trace', 'info'],
				conf  => { stderr => 0
				         , use_color => 0},
			},
			{
				level => 'warn',
				conf  => { stderr => 1
				         , use_color => -t STDERR},
			},
		],
	}
);
use Log::ger;
use Log::ger::Util;

# Emit usage
sub usage {
	# -verbosity == 99: Only print sections in -section
	pod2usage( -verbose  => 99
	         , -exitval  => 'NOEXIT'
	         , -sections => 'SYNOPSIS'
	         );
}

sub usage_full {
	# -verbose > 2: Print all sections
	pod2usage( -verbose  => 42
	         , -exitval  => 'NOEXIT'
	         );

}

# Find out which task to run based on the --task variable or the system hostname
sub find_task {
	my ($opts, $cfgs) = @_;

	my $task = $opts->{task};
	return $task if defined $task;

	my $identifier = App::Igor::Util::guess_identifier;
	my @tasks = grep {
		my $re = $cfgs->{$_}->{pattern} // $_;
		$identifier =~ /$re/
	} sort keys %$cfgs;

	die "Automatic task selection using identifier '$identifier' not unique: " . @tasks if @tasks > 1;
	die "Task selection using identifier '$identifier' matched no configurations" unless @tasks;

	return $tasks[0];
}

sub parse_commandline {
	local @ARGV = @_;

	# Setup the defaults
	my %opts = (
		configfile => './config.toml',
		verbositylevel  => 0,
		help => 0,

	);

	my $res = GetOptions(
		summary => 'Frankensteins configuration management',

		# common options recognized by all subcommands
		options => {
			'help|h|?+' => {
				summary => 'Display help message',
				handler => \$opts{help}
			},
			'config|c=s' => {
				summary => 'Specified config',
				handler => \$opts{configfile}
			},
			'verbose|v+' => {
				summary => 'Verbosity level',
				handler => \$opts{verbositylevel}
			},
			'task=s' => {
				summary => 'Task to execute',
				handler => \$opts{task}
			},
		},

		subcommands => {
			apply => {
				summary => 'Apply a given configuration',
				options => {
					'dry-run' => {
						summary => 'Only simulate the operations',
						handler => \$opts{dryrun}
					},
				}
			},
			gc => {
				summary => 'List obsolete files'
			},
			diff => {
				summary => 'Show the difference between applied and configured states'
			},
		},
	);

	# Display help on illegal input
	unless ($res->{success} && ($opts{help} || @{$res->{subcommand}})) {
		print STDERR "Parsing of commandline options failed.\n";
		usage();
		exit(-1);
	}

	# Emit a help message
	if ($opts{help}) {
		# For a specific subcommand
		if (@{$res->{subcommand}}) {
			pod2usage( -verbose  => 99
					 , -sections => "SUBCOMMANDS/@{$res->{subcommand}}"
					 , -exitval  => 0
					 );
		} else {
			# General help
			if ($opts{help} >= 2) {
				usage_full();
			} else {
				usage();
			}
			exit(0);
		}
	}

	# Assert: only one subcommand given
	if (@{$res->{subcommand}} != 1) {
		die "Igor expectes just one subcommand, but received @{[scalar(@{$res->{subcommand}})]}:"
		  . " @{$res->{subcommand}}";
	}

	$opts{subcommand} = $res->{subcommand};

	return \%opts;
}

# Parse and dispatch the commands
sub main {
	my $opts = parse_commandline(@_);

	# Set log level based on verbosity
	# 4 = loglevel "info"
	my $loglevel = 4 + $opts->{verbositylevel};
	# Log::ger is a bit weird, I found no documentation on it, but numeric
	# levels seem to need a scaling factor of 10
	Log::ger::Util::set_level($loglevel * 10);
	# I want log_warn to be red (also undocumented behaviour)
	$Log::ger::Output::Screen::colors{20} = "\e[0;31m";

	# Parse the configfile
	my $config = App::Igor::Config::from_file($opts->{configfile});

	# Determine the task to run
	my $task = find_task($opts, $config->configurations);
	log_info colored(['bold'], "Running task @{[colored(['bold blue'], $task)]}");

	# Layer the dependencies of the task and merge their configurations
	my $effective_configuration = $config->determine_effective_configuration($task);
	log_trace "Effective configuration:\n" . Dumper($effective_configuration);

	# Determine which packages need to be installed
	# FIXME: Run factors before expanding perl-based packages.
	my @packages = $config->expand_packages( $effective_configuration->{repositories}
	                                       , $effective_configuration->{packages}
	                                       , $effective_configuration
	                                       );
	log_debug "Packages to be installed: @{[map {$_->qname} @packages]}";
	log_trace "Packages to be installed:\n" . Dumper(\@packages);

	# Now dispatch the subcommands
	my ($subcommand) = @{$opts->{subcommand}};
	log_info colored(['bold'], "Running subcommand @{[colored(['bold blue'], $subcommand)]}");

	# Get the transactions required for our packages
	my @transactions = map { $_->to_transactions } @packages;

	if      (("apply" eq $subcommand) || ("diff" eq $subcommand)) {
		# We now make three passes through the transactions:
		#   prepare (this will run sideeffect preparations like expanding templates, etc.)
		#   check   (this checks for file-conflicts etc as far as possible)
		# And depending on dry-run mode:
		#   apply   (acutally perform the operations)
		# or
		#   log     (only print what would be done)
		# or
		#   diff    (show differences between repository- and filesystem-state

		# Build the context and create the "EmitCollection" transactions for the collections
		my ($ctx, $colltrans) = $config->build_collection_context($effective_configuration);
		push @transactions, @$colltrans;
		$ctx->{$_} = $effective_configuration->{$_} for qw(facts packages);


		my @files = map {
			$_->get_files()
		} @packages;
		my %uniq;
		for my $f (@files) {
			if ($uniq{$f}++) {
				die "Multiple packages produce file '$f' which is not an collection";
			}
		}


		# Run the factors defined in the configuration
		push @transactions, @{$config->build_factor_transactions($effective_configuration->{factors})};
		push @transactions, @{$config->build_vault_transactions($effective_configuration->{vaults}, $effective_configuration->{merger}, $effective_configuration->{cachedirectory})};

		# Make sure they are ordered correctly:
		@transactions = sort {$a->order cmp $b->order} @transactions;

		# Wrapper for safely executing actions
		my $run = sub {
			my ($code, $transactions) = @_;

			for my $trans (@$transactions) {
				try {
					$code->($trans);
				} catch {
					my $id;
					if (defined($trans->package)) {
						$id = "package @{[$trans->package->qname]}";
					} else {
						$id = "toplevel or automatic transaction";
					}
					log_error("Error occured when processing $id:");
					log_error($_);
					die "Got a terminal failure for $id";
				}
			}
		};

		log_info colored(['bold'], "Running stage \"prepare\":");
		$run->(sub { $_[0]->prepare($ctx) }, \@transactions);
		log_info colored(['bold'], "Running stage \"check\":");
		$run->(sub { $_[0]->check($ctx) }, \@transactions);

		if    ("apply" eq $subcommand) {
			if ($opts->{dryrun}) {
				log_info colored(['bold'], "Running stage \"log\":");
				$run->(sub { $_[0]->log($ctx) }, \@transactions);
			} else {
				log_info colored(['bold'], "Running stage \"apply\":");
				$run->(sub { $_[0]->apply($ctx) }, \@transactions);
			}
		} elsif ("diff"  eq $subcommand) {
			log_info colored(['bold'], "Running stage \"diff\":");
			$run->(sub { print $_[0]->diff($ctx) }, \@transactions);
		} else {
			die "Internal: wrong subcommand $subcommand";
		}
	} elsif ("gc"    eq $subcommand) {
		# Show artifacts that exist in the filesystem which stem from
		# absent packages
		my @blacklist = map {
			$_->gc()
		} $config->complement_packages(\@packages);

		# Remove duplicates
		my %uniq;
		$uniq{$_} = 1 for @blacklist;

		# Remove files created by installed packages
		# (e.g.: two packages provide ~/config/tmux.conf, one of which is installed)
		my @whitelist = map {
			$_->get_files()
		} @packages;
		delete $uniq{$_} for @whitelist;

		# Rewrite urls to use ~ for $HOME if possible
		if (defined($ENV{HOME})) {
			@blacklist = map { $_ =~ s/^\Q$ENV{HOME}\E/~/; $_ } keys %uniq;
		} else {
			@blacklist = keys %uniq;
		}

		print $_ . "\n" for sort @blacklist;
	} else {
		die "Internal: Unknown subcommand $subcommand";
	}
}

1;

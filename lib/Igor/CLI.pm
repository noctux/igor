package Igor::CLI;

use warnings;
use strict;

use Const::Fast;
use Data::Dumper;
use Getopt::Long::Subcommand;
use Igor::Config;
use Igor::Repository;
use Igor::Package;
use Igor::Util qw(colored);
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
	pod2usage( -verbose  => 99
	         , -exitval  => 'NOEXIT'
			 , -sections => 'SYNOPSIS'
	         );
}

# Find out which task to run based on the --task variable or the system hostname
sub find_task {
	my ($opts, $cfgs) = @_;

	my $task = $opts->{task};
	return $task if defined $task;

	my $identifier = Igor::Util::guess_identifier;
	my @tasks = grep {
		my $re = $cfgs->{$_}->{pattern} // $_;
		$identifier =~ /$re/
	} sort keys %$cfgs;

	die "Automatic task selection using identifier '$identifier' not unique: " . @tasks if @tasks > 1;
	die "Task selection using identifier '$identifier' machted no configurations" unless @tasks;

	return $tasks[0];
}

sub parse_commandline {
	local @ARGV = @_;

	# Setup the defaults
	my %opts = (
		configfile => './config.toml',
		verbositylevel  => 0,
		help => '',

	);

	my $res = GetOptions(
		summary => 'Frankensteins configuration management',

		# common options recognized by all subcommands
		options => {
			'help|h|?' => {
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
		},

		subcommands => {
			apply => {
				summary => 'Apply a given configuration',
				options => {
					'dry-run' => {
						summary => 'Only simulate the operations',
						handler => \$opts{dryrun}
					},
					'task=s' => {
						summary => 'Task to execute',
						handler => \$opts{task}
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
			usage();
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
	my $config = Igor::Config::from_file($opts->{configfile});

	# Determine the task to run
	my $task = find_task($opts, $config->configurations);
	log_info colored(['bold'], "Running task @{[colored(['bold blue'], $task)]}");

	# Layer the dependencies of the task and merge their configurations
	my $effective_configuration = $config->determine_effective_configuration($task);
	log_trace "Effective configuration:\n" . Dumper($effective_configuration);

	# Determine which packages need to be installed
	my @packages = $config->expand_packages( $effective_configuration->{repositories}
	                                       , $effective_configuration->{packages});
	log_debug "Packages to be installed: @{[map {$_->qname} @packages]}";
	log_trace "Packages to be installed:\n" . Dumper(\@packages);

	# Now dispatch the subcommands
	my ($subcommand) = @{$opts->{subcommand}};
	log_info colored(['bold'], "Running subcommand @{[colored(['bold blue'], $subcommand)]}");

	if      ("apply" eq $subcommand) {
		# Get the transactions required for our packages
		my @transactions = map { $_->to_transactions } @packages;

		# We now make three passes through the transactions:
		#   prepare (this will run sideeffect preparations like expanding templates, etc.)
		#   check   (this checks for file-conflicts etc as far as possible)
		# And depending on dry-run mode:
		#   apply   (acutally perform the operations)
		# or
		#   log     (only print what would be done)

		# Build the context and create the "EmitCollection" transactions for the collections
		my ($ctx, $colltrans) = $config->build_collection_context($effective_configuration->{collections});
		push @transactions, @$colltrans;
		$ctx->{$_} = $effective_configuration->{$_} for qw(facts packages);

		# Make sure they are ordered correctly:
		@transactions = sort {$a->order cmp $b->order} @transactions;

		# Wrapper for safely executing actions
		my $run = sub {
			my ($code, $transactions) = @_;

			for my $trans (@$transactions) {
				try {
					$code->($trans);
				} catch {
					log_error("Error occured when processing package @{[$trans->package->qname]}:");
					log_error($_);
					die "Got a terminal failure for @{[$trans->package->qname]}";
				}
			}
		};
		log_info colored(['bold'], "Running stage \"prepare\":");
		$run->(sub { $_[0]->prepare($ctx) }, \@transactions);
		log_info colored(['bold'], "Running stage \"check\":");
		$run->(sub { $_[0]->check($ctx) }, \@transactions);
		if ($opts->{dryrun}) {
			log_info colored(['bold'], "Running stage \"log\":");
			$run->(sub { $_[0]->log($ctx) }, \@transactions);
		} else {
			log_info colored(['bold'], "Running stage \"apply\":");
			$run->(sub { $_[0]->apply($ctx) }, \@transactions);
		}

	} elsif ("gc"    eq $subcommand) {

	} elsif ("diff"  eq $subcommand) {

	} else {
		die "Internal: Unknown subcommand $subcommand";
	}
}

1;

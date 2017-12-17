#!/usr/bin/env perl

use warnings;
use strict;

BEGIN { unshift @INC, './lib'; }

use Const::Fast;
use Data::Dumper;
use Getopt::Long::Subcommand;
use Igor::Config;
use Igor::Repository;
use Igor::Package;
use Igor::Util;
use Term::ANSIColor;
use Try::Tiny;
use Pod::Usage;

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
				conf  => {stderr => 1},
			},
		],
	}
);
use Log::ger;
use Log::ger::Util;

sub usage {
	pod2usage( -verbose  => 99
	         , -exitval  => 'NOEXIT'
			 , -sections => 'SYNOPSIS'
	         );
}

sub find_task {
	my ($opts, $cfgs) = @_;

	my $task = $opts->{task};
	return $task if defined $task;

	my $identifier = Igor::Util::guess_identifier;
	my @tasks = grep { $identifier =~ /$_/ } sort keys %$cfgs;

	die "Automatic task selection using identifier '$identifier' not unique: " . @tasks if @tasks > 1;
	die "Task selection using identifier '$identifier' machted no configurations" unless @tasks;

	return $tasks[0];
}

# Parse and dispatch the commands
sub main {
	local @ARGV = @_;

	# Setup the defaults
	my %opts = (
		configfile => './config.toml',
		verbositylevel  => 0,

	);
	my $help = '';

	my $res = GetOptions(
		summary => 'Frankensteins configuration management',

		# common options recognized by all subcommands
		options => {
			'help|h|?' => {
				summary => 'Display help message',
				handler => \$help
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

	unless ($res->{success} && ($help || @{$res->{subcommand}})) {
		print STDERR "Parsing of commandline options failed.\n";
		usage();
		exit(-1);
	}

	# Set log level based on verbosity
	# 4 = loglevel "info"
	my $loglevel = 4 + $opts{verbositylevel};
	# Log::ger is a bit weird, I found no documentation on it, but numeric
	# levels seem to need a scaling factor of 10
	Log::ger::Util::set_level($loglevel * 10);
	# I want log_warn to be red (also undocumented behaviour)
	$Log::ger::Output::Screen::colors{20} = "\e[0;31m";

	# Emit a help message
	if ($help) {
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

	my $config = Igor::Config::from_file($opts{configfile});

	my $task = find_task(\%opts, $config->configurations);
	log_info colored(['bold'], "Running task @{[colored(['bold blue'], $task)]}");

	my $effective_configuration = $config->determine_effective_configuration($task);
	log_trace "Effective configuration:\n" . Dumper($effective_configuration);

	my @packages = $config->expand_packages( $effective_configuration->{repositories}
	                                       , $effective_configuration->{packages});
	log_debug "Packages to be installed: @{[map {$_->qname} @packages]}";
	log_trace "Packages to be installed:\n" . Dumper(\@packages);

	if (@{$res->{subcommand}} != 1) {
		die "Igor expectes just one subcommand, but received @{[scalar(@{$res->{subcommand}})]}:"
		  . " @{$res->{subcommand}}";
	}
	my ($subcommand) = @{$res->{subcommand}};
	log_info colored(['bold'], "Running subcommand $subcommand");

	if      ("apply" eq $subcommand) {
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
		log_debug "Running stage \"prepare\":";
		$run->(sub { $_[0]->prepare($ctx) }, \@transactions);
		log_debug "Running stage \"check\":";
		$run->(sub { $_[0]->check($ctx) }, \@transactions);
		if ($opts{dryrun}) {
			log_debug "Running stage \"log\":";
			$run->(sub { $_[0]->log($ctx) }, \@transactions);
		} else {
			log_debug "Running stage \"apply\":";
			# $run->(sub { $_[0]->apply($ctx) }, \@transactions);
		}

	} elsif ("gc"    eq $subcommand) {

	} elsif ("diff"  eq $subcommand) {

	} else {
		die "Internal: Unknown subcommand $subcommand";
	}

	#my $repository = Igor::Repository->new(id => 'repo', directory => './repo');
	##my $package = Igor::Package::from_file('./repo/tmux/package.toml', 'repository');
	#print Dumper($repository);
	#my @vals = $package->to_transactions;
	#print Dumper(\@vals);
}

main(@ARGV);

__END__

=head1 NAME

igor - Because nothing makes you feel so as home as a good igor

I<A humble attempt at configuration management>

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

Print a brief help message and exits.

=item B<C<--config|-c> conffile>

Set the config file to use, instead of F<config.toml> in the current directory

=item B<C<--verbose|-v>>

Be a bit more verbose when conduction business

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

=cut

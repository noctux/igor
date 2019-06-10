#!/usr/bin/env perl

use warnings;
use strict;

use Cwd;
use File::Basename;
use File::Path qw(make_path);

my $dirname = dirname(__FILE__);

my %distros = (
	debian => {
		base => 'debian:oldstable-slim',
		update => "apt-get update",
		install => "apt-get install -y",
		sudogrp => "sudo",
	},
	ubuntu => {
		base => 'ubuntu:latest',
		update => "apt-get update",
		install => "apt-get install -y",
		sudogrp => "sudo",
	},
	archlinux => {
		base => 'archimg/base',
		update => "pacman -Syy",
		install => "pacman -S --noconfirm",
		sudogrp => "wheel",
	},
);


for my $distro (sort keys %distros) {
	my $cfg = $distros{$distro};

	my $dir = "$dirname/../docker/$distro";

	make_path($dir, {error => \my $err});
	die "make_path failed: @$err" if @$err;

	open(my $file, '>', "$dir/Dockerfile") or die "$dir/Dockerfile: $!";

	print $file <<"EOF";
# Set the base image to Ubuntu Utopic (14.10)
FROM @{[$cfg->{base}]}

MAINTAINER bin/builddocker.pl

# Install Packages required execute standalone igor
RUN @{[$cfg->{update}]} && @{[$cfg->{install}]} perl sudo

RUN useradd user; mkdir /home/user; chown user /home/user
RUN echo 'user:user' | chpasswd; chsh user --shell /bin/bash
RUN usermod -aG @{[$cfg->{sudogrp}]} user
RUN sed -i 's/^#\\s*\\(%wheel\\s\\+ALL=(ALL)\\s\\+NOPASSWD:\\s\\+ALL\\)/\\1/' /etc/sudoers

# SSH login fix. Otherwise user is kicked off after login
# RUN mkdir /var/run/sshd
# RUN sed 's\@session\\s*required\\s*pam_loginuid.so\@session optional pam_loginuid.so\@g' -i /etc/pam.d/sshd

ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile

USER user
ENV HOME /home/user
WORKDIR /home/user

CMD bash

EOF
	close($file) or die "Failed to close $dir/Dockerfile: $!";

	system(qw(docker build --rm --tag), "igor:$distro", $dir) == 0 or die "Failed to build container: $distro: $!";
}

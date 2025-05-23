# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2015 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

package consoles::sshXtermIPMI;

use Mojo::Base 'consoles::localXvnc', -signatures;
use autodie ':all';
require IPC::System::Simple;
use Feature::Compat::Try;
use File::Which;
use Time::HiRes qw(usleep);
use POSIX qw(waitpid WNOHANG);

sub start_sol ($self) {
    my $testapi_console = $self->{testapi_console};

    my @command = $self->backend->ipmi_cmdline;
    push(@command, qw(sol activate));
    my $serial = $self->{args}->{serial};
    my $cstr = join(' ', @command);

    # Try to deactivate IPMI SOL before activate
    # IPMI response like SOL payload already de-activated is expected
    try { $self->backend->ipmitool("sol deactivate") }
    catch ($e) { die "Unexpected IPMI response: $e" unless $e =~ /SOL payload already de-activated/ }
    $self->{xterm_pid} = $self->callxterm($cstr, "ipmitool:$testapi_console");
}

sub activate ($self) {
    # start Xvnc
    $self->SUPER::activate;
    $self->start_sol;
    $self->{reconnects} = 0;
}

sub reset ($self) {
    # Deactivate sol connection if it is activated
    if ($self->{activated}) {
        $self->backend->ipmitool("sol deactivate");
        $self->{activated} = 0;
    }
    return;
}

sub disable ($self) {
    # Try to deactivate IPMI SOL during disable
    $self->reset;
    $self->SUPER::disable;
}

sub do_mc_reset ($self) {
    if ($self->{activated}) {
        $self->backend->do_mc_reset;
        $self->{activated} = 0;
    }
    return;
}

sub current_screen ($self) {
    my $retry = 0;
    my $max_errs = $bmwqemu::vars{IPMI_SOL_MAX_RECONNECTS} // 5;

    while (1) {
        my $ret = $self->SUPER::current_screen;
        return $ret if waitpid($self->{xterm_pid}, WNOHANG) == 0;
        die 'Too many IPMI SOL errors' if ++$self->{reconnects} > $max_errs;
        bmwqemu::fctwarn("IPMI SOL connection died, reconnect $self->{reconnects} / $max_errs");
        usleep(500_000 * $retry++);    # sleep between retries
        $self->start_sol;
    }
}

1;

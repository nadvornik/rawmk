package PLMake::Rule;

use strict;

sub new {
    my $class = shift;
    my $targets = shift;
    my $sources = shift;
    my $self = bless {
        targets => $targets,
        sources => $sources,
        cmd => [@_],
        prio => 0,
    }, $class;
    return $self;
}

sub set_prio {
    my ($self, $prio) = @_;
    $self->{prio} = $prio;
}


sub matches_target {
    my ($self, $target) = @_;
    
    for my $t (@{$self->{targets}}) {

        if ($t =~ /%/) {
            my $re = $t;
            $re =~ s/%/(.*)/g;
            if ($target->{name} =~ /^$re$/) {
                return {
                    stem => $1,
                    target => $t
                }
            }
        }
        else {
            return { target => $t } if $target->{name} eq $t;
        }
    }
}

sub sources_for_target {
    my ($self, $target) = @_;

    die "target does not match" unless my $match = $self->matches_target($target);

    my @ret;
    for my $t (@{$self->{sources}}) {
        my $rt = $t;
        $rt =~ s/%/$match->{stem}/;
        push @ret, $rt;
    }
    return @ret;
}

sub siblings_for_target {
    my ($self, $target) = @_;

    die "target does not match" unless my $match = $self->matches_target($target);
    my @ret;
    for my $t (@{$self->{targets}}) {
        next if $t eq $match->{target};
        my $rt = $t;
        $rt =~ s/%/$match->{stem}/;
        push @ret, $rt;
    }
    return @ret;
}

sub print_cmd {
    my ($self, $target, $proc) = @_;
    
    die "target does not match" unless my $match = $self->matches_target($target);

    for my $cmd (@{$self->{cmd}}) {
        if(ref($cmd) eq 'ARRAY'){
            for my $arg (@$cmd) {
               my $proc_arg = $arg;
               $proc_arg =~ s/\$\*/$match->{stem}/g if $proc;
               print "$proc_arg ";
            }
            print "\n";
        }
        elsif(ref($cmd) eq 'CODE') {
            print "$cmd\n";
        }
        else {
            my $proc_cmd = $cmd;
            $proc_cmd =~ s/\$\*/$match->{stem}/g if $proc;
            print "$proc_cmd\n";
        }
    }
    print "\n";
}

sub execute_cmd {
    my ($self, $target, $dry_run) = @_;
    
    die "target does not match" unless my $match = $self->matches_target($target);

    for my $cmd (@{$self->{cmd}}) {
        if(ref($cmd) eq 'ARRAY'){
            my @a;
            for my $arg (@$cmd) {
               my $proc_arg = $arg;
               $proc_arg =~ s/\$\*/$match->{stem}/g;
               push @a, $proc_arg;
            }
            print join(' ', @a), "\n";
            my $ret = 0;
            $ret = system(@a) unless $dry_run;
            return $ret if $ret;
        }
        elsif(ref($cmd) eq 'CODE') {
            $cmd->();
        }
        else {
            my $proc_cmd = $cmd;
            $proc_cmd =~ s/\$\*/$match->{stem}/g;
            print "$self $proc_cmd\n";
            my $ret = 0;
            $ret = system($proc_cmd) unless $dry_run;
            return $ret if $ret;
        }
    }
    return 0;
}

1;


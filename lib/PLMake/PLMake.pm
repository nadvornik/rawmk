package PLMake::PLMake;

use strict;
use PLMake::Rule;
use PLMake::Target;
use Data::Dumper;
use Parallel::ForkManager;

sub new {
    my $class = shift;
    my ( $dir ) = @_;
    my $self = bless {
        rules => [],
        targets => {},
        dir => $dir,
    }, $class;
    return $self;
}

sub add_rule {
    my $self = shift;
    my $rule = PLMake::Rule->new(@_);
    die "can't create rule" unless $rule;
    push @{$self->{rules}}, $rule;
    return $rule;
}

sub add_target {
    my $self = shift;
    my ($name, $flags) = @_;
    my $target = $self->{targets}->{$name};
    if ($target) {
        $target->set_flags(%$flags);
    }
    else {
        $target = PLMake::Target->new($name, $flags);
        die "can't create target" unless $target;
        $self->{targets}->{$target->{name}} = $target;
    }
    return $target;
}

sub phony {
    my $self = shift;
    
    for my $name (@_) {
        $self->add_target($name, {phony => 1}); 
    }
}

sub apply_rules {
    my $self = shift;
    
    chdir($self->{dir});
print Dumper($self);
    my $done;
    # apply all rules, get all possible targets
    do {
        $done = 1;
        for my $t (values %{$self->{targets}}) {
            for my $r (@{$self->{rules}}) {
                next if $t->has_rule($r);
                if ($r->matches_target($t)) {
                    $done = 0;
                    my @sources = $r->sources_for_target($t);
                    for my $s (@sources) {
                        $self->add_target($s, {});
                    }
                    my @siblings = $r->siblings_for_target($t);
                    for my $s (@siblings) {
                        $self->add_target($s, {});
                    }
                    $t->add_rule($r);
                }
            }
        }
    } while (!$done);

    # remove rules without sources
    do {
        $done = 1;
        for my $t (values %{$self->{targets}}) {
            for my $r ($t->get_rules) {
                my @sources = $r->sources_for_target($t);
                for my $s (@sources) {
                    my $s_ref = $self->{targets}->{$s};
                    if ($s_ref->{flags}->{missing} && !$s_ref->{flags}->{phony} && !$s_ref->{flags}->{requested} && $s_ref->get_rules == 0) {
                        print "irrelevant $s -> $t->{name}\n";
                        $t->remove_rule($r);
                        $done = 0;
                        last;
                    }
                }
            }
        }
    } while (!$done);

    for my $t (values %{$self->{targets}}) {
        if ($t->{flags}->{missing} && $t->get_rules == 0) {
            print "irrelevant target $t->{name}\n";
            delete $self->{targets}->{$t->{name}}
        }
    }


    for my $t (values %{$self->{targets}}) {
        my @rules = $t->get_rules;
        if (@rules > 1) {
            my @s_rules = sort {$b->{prio} <=> $a->{prio}} @rules;
            die "conflicting rules for $t->{name}" if @s_rules[0]->{prio} == @s_rules[1]->{prio};
            for my $r (@s_rules[1 .. $#s_rules]) {
                print "removing lower prio rule for $t->{name}\n";
                print Dumper($r);
                $t->remove_rule($r);
            }
            print "keeping rule for $t->{name}\n";
            print Dumper($s_rules[0]);
        }
    }
    
    for my $t (values %{$self->{targets}}) {
        my @rules = $t->get_rules;
        die "conflicting rules for $t->{name}" if @rules > 1;
        if (@rules == 1) {
            my %s_refs;
            my @sources = $rules[0]->sources_for_target($t);
            for my $s (@sources) {
                print "source $s -> $t->{name}\n";
                my $sr = $self->{targets}->{$s};
                die "no source for $s -> $t->{name}" unless $sr;
                $s_refs{$sr} = $sr;
            }
            $t->{sources} = [values %s_refs];

            my @sb_refs;
            my @siblings = $rules[0]->siblings_for_target($t);
            for my $s (@siblings) {
#                print "sibling $s\n";
                die "multiple rules for siblings" if $rules[0] != $self->{targets}->{$s}->rule;
                push @sb_refs, $self->{targets}->{$s};
            }
            $t->{siblings} = \@sb_refs;
        }
    }
}

sub check_remake {
    my $self = shift;
    $self->{to_remake} = {};
#    my $n_to_remake;
#    do {
#        $n_to_remake = keys %{$self->{to_remake}};
#        for my $t (values %{$self->{targets}}) {
#            if ($t->{flags}->{requested}) {
#                $t->must_remake($self->{to_remake});
#            }
#        }
#    } while ($n_to_remake < keys %{$self->{to_remake}});
print "check remake back\n";
    for my $t (values %{$self->{targets}}) {
        $t->mark_req_sources() if ($t->{flags}->{requested});
    }

    for my $t (values %{$self->{targets}}) {
        if (!$t->{flags}->{req_source} && !$t->{flags}->{requested}) {
            print "not requested target $t->{name}\n";
            delete $self->{targets}->{$t->{name}}
        }
    }

    for my $t (values %{$self->{targets}}) {
        for my $s (@{$t->{sources}}) {
            $s->{targets} //= {};
            $s->{targets}->{$t} = $t;
        }
    }

    for my $t (values %{$self->{targets}}) {
        $t->add_missing_timestamp() if ($t->{flags}->{requested});
    }

print "check remake forward\n";
    my $n;
    do {
        for my $t (values %{$self->{targets}}) {
            $t->check_remake() if (@{$t->{sources}} == 0);
        }
        
        $n = values %{$self->{to_remake}};
        
        for my $t (values %{$self->{targets}}) {
            $t->remake_missing if $t->{flags}->{remake};
        }
        

        for my $t (values %{$self->{targets}}) {
            $self->{to_remake}->{$t} = $t if $t->{flags}->{remake};
        
            die "brogen dep graph" unless $t->{num_src_checked} == @{$t->{sources}};
            print "$t->{name} $t->{flags}->{remake} checked  $t->{num_src_checked} \n";
            
            delete $t->{num_src_checked};
        }
    } while ($n != values %{$self->{to_remake}});
}

sub next_to_remake {
    my $self = shift;

    for my $t (sort {$a->{name} cmp $b->{name}} values %{$self->{to_remake}}) {
        next if $t->{in_progress};
        my $src_ready = 1;
        for my $s (@{$t->{sources}}) {
            if ($self->{to_remake}->{$s}) {
                $src_ready = 0;
                last;
            }
        }
        if ($src_ready) {
            $t->{in_progress} = 1;
            for my $s (@{$t->{siblings}}) {
                $s->{in_progress} = 1;
            }
            return $t;
        }
    }
}

sub remake_done {
    my ($self, $t) = @_;
    
    for my $s (@{$t->{siblings}}) {
        delete $self->{to_remake}->{$s};
    }
    delete $self->{to_remake}->{$t};
}

sub remake_j1 {
    my $self = shift;
    
    while (my $t = $self->next_to_remake) {
        print "# $t->{name}\n#   ";
        my @sources = $t->rule->sources_for_target($t);
        for my $s (@sources) {
            print "$s ";
        }
        print "\n";
        if ($t->rule->execute_cmd($t, 0) != 0) {
            print "Command failed\n";
            exit(1);
        }
        $self->remake_done($t);
    }
}

sub remake_parallel {
    my $self = shift;
    
    my $max_jobs = 4;
    my $num_slots = $max_jobs;
    my $pm = Parallel::ForkManager->new($max_jobs);
    my $error = 0;
    
    $pm->run_on_start(sub {
        $num_slots--;
        print "on start num_slots $num_slots\n";
    });

    $pm->run_on_finish( sub {
        my ($pid, $code, $t) = @_;
        $num_slots++;
        $error = 1 if $code != 0;

        print "on finish num_slots $num_slots error $error   par $pid, $code, $t->{name}\n";
        $self->remake_done($t);
    });
    
    while ((my $n = values %{$self->{to_remake}}) > 0 && !$error) {
        my $t;
        print "check next ($n)\n";
        if (! ($t = $self->next_to_remake)) {
            print "waiting\n";
            die "no next target" if $num_slots >= $max_jobs;
            $pm->wait_for_available_procs($num_slots + 1);
            next;
        }
        print "start $t->{name}\n";
        
        $pm->start($t) and next;

        print "# $t->{name}\n#   ";
        my @sources = $t->rule->sources_for_target($t);
        for my $s (@sources) {
            print "$s ";
        }
        print "\n";
        
        my $ret = $t->rule->execute_cmd($t, 0);
        print "Command failed\n" if $ret != 0;
        
        $pm->finish($ret)
    }
    
    $pm->wait_all_children;
}

sub remake {
    my $self = shift;

    if ($self->{jobs} && $self->{jobs} > 1) {
        return $self->remake_parallel;
    }
    else {
        return $self->remake_j1;
    }
}

sub jobs {
    my ($self, $jobs) = @_;
    $self->{jobs} = $jobs;
}

1;


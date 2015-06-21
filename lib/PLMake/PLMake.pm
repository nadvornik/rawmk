package PLMake::PLMake;

use strict;
use PLMake::Rule;
use PLMake::Target;
use Data::Dumper;

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

    print Dumper($self);

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
            my @s_refs;
            my @sources = $rules[0]->sources_for_target($t);
            for my $s (@sources) {
                print "source $s -> $t->{name}\n";
                my $sr = $self->{targets}->{$s};
                die "no source for $s -> $t->{name}" unless $sr;
                push @s_refs, $sr;
            }
            $t->{sources} = \@s_refs;

            my @sb_refs;
            my @siblings = $rules[0]->siblings_for_target($t);
            for my $s (@siblings) {
                print "sibling $s\n";
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
    my $n_to_remake;
    do {
        $n_to_remake = keys %{$self->{to_remake}};
        for my $t (values %{$self->{targets}}) {
            if ($t->{flags}->{requested}) {
                $t->must_remake($self->{to_remake});
            }
        }
    } while ($n_to_remake < keys %{$self->{to_remake}});
}

sub next_to_remake {
    my $self = shift;

    for my $t (values %{$self->{to_remake}}) {
        my $src_ready = 1;
        for my $s (@{$t->{sources}}) {
            if ($self->{to_remake}->{$s}) {
                $src_ready = 0;
                last;
            }
        }
        if ($src_ready) {
            return $t;
        }
    }
}

sub remake_done {
    my ($self, $t) = @_;
    
    delete $self->{to_remake}->{$t};
    for my $s (@{$t->{siblings}}) {
        delete $self->{to_remake}->{$s};
    }
}

sub remake {
    my $self = shift;
    
    while (my $t = $self->next_to_remake) {
        print "# $t->{name}\n#   ";
        my @sources = $t->rule->sources_for_target($t);
        for my $s (@sources) {
            print "$s ";
        }
        print "\n";
#        print Dumper $t->rule;
        
#        $t->rule->print_cmd($t,1);
        if ($t->rule->execute_cmd($t, 0) != 0) {
            print "Command failed\n";
            exit(1);
        }
        $self->remake_done($t);
    }
}

1;


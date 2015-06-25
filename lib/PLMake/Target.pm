package PLMake::Target;
use Time::HiRes qw( stat );

use strict;

sub new {
    my $class = shift;
    my ( $name, $flags ) = @_;
    my $self = bless {
        name => $name,
        flags => $flags,
        rules => {},
    }, $class;

    my @stat = stat($name);
    if (@stat) {
        $self->{timestamp} = $stat[9];
    }
    else {
        $self->{flags}->{missing} = 1;
    }

    return $self;
}

sub set_flags {
    my $self = shift;
    %{$self->{flags}} = (%{$self->{flags}}, @_);
}

sub has_rule {
    my ($self, $rule) = @_;

    return $self->{rules}->{$rule};
}

sub add_rule {
    my ($self, $rule) = @_;

    $self->{rules}->{$rule} = $rule;
}

sub remove_rule {
    my ($self, $rule) = @_;

    delete $self->{rules}->{$rule};
}

sub get_rules {
    my ($self) = @_;

    return values %{$self->{rules}};
}

sub rule {
    my ($self) = @_;

    my @rules = $self->get_rules;
    die "conflicting rules" if @rules > 1;
    return $rules[0];
}

sub mark_req_sources {
    my ($self) = @_;

    return if $self->{flags}->{req_source};

    $self->{flags}->{req_source} = 1;

    for my $s (@{$self->{sources}}) {
        $s->mark_req_sources();
    }
}

sub add_missing_timestamp {
    my ($self, $ts) = @_;

    $self->{num_tgt_checked} //= 0;
    $self->{num_tgt_checked}++ if (values %{$self->{targets}} > 0);

    
    if (defined $ts) {
        if ($self->{flags}->{missing} && !$self->{flags}->{phony}) {
            if (!defined $self->{timestamp} || $self->{timestamp} > $ts) {
                $self->{timestamp} = $ts;
            }
        }
    }
    
    if ($self->{flags}->{missing} && 
        ($self->{flags}->{requested} || $self->{flags}->{phony})) {
        $self->{timestamp} = 0;
    }

    if ($self->{num_tgt_checked} == values %{$self->{targets}}) {
        for my $s (@{$self->{sources}}) {
            $s->add_missing_timestamp($self->{timestamp});
        }
    }
}

sub check_remake {
    my ($self, $remake, $ts) = @_;
    
    $self->{num_src_checked} //= 0;
    $self->{num_src_checked}++ if (@{$self->{sources}} > 0);
    
    $self->{flags}->{remake} = 1 if (defined $ts && $ts > $self->{timestamp});
    $self->{flags}->{remake} = 1 if $remake;
    $self->{flags}->{remake} = 1 if $self->{flags}->{phony};
    
    if ($self->{num_src_checked} == @{$self->{sources}}) {
        if ($self->{flags}->{remake}) {
            for my $s (@{$self->{siblings}}) {
                $s->{flags}->{remake} = 1;
            }
        }
        for my $t (values %{$self->{targets}}) {
            print "check remake targets  =$self->{flags}->{remake}= $self->{name} $self->{timestamp} -> =$t->{flags}->{remake}= $t->{name} $t->{timestamp}\n";
            $t->check_remake($self->{flags}->{remake}, $self->{timestamp});
        }
    }
}

sub remake_missing {
    my ($self) = @_;
    
    for my $s (@{$self->{sources}}) {
        if ($s->{flags}->{missing} && !$s->{flags}->{remake}) {
            $s->{flags}->{remake} = 1;
            $s->remake_missing;
        }
    }
}

1;


package Iston::Application::Observer;
$Iston::Application::Observer::VERSION = '0.01';
use 5.12.0;

use Moo;
use OpenGL qw(:all);
use Time::HiRes qw/gettimeofday tv_interval usleep sleep/;

use aliased qw/Iston::History::Record/;

with('Iston::Application');

has started_at     => (is => 'ro', default => sub { [gettimeofday]} );
has object_path    => (is => 'ro', required => 1);
has main_object    => (is => 'rw');
has mouse_position => (is => 'rw');

sub BUILD {
    my $self = shift;
    $self->init_app;
    my $object = $self->load_object($self->object_path);
    $self->main_object($object);
    push @{ $self->objects }, $object;

    my ($x, $y) = ($self->width/2, $self->height/2);
    glutWarpPointer($x, $y);
    $self->mouse_position([$x, $y]);

    $self->_log_state;
};

sub objects {
    my $self = shift;
    return [$self->main_object];
}

sub _log_state {
    my $self = shift;

    return unless $self->history;
    my $record = Record->new(
        timestamp     => tv_interval ( $self->started_at, [gettimeofday]),
        x_axis_degree => $self->main_object->rotation->[0],
        y_axis_degree => $self->main_object->rotation->[1],
        camera_x      => $self->camera_position->[0],
        camera_y      => $self->camera_position->[1],
        camera_z      => $self->camera_position->[2],
    );
    push @{ $self->history->records }, $record;
}

sub _exit {
    my $self = shift;
    say "...exiting from observer";
    $self->_log_state;
    $self->history->save if($self->history);
    $self->cv_finish->send;
}


sub key_pressed {
    my ($self, $key) = @_;
    my $rotate_step = 2;
    my $rotation = sub {
        my ($c, $step) = @_;
        my $subject = $self->main_object;
        return sub {
            $subject->rotation->[$c] += $step;
            $subject->rotation->[$c] %= 360;
        }
    };
    my $camera_z_move = sub {
        my $value = shift;
        return sub {
            $self->camera_position->[2] += $value;
        };
    };
    my $dispatch_table = {
        'w' => $rotation->(0, -$rotate_step),
        's' => $rotation->(0, $rotate_step),
        'a' => $rotation->(1, -$rotate_step),
        'd' => $rotation->(1, $rotate_step),
        '+' => $camera_z_move->(0.1),
        '-' => $camera_z_move->(-0.1),
        'q' => sub {
            my $m = glutGetModifiers;
            $self->_exit if($m & GLUT_ACTIVE_ALT);
        },
    };
    my $key_char = chr($key);
    my $action = $dispatch_table->{$key_char};
    $action->() if($action);
    $self->_log_state;
}

sub mouse_movement {
    my ($self, $x, $y) = @_;

    # guard the edges
    my $barrier = 30;
    my $reset_position = 0;
    ($reset_position, $x) = (1, $self->width/2)
        if ($x < $barrier or $self->width - $x < $barrier);
    ($reset_position, $y) = (1, $self->height/2)
        if ($y < $barrier or $self->height -$y < $barrier);
    if ($reset_position) {
        glutWarpPointer($x, $y);
        return $self->mouse_position( [$x, $y] );
    }

    my $last_position = $self->mouse_position;
    my ($dX, $dY) = ($last_position->[0] - $x, $last_position->[1] - $y);

    my ($dx_axis_degree, $dy_axis_degree) = map { $_ * -1} ($dX, $dY);
    my $rotation = $self->main_object->rotation;
    $rotation->[1] += $dx_axis_degree;
    $rotation->[1] %= 360;
    $rotation->[0] += $dy_axis_degree;
    $rotation->[0] %= 360;
    $self->_log_state;
    $self->mouse_position( [$x, $y] );
    glutPostRedisplay;
}

sub mouse_click {
    my ($self, $button, $state, $x, $y) = @_;
    if ($button == 3 or $button == 4) { # scroll event
        if (!$state != GLUT_UP) {
            my $step = 0.1 * ( ($button == 3) ? 1: -1);
            $self->camera_position->[2] += $step;
        }
    }
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Iston::Application::Observer

=head1 VERSION

version 0.01

=head1 AUTHOR

Ivan Baidakou <dmol@gmx.com>,

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Ivan Baidakou.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

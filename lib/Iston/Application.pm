package Iston::Application;
$Iston::Application::VERSION = '0.07';
use 5.12.0;

use AntTweakBar qw/:all/;
use AnyEvent;
use File::ShareDir::ProjectDistDir (':all', projectdir => 'share');
use Function::Parameters qw(:strict);
use Iston::Matrix;
use Iston::Utils qw/perspective look_at translate identity/;
use Moo::Role;
use OpenGL qw(:all);
use OpenGL::Shader;
use SDL;
use SDLx::App;
use SDL::Joystick;
use SDL::Mouse;
use SDL::Video;
use SDL::Events;
use SDL::Event;
use Time::HiRes qw/gettimeofday tv_interval/;

use aliased qw/Iston::Loader/;
use aliased qw/Iston::Vector/;
use aliased qw/Iston::EventDistributor/;

has camera_position => (is => 'rw', trigger => 1);
has shader_for      => (is => 'rw', default => sub { {} });
has cv_finish       => (is => 'ro', default => sub { AE::cv });
has max_boundary    => (is => 'ro', default => sub { 3.0 });
has full_screen     => (is => 'ro', default => sub { 1 });
has sdl_event       => (is => 'ro', default => sub { SDL::Event->new } );
has sdl_app         => (is => 'rw');
has width           => (is => 'rw');
has height          => (is => 'rw');
has settings_bar    => (is => 'lazy');
has history         => (is => 'rw');

# event distributor
has _notifyer => (is => 'rw', default => sub { EventDistributor->new } );

# matrices
has view            => (is => 'rw', trigger => 1, default => sub { identity } );
has projection      => (is => 'rw', trigger => 1);

has view_oga        => (is => 'rw');
has projection_oga  => (is => 'rw');

requires qw/process_event/;
requires qw/objects/;

sub init_app {
    my $self = shift;

    $self->_notifyer->declare('view_change');
    SDL::init(SDL_INIT_VIDEO);

    my $video_info = SDL::Video::get_video_info();
    my %display_dimension = $self->full_screen
        ? (width => $video_info->current_w, height => $video_info->current_h)
        : (width => 800, height => 600);

    my %app_options = (
        title => 'Iston',
        gl    => 1,
        ($self->full_screen ? (fullscreen => 1) : ()),
        %display_dimension,
    );
    $self->sdl_app( SDLx::App->new(%app_options) );

    glutInit;
    glEnable(GL_DEPTH_TEST);
    glClearColor(0.0, 0.0, 0.0, 0.0);
    $self->_initGL;
    $self->_init_shaders(qw/object/);
    #$self->object_shader->Enable;
    $self->camera_position([0, 0, -7]);
    # $self->view( look_at(
    #         Vector->new([0.0, 2.0, 0.0]),
    #         $self->camera_position,
    #         Vector->new([0.0, 1.0, 0.0]),
    # ));
    $self->projection(
        perspective(45.0, 1.0 * $self->width/$self->height, 0.1, 30.0)
    );
    AntTweakBar::init(TW_OPENGL);
    my ($width, $height) = map { $self->sdl_app->$_ } qw/w h/;
    AntTweakBar::window_size($width, $height);

    # remove all mouse motion events from queue (garbage)
    my $mouse_motion_mask = SDL_EVENTMASK(SDL_MOUSEMOTION);
    SDL::Events::peep_events($self->sdl_event, 127, SDL_GETEVENT, $mouse_motion_mask);
}


method _init_shaders(@names) {
    my $dist_dir = dist_dir('Iston');
    say "dist dir: $dist_dir";
    for (0 .. @names-1) {
        my $name = $names[$_];
        my $shader = OpenGL::Shader->new('GLSL');
        say "Shader ", $shader->GetType, " version: ", $shader->GetVersion if(!$_);

        my @shader_files = (
            "$dist_dir/shaders/$name.fragment.glsl",
            "$dist_dir/shaders/object.vertex.glsl"
        );
        my $info = $shader->LoadFiles(@shader_files);
        die ("shaders $name loading: $info") if $info;
        say "loaded shaders for $name";
        $self->shader_for->{$name} = $shader;
    }
}

method _trigger_view($matrix) {
    $self->_update_view;
}

method _trigger_camera_position {
    $self->_update_view;
}

method _update_view {
    my $camera = $self->camera_position;
    my $translate = translate($camera);
    my $view = $self->view;
    my $matrix = $view * $translate;
    $self->_notifyer->publish('view_change', $matrix);
    $matrix = ~$matrix;
    #say "upating view with\n", $matrix;
    #say "list: \n", join(', ', $matrix->as_list);
    for my $shader (values %{ $self->shader_for }) {
        $shader->Enable;
        $shader->SetMatrix(
            view => OpenGL::Array->new_list(GL_FLOAT, $matrix->as_list)
        );
        $shader->SetVector('camera', @$camera, 0.0);
        $shader->Disable;
    }
}

method _trigger_projection($matrix) {
    $matrix = ~$matrix;
    #say "upating projection with\n", $matrix;
    #say "list: \n", join(', ', $matrix->as_list);
    for my $shader (values %{ $self->shader_for }) {
        $shader->Enable;
        $shader->SetMatrix(
            projection => OpenGL::Array->new_list(GL_FLOAT, $matrix->as_list)
        );
        $shader->Disable;
    }
}

sub _initGL {
    my $self = shift;
    my ($width, $height) = map { $self->sdl_app->$_ } qw/w h/;
    $self->width( $width );
    $self->height( $height );
    say "screen: ${width}x${height} px";
    #glMatrixMode(GL_PROJECTION);
    glShadeModel(GL_SMOOTH);
}

sub _build_settings_bar {
    AntTweakBar->new("Settings");
}

sub _drawGLScene {
    my $self = shift;
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    for(@{ $self->objects }) {
        next if !$_ or !$_->enabled;
        $_->draw_function->();
    }
    AntTweakBar::draw;
    glFlush;
}

sub refresh_world {
    my $self = shift;
    $self->_handle_polls;
    $self->_drawGLScene;
    $self->sdl_app->sync;
}

sub _handle_polls {
    my $self = shift;

    SDL::Events::pump_events;
    my $event = $self->sdl_event;
    while (SDL::Events::poll_event($event)) {
        $self->process_event($event);
    }
    return $event->type != SDL_QUIT;
}

sub load_object {
    my ($self, $path) = @_;
    my $start = [gettimeofday];
    my $object = Loader->new(file => $path)->load;

    my $scale_to = 1 / ($object->radius / $self->max_boundary);

    $object->scale( $scale_to );
    say "model $path loaded, scaled: $scale_to";
    $object->shader($self->shader_for->{object});
    $object->notifyer($self->_notifyer);
    my $elapsed = tv_interval ( $start );
    say "Object $path loaded at ", sprintf("%0.4f", $elapsed), " seconds";
    return $object;
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Iston::Application

=head1 VERSION

version 0.07

=head1 AUTHOR

Ivan Baidakou <dmol@gmx.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Ivan Baidakou.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

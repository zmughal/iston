use 5.12.0;

use Test::More;
use Test::Warnings;

use aliased qw/Iston::History/;
use aliased qw/Iston::History::Record/;
use aliased qw/Iston::Vertex/;
use aliased qw/Iston::Vector/;
use aliased qw/Iston::Analysis::Projections/;
use aliased qw/Iston::Object::HTM/;
use aliased qw/Iston::Object::ObservationPath/;

my $_a2r = sub {
    my $ts_idx = 0;
    my $angles = shift;
    return [ map  {
        my ($a, $b) = @$_;
        Record->new(
            timestamp     => $ts_idx++,
            x_axis_degree => $a,
            y_axis_degree => $b,
            camera_x      => 0,
            camera_y      => 0,
            camera_z      => -7,
        );
    } @$angles ] ;
};

subtest "unique vertex on sphere hit to just 1 trianle" => sub {
# rotate down and counter clock-wise, such a way, that we are looking
# at the north-front triangle (level 0, index: 0), and then to the
# rightmost subtriangle (level 1, index: 2). Triangle details:

# base triangle:

# 0  'vertex[0.0000000, 1.0000000, 0.0000000]'
# 0  'vertex[-0.7071068, 0.0000000, 0.7071068]'
# 0  'vertex[0.7071068, 0.0000000, 0.7071068]'

# --------------------------------------
# subtriangles
# 0
# 0  'vertex[0.0000000, 1.0000000, 0.0000000]'
# 0  'vertex[-0.5000000, 0.7071068, 0.5000000]'
# 0  'vertex[0.5000000, 0.7071068, 0.5000000]'

# 1
# 0  'vertex[-0.7071068, 0.0000000, 0.7071068]'
# 0  'vertex[0.0000000, 0.0000000, 1.0000000]'
# 0  'vertex[-0.5000000, 0.7071068, 0.5000000]'

# 2
# 0  'vertex[0.7071068, 0.0000000, 0.7071068]'
# 0  'vertex[0.5000000, 0.7071068, 0.5000000]'
# 0  'vertex[0.0000000, 0.0000000, 1.0000000]'

# 3
# 0  'vertex[-0.5000000, 0.7071068, 0.5000000]'
# 0  'vertex[0.0000000, 0.0000000, 1.0000000]'
# 0  'vertex[0.5000000, 0.7071068, 0.5000000]'
    my $h = History->new;
    my @angels = ([1, -33], [2, -35]);
    my $records = $_a2r->(\@angels);
    push @{$h->records}, @$records;
    my $o = ObservationPath->new(history => $h);
    my $htm = HTM->new;
    $htm->level(1);
    my $projections = Projections->new(
        observation_path => $o,
        htm              => $htm,
    );

    my $projections_map = $projections->projections_map;

    is_deeply $projections_map, {
        0 => {                  # vertex in observation path index
            0 => ["path[0]"],   # level => triangle index
            1 => ["path[0:2]"],
        },
        1 => {
            0 => ["path[0]"],
            1 => ["path[0:2]"],
        },
    };
    $projections->distribute_observation_timings;
    is $projections_map->{0}{0}[0]->triangle->payload->{total_time},
        1, "right time on NF triangle";
    is $projections_map->{0}{1}[0]->triangle->payload->{total_time},
        1, "right time on NF sub-triangle";
};

subtest "vertex on sphere hit to 2 adjacent trianle" => sub {
    my $h = History->new;
    my @angels = ([0, -10], [0, -15]);
    my $records = $_a2r->(\@angels);
    push @{$h->records}, @$records;
    my $o = ObservationPath->new(history => $h);
    my $htm = HTM->new;
    $htm->level(1);

    my $projections = Projections->new(
        observation_path => $o,
        htm              => $htm,
    );
    my $projections_map = $projections->projections_map;

    is_deeply $projections_map, {
        0 => {
            0 => [qw/path[0]   path[4]/],
            1 => [qw/path[0:2] path[4:1]/],
        },
        1 => {
            0 => [qw/path[0]   path[4]/],
            1 => [qw/path[0:2] path[4:1]/],
        },
    };

    $projections->distribute_observation_timings;

    is $projections_map->{0}->{0}->[0]->triangle->payload->{total_time},
        0.5, "right time on NF triangle";
    is $projections_map->{0}->{0}->[1]->triangle->payload->{total_time},
        0.5, "right time on SF triangle";

    is $projections_map->{0}->{1}->[0]->triangle->payload->{total_time},
        0.5, "right time on NF subtriangle";
    is $projections_map->{0}->{1}->[1]->triangle->payload->{total_time},
        0.5, "right time on SF subtriangle";
};

subtest "vertex on sphere hit to the vertex of the 4 triangles (north pole)" => sub {
    my $h = History->new;
    my @angels = ([10, 0], [90, 0] );
    my $records = $_a2r->(\@angels);
    push @{$h->records}, @$records;
    my $o = ObservationPath->new(history => $h);
    my $htm = HTM->new;
    $htm->level(1);

    my $projections = Projections->new(
        observation_path => $o,
        htm              => $htm,
    );
    my $projections_map = $projections->projections_map;


    is_deeply $projections_map, {
        0 => {
            0 => [qw/path[0]/],
            1 => [qw/path[0:3]/],
        },
        1 => {
            0 => [qw/path[0]   path[1]   path[2]   path[3]/],
            1 => [qw/path[0:0] path[1:0] path[2:0] path[3:0]/],
        },
    };

};

subtest "vertex on sphere hit to the vertex of the 6 triangles" => sub {
    my $h = History->new;
    my @angels = ([0, 0], [10, 0] );
    my $records = $_a2r->(\@angels);
    push @{$h->records}, @$records;
    my $o = ObservationPath->new(history => $h);
    my $htm = HTM->new;
    $htm->level(1);

    my $projections = Projections->new(
        observation_path => $o,
        htm              => $htm,
    );
    my $projections_map = $projections->projections_map;

    is_deeply $projections_map, {
        0 => {
            0 => [qw/path[0]   path[4]/],
            1 => [qw/path[0:1] path[0:2] path[0:3] path[4:1] path[4:2] path[4:3]/],
        },
        1 => {
            0 => [qw/path[0]/],
            1 => [qw/path[0:3]/],
        },
    };

    $projections->distribute_observation_timings;
    is $projections_map->{0}->{0}->[0]->triangle->payload->{total_time},
        0.5, "right time on NF triangle";
    is $projections_map->{0}->{1}->[1]->triangle->payload->{total_time},
        1/6, "right time on NF subtriangle";
};

done_testing;

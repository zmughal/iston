use 5.12.0;

use Test::More;
use Test::Warnings;

use Path::Tiny;

use aliased qw/Iston::History/;
use aliased qw/Iston::History::Record/;

subtest "simple-history" => sub {
    my $tmp_dir = Path::Tiny->tempdir( CLEANUP => 1);
    my $history_path = path($tmp_dir, "h.csv");
    my $h = History->new(path => $history_path);
    my $record = Record->new(
        timestamp     => sprintf('%0.7f', 0),
        x_axis_degree => sprintf('%0.7f', 1),
        y_axis_degree => sprintf('%0.7f', 2),
        camera_x      => sprintf('%0.7f', 3),
        camera_y      => sprintf('%0.7f', 4),
        camera_z      => sprintf('%0.7f', 5),
        label         => '',
    );
    push @{ $h->records }, $record;
    $h->save;
    my $h2 = History->new(path => $history_path)->load;
    is_deeply($h->records, $h2->records);
};

subtest "history load" => sub {
    my $tmp_dir = Path::Tiny->tempdir( CLEANUP => 1);
    my $data =<<DATA;
timestamp,x_axis_degree,y_axis_degree,camera_x,camera_y,camera_z,label
17.621475,16,262,0,0,-7.5,
17.722533,14,262,0,0,-7.5,

DATA
    my $data_path = path($tmp_dir, "x.csv");
    $data_path->spew($data);
    my $h = History->new(path => $data_path);
    $h->load;
    is $h->elements, 2, "history has correct number of records";
};

done_testing;

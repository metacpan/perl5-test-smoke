use v5.42;
use warnings;
use experimental qw(signatures);
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../local/lib/perl5";

use_ok 'CoreSmoke::App';
use_ok 'CoreSmoke::Model::DB';
use_ok 'CoreSmoke::Model::Plevel';
use_ok 'CoreSmoke::Model::Reports';
use_ok 'CoreSmoke::Model::Ingest';
use_ok 'CoreSmoke::Model::ReportFiles';
use_ok 'CoreSmoke::Controller::Api';
use_ok 'CoreSmoke::Controller::JsonRpc';
use_ok 'CoreSmoke::Controller::System';
use_ok 'CoreSmoke::Controller::Web';
use_ok 'CoreSmoke::Controller::Ingest';

done_testing;

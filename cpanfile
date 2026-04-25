requires 'perl', '5.042000';

# core framework
requires 'Mojolicious',           '>= 9.34';
requires 'Mojo::SQLite',          '>= 3.009';

# config
requires 'Mojolicious::Plugin::Config';

# misc
requires 'JSON::PP',              '>= 4.16';
requires 'Digest::MD5';
requires 'Date::Parse';
requires 'DateTime';
requires 'DateTime::Format::SQLite';

# request gzip + on-disk xz files
requires 'IO::Compress::Gzip';
requires 'IO::Uncompress::Gunzip';
requires 'IO::Compress::Xz';
requires 'IO::Uncompress::UnXz';

# YAML for OpenAPI spec
requires 'YAML::PP';

on 'develop' => sub {
    requires 'Test::More',        '>= 1.302';
    requires 'Test::Mojo';
    requires 'Test::Deep';
    requires 'Test::Warnings';
    requires 'Perl::Critic';
    requires 'Devel::Cover';
};

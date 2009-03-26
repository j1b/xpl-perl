#!#!/usr/bin/perl -w
#
# Copyright (C) 2009 by Mark Hindess

use strict;
use IO::Socket::INET;
use IO::Select;
use Socket;
use Test::More tests => 17;
use t::Helpers qw/test_warn test_error test_output/;
$|=1;

$ENV{PATH} = 't/bin:blib/script:'.$ENV{PATH};
use_ok('xPL::Dock','Heyu');

my @msg;
sub xPL::Dock::send_aux {
  my $self = shift;
  my $sin = shift;
  push @msg, [@_];
}

$ENV{XPL_HOSTNAME} = 'mytestid';
my $xpl;

{
  local $0 = 'dingus';
  local @ARGV = ('--verbose',
                 '--heyu-verbose', '--heyu-verbose',
                 '--define', 'ip=127.0.0.1',
                 '--define', 'broadcast=127.0.0.1',
                 '--define', 'hubless=1',
                 #'--', '-v',
                );
  $xpl = xPL::Dock->new(port => 0);
}
ok($xpl, 'created dock client');
my $plugin = ($xpl->plugins)[0];
ok($plugin, 'plugin exists');
is(ref $plugin, 'xPL::Dock::Heyu', 'plugin has correct type');
my $out = '';
while (!$plugin->{_monitor_ready}) {
  $out .= test_output(sub { $xpl->main_loop(1) }, \*STDERR);
}
ok(1, 'monitor ready');
my $sel = IO::Select->new($plugin->{_monitor_fh});
while ($sel->can_read(0.1)) {
  $out .= test_output(sub { $xpl->main_loop(1) }, \*STDERR);
}
is($out,
   q{Sending x10.basic a0 on
Sending x10.basic a2 bright 8
Sending x10.confirm a3,10 on
Sending x10.basic l6 xfunc data1=49 data2=63
monitor reported unsupported line:
  testing unsupported line
},
 'unsupported line output');

is(test_output(sub {
                 $xpl->dispatch_xpl_message(
                   xPL::Message->new(message_type => 'xpl-cmnd',
                                     head =>
                                     {
                                      source => 'acme-heyu.test',
                                     },
                                     class=> 'x10',
                                     class_type => 'basic',
                                     body =>
                                     {
                                      'command' => 'on',
                                      'device' => 'a3',
                                     })); }, \*STDERR),
   ("queued: 00000000 on a3\n".
    "sent: 00000000 on a3\n"),
   'x10.basic command=extended output');

my $count = $xpl->input_callback_count($plugin->{_helper_rh});
$out = '';
while ($count == $xpl->input_callback_count($plugin->{_helper_rh})) {
  $out = test_output(sub { $xpl->main_loop(1); }, \*STDERR);
}

is($out, "Acknowledged 00000000\n", 'helper ack 0');

check_sent_msg({
                message_type => 'xpl-trig',
                class => 'x10.basic',
                body => {
                         'device' => 'a0',
                         'command' => 'on'
                        },
               }, 'monitor: a0 on');

check_sent_msg({
                message_type => 'xpl-trig',
                class => 'x10.basic',
                body => {
                         device => 'a2',
                         command => 'bright',
                         level => 36,
                        },
               }, 'monitor: a2 bright');

check_sent_msg({
                message_type => 'xpl-trig',
                class => 'x10.confirm',
                body => {
                         device => 'a3,a10',
                         command => 'on',
                        },
               }, 'monitor: a3 on');

check_sent_msg({
                message_type => 'xpl-trig',
                class => 'x10.basic',
                body => {
                         device => 'l6',
                         command => 'extended',
                         data1 => 49,
                         data2 => 63,
                        },
               }, 'monitor: l6 xfunc 49 63');

is(test_output(sub {
                 $xpl->dispatch_xpl_message(
                   xPL::Message->new(message_type => 'xpl-cmnd',
                                     head =>
                                     {
                                      source => 'acme-heyu.test',
                                     },
                                     class=> 'x10',
                                     class_type => 'basic',
                                     body =>
                                     {
                                      'command' => 'dim',
                                      'level' => 10,
                                      'house' => 'a',
                                     })); }, \*STDERR),
   ("queued: 00000001 dim a1 2\n".
    "sent: 00000001 dim a1 2\n"),
   'x10.basic command=extended output');

$count = $xpl->input_callback_count($plugin->{_helper_rh});
$out = '';
while ($count == $xpl->input_callback_count($plugin->{_helper_rh})) {
  $out = test_output(sub { $xpl->main_loop(1); }, \*STDERR);
}

is($out, "Acknowledged 00000001\n", 'helper ack 1');

is(test_output(sub {
                 $xpl->dispatch_xpl_message(
                   xPL::Message->new(message_type => 'xpl-cmnd',
                                     head =>
                                     {
                                      source => 'acme-heyu.test',
                                     },
                                     class=> 'x10',
                                     class_type => 'basic',
                                     body =>
                                     {
                                      command => 'extended',
                                      device => 'a10,a12',
                                      data1 => 49,
                                      data2 => 63,
                                     })); }, \*STDERR),
   ("queued: 00000002 xfunc 31 a10,12 3f\n".
    "sent: 00000002 xfunc 31 a10,12 3f\n"),
   'x10.basic command=extended output');

$count = $xpl->input_callback_count($plugin->{_helper_rh});
$out = '';
while ($count == $xpl->input_callback_count($plugin->{_helper_rh})) {
  $out = test_output(sub { $xpl->main_loop(1); }, \*STDERR);
}

is($out, "Helper wrote: Testing error case\n", 'helper output');

$count = $xpl->input_callback_count($plugin->{_helper_rh});
$out = '';
while ($count == $xpl->input_callback_count($plugin->{_helper_rh})) {
  $out = test_output(sub { $xpl->main_loop(1); }, \*STDERR);
}

is($out, "Received 00000002: 65280 65280\n", 'helper error');

sub check_sent_msg {
  my ($expected, $desc) = @_;
  my $msg = shift @msg;
  while ((ref $msg->[0]) =~ /^xPL::Message::hbeat/) {
    $msg = shift @msg; # skip hbeat.* message
  }
  if (defined $expected) {
    my %m = @{$msg};
    is_deeply(\%m, $expected, 'message as expected - '.$desc);
  } else {
    is(scalar @msg, 0, 'message not expected - '.$desc);
  }
}

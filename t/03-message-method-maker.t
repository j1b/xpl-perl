#!/usr/bin/perl -w
#
# Copyright (C) 2005 by Mark Hindess

use strict;
use Test::More tests => 3;
use xPL::Message;
use lib 't/lib';

my $msg = xPL::Message->new(class => 'test.basic',
                            head => { source => 'bnz-test.default' });
ok($msg);
is($msg->field, 'field not overriden',
   'field not overriden by automatic methods');
is($msg->body_fields, 'body_fields not overriden',
   'body_fields not overriden by automatic methods');

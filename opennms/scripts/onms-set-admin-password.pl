#!/usr/bin/perl

use strict;
use Digest::MD5;

my $opennms_home = "/opt/opennms";

if ($#ARGV != 2) {
	die("Incorrect number of command-line arguments. Usage: $0 <users.xml file> <user> <password>\n");
}

my $users_xml = shift(@ARGV);
my $user = shift(@ARGV);
my $password = shift(@ARGV);

my $digest = uc(Digest::MD5::md5_hex($password));

open(IN, "<$users_xml") || die("Could not open $users_xml for reading: $!\n");
$_ = join("", <IN>);
close(IN);

my $user_quoted = quotemeta($user);

s%(<user>\s*<user-id>$user_quoted</user-id>.*?)<password[^>]*>[^<]*</password>(.*?</user>\s*)%\1<password>$digest</password>\2%s || die("Did not find user '$user' in $users_xml\n");

open(OUT, ">$users_xml") || die("Could not open $users_xml for writing: $!\n");
print OUT $_;
close(OUT);

#!/usr/bin/perl
# Copyright (C) 2016  Jesse McGraw (jlmcgraw@gmail.com)
#
# Create commands to add forward and reverse DNS entries into
# Microsoft DNS server from a hosts file
#
#-------------------------------------------------------------------------------
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see [http://www.gnu.org/licenses/].
#-------------------------------------------------------------------------------

#Standard modules
use strict;
use warnings;
use autodie;

# use Socket;
# use Config;
# use Data::Dumper;
# use Storable;
# use threads;
# use Thread::Queue;
# use threads::shared;
# use Getopt::Std;
use FindBin '$Bin';
use vars qw/ %opt /;
use File::Copy;
use Config;
use File::Basename;

#Use a local lib directory so users don't need to install modules
use lib "$FindBin::Bin/local/lib/perl5";

#Additional modules
use Modern::Perl '2014';
use Params::Validate qw(:all);

#Smart_Comments=1 perl my_script.pl to show smart comments
use Smart::Comments -ENV;

if ( !@ARGV ) {
    say "$0 <host file(s)>";
}

#Save original ARGV
my @ARGV_unmodified;

#Expand wildcards on command line since windows doesn't do it for us
if ( $Config{archname} =~ m/win/ix ) {
    use File::Glob ':bsd_glob';

    #Expand wildcards on command line
    ### "Expanding wildcards for Windows";
    @ARGV_unmodified = @ARGV;
    @ARGV = map { bsd_glob $_ } @ARGV;
}

#An octet
#Longest matches first
my $octetRegex = qr/(?: 25[0-5] | 2[0-4][0-9] | 1[0-9]{2} | [0-9]{1,2})/mx;

#IPv4 address and netmasks are 4 octets
my $ipv4_dotted_quad_regex = qr/(?:$octetRegex)\.
                                (?:$octetRegex)\.
                                (?:$octetRegex)\.
                                (?:$octetRegex)
                                /x;

#Change these as needed
my $dns_server  = 'dns_server';
my $domain_name = 'example.com';

#For each file from the command line...
foreach my $file ( sort @ARGV ) {

    #Skip if this isn't actually a file
    next unless -f $file;

    my ( $file_text, $hostname, $ip_addr );

    #Read in the whole file
    {
        local $/;
        open my $fh, '<', $file or die "can't open $file: $!";
        $file_text = <$fh>;
        close $fh;
    }

    #Process each line in the config file sequentially...
    foreach my $line ( split /^/, $file_text ) {

        given ($line) {

            #Skip comments
            when (
                /^ \s*                                  #BOL and zero+ whitespace
                    \#
                    /ix
              )
            {
                next;
            }

            when (
                /^ \s*                                          #BOL and zero+ whitespace
                    (?<ip_addr> $ipv4_dotted_quad_regex ) \s+
                    (?<hostname> [^\s]+ )  
                 
                 \s* $                                       #Zero+ whitespace and EOL
                 
                /ix
              )
            {
                #Pull out the components
                $hostname = $+{hostname};
                $ip_addr  = $+{ip_addr};

                #If we have both components
                if ( $ip_addr && $hostname ) {

                    #Split the IP address into octets
                    my @octets = split( /\./, $ip_addr );

                    #Construct the reversed IP information
                    my $reversed_ip = "$octets[2].$octets[1].$octets[0]";
                    my $reverse_ptr = $reversed_ip . '.in-addr.arpa.';

                    say
                      "dnscmd $dns_server /RecordAdd $domain_name $hostname A $ip_addr";
                    say
                      "dnscmd $dns_server /RecordAdd $reverse_ptr $octets[3] PTR $hostname.$domain_name";

                    # dnscmd . /RecordAdd enkitec.com  enkx3sw-pdua A 192.168.8.245
                    # dnscmd . /recordadd 8.168.192.in-addr.arpa. 245 PTR enkx3sw-pdua.enkitec.com
                    #
                    # Add PTR Record for 245.8.168.192.in-addr.arpa. at 8.168.192.in-addr.arpa.
                    # Command completed successfully.
                }
                else {
                    warn $line;
                    die "Problem with $file";
                }
            }

        }

    }
}

#!/usr/bin/perl -w
# 
# ChatSimple Client by Florian Schiessl. <florian at floriware.de>
# 
# Dev-Start: 23.2.2013
# 
# Usage:
# ./chatsimple-client.pl [-u username] [-p password] [host[:port]
#
# Options
# -i, --ip   : IP-Address / Hostname of Server
# -o, --port : Server-Port
# -n, --no-colors : Don't use colors
# -u, --user : Your username
# -p, --password : The server's password
# -q, --quiet : Don't show welcome message and connection information
# -t, --no-timestamps : Don't draw timestamp before messages.
#
# Changelog:
# 4.3.2013 Florian Schiessl:
# - removed not working colors for Windows users.
# 5.3.2013 Florian Schiessl:
# - cleaning up (use strict added)
# - added &requestok (function to wait for servers 'ok' answer)
# - added reverse line feed for own messages
# - added colors for yourself (cyan) and others (magenta)
# 7.3.2013 Florian Schiessl:
# - adding command line options for user,pass,etc...
# 8.3.2013 Florian Schiessl:
# - adding perlpod documentation after __END__
#

use strict;
use IO::Socket;
use threads;
use threads::shared;
use Thread::Queue;
use Term::ANSIColor;
use Term::ReadKey;
use Getopt::Long qw( :config no_ignore_case bundling );
#use Time::HiRes qw( usleep );

##################
# Configuration
my $sep = '::'; # Separator for commands
my $default_port = 5060;
my $default_ip = "127.0.0.1";

####################
# Getting options
my $ip;
my $port;
my $no_colors = 0;
my $username :shared; # The used username as shared (between threads) variable. Default = system user.
my $password :shared = ''; # The server password
my $quiet = 0; # Don't show Connection information (welcome message) when connecting.
my $no_timestamps = 0; # Don't show timestamps on incoming messages.

GetOptions(
	'i|ip:s' => \$ip,
	'o|port:s' => \$port,
	'n|no-colors' => \$no_colors,
	'u|user:s' => \$username,
	'p|password:s' => \$password,
	'q|quiet' => \$quiet,
	't|no-timestamps' => \$no_timestamps
);

# For telnet style "ip port" only
if(!defined($ip))
{
	$ip = $default_ip;
	$ip = $ARGV[0] if defined($ARGV[0]);
}
($ip,$port) = split(':',$ip) if $ip =~ m/:/; # For ip:port

if(!defined($port))
{
	$port = $default_port;
	$port = $ARGV[1] if defined($ARGV[1]);
}

##########
# Start

my $ok :shared = 0; # must be >0 for requesting an ok message (see &requestok)

my $okqueue = Thread::Queue->new();

# Catching Signals
$SIG{INT} = \&exittsk;
$SIG{TERM} = \&exittsk;
$SIG{QUIT} = \&exittsk;
$SIG{ABRT} = \&exittsk;
$SIG{HUP} = \&exittsk;

# Signal action
sub exittsk
{
	ReadMode(0);
	print "\nBye.\n";
	exit 0;
}

if($quiet == 0)
{
	# Welcome message
	&textcolor('bold blue',"ChatSimple Client v.1.1.0
IP: $ip
Port: $port
Exit: Ctrl+C");
	print "\n";
}

# try to open connection to server
my $socket = new IO::Socket::INET (
	PeerAddr => $ip,
	PeerPort => $port,
	Type => SOCK_STREAM,
);
die "Unable to open connection: $!\n" unless defined $socket;

# the connection was established.
&textcolor('green',"Connection established.\n");


if (!defined($username))
{
	# Show login prompt to user if no credentials supplied

	# Suggest the user's username to the user
	# http://stackoverflow.com/questions/3526420/how-do-i-get-the-current-user-in-perl-in-a-portable-way
	$username = getpwuid($<) if !&windows; # Set to current User (Linux)
	$username = getlogin if &windows; # Use getlogin on Windows.

	my $result;
	# ask for username and password until the server answer is "ok"
	do
	{
		&textcolor('yellow',"Username (".$username."): ");
		my $new_username = <STDIN>;
		$username = (defined($new_username) && $new_username ne "\n") ? $new_username : $username;
		&textcolor('yellow',"Server Password: ");
		$password = &getpassword;
		chomp($username);
		chomp($password);

		$result = &login($username,$password);
	}
	until($result eq "ok");
	undef $result; # clear up for eventually later use
}
else
{
	# use supplied credentials
	if(&login($username,$password) ne "ok")
	{
		&textcolor('red','Login Failed!');
		print "\n";
		exit 1;
	}
}

# Login successfull
&textcolor('green',"Login successfull.\n");

# Starting new Thread, which handles incomming messages from the server
my $thread = threads->new(\&thread,$socket);
$thread->detach;

# Wait for user input
while(my $line = <STDIN>)
{
	chomp($line);
	
	# Check if line starts with / (command mode)
	if($line =~ s/^\///g)
	{
		# The rename function
		if($line =~ s/rename //g)
		{
			$ok = "needed"; # reset $ok, so that it is not ok anymore
			print $socket "rename".$sep.$username.$sep.$line."\n";
			my $success = &requestok(1); # check, if first (1) answer from server after this was 'ok'
			# check if the answer was ok
			if($success eq "ok")
			{
				$username = $line;
			}
		}
		
		# ask for userlist (output handled by our thread)
		elsif($line =~ s/list//g)
		{
			print $socket "list\n";
		}

		# logout with logout message
		elsif($line =~ s/logout //g)
		{
			print $socket "logout".$sep.$username.$sep.$line."\n";
			
		}
		
		# generic logout (without message)
		elsif($line =~ m/logout/)
		{
			print $socket "logout".$sep.$username."\n";
		}
		
		# exit
		elsif($line =~ m/exit/ || $line =~ m/quit/)
		{
			print $socket "logout".$sep.$username."\n";
			&exittsk;
		}

		# and all unknown commands.
		else
		{
			&textcolor('red',"Unknown Command!");
			print "\n";
		}
	}
	
	# else interpret input as normal message
	else
	{
		print $socket "say".$sep.$username.$sep.$line."\n";
	}

}
&textcolor('yellow',"End of STDIN");
print "\n";
exit 1;

# The thread. It takes up all incoming messages from the server
# and print them to the user's terminal.
sub thread
{
	$socket = shift;
	while(<$socket>)
	{
		my $line = $_;
		chomp($line); # Remove newline
		my @data = split($sep,$line); # Split up answer
		$data[0] = "" if !$data[0];
		$data[1] = "" if !$data[1];
		$data[2] = "" if !$data[2];
		
		# Incomming chatmessage
		if($data[0] eq "msg")
		{
			print "\e[A" if $data[1] eq $username; # reverse line feed
			&newinput;
			&textcolor($data[1] eq $username ? 'cyan' : 'magenta',$data[1].": ");
			print $data[2]."\n";
		}
		
		# Incoming notification
		elsif($data[0] eq "notify")
		{
			&newinput;
			&textcolor('bold yellow',$data[1].": ".$data[2]);
			print "\n";
		}
		
		# Incoming error message
		elsif($data[0] eq "err")
		{
			&newinput;
			&textcolor('bold red',$data[1].": ".$data[2]);
			print "\n";
		}
		
		# Incoming client list
		elsif($data[0] eq "clients")
		{
			&newinput;
			&textcolor('yellow',"Connected Clients:");
			print join(" ",split(",",$data[1]))."\n";
		}
		
		# Incoming ok
		elsif($data[0] eq "ok")
		{
			if($ok >= 1)
			{
				# an ok was requested
				$ok = 0;
				$okqueue->enqueue('ok'); # Send an answer
			}
		}
		
		# decrease $ok if message was not 'ok'
		if($ok > 0)
		{
			$okqueue->enqueue('err') if(--$ok == 0); # no ok message was within
		}
	}
	
	# The connection to the Server was lost.
	&textcolor('red',"\nConnection lost!\n");
	&exittsk;
}

#########
# Subs

# try to log in
sub login
{
	my $username = shift;
	my $password = shift;

	print $socket "login".$sep.$username.$sep.$password."\n";

	# getting server's answer
	my $result = <$socket>;
	chomp($result);
	my @data = split($sep,$result);
	if($data[0] eq "err")
	{
		&textcolor('red',$data[2]."\n"); # Show error message to user
	}
	return $data[0];
}

# Print text with fancy colors
sub textcolor
{
	my $color = shift; # The color
	my $text = shift; # The text to colorize

	# Don't use Term::ANSIColor on Windows!
	if($no_colors == 1 || &windows)
	{
		print $text;
	}
	else
	{
		print color $color;
		print $text;
		print color 'reset';
	}
}

sub windows
{
	return $^O =~ m/mswin/i;
}

# Print default input heading
sub newinput
{
	return if $no_timestamps;
	print "\r\e[K"; # Clear last Line
	print &timestamp." ";
}

# A simple Timestamp
sub timestamp
{
	return "[".&dt('hour').":".&dt('minute').":".&dt('second')."]";
}

# Returns a part of the current date
sub dt
{
	my @localtime=localtime(time);
	if ($_[0] eq 'year')
	{return $localtime[5]+1900}
	elsif ($_[0] eq 'month')
	{return &attachleading(2,$localtime[4]+1)}
	elsif ($_[0] eq 'day')
	{return &attachleading(2,$localtime[3])}
	elsif ($_[0] eq 'hour')
	{return &attachleading(2,$localtime[2])}
	elsif ($_[0] eq 'minute')
	{return &attachleading(2,$localtime[1])}
	elsif ($_[0] eq 'second')
	{return &attachleading(2,$localtime[0])}
	else {return "dterror"}
}

# attaches a leading 0 to input
sub attachleading
{
	(my $length, my $input) = @_;
	return sprintf("%0".$length."d",$input);
}

sub requestok
{
	$ok = shift; # the count of next messages from Server the ok could be within
	while(my $success = $okqueue->dequeue())
	{
		return $success;
	}
}

# Get password without showing it to user
# Adapted from http://stackoverflow.com/questions/701078/how-can-i-enter-a-password-using-perl-and-replace-the-characters-with
sub getpassword
{
	my $password = "";
	my $key;
	# Start reading the keys
	ReadMode(4); #Disable the control keys
	while(defined($key = ReadKey(0)) && ord($key) != 10)
	# This will continue until the Enter key is pressed (decimal value of 10)
	{
		# For all value of ord($key) see http://www.asciitable.com/
		if(ord($key) == 127 || ord($key) == 8)
		{
			# DEL/Backspace was pressed
			#1. Remove the last char from the password
			chop($password);
			#2 move the cursor back by one, print a blank character, move the cursor back by one
			#print "\b \b";
		}
		elsif(ord($key) < 32)
		{
			# Do nothing with these control characters
		}
		else
		{
			$password = $password.$key;
		#	print $key;
		#	print "*(".ord($key).")";
		}
	}
	ReadMode(0); #Reset the terminal once we are done
	print "\n";
	return $password;
}

__END__

=head1 NAME

B<chatsimple-client.pl> - Simple chat client using a simple chat protocoll.

=head1 SYNOPSIS

B<chatsimple-client.pl> [OPTIONS] [host[:port]]

B<chatsimple-client.pl> -u florian test.example.com:5061

=head1 OPTIONS

=over

=item C<-i, --ip>

IP-Address / Hostname of Server

=item C<-o, --port>

Server-Port

=item C<-n, --no-colors>

Don't use colors

=item C<-u, --user>

Your username

=item C<-p, --password>

The server's password

=item C<-q, --quiet>

Don't show welcome message and connection information

=item C<-t, --no-timestamps>

Don't draw timestamp before messages.

=back

=head1 AUTHOR

Florian Schiessl <florian at floriware.de> (23.2.2013)

=head1 SEE ALSO

B<chatsimple-server.pl> - the matching server for this client


#!/usr/bin/perl -w
# 
# ChatSimple Client by Florian Schiessl. <florian at floriware.de>
# 
# Dev-Start: 23.2.2013
# 

use IO::Socket;
use threads;
use threads::shared;
use Term::ANSIColor;
use Time::HiRes qw( usleep );

# Catching Signals
$SIG{INT} = \&tsktsk;
$SIG{TERM} = \&tsktsk;
$SIG{QUIT} = \&tsktsk;
$SIG{ABRT} = \&tsktsk;
$SIG{HUP} = \&tsktsk;

# Signal action
sub tsktsk
{
	print "\nBye.\n";
	exit 0;
}

# If given Argument 0 then ip = Argument 0 else "127.0.0.1". Google Ternary Operator if curious.
$ip = $ARGV[0] ? $ARGV[0] : "127.0.0.1";
$port = $ARGV[1] ? $ARGV[1] : "5060";

my $username :shared; # The used username as shared (between threads) variable.
my $password :shared; # The server password
my $ok :shared; # Is ok, if last message from server was "ok"

# Welcome message
&textcolor('bold blue',"ChatSimple Client v.1.0
IP: $ip
Port: $port
Exit: Ctrl+C");
print "\n";

# try to open connection to server
my $socket = new IO::Socket::INET (
	PeerAddr => $ip,
	PeerPort => $port,
	Type => SOCK_STREAM,
);
die "Unable to open connection: $!\n" unless defined $socket;

# the connection was established.
&textcolor('green',"Connection established.\n");

# ask for username and password unless the server answer is "ok"
do
{
	&textcolor('yellow',"Username: ");
	$username = <STDIN>;
	&textcolor('yellow',"Server Password: ");
	$password = <STDIN>;
	chomp($username);
	chomp($password);

	# try to log in
	print $socket "login::".$username."::".$password."\n";
	
	# getting server's answer
	$result = <$socket>;
	chomp($result);
	@data = split("::",$result);
	if($data[0] eq "err")
	{
		&textcolor('red',$data[2]."\n"); # Show error message to user
	}
}
while ($result ne "ok");

# Login successfull
&textcolor('green',"Login successfull.\n");

# Starting new Thread, which handles incomming messages from the server
$thread = threads->new(\&thread,$socket);
$thread->detach;

# Wait for user input
while(<STDIN>)
{
	$line = $_;
	chomp($line);
	
	# Check if line starts with / (command mode)
	if($line =~ s/^\///g)
	{
		# The rename function
		if($line =~ s/rename //g)
		{
			$ok = "needed"; # reset $ok, so that it is not ok anymore
			print $socket "rename::".$username."::".$line."\n";
			usleep(50000); # wait for the server answer
			# check if the answer was ok
			if($ok eq "ok")
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
			print $socket "logout::".$username."::".$line."\n";
			
		}
		
		# generic logout (without message)
		elsif($line =~ s/logout//g)
		{
			print $socket "logout::".$username."\n";
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
		print $socket "say::".$username."::".$line."\n";
	}
}

sub thread
{
	$socket = shift;
	while(<$socket>)
	{
		$line = $_;
		chomp($line);
		@data = split("::",$line);
		if(!defined($data[0])){$data[0] = "";}
		if(!defined($data[1])){$data[1] = "";}
		if(!defined($data[2])){$data[2] = "";}
		if($data[0] eq "msg" && $data[1] ne $username)
		{
			print &timestamp." ";
			&textcolor('bold',$data[1].": ");
			print $data[2]."\n";
		}
		elsif($data[0] eq "notify")
		{
			print &timestamp." ";
			&textcolor('bold yellow',$data[1].": ".$data[2]);
			print "\n";
		}
		elsif($data[0] eq "err")
		{
			print &timestamp." ";
			&textcolor('bold red',$data[1].": ".$data[2]);
			print "\n";
		}
		elsif($data[0] eq "ok")
		{
			$ok = "ok";
		}
		elsif($data[0] eq "clients")
		{
			print &timestamp." ";
			&textcolor('yellow',"Connected Clients:");
			print join(" ",split(",",$data[1]))."\n";
		}
	}
	&textcolor('red',"\nConnection lost!\n");
	exit 0;
}

# Print text with fancy colors
sub textcolor
{
	my $color = shift; # The color
	my $text = shift; # The text to colorize

	# Don't use Term::ANSIColor on Windows!
	if($^O !~ m/mswin/i)
	{
		print color $color;
		print $text;
		print color 'reset';
	}
	else
	{
		print $text;
	}
}

# A simple Timestamp
sub timestamp
{
	return "[".&dt('hour').":".&dt('minute').":".&dt('second')."]";
}

# Returns a part of the current date
sub dt
{
        @localtime=localtime(time);
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
        (my $length, my $string) = @_;
        for (my $count = $length - length($string); $count>0; --$count)
        {
                $string = "0$string";
        }
        return $string;
}

__END__


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

$SIG{INT} = \&tsktsk;
$SIG{TERM} = \&tsktsk;
$SIG{QUIT} = \&tsktsk;
$SIG{ABRT} = \&tsktsk;
$SIG{HUP} = \&tsktsk;
sub tsktsk
{
	print color 'reset';
	print "\nBye.\n";
	exit 0;
}

if ($ARGV[0]) {chomp($ip=$ARGV[0])} else {$ip="127.0.0.1"}
if ($ARGV[1]) {chomp($port=$ARGV[1])} else {$port="5060"}
if ($ARGV[2]) {chomp($prefix=$ARGV[2])} else {$prefix=""}

my $username :shared;
my $password :shared;
my $ok :shared;

print color 'bold blue';
print "ChatSimple Client v.1.0\n";
print "IP: $ip\n";
print "Port: $port\n";
print "Exit: Ctrl+C\n";
print color 'reset';

my $socket = new IO::Socket::INET (
	PeerAddr => $ip,
	PeerPort => $port,
	Type => SOCK_STREAM,
);
die "Unable to open connection: $!\n" unless defined $socket;
print color 'green';
&textcolor('green',"Connection established.\n");

do
{
	&textcolor('yellow',"Username: ");
	$username = <STDIN>;
	&textcolor('yellow',"Server Password: ");
	$password = <STDIN>;
	chomp($username);
	chomp($password);

	# logging in
	print $socket "login::".$username."::".$password."\n";
	$result = <$socket>;
	chomp($result);
	@data = split("::",$result);
	if($data[0] eq "err")
	{
		&textcolor('red',$data[2]."\n");
	}
}
while ($result ne "ok");

&textcolor('green',"Login successfull.\n");

$thread = threads->new(\&thread,$socket);
$thread->detach;

while(<STDIN>)
{
	$line = $_;
	chomp($line);
	if($line =~ s/^\///g)
	{
		if($line =~ s/rename //g)
		{
			$ok = "needed";
			print $socket "rename::".$username."::".$line."\n";
			usleep(50000);
			if($ok eq "ok")
			{
				$username = $line;
			}
		}
		elsif($line =~ s/list//g)
		{
			print $socket "list\n";
		}
		elsif($line =~ s/logout //g)
		{
			print $socket "logout::".$username."::".$line."\n";
			
		}
		elsif($line =~ s/logout//g)
		{
			print $socket "logout::".$username."\n";
		}
		else
		{
			&textcolor('red',"Unknown Command!");
			print "\n";
		}
	}
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

sub textcolor
{
	my $color = shift;
	my $text = shift;
	print color $color;
	print $text;
	print color 'reset';
}

sub timestamp
{
	return "[".&dt('hour').":".&dt('minute').":".&dt('second')."]";
}

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

sub attachleading
{
        (my $length, my $string) = @_;
        for (my $count = $length - length($string); $count>0; --$count)
        {
                $string = "0$string";
        }
        return $string;
}

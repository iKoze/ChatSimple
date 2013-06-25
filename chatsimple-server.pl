#!/usr/bin/perl -w
# 
# ChatSimple Server by Florian Schiessl. <florian at floriware.de>
# 
# Dev-Start: 22.2.2013
# 

use IO::Socket;
use threads;
use threads::shared;
use Time::HiRes qw( usleep );
use POSIX "setsid";
use Data::Dumper;

#############
# Settings

# Localhost
my $port = 5060; # Server Port
my $password = ""; # Server Passwort
my $iam = "chatserver";

# +++++++++++++++++ Beginning +++++++++++++++++ #
# Catching Sigterm & Co.
$SIG{INT} = \&exittsk;
$SIG{TERM} = \&exittsk;
$SIG{QUIT} = \&exittsk;
$SIG{ABRT} = \&exittsk;
$SIG{HUP} = \&exittsk;

my @threads; # All running threads.
my %usernames; # Number of client connection in @conns.
share(%usernames);
$usernames{"SERVER"} = -1; # The username SERVER should not be used.
my @conns = (); # All client connections.
share(@conns);

my $socket = new IO::Socket::INET (
	LocalPort => $port,
	Type => SOCK_STREAM,
	Listen => SOMAXCONN,
	Reuse => 5,
	);

$socket->autoflush(1);
die "Unable to setup socket: $!\n" unless defined $socket;

while ((my $conn = $socket->accept))
{
	my $fileno = fileno($conn);
	my $peerhost = $conn->peerhost();
	$new_thread = threads->new(\&thread,$conn,$peerhost,$fileno);
	push(@threads,$new_thread);
}

sub thread
{
	my $conn = shift;
	my $peerhost = shift;
	my $fileno = shift;
	my $loggedin = "false";
	my $username = "";
	my @data;

	&debug("[$peerhost] -> connection established.");
	
	while(<$conn>)
	{
		$line = $_;
		$line =~ s/\r//g; # Removing CR Characters
		chomp($line);
		&debug("[$peerhost] [$username]: ".$line);
		@data = split('::',$line);
		if(!defined($data[0])){$data[0] = "";}
		if(!defined($data[1])){$data[1] = "";}
		if(!defined($data[2])){$data[2] = "";}
		if(!defined($data[3])){$data[3] = "";}
		if($loggedin eq "false")
		{
			if($data[0] eq "login")
			{
				if($data[2] eq $password)
				{
					if($data[1] eq "")
					{
						print $conn "err::SERVER::empty username!\n";
					}
					elsif(!defined($usernames{$data[1]}))
					{
						push(@conns,$fileno);
						$usernames{$data[1]} = $fileno;
						$username = $data[1];
						&debug("[$peerhost] [".$data[1]."] -> logged in");
						print $conn "ok\n";
						&tellall("notify::SERVER::".$data[1]." logged in from ".$peerhost."\n");
						$loggedin="true";
					}
					else
					{
						print $conn "err::SERVER::username already in use!\n";
					}
				}
				else
				{
					print $conn "err::SERVER::wrong password!\n";
				}
			}
			else
			{
				print $conn "err::SERVER::you must login first!\n";
			}			
		}
		else
		{
			if($data[0] eq "say" || $data[0] eq "tell")
			{
				if($data[1] eq $username)
				{
					if($data[0] eq "say")
					{
						print $conn "ok\n";
						&tellall("msg::".$username."::".$data[2]."\n");
					}
					if($data[0] eq "tell")
					{
						print $conn "ok\n";
						my @receiver = split(",",$data[2]);
						my @receiver_with_sender = @receiver;
						push(@receiver_with_sender, $username);
						&tell("whisper::".$username."::".join(",",@receiver)."::".$data[3]."\n", @receiver_with_sender);
					}
				}
				else
				{
					print $conn "err::SERVER::change your username first!\n";
				}
			}
			elsif($data[0] eq "rename")
			{
				if($data[1] eq $username)
				{
					if(!defined($usernames{$data[2]}))
					{
						my $id = $usernames{$data[1]};
						delete($usernames{$data[1]});
						$usernames{$data[2]} = $id;
						$username = $data[2];
						print $conn "ok\n";
						&tellall("notify::SERVER::".$data[1]." is now known as ".$data[2]."\n");
					}
					else
					{
						print $conn "err::SERVER::nickname already in use!\n";
					}
				}
				else
				{
					print $conn "err::SERVER::you can only rename yourself!\n";
				}
			}
			elsif($data[0] eq "list")
			{
				print $conn "clients::".join(',',sort keys(%usernames))."\n";
			}
			elsif($data[0] eq "logout")
			{
				print $conn "ok\n";
				&debug("[$peerhost] [$username] -> logged out. ".$data[2]);
				last;
			}
			else
			{
				print $conn "err::SERVER::unknown command!\n";
			}
		}
	}

	if(defined($data[0]) && $data[0] eq "logout" && $data[2] ne "")
	{
		&tellall("notify::SERVER::$username logged out: ".$data[2]."\n");
	}
	elsif(defined($data[0]) && $data[0] eq "logout")
	{
		&tellall("notify::SERVER::$username logged out.\n");
	}
	else
	{
		&tellall("notify::SERVER::$username: lost connection.\n");
	}
	close($conn);
	#remove multi-echo-clients from echo list
	@conns = grep {$_ !~ $fileno} @conns;
	delete($usernames{$username});
	&debug("[$peerhost] [$username] -> connection lost.");
}

sub debug
{
	$message = shift;
	print "[".&dt('hour').":".&dt('minute').":".&dt('second')."] ".$message."\n";
}

sub tellall
{
	$data = shift;
	foreach my $conn (@conns)
	{
		open my $fh, ">&=$conn" or warn $! and die;
		print $fh $data;
		next;
	}
}

sub tell
{
	$data = shift;
	foreach my $receiver (@_)
	{
		#print "DEBUG:".$receiver.$usernames{$receiver}."h\n";
		$conn = $usernames{$receiver};
		if (defined($conn))
		{
			open my $fh, ">&=$conn" or warn $! and die;
			print $fh $data;
		}
		next;
	}
}


###############
# Misc Sub's
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
        (my $length, my $string) = @_; # Gesamtlänge des Strings, String
        for (my $count = $length - length($string); $count>0; --$count)
        {
                $string = "0$string";
        }
        return $string;
}

sub daemonize {
	chdir("/") || die "can't chdir to /: $!";
	open(STDIN, "< /dev/null") || die "can't read /dev/null: $!";
	open(STDOUT, "> /dev/null") || die "can't write to /dev/null: $!"; # Siehe hier.
	defined(my $pid = fork()) || die "can't fork: $!";
	exit if $pid; # non-zero now means I am the parent
	(setsid() != -1) || die "Can't start a new session: $!";
	open(STDERR, ">&STDOUT") || die "can't dup stdout: $!";
}

# Exittask
sub exittsk
{
	foreach(@threads)
	{
		$_->detach;
	}
	exit 0;
}

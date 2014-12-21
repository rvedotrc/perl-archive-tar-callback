#!/usr/bin/perl -w
# vi: set ts=4 sw=4 :

use warnings;
use strict;

package Archive::Tar::Callback;

my $tar_unpack_header 
    = 'A100 A8 A8 A8 A12 A12 A8 A1 A100 A6 A2 A32 A32 A8 A8 A155 x12';
my $tar_header_length = 512;

## Subroutines to return type constants 
sub FILE() { return 0; }
sub HARDLINK() { return 1; }
sub SYMLINK() { return 2; }
sub CHARDEV() { return 3; }
sub BLOCKDEV() { return 4; }
sub DIR() { return 5; }
sub FIFO() { return 6; }
sub SOCKET() { return 8; }
sub UNKNOWN() { return 9; }

sub read
{
	my $class = shift;
	my $fh = shift;
	my $callback = shift;

    my ($head, $offset, $size);

	$class->readin($fh, \$head, $tar_header_length);

    $offset = $tar_header_length;

 READLOOP:
	while (length ($head) == $tar_header_length) {

		#my $h = $head;
		#$h =~ tr/ -~/./c;
		#print "head=[$h]\n";

		my ($name,		# string
			$mode,		# octal number
			$uid,		# octal number
			$gid,		# octal number
			$size,		# octal number
			$mtime,		# octal number
			$chksum,		# octal number
			$type,		# character
			$linkname,		# string
			$magic,		# string
			$version,		# two bytes
			$uname,		# string
			$gname,		# string
			$devmajor,		# octal number
			$devminor,		# octal number
			$prefix) = unpack ($tar_unpack_header, $head);
		my ($data, $block, $entry);

		$mode = oct $mode;
		$uid = oct $uid;
		$gid = oct $gid;
		$size = oct $size;
		$mtime = oct $mtime;
		$chksum = oct $chksum;
		$devmajor = oct $devmajor;
		$devminor = oct $devminor;
		$name = $prefix."/".$name if $prefix;
		$prefix = "";
		# some broken tar-s don't set the type for directories
		# so we ass_u_me a directory if the name ends in slash
		$type = DIR
			if $name =~ m|/$| and $type == FILE;

		last READLOOP if $head eq "\0" x 512; # End of archive
		# Apparently this should really be two blocks of 512 zeroes,
		# but GNU tar sometimes gets it wrong. See comment in the
		# source code (tar.c) to GNU cpio.

		substr ($head, 148, 8) = "        ";
		my $chkok = (unpack ("%16C*", $head) == $chksum);

		require IO::ReadLimit;
		my $datafh = IO::ReadLimit->new($fh, $size);

		&$callback({
			name	=> $name,		# string
			mode	=> $mode,		# octal number
			uid		=> $uid,		# octal number
			gid		=> $gid,		# octal number
			size	=> $size,		# octal number
			mtime	=> $mtime,		# octal number
			chksum	=> $chksum,		# octal number
			chkok	=> $chkok,		# boolean
			type	=> $type,		# character
			linkname=> $linkname,	# string
			magic	=> $magic,		# string
			version	=> $version,	# two bytes
			uname	=> $uname,		# string
			gname	=> $gname,		# string
			devmajor=> $devmajor,	# octal number
			devminor=> $devminor,	# octal number
			prefix	=> $prefix,
			offset	=> $offset,
			data	=> $datafh,
		});
		
		# consume the rest of the data in $datafh
		for (;;)
		{
			my $r = sysread($datafh, my $buffer, 1024);
			last if $r == 0;
		}

		$offset += $size;

		# Pad to 512 byte block
		if (my $mod = ($size % $tar_header_length))
		{
			$class->readin($fh, \my $dummy, $tar_header_length-$mod);
			$offset += $tar_header_length-$mod;
		}

		# Guard against tarfiles with garbage at the end
		last READLOOP if $name eq ''; 

		$class->readin($fh, \$head, $tar_header_length);
		$offset += $tar_header_length;
	}
}

sub readin
{
	my ($class, $fh, $dataref, $size) = @_;
	#my $tell = sysseek($fh, 0, 1);
	#defined($tell) or die $!;
	#print "Reading $size bytes from position $tell\n";
	$$dataref = "";
	while ($size)
	{
		my $r = sysread($fh, $$dataref, $size, length($$dataref));
		defined $r or die $!;
		return if $r == 0;
		$size -= $r;
	}
	$size==0 or die;
	#print "Read ".length($$dataref)." bytes\n";
}

return 1 if caller;
eval do { local $/; <DATA> }; die $@ if $@;
__DATA__

package main;
Archive::Tar::Callback::read(
	\*STDIN,
	sub {
		my $args = shift;
		use Data::Dumper;
		#print Data::Dumper->Dump([ \$args ],[ 'args' ]);
		$DB::single = 1;
		printf "%-50.50s  %12d  %-20.20s %d\n",
			$args->{name}, $args->{size},
			scalar(gmtime $args->{mtime}),
			$args->{type},
			if 1;
		my $data = $args->{data};
		#while (<$data>) { print ">> $_"; }
		#while (defined(my $c = getc $data)) { print $c if 0 }

		for (;;)
		{
			my $l = 10 + int rand 100;
			my $buff = "INIT";
			my $r = sysread($data, $buff, $l);
			last if $r == 0;
			print $buff, "`";
		}
	},
);

1;
# eof Archive::Tar::Callback.pm

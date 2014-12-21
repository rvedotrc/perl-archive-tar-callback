#!/usr/bin/perl -w
# vi: set ts=4 sw=4 :

use strict;

# Given a filehandle which is open for sysread()ing,
# and a byte count, generate a tied filehandle based on the first one which
# allows the user to read no more than the specified number of bytes.
# Writing, seeking and closing are disallowed.

package IO::ReadLimit;

sub new
{
	my $class = shift;
	require IO::Handle;
	my $fh = IO::Handle->new;
	tie *$fh, $class, @_;
	$fh;
}

sub TIEHANDLE
{
	my ($class, $fh, $size) = @_;
	bless {
		FH=>$fh,
		BUFFER=>"",
		SIZE=>$size,
		EOF=>($size == 0),
	}, $class;
	# SIZE is amount of data we can still read from FH.
	# EOF is true as soon as there is no more data, i.e.
	# BUFFER is empty and SIZE is zero.
}

sub need
{
	my ($self, $need) = @_;
	# Ensure BUFFER contains at least $need bytes (unless we hit EOF)

	while (length($self->{BUFFER}) < $need)
	{
		return if $self->{SIZE} == 0;
		my $size = $self->{SIZE};
		$size = 1024 if $size > 1024;
		my $r = sysread($self->{FH}, $self->{BUFFER}, $size, length($self->{BUFFER}));
		defined $r or die $!;
		#printf STDERR "lb=%d size=%d ask=%d got=%d\n", length($self->{BUFFER}), $self->{SIZE}, $size, $r;
		die if $r == 0;
		$self->{SIZE} -= $r;
	}

	length($self->{BUFFER}) >= $need or die;
}

sub READLINE
{
	my $self = shift;
	return undef if $self->{EOF}; # hmm. undef, or ""?

	if (not defined $/)
	{
		# Slurp!
		$self->need(length($self->{BUFFER}) + $self->{SIZE});
		$self->{SIZE} == 0 or die;
		my $r = $self->{BUFFER};
		$self->{BUFFER} = "";
		$self->{EOF} = 1;
		return $r;
	}

	die if $/ eq "";

	# Keep filling BUFFER until either it contains $/, or
	# we run out of data (SIZE==0).
	for (;;)
	{
		my $i = index($self->{BUFFER}, $/);
		if ($i >= 0)
		{
			my $line = substr($self->{BUFFER}, 0, $i+length($/), "");
			$self->{EOF} = 1 if $self->{SIZE}==0 and $self->{BUFFER} eq "";
			return $line;
		}

		if ($self->{SIZE} == 0)
		{
			my $line = $self->{BUFFER};
			$self->{BUFFER} = "";
			$self->{EOF} = 1;
			return $line;
		}

		$self->need(length($self->{BUFFER})+1024);
	}
}

sub GETC
{
	my $self = shift;
	return undef if $self->{EOF};
	$self->need(1);
	my $c = substr($self->{BUFFER}, 0, 1, "");
	$self->{EOF} = 1 if $self->{SIZE}==0 and $self->{BUFFER} eq "";
	$c;
}

sub READ
{
	my ($self, $bufref, $len, $offset) = @_;
	$bufref = \$_[1];
	$self->need($len);

	if ($offset)
	{
		my $read = $len;
		$len = length($self->{BUFFER}) if $len > length($self->{BUFFER});
		substr($$bufref, $offset, length($$bufref)-$offset) = substr($self->{BUFFER}, 0, $len, "");
		$self->{EOF} = 1 if $self->{SIZE}==0 and $self->{BUFFER} eq "";
		return $len;
	} else {
		my $read = $len;
		$len = length($self->{BUFFER}) if $len > length($self->{BUFFER});
		$$bufref = substr($self->{BUFFER}, 0, $len, "");
		$self->{EOF} = 1 if $self->{SIZE}==0 and $self->{BUFFER} eq "";
		return $len;
	}
}

sub CLOSE { 1 }
sub BINMODE { 1 }
sub EOF { $_[0]{EOF} }
sub FILENO { fileno $_[0]{FH} }

1;
# eof ReadLimit.pm

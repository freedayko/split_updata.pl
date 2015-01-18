#!/usr/bin/perl
######################################################################
#
#   File          : split_updata.pl
#   Author(s)     : McSpoon
#   Description   : Unpack a Huawei U8220 'UPDATA.APP' file.
#                   http://pulse.modaco.com
#
#   Last Modified : Thu 24 December 2009
#   By            : McSpoon
#
#   Last Modified : Wed 18 June 2010
#   By            : ZeBadger (z e b a d g e r @ h o t m a i l . c o m)
#   Comment       : Added filename selection
#
#   Last Modified : Wed 19 June 2010
#   By            : ZeBadger (z e b a d g e r @ h o t m a i l . c o m)
#   Comment       : Added CRC checking
#
#   Last Modified : Wed 18 January 2015
#   By            : FreeDayKo (f r e e d a y k o @ g i t h u b . c o m)
#   Comment       : Update for new firmware type
#
######################################################################
 
use strict;
use warnings;

my $CRC_CHECK= -e "crc" && -x _;
 
# Turn on print flushing.
$|++;
 
# Unsigned integers are 4 bytes.
use constant UINT_SIZE => 4;
 
# If a filename wasn't specified on the commmand line then
# assume the file to be unpacked is called "UPDATA.APP". 
my $FILENAME = undef;
if ($#ARGV == -1) {
	$FILENAME = "UPDATA.APP";
}
else {
	$FILENAME = $ARGV[0];
}
 
open(INFILE, $FILENAME) or die "Cannot open $FILENAME: $!\n";
binmode INFILE;
 
# Skip the first 92 bytes, they're blank.
#seek(INFILE, 92, 0);
 
# We'll dump the files into a folder called "output".
my $fileLoc=0;
my $BASEPATH = "output/";
mkdir $BASEPATH;

while (!eof(INFILE))
{
	$fileLoc=&find_next_file($fileLoc);
	seek(INFILE, $fileLoc, 0);
	$fileLoc=&dump_file();
}

close INFILE;
 

# Find the next file block in the main file
sub find_next_file
{
	my ($_fileLoc) = @_;
	my $_buffer = undef;
	my $_skipped=0;

	read(INFILE, $_buffer, UINT_SIZE);
	while ($_buffer ne "\x55\xAA\x5A\xA5" && !eof(INFILE))
	{
		read(INFILE, $_buffer, UINT_SIZE);
		$_skipped+=UINT_SIZE;
	}

	return($_fileLoc + $_skipped);
}
 
# Unpack a file block and output the payload to a file.
sub dump_file {
    my $buffer = undef;
    my $outfilename = undef;
    my $fileSeq;
    my $calculatedcrc = undef;
    my $sourcecrc = undef;
    my $fileChecksum;
 
    # Verify the identifier matches.
    read(INFILE, $buffer, UINT_SIZE); # Packet Identifier
    unless ($buffer eq "\x55\xAA\x5A\xA5") { die "Unrecognised file format. Wrong identifier.\n"; }
    read(INFILE, $buffer, UINT_SIZE); # Packet Length. Little endian 32bit long
    my ($headerLength) = unpack("V", $buffer);
    read(INFILE, $buffer, UINT_SIZE); # Always 1
    read(INFILE, $buffer, 8);         # Hardware ID
    read(INFILE, $buffer, UINT_SIZE); # ??? ex FILE SEQ
    read(INFILE, $buffer, UINT_SIZE); # Data file length
    my ($dataLength) = unpack("V", $buffer);
    read(INFILE, $buffer, 16);        # File date
    read(INFILE, $buffer, 16);        # File time
    read(INFILE, $fileSeq,  32);# File NAME
    $outfilename = unpack("A32", $fileSeq);

#   
    read(INFILE, $buffer,  2);
    read(INFILE, $buffer,  UINT_SIZE);

    # Grab the checksum of the file
    read(INFILE, $fileChecksum, $headerLength-98);
    $sourcecrc=slimhexdump($fileChecksum);
    
    # Dump the payload.
    read(INFILE, $buffer, $dataLength);
    open(OUTFILE, ">$BASEPATH$outfilename") or die "Unable to create $outfilename: $!\n";
    binmode OUTFILE;
    print OUTFILE $buffer;
    close OUTFILE;

    $calculatedcrc=`./crc $BASEPATH$outfilename` if $CRC_CHECK;
    chomp($calculatedcrc) if $CRC_CHECK;

    print STDOUT "Extracted $outfilename";
    print "\n" if !$CRC_CHECK;
    if($CRC_CHECK){
    	if ($calculatedcrc eq $sourcecrc)
	{
		print " - CRC Okay\n";
	}
	else
	{
		print " - ERROR: CRC did not match\n";
	}
    }
    
	$buffer = substr($buffer, 0, 4);
	if ($buffer eq "\x3A\xFF\x26\xED") { # Ext4 Sparce
	    `simg2img $BASEPATH$outfilename $BASEPATH\L$outfilename.img`;
	    unlink "$BASEPATH$outfilename";
	} elsif ($buffer eq "\xEB\x3C\x90\x4D") { # Fat16
	    rename "$BASEPATH$outfilename", "$BASEPATH\L$outfilename.img";
	} elsif ($buffer eq "\x41\x4E\x44\x52") { # Android recovery?
	    rename "$BASEPATH$outfilename", "$BASEPATH\L$outfilename.img";
	}
	
    # Ensure we finish on a 4 byte boundary alignment.
    my $remainder = UINT_SIZE - (tell(INFILE) % UINT_SIZE);
    if ($remainder < UINT_SIZE) {
    	# We can ignore the remaining padding.
    	read(INFILE, $buffer, $remainder);
    }
    
    return (tell(INFILE));
}

sub hexdump ()
{
        my $num=0;
        my $i;
        my $rhs;
        my $lhs;
        my ($buf) = @_;
        my $ret_str="";

        foreach $i ($buf =~ m/./gs)
        {
                # This loop is to process each character at a time.
                #
                $lhs .= sprintf(" %02X",ord($i));

                if ($i =~ m/[ -~]/)
                {
                        $rhs .= $i;
                }
                else
                {
                        $rhs .= ".";
                }

                $num++;
                if (($num % 16) == 0)
                {
                        $ret_str.=sprintf("%-50s %s\n",$lhs,$rhs);
                        $lhs="";
                        $rhs="";
                }
        }
        if (($num % 16) != 0)
        {
                $ret_str.=sprintf("%-50s %s\n",$lhs,$rhs);
        }

	return ($ret_str);
}
        
sub slimhexdump ()
{
        my $i;
        my ($buf) = @_;
        my $ret_str="";

        foreach $i ($buf =~ m/./gs)
        {
                # This loop is to process each character at a time.
                #
                $ret_str .= sprintf("%02X",ord($i));
        }

	return ($ret_str);
}

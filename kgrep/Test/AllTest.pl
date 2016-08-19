#!/usr/bin/perl -w

use strict;
use warnings;

sub main
{
   print test( "Color" );
   print test( "File" );
}

main;

sub test
{
   my $type = $_[0];
   my $typeHandler = $type . 'TestHandler.pl';
   my $i = `./$typeHandler`;
   my $failureFlag = 0;
   my $typeOutput = $type . "Output/" . $type . "TestOutput";
   
   for my $j ( 1 .. $i )
   {
      my $x = `./$typeHandler $j > tmpOutput`;
      $x = `diff tmpOutput $typeOutput$j`;
      if( $x ne "" )
      {
         print "Failed on case $j\n";
	 $failureFlag = 1;
      }
   }
   `rm tmpOutput`;
   if( !$failureFlag )
   {
      return "Success!\n";
   }
}

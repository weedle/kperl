#!/usr/bin/perl -w

package Kgrep::FileModule;

use strict;
use warnings;

use Path::Class;
use Scalar::Util qw( looks_like_number );
use Kgrep::ColorModule;
use Package::Alias KCM => 'Kgrep::ColorModule';

# Array: files
# files stores all the files in each file list
# These can be added manually and from the search commands
# It's a two dimensional array, the first index selects which list, and the second
# index indexes into the specified file list
my @files = ();

# Array: fileResults
# fileResults stores the lines containing search parameters for the previous search
# The first index chooses which file, and the second one chooses which line
my @fileResults;

# Array: fileResultsTally
# fileResultsTally contains the number of lines containing search parameters for
# each file from the previous search
my @fileResultsTally;


# Function: emptyFiles
# purpose: this function empties the current list of files
#    (we don't want this being done outside of the moedule,
#    even if it's a trivial operation)
# parameters: none
# output: none
sub emptyFiles
{
   @files[0] = ();
}

# Function: fileListExists
# purpose: check if file lists given are legit
# parameters:
#    param1 [Array]: params is a list of file list numbers
# output: 0 if anything is wrong, 1 if the file lists given are fine
sub fileListExists
{
   my @params = @_;
   if( @params <= 0 )
   {
      print KCM::formatErr( "Please supply a file list\n" );
      return 0;
   } 
   #check if the file list we've been given is legit
   if( @params >= 1 ) {
      # in case kgrep was just started up, and @files is totally empty
      if( !@files ) {
         print KCM::formatErr( "No file lists are available\n" );
         return 0;
      }
      # check if we've been given a valid number
      if( !isNumber( $_[0] ) ) {
         print KCM::formatErr( "Please provide a valid number for file list index\n" );
         return 0;
      }
      # check if valid number isn't too high or negative
      if( ( $_[0] < 0 ) || ( $_[0] >= @files ) ) {
         print KCM::formatErr( "File list index provided (" );
         print KCM::formatNum( $_[0] );
         print KCM::formatErr( ") is out of range (" );
         print KCM::formatNum( "0" );
         print KCM::formatErr( " to " );
         print KCM::formatNum( @files - 1 );
         print KCM::formatErr( ")\n" );
         return 0;
      }
      # check if corresponding file list exists
      if( !$files[$_[0]] ) {
         print KCM::formatText( "File list " );
         print KCM::formatNum( $_[0] );
         print KCM::formatErr( " does not exist\n" );
         return 0;
      }
   }
   return 1;
}

# Function: fileExists
# purpose: check if files given are legit
# parameters:
#    param1 [Array]: first element is a file list index, rest are file indicies
# output: 0 if anything is wrong, 1 if the files are all legit
sub fileExists
{
   my @params = @_;
   if( @params < 2 )
   {
      print KCM::formatErr( "Please supply a file list and one or more files\n" );
      return 0;
   } 
   if( !fileListExists( $_[0] ) ) {
      return 0;
   }
   # file list now guaranteed to be good
   # check individual files in list
   if( @params >= 2 ) {
      for my $i ( 1 .. @_-1 ) {
         # check if we've been given a valid number
         if( isNumber( $_[$i] ) ) {
            # check if valid number isn't too high or negative
            if( ( $_[$i] < 0 ) || ( $_[$i] >= @{$files[$_[0]]} ) ) {
	       print KCM::formatErr( "File list index provided (" );
	       print KCM::formatNum( $_[$i] );
	       print KCM::formatErr( ") is out of range (" );
	       print KCM::formatNum( "0" );
	       print KCM::formatErr( " to " );
	       print KCM::formatNum( @{$files[$_[0]]} - 1 );
	       print KCM::formatErr( ")\n" );
               return 0;
            }
         }
         # note: if not a number, that's okay! we allow specifying file names
         # no need to check for existence specifically, files in lists always go from 0 ...  n
      }
   }
   # all checks passed!
   # pass is silent because a lot of other functions will call this
   # we don't want to cause noise for successful calls, but we do want to fail visibly
   return 1;
}

# Function: isNumber
# purpose: just a shortcut to get looks_like_number without
#    checking for inf every time
# parameters:
#    $_[0] is the number to check
# output: 0 if number, 1 if fine
sub isNumber
{
   if( looks_like_number( $_[0] ) &&
     ( ( $_[0] ne "inf" ) && ( $_[0] ne "infinity" ) ) ) {
      return 1;
   }
   return 0;
}

# Function: fileListList
# purpose: list all file lists
# parameters: none
# output: each list of files and their size
sub fileListList
{
   if( !@files ) {
      print KCM::formatErr( "No files in memory.\n" );
      return;
   }
   print KCM::formatNum( "Files in memory:\n" );
   for my $i ( 0 .. @files - 1 ) {
      my $filesNum = 0;
      if( fileListExists( $i ) ) {
	 my @list = @{$files[$i]};
	 for my $j ( @list ) {
	    $filesNum += 1;
	 }
         print KCM::formatText( "File list " );
         print KCM::formatNum( $i );
         print KCM::formatText( " has " );
         print KCM::formatFile( $filesNum );
         print KCM::formatText( " files.\n" );
      }
   }  
}

# Function: fileList
# purpose: list the current list of files
# parameters: none
# output: all the files in the current list
sub fileList
{
   fileListNonPrimary( 0 );
}

# Function: fileListNonPrimary
# purpose: list a specific file list
# parameters: $_[0] is a specific list
# output: fileList, but for the specific list
sub fileListNonPrimary
{
   if( !fileListExists( @_ ) ) {
      return;
   } 
   my $mainList = $files[$_[0]];
   for my $i ( 0 .. @{$mainList} - 1 )
   {
      my $iC = KCM::formatNum( $i );
      my $fileNameC = KCM::formatFile( $files[$_[0]][$i] ); 
      print $iC . ".\t" . $fileNameC . "\n";
   }
}

# Function: fileListType
# purpose: add all files of a certain extension/ending
#    to the current llist
# parameters: $_ is the suffix, or ending thing
# output: none
sub fileListType
{
   @files[0] = ();
   @fileResults = ();
   @fileResultsTally = ();
   for ( @_ )
   {
      push ( @{$files[0]}, `ls *.$_` );
   }
   my $i = 0;
   for my $file ( @{$files[0]} )
   {
      $file = file( $file )->absolute();
      chomp( $file );
      $fileResultsTally[ $i ] = 0;
      $i++;
   }
   fileList();
} 

# Function: fileListCreate
# purpose: create a file list
# parameters: @_ is a bunch of files
# output: nada
sub fileListCreate
{
   if ( @_ == 0 ) {
      print KCM::formatErr( "No parameters provided\n" );
      return;
   }
   fileListCreateNonPrimary( 0, @_ );
}

# Function: fileListCreateNonPrimary
# purpose: create a file list at the specified list index
# parameters: $_[0] is the index of the list, rest of array is files
# output: nada
sub fileListCreateNonPrimary
{
   if ( @_ < 2 ) {
      print KCM::formatErr( "Please provide a file list index and one or more valid files\n" );
      return;
   }
   # catches edge case for trying to create primary file list
   # from primary file list (look someone will try it)
   if( $_[0] != 0 )
   {
      @files[$_[0]] = ();
      my $pos = 0;
      for my $i ( 1 .. @_ - 1 )
      {
         my $curVal = $_[$i];
         if( isNumber( $curVal ) )
         {
            if( !fileExists( 0, $curVal ) ) {
               next;
            }
            $files[$_[0]][$pos] = $files[0][$curVal];
         } else {
            $files[$_[0]][$pos] = file( $_[$i] )->absolute();
         }
         $pos++;
      }
   } else {
      my @filesBackup = ();
      if( $files[0] ) {
         @filesBackup = @{$files[0]};
      }
      @files[$_[0]] = ();
      # edge case handling
      my @fileResultsOld = @fileResults;
      my @fileResultsTallyOld = @fileResultsTally;
      @fileResults = ();
      @fileResultsTally = ();
      my $pos = 0;
      for my $i ( 1 .. @_ - 1 )
      {
         my $curVal = $_[$i];
         if( isNumber( $curVal ))
         {
            if ( @filesBackup == 0 ) {
               print KCM::formatErr( "Primary file list is uninitialized\n" );
               return 0;
            }
            if( ( $curVal < 0 ) || ( $curVal >= @filesBackup ) ) {
               print KCM::formatErr( "File list index provided (" );
	       print KCM::formatNum( $curVal );
	       print KCM::formatErr( ") is out of range (" );
	       print KCM::formatNum( "0" );
	       print KCM::formatErr( " to " );
	       print KCM::formatNum( @filesBackup - 1 );
	       print KCM::formatErr( ")\n" );
               return 0;
            }

            $files[$_[0]][$pos] = $filesBackup[$curVal];
            if( @fileResultsOld ) {
               if( $fileResultsOld[$curVal] ) {
                  @{$fileResults[$pos]} = @{$fileResultsOld[$curVal]};
                  $fileResultsTally[$pos] = $fileResultsTallyOld[$curVal];
               } else {
               $fileResultsTally[$pos] = 0;
               }
            } 
         } else {
            $files[$_[0]][$pos] = file( $_[$i] )->absolute();
         }
         $pos++;
      }
   }
}

# Function: fileListAdd
# purpose: add some files to the current list
# parameters: @_ is a bunch of files
# output: none
sub fileListAdd
{
   fileListAddNonPrimary(0, @_);
}

# Function: fileListAddNonPrimary
# purpose: add some files to a specific list
# parameters: $_[0] is a list index, rest of array is files
# output: none
sub fileListAddNonPrimary
{
   if( @_ == 0 ) {
      print KCM::formatErr( "Specify a file list number.\n" );
      return;
   }
   my $listNum = $_[0];
   for my $i ( 1 .. @_ - 1 )
   {
      my $curVal = $_[$i];
      if( !fileListExists( $listNum ) ) {
	 return;
      }
      if( !fileExists( 0, $curVal ) ) {
	 next;
      }

      if( looks_like_number( $curVal ) &&
         !( ( $curVal < 0) || ( $curVal >= @{$files[0]} ) ) &&
         ( ( $curVal ne "inf" ) && ( $curVal ne "infinity" ) ) )
      {
	 $files[$listNum][@{$files[$listNum]}] = $files[0][$curVal];
      } else {
         $files[$listNum][@{$files[$listNum]}] = file( $curVal )->absolute();
      }
   }
}

# Function: fileListRemove
# purpose: remove some files from the current list
# parameters: @_ is a bunch of file indices
# output: none
sub fileListRemove
{
   fileListRemoveNonPrimary(0, @_);
}

# Function: fileListRemoveNonPrimary
# purpose: remove some files from a specified list
# parameters: $_[0] is a file list index, rest of array is files
# output: none
sub fileListRemoveNonPrimary
{
   if( @_ == 0 ) {
      print KCM::formatErr( "Specify a file list number.\n" );
      return;
   }
   if( !fileListExists( $_[0] ) ) {
      print KCM::formatErr( "Please specify a valid file list.\n" );
      return;
   }
   if( @_ < 2 ) {
      print KCM::formatErr( "Please specify one or more files.\n" );
      return;
   }
   my $listNum = $_[0];
   my @not = @_[ 1 .. @_ - 1 ];
   my @allFiles = 0 .. @{$files[$listNum]}-1;

   for my $n ( @not ) {
      my $index = first_index{ $_ < @allFiles && $allFiles[ $_ ] == $n } @allFiles;
      if( $index != -1 ) {
         $allFiles[ $index ]  = -1;
         #splice( @allFiles, $index, 1 );
      } else {
         print KCM::formatErr( "Failed to remove file number " );
         print KCM::formatNum( "$n\n" );
      }
   }

   my @newList;

   for $a ( @allFiles ) {
      if( $a != -1 ) {
	 $newList[ @newList ] = $files[$listNum][$a];
      }
   }

   @{$files[$listNum]} = @newList;
}

# Function: fileSpecific
# purpose: list all the results for some files in the current list
# parameters: @_ is the list of file indices
# output: search results, with highlighting, for those files
sub fileSpecific
{  
   if( @_ == 0 )
   {
      print KCM::formatErr( "Supply file numbers for details.\n" );
      return;
   }
   if( !fileListExists( 0 ) ) {
      return;
   }
   if( $_[0] eq "*" )
   {
      for my $i ( 0 .. @{$files[0]} - 1 )
      {
         my $fileNum = $i;
         print KCM::formatNum( "File: " );
         print KCM::formatFile( $files[0][$fileNum] . "\n" );
         if( !@fileResultsTally ){
            print KCM::formatText( "No results.\n" );
         } else {
            for my $i ( 1 .. $fileResultsTally[$fileNum] )
            {
               print $fileResults[$fileNum][$i] . "\n";
            }
         }
      }
   }
   else
   {
      for my $j ( 0 .. @_ - 1 )
      {
         my $i = $_[$j];
         if( looks_like_number( $i ) && ( $i >= 0 ) && ( $i < scalar(@{$files[0]}) ) )
         {
            my $fileNum = $i;
            print KCM::formatNum( "File: " );
            print KCM::formatFile( $files[0][$fileNum] . "\n" );
            if( !@fileResultsTally ){
               print KCM::formatText( "No results.\n" );
            } else {
               for my $i ( 1 .. $fileResultsTally[$fileNum] )
               {
                  print $fileResults[$fileNum][$i] . "\n";
               }
            } 
	 } else {
	    print KCM::formatErr( "File number " );
	    print KCM::formatNum( $i );
	    print KCM::formatErr( " is invalid.\n" );
	 }
      }
   }
}

# Function: useNonPrimary
# purpose: set a specified list as the current list
# parameters: $_[0] is the new index
# output: none
sub useNonPrimary
{
   if( @_ == 0 ) {
      print KCM::formatErr( "Please specify a file list.\n" );
   }
   my $listNumber = $_[0];
   if( !fileListExists( $listNumber ) ) {
      return;
   }
   my @temp = @{$files[$listNumber]};
   @{$files[$listNumber]} = @{$files[0]};
   @{$files[0]} = @temp;
}



# Function: setFile
# purpose: set a specific file in a specific list
# parameters: $_[0] is the list number
#             $_[1] is the file mumber
#             $_[2] is the file
# output: none
sub setFile
{
    $files[$_[0]][$_[1]] = $_[2];
}

# Function: chompFile
# purpose: chomp a specific file
# parameters: $_[0] is the list number
#             $_[1] is the file mumber
# output: none
sub chompFile
{
   chomp( $files[$_[0]][$_[1]] );
}

# Function: getFiles
# purpose: return file array
# parameters: none
# output: none
sub getFiles
{
   return @files;
}

# Function: setFile
# purpose: set the file array
# parameters: $_[0] is a reference to the new file array
# output: none
sub setFiles
{
   @files = @{$_[0]};
}

# Function: listContains
# purpose: search through a file list for a specific file
# parameters: $_[0] is a list index
#             $found is an absolute file path
# output: 1 if found, 0 if not found
sub listContains
{
   my $found = 0;
   my $searchFor = $_[1];
   for my $file ( @{$files[$_[0]]} ) {
      if( file( $file )->absolute() =~ m/$_[1]/ )
      {
         $found = 1;
	 last;
      }
   }
   return $found;
}
return 1;

#!/usr/bin/perl -w
use strict;
use warnings;
use threads;
use Thread::Running;
use Path::Class;
use Switch;
use Scalar::Util qw( looks_like_number );
use List::MoreUtils 'first_index';
use Tree::DAG_Node;
use IO::Prompter;
use POSIX;

#use Kgrep::ColorModule;
#use Package::Alias KCM => 'Kgrep::ColorModule';

use Kgrep::FileModule;
use Package::Alias KFM => 'Kgrep::FileModule';

# Array: lineHistory
# lineHistory is used in the "c" command, which lets you quickly run previous ommands
my @lineHistory = ();

# Scalar: lineHistMax
# lineHistMax is the max number of lines to store, which can be accessed with the "c"
# command
my $lineHistMax = 16;

# Scalar: context
# context displays the specified number of lines around each search result
# This means lines above and below a line containing a search result will also be
# displayed
my $context = 0;

# Scalar: defaultLsColNum
# defaultLsColNum chooses how many columns to use when displaying the results of the
# "ls" command
# the "auto" setting means the number of columns displayed is automatically displayed
# based on the terminal width
my $defaultLsColNum = "auto";


# Array: fileResults
# fileResults stores the lines containing search parameters for the previous search
# The first index chooses which file, and the second one chooses which line
my @fileResults;

# Array: fileResultsTally
# fileResultsTally contains the number of lines containing search parameters for
# each file from the previous search
my @fileResultsTally;

# Array: completionList
# completionList contains the various functions you can call from the kgrep command
# line. Mainly used for tab completion
my @completion_list = ( "search", "searchlist", "help", "vim", "filelist", "filelistnonprimary", "filelistadd", "filelistaddnonprimary", "filelistcreate", "filelistcreatenonprimary", "filelistype", "filespecific", "quit", "highlightcat", "constants" ); 

# Scalar: tree
# Initially meant for shell completion, but that was replaced with the implmentation
# built into IO:Prompter
# Now used to display a file list as a hierarchy
my $tree;

# Scalar: singleCommand
# enables/disables single command mode
# Single command mode is used when you run something like "kgp s penguin"
# Instead of launching the kgrep shell, it will only run that command, and you stay
# in your original terminal
# The file list is saved to a directory determined by an environmental variable
# You can access the results with "kgp s fl" and similar commands
my $singleCommand = 0;

# Scalar: singleCommandModeDir
# The environmental variable that decides where to store temporary files
# This allows you to run commands in kgrep as if they were stand-alone programs
# It needs to link to a writable folder
my $singleCommandModeDir = $ENV{ 'KPERLSCMDIR' };

# Hash: functions
# contains every function that can be accessed from the command line
# also defines shortcuts
# I may make these shortcuts customizable sometime
# files that aren't described in help are labeled as #undocumented
my %functions = (
   s => \&search,
   search => \&search,
   sl => \&searchList,
   searchlist => \&searchList,
   f => \&find,
   find => \&find,
   h => \&help,
   help => \&help,
   v => \&openv,
   vim => \&openv,
   hcat => => \&highlightcat,
   highlightcat => \&highlightcat,
   c => \&showHistory,
   commandlist => \&showHistory,
   con => \&constants,
   constants => \&constants,
   sep => \&separationOfVariables,
   cd => \&cd,
   fh => \&fileHierarchy,
   filehierarchy => \&fileHierarchy,
   pwd => \&pwd,
   ls => \&ls,
   list => \&ls,
   test => \&test,                        #undocumented
   test2 => \&test2,                      #undocumented
   test3 => \&test3,                      #undocumented
   ef => \&fileExists,                     #undocumented
   el => \&fileListExists,                     #undocumented
   about => \&about,                      #undocumented
   fl => \&fileList,
   filelist => \&fileList,
   filelistlist => \&fileListList,
   fll => \&fileListList,
   fc => \&fileListCreate,
   filelistcreate => \&fileListCreate,
   fa => \&fileListAdd,
   filelistadd => \&fileListAdd,
   fr => \&fileListRemove,
   filelistremove => \&fileListRemove,
   frs => \&fileListRemoveNonPrimary,
   filelistremovenonprimary => \&fileListRemoveNonPrimary,
   fls => \&fileListNonPrimary,
   ft => \&fileListType,
   filelisttype => \&fileListType,
   filelistnonprimary => \&fileListNonPrimary,
   fcs => \&fileListCreateNonPrimary,
   filelistcreatenonprimary => \&fileListCreateNonPrimary,
   fas => \&fileListAddNonPrimary,
   filelistaddnonprimary => \&fileListAddNonPrimary,
   fs => \&fileSpecific,
   filespecific => \&fileSpecific,
   us => \&useNonPrimary,             #undocumented
   usenonprimary => \&useNonPrimary,  #undocumented
   save => \&saveFile,                #undocumented
   load => \&readFile,                #undocumented
   q => \&quit,
   quit => \&quit,
);
# Hcat constants!
# how far m scrolls forward in hcat
my $mDist = 20;
# Whether the standard help line is displayed during hcat, or a progress bar
my $progressBar = 0;
# The character that makes up the progressbar (I find # works best)
my $progressChar = "#";
my $delineationChar = "\"";

# helper fn to color a specific string
# parameters:
# param1 is the number used to determine the color
# param2 is the string to be colored
sub kcolor
{
   KCM::kcolor( @_ );
}

# helper fn to highlight occurrences of a specific term in a string
# param1 is used to pick the highlight color
# param2 is the string to be highlighted
# param3 is the line to be processed
sub highlight
{
   KCM::highlight( @_ );
}

# helper fn to process resulting file list from search
# param1 is a list of strings to highlight
# each one gets highlighted in a different color btw
# assuming you don't pass in too many strings
# param2 is the results from search
# it's a list of files and matching lines in a specific format
sub processResults
{
   my @params = @{$_[0]};
   my @results = @{$_[1]};
   my $oldFile = "";
   KFM::emptyFiles();
   my $fileNum = 0;
   my $resultLineNum = 0;
   my $resultCount;
   my $partialResult;
   for my $file ( @results )
   {
      my $result = $file;
      $file =~ s/[:-]\d+[:-].+//;
      $result =~ s/$file[:-](\d*)[:-](.*)/$2/;
      $resultLineNum = $1;
      if ( $file eq "--" )
      {
         print "\n";
      }
      if( ( $file ne "--" ) && !( $file =~ m/Binary file .+ matches/ ) )
      {
         if( $file ne $oldFile )
         {
            $resultCount = 0;
            KFM::setFile( 0, $fileNum, file( $file )->absolute() );
            KFM::chompFile( 0, $fileNum );
            print KCM::formatNum( $fileNum ) . "  " . KCM::formatFile( $file ) . "\n";
            $fileNum += 1;
            $oldFile = $file;
         }
         my $currLine = quotemeta $result;
         for my $i ( 0 .. @params - 1 )
         {
            if ( ( $currLine =~ m#$params[$i]# ) ) 
            {
               $partialResult = highlight( $i, $params[$i], $currLine );
               $currLine = $partialResult;
            }
         }
         $resultCount += 1;
         $currLine =~ s#\\##g;
         my $lineCountC = KCM::formatNum( $resultLineNum );
         $fileResults[$fileNum-1][$resultCount] = "\t$lineCountC\t" . $currLine;
         $fileResultsTally[$fileNum-1] = $resultCount;
         print "\t$lineCountC\t" . $currLine . "\n";
      }
   }
}

# saves the current list of files into a file in a specified directory
# the format is weird, and the output isn't really very human readable
# what with all the escaped color sequences
# but all that matters is that saveFile and readFile agree with each other
sub saveFile
{
   my $scmFileLoc = dir( $singleCommandModeDir );
   my $scmFile = $scmFileLoc->file( "tmpKgrep.txt" )->absolute();
   my $scmFh = $scmFile->open( ">" ) or die "failed to open $scmFile";
   my @files = KFM::getFiles();
   if( @files )
   {
      if( @{$files[0]} > 0 )
      {
         for my $i ( 0 .. @{$files[0]} - 1 )
         {
            my $fileNum = $i;
            print $scmFh "KGPFILE: $i:";
            print $scmFh $files[0][$fileNum];
            print $scmFh ":$i\n";
            for my $i ( 1 .. $fileResultsTally[$fileNum] )
            {
               print $scmFh "KGPRESULT: " . $fileResults[$fileNum][$i] . "\n";
            }
         }
      }
   }
   for my $i ( 1 .. @files - 1 )
   {
      for my $j ( 0 .. @{$files[$i]} - 1 )
      {
         my $fileNum = $j;
         print $scmFh "KGPFILE$i: $j:";
         print $scmFh $files[$i][$fileNum];
         print $scmFh ":$j\n";
      }
   }
}

# processes the file saved by saveFile
# if there isn't a file, then readFile won't do anything
sub readFile
{
   my $scmFileLoc = dir( $singleCommandModeDir );
   my $scmFile = $scmFileLoc->file( "tmpKgrep.txt" )->absolute();
   unless ( -e $scmFile ) { return; }
   my $scmFh = $scmFile->openr() or die "failed to open $scmFile";

   my @files;
   $files[0] = ();
   @fileResults = ();
   @fileResultsTally = ();
   my $fileNum = 0;

   while( my $line = $scmFh->getline() )
   {
      if( $line =~ m/KGPFILE: (\d+):(.*):\g1/)
      {
         $fileNum = $1;
         $fileResultsTally[ $fileNum ] = 0;
         $files[0][ $fileNum ] = $2;
      }
      elsif( $line =~ m/KGPFILE(\d+): (\d+):(.*):\g2/)
      {
         $fileNum = $2;
         $files[$1][ $fileNum ] = $3;
      }
      elsif( $line =~ m/KGPRESULT: (.*)/ )
      {
         $fileResultsTally[ $fileNum ]++;
         $fileResults[ $fileNum ][ $fileResultsTally[ $fileNum ] ] = $1;
      }
   }
   KFM::setFiles( \@files );
}

# fn to handle main search
# this launches grep and calls the function to process the results
sub search
{
   my @params = @_;
   if( @params == 0 )
   {
      print KCM::formatErr( "No search parameters provided.\n" );
      return;
   }
   #if( @params == 1 )
   #{
   #   $params[1] = $params[0];
   #}
   my $searchParam = $params[0];
   for my $i ( 0 .. @params - 1 )
   {
      $searchParam = $searchParam . "\\|$params[ $i ]";
   }
   $| = 1;
   my ($thr) = threads->new( 
      sub { 
         my @results = `grep \"$searchParam\" . -nsrC $context`;
         return \@results; } );
   while( $thr->running() ) {
      #print ".";
      select( undef, undef, undef, 2 );
   }
   $| = 0;
   print "\r";
   my @return = $thr->join();
   my @results = @{$return[0]};
   if ( 0 == @results )
   {
      print KCM::formatText( "No files found.\n" )
   }
   chomp(@results);
   processResults( \@params, \@results );
}

sub searchList
{
   my @files = KFM::getFiles();
   my @params = @_[ 1 .. @_- 1 ];
   if( @params < 1 )
   {
      print KCM::formatErr( "Insufficient parameters provided.\n" );
      return;
   }
   if ( !@files ) {
      print KCM::formatErr( "No file lists to search through.\n" );
      return;
   }
   my $fileNum = $_[0];
   if( !looks_like_number( $fileNum  ) || 
     ( $_[0] < 0 || $_[0] >= @files ) ) 
   {
      print KCM::formatErr( "Invalid file number provided.\n" );
      return;
   }
   if( @{$files[$fileNum]} == 0 )
   {
      print KCM::formatErr( "No files in file list.\n" );
      return;
   }
   my @fileParams;
   $fileParams[ 0 ] = $files[$fileNum][ 0 ];
   for my $i ( 1 .. @{$files[$fileNum]} - 1 )
   {
      my $file = $files[$fileNum][ $i ];
      $fileParams[ $i ] .= " " . $file;
   }
   my $searchParam = $params[0];
   for my $i ( 0 .. @params - 1 )
   {
      $searchParam = $searchParam . "\\|$params[ $i ]";
   }
   $| = 1;
   my ($thr) = threads->new(
      sub {
         my @results = `grep \"$searchParam\" -nsHC $context @fileParams`;
         return \@results; } );
   while( $thr->running() ) {
      print ".";
      select( undef, undef, undef, 2 );
   }
   $| = 0;
   print "\r";
   my @return = $thr->join();
   my @results = @{$return[0]};
   if ( 0 == @results )
   {
      print KCM::formatText( "No files found.\n" )
   }
   chomp( @results );
   processResults( \@params, \@results );
}

# helper fn for help to display help
sub helper
{
   my $command = $_[0];
   my $shortcut = $_[1];
   my $helpText = $_[2];
   print "     " . KCM::formatText( $command ) . "(" . KCM::formatText( $shortcut ) . "): " . $helpText;
}

# help fn to display... help
sub help
{
   my $second = 0;
   my $third = 0;
   my $text;
   if( @_ != 0 )
   {
      $second = $_[0];
   }
   if( @_ > 1 )
   {
      $third = $_[1];
   }
   if( @_ == 0 )
   {
      print "\n     Welcome to the grepshell console. Each command operates from the current directory and recursively.\n";
      print "     Each command has a shortcut, and their instructions for use will be displayed as such.\n";
      print "     Tab completion is now a feature!\n";
      print "     Press tab on a partially typed command to have the shell autocomplete your request for you :D\n";
      print "     Command (short form): Brief description of usage and function.\n";
      print "     For detailed instructions on a specific command, type 'help [command]', except without square brackets or single quotes.\n\n";

      $text = "This command requires at least one parameter. If one is provided, it will search recursively\n";
      $text .= "     and display a list of results. If multiple keywords are provided, the first one will be used to build\n";
      $text .= "     the list of files, and the rest of the keywords will be found and highlighted within those files.\n";
      $text .= "     Note: Each file result will be assigned a number for access until the next search.\n\n";
      helper( "search", "s", $text );

      $text = "This command requires at least one parameter. If one is provided, it will search recursively\n";
      $text .= "     This command is different from " . KCM::formatText( "search" ) . " in that it will only search through the current list of files (usually resulting from the last search.\n";
      helper( "searchlist", "sl", $text );
      
      $text = "This command lets you open a target file with the editor vim. If a number is provided, the\n";
      $text .= "     file from the previous search with the corresponding number will be opened. Otherwise, the command will\n";
      $text .= "     be executed as though the parameter were a file name.\n\n";
      helper( "vim", "v", $text );
      
      helper( "vim", "v", $text );
     

      $text = "Same find as in bash. But formatted differently and added to the file list.\n\n";
      helper( "find", "f", $text );

      $text = "This command will list all the files from the previous search, with their corresponding\n";
      $text .= "     file numbers down the left.\n";
      helper( "filelist", "fl", $text );
     
      $text = "This command will list all file lists and tell you how many files each one has.\n";
      helper( "filelistlist", "fll", $text );

      $text = "This command will list all the files from a specified list of files.\n";
      helper( "filelistnonprimary", "fls", $text );
 
      $text = "This command lets you add one or more files to the current list of files.\n";
      helper( "filelistadd", "fa", $text );
 
      $text = "This command lets you add one or more files to a specified list of files.\n";
      helper( "filelistaddnonprimary", "fas", $text );
 
      $text = "This command lets you remove one or more files from the current list of files.\n";
      helper( "filelistremove", "fr", $text );

      $text = "This command lets you remove one or more files from a specified list of files.\n";
      helper( "filelistremovenonprimary", "frs", $text );
 
      $text = "This command lets you create a current list of files.\n";
      helper( "filelistcreate", "fc", $text );
 
      helper( "filelistcreatenonprimary", "fcs", $text );
      $text = "This command lets you create a list of files.\n";

      $text = "This command lets you set the file list to all files in the current dir with the given filetypes.\n";
      helper( "filelisttype", "ft", $text );
 
      $text = "This command will list all the results specific to the file number(s) provided.\n\n";
      helper( "filespecific", "fs", $text );
      
      $text = "This command will open up a file in the console. You can press n to move forward\n";
      $text .= "     a line and q to go back to the shell.\n\n";
      helper( "highlightcat", "hcat", $text );
      
      $text = "This command will let you change constants specific to the grepshell.\n\n";
      helper( "constants", "con", $text );

      $text = "This command lets you view previous commands, up to a predetermined maximum.\n";
      $text .= "     You can redo a numbered command using r <number>\n\n";
      helper( "commandList", "c", $text );

      $text = "This command sets a specified list of files as the primary.\n";
      $text .= "     This will not update the results from filespecific.\n\n";
      helper( "usenonprimary", "us", $text );
      
      $text = "This exits the shell and returns you to the console.\n\n";
      helper( "quit", "q", $text );
      
      $text = "Type this to view these helpful instructions.\n\n";
      helper( "help", "h", $text );
   }
   elsif( @_ == 1 )
   {
      switch( $second )
      {
         case "search"
         {
            print "\n     So, search has two functions, depending on how many parameters you enter.\n";
            print "     If one keyword is entered, then search conducts a recursive grep on that term.\n";
            print "     All the results for that are processed and displayed in the following format.\n\n";
            
            
            print KCM::formatPrompt() . "s keyword\n";
            print "File Number   Filename:\n";
            my $egKeyword = kcolor( 0, "keyword" );
            
            print "\tLine Number\tLine with " . $egKeyword . " highlighted.\n";
            print "\tDifferent Line Number\tLine with " . $egKeyword . " highlighted.\n\n\n";
            print "Next File Number   Different Filename:\n";
            print "\tLine Number\tLine with " . $egKeyword . " highlighted.\n";
            print "\n     With multiple keywords, the first one is used to find the files, but all are highlighted.\n\n";

            
            print KCM::formatPrompt() . "s keyword secondKeyword thirdKeyword\n";  
            print "File Number   Filename:\n";
            my $egKeyword2 = kcolor( 1, "secondKeyword" );
            my $egKeyword3 = kcolor( 2, "thirdKeyword" );
            
            print "\tLine Number\tLine with " . $egKeyword3 . " highlighted.\n";
            print "\tDifferent Line Number\tLine with " . $egKeyword3 . " and " . $egKeyword . " and maybe also " . $egKeyword2 . " highlighted.\n";
           
            
            print "\n     And so on. The file numbers are used to easily access the file using other tools.\n";
            print "     For example, fs [file number] will show you all the results for that file again, and ge [file number]\n";
            print "     will open that file in gedit.\n";
            print "     Shortcut: " . KCM::formatText( "s" ) . "\n\n";
         }
         case "vim"
         {
            print "\n     This command functions the same way as in shell, it will open in vim the file whose filename is provided.\n";
            print "     You can also provide a file number instead, which is usually quicker.\n";
            print "     Shortcut: " . KCM::formatText( "v" ) . "\n\n";
         }
         case "list"
         {
            print "\n     This command is much like the shell command. The only difference in usage is that you can supply a number\n";
            print "     to determine the number of columns (2 by default). Folders are green, and files are varying shades from grey\n";
            print "     to blue depending on how recently they were accessed. Blue is for more recently accessed ones.\n";
            print "     Shortcut: " . KCM::formatText( "ls" ) . "\n\n";
         }
         case "find"
         {
            print "\n     This command is basically just the find command from shell. Use it as you would normally, and the resulting\n";
            print "     files will be added to the file list, viewable through filelist.";
            print "     Shortcut: " . KCM::formatText( "f" ) . "\n\n";
         }
         case "filelist"
         {
            print "\n     This command will list all the files from the previous search, in addition to their file numbers. File\n";
            print "     numbers go down the left, with their corresponding filenames down the right.\n";
            print "     Shortcut: " . KCM::formatText( "fl" ) . "\n";
            print "Sample Output:\n";
            print KCM::formatPrompt() . "fl\n";
            my $iC = KCM::formatNum( "0." );
            my $fileNameC = KCM::formatFile( "file1" );
            print $iC . "\t" . $fileNameC . "\n";
            $iC = KCM::formatNum( "1." );
            $fileNameC = KCM::formatFile( "file2" );
            print $iC . "\t" . $fileNameC . "\n";
            $iC = KCM::formatNum( "2." );
            $fileNameC = KCM::formatFile( "file3" );
            print $iC . "\t" . $fileNameC . "\n";
         }
         case "filelistlist"
         {
            print "\n     This command will list all file lists in sequential order, and tell you how many files are stored in\n";
            print "each one. Some sample output is shown below.\n";
            print "     Shortcut: " . KCM::formatText( "fll" ) . "\n";
            print "Sample Output:\n";
            print KCM::formatPrompt() . "fll\n";
            print KCM::formatText( "File list " );
            print KCM::formatNum( "0" );
	    print KCM::formatText( " has " );
	    print KCM::formatNum( "20" );
	    print KCM::formatText( " files.\n" );
         }
         case "filelistnonprimary"
         {
            print "\n     This command will list all the files from a specified list of files, in addition to their file numbers. File\n";
            print "     numbers go down the left, with their corresponding filenames down the right.\n";
            print "     Shortcut: " . KCM::formatText( "fls" ) . "\n";
            print "Sample Output:\n";
            print KCM::formatPrompt() . "fl\n";
            my $iC = KCM::formatNum( "0." );
            my $fileNameC = KCM::formatFile( "file1" );
            print $iC . "\t" . $fileNameC . "\n";
            $iC = KCM::formatNum( "1." );
            $fileNameC = KCM::formatFile( "file2" );
            print $iC . "\t" . $fileNameC . "\n";
            $iC = KCM::formatNum( "2." );
            $fileNameC = KCM::formatFile( "file3" );
            print $iC . "\t" . $fileNameC . "\n";
         }
         case "filelistadd"
         {
            print "\n     This command lets you add a file to the current list of files, perhaps for use with sl (searchList).\n";
            print "     Shortcut: " . KCM::formatText( "fa" ) . "\n";
         }
         case "filelistaddnonprimary"
         {
            print "\n     This command lets you add a file to a specified list of files. This would be useful if, say, you wanted to \n";
            print "keep a list of files to quickly reference and open, without having them be overwritten by a search.\n";
            print "     Shortcut: " . KCM::formatText( "fas" ) . "\n";
         }
         case "filelistcreate"
         {
            print "\n     This command lets you manually specify the entirety of the current list of files.\n";
            print "For an example usage, you could quickly search for a term through a few files you know the names of.\n";
            print "     Shortcut: " . KCM::formatText( "fa" ) . "\n";
         }
         case "filelistcreatenonprimary"
         {
            print "\n     This command lets you manually specify the entirety of a specified list of files.\n";
            print "I'd use this if I had a few files I wanted to keep on hand, that I could mess with later as needed.\n";
            print "     Shortcut: " . KCM::formatText( "fa" ) . "\n";
         }
         case "filelisttype"
         {
            print "\n     This command lets you quickly set the current list of files to all files in the current directory with the\n";
            print "     given file types. This is useful if you want to, say, go through all the cpp files in a dir with many types.\n";
            print "     Shortcut: " . KCM::formatText( "ft" ) . "\n";
         }
         case "filespecific"
         {
            print "\n     This command will display all the results for specific files from the previous search. Format is exactly\n";
            print "     the same as search, but limited to the listed file. Use filespecific * to print the results for all files.\n";
            print "     Shortcut: " . KCM::formatText( "fs" ) . "\n\n";
         }
         case "quit"
         {
            print "\n     This command will exit the shell, returning you to bash or wherever you were before this.\n";
            print "     Consider it a Ctrl+C.\n";
            print "     Shortcut: " . KCM::formatText( "q" ) . "\n\n";
         }
         case "highlightcat"
         {
            print "\n     This command is like cat in gedit, it will open a file and let you view it in the console. Press n to move\n";
            print "     forward a line, and q to quit. m will move foward a specific number of times, this can be changed through the \n";
            print "     constants command. a will scroll through the entire file and only stop when finished.\n";
            print "     Shortcut: " . KCM::formatText( "hcat" ) . "\n\n";
         }
         case "constants"
         {
            print "\n     This command lets you change constants use by the shell. Current constants you can modify include:\n";
            print "     mDist - This controls how many lines pressing m will process in highlightcat. By default 20.\n";
            print "     progressBar - This controls whether or not you see a progress bar instead of the little Press n/m/a\n";
            print "     line that you normally see when using hcat. 0 (disabled) by default, can be set to 1 to enable it.\n";
            print "     progressChar - This is the character that makes up the progress bar, by default #.\n";
            print "     delineationChar - This is the character used to group parameters in searches. By default, \"\n";
            print "     For example, if you wanted to search through files containing the phrase \"White Rabbit\" but only\n";
            print "     highlight the word Rabbit, you would type: s \"White Rabbit\" Rabbit\n";
            print "     context - This determines how much context to display in search results. You can view lines following\n";
            print "     search terms by setting this to a positive value.\n";
            print "     Shortcut: " . KCM::formatText( "con" ) . "\n\n";
         }
         case "help"
         {
            print "\n     This command will provide you with abundant helpful information the likes of the which you have never before\n";
            print "     seen. Simply replace the second help in your previous query with any other command, and recieve specific help\n";
            print "     for that command's usage.\n";
            print "     Shortcut: " . KCM::formatText( "h" ) . "\n\n";
         }
      }
   }
   elsif( @_ == 2 )
   {
      if( $second eq "help" && $third eq "help" )
      {
         print "\n     Ok, no, stoppit.\n";
      }
   }
}

# fn to open vim through shell
sub openv
{
   my @files = KFM::getFiles();
   if( @_ == 0 )
   {
      print KCM::formatText( "Supply a file/file number.\n" );
      return;
   } 
   if ( !$files[0] ) {
      print KCM::formatErr( "No files in lists.\n" );
      return;
   }
   my $fileNum = $_[0];
   if( !looks_like_number( $fileNum  ) ||                     # We need to use file numbers if provided, but also rule out inputs
      ( ( ( $fileNum < 0 ) || ( $fileNum >= @{$files[0]} ) ) ||        # that are technically considered numbers, like inf or infinity.
      !( ( $fileNum ne "inf" ) && ( $fileNum ne "infinity" ) ) ) )
   {
      printf KCM::formatErr( "Invalid file number. Max number is " . scalar @{$files[0]}-1 . "\n" );
   }
   else  # If a file name is provided, we should try that instead.
   {
      if( looks_like_number( $fileNum)  )
      {
         my $command =  "vim $files[0][$fileNum]";
         system( "$command" );
      }
      else
      {
         my $command =  "vim $fileNum";
         system( "$command" );     
      }
   }
}

# helper fn to process a specific line
sub hcatHelper
{
   my $lineCount = $_[0];
   my $fh = $_[1];
   my @params = @{$_[2]};
   if( defined( my $currLine = <$fh>)  )
   {
      my $tempLine = quotemeta( $currLine );
      $currLine = $tempLine;
      for my $i ( 1 .. @params - 1 )
      {
         if ( $currLine =~ m#$params[$i]# ) 
         {
             my $partialResult = highlight( $i, $params[$i], $currLine );
             $currLine = $partialResult;
         }
      }
      $lineCount += 1;
      $currLine =~ s#\\##g;
      my $lineCountC = KCM::formatNum( $lineCount );
      print "\e[K" . $lineCountC . "  " . $currLine;
   }
   else
   {
      return 0;
   }
}

# helper fn to update the progress line/bar
sub hcatUpdater
{
   my $lineCount = $_[0];
   my $fileSize = $_[1];
   my $progress = $lineCount/$fileSize;
   if ( $progressBar == 0 )
   {
      my $lineCol = 0;;

      if ( $progress > 0 )
      {
         $lineCol = kcolor( 4, $lineCount );
      }
      if ( $progress > 0.25 )
      {
         $lineCol = kcolor( 0, $lineCount );   
      }
      if ( $progress > 0.5 )
      {
         $lineCol = kcolor( 3, $lineCount );   
      }
      if ( $progress > 0.75 )
      {
         $lineCol = kcolor( 1, $lineCount );   
      }
      print "On line $lineCol/" . kcolor( 1, $fileSize ) . ", " . kcolor( 0, "n" ) . "/" . kcolor( 0, "m" ) . "/" . kcolor( 0, "a" ) . " to continue, " . kcolor( 0, "q" ) . " to quit\r";
   }
   else
   {
      my $soFar = int( $progress * 50 );
      my $toGo = 50 - $soFar;
      for my $i ( 1 .. $soFar )
      {
         if ( $progress > 0.75 )
         {
            print kcolor( 4, $progressChar );
         }
         elsif ( $progress > 0.50 )
         {
            print kcolor( 0, $progressChar );   
         }
         elsif ( $progress > 0.25 )
         {
            print kcolor( 3, $progressChar );   
         }
         elsif ( $progress > 0 )
         {
            print kcolor( 1, $progressChar );   
         }      
      }
      for my $i ( 1 .. $toGo )
      {
         print kcolor( 2, $progressChar );
      }
      print " $lineCount/$fileSize\r";
   }
}

# fn to cat a specific file with highlighting
sub highlightcat
{
   my @files = KFM::getFiles();
   if( @_ < 2 )
   {
      print KCM::formatErr( "Need more parameters.\n" );
      return;
   }
   if( !$files[0] )
   {
      print KCM::formatErr( "No files in primary list.\n" );
      return;
   }
   my $fileNum = $_[0];
   my @params = @_;
   use Term::ReadKey;
   ReadMode 4;
   my $key;
   my $file;
   if( looks_like_number( $fileNum ) && 
      ( ( $fileNum < 0 ) || ( $fileNum >= @{$files[0]} ) ) && 
      ( ( $fileNum ne "inf" ) && ( $fileNum ne "infinity" ) ) )
   {
      printf KCM::formatErr( "Invalid file number. Max number is " );
      print KCM::formatNum( scalar @{$files[0]}-1 ) . "\n";
      return;
   }
   else
   {
      if( looks_like_number( $fileNum ) )
      {
         $file =  $files[0][$fileNum];
      }
      else
      {
         $file =  $fileNum;   
      }
   }
   print $file . "\n";
   my $lineCount = 0;
   if ( open( my $fh, $file ) )
   {
      while( <$fh> ){}
      my $fileSize=$.;
      close( $fh );
      open( $fh, $file );
      $| = 1;
      while( 1 )
      {
         while ( not defined ( $key = ReadKey( -1 ) ) ) {}
         switch( $key )
         {
            case "q"
            {
               print "\n";
               close( $fh );
               return;
            }
            case "n"
            {
               if( hcatHelper( $lineCount, $fh, \@params)  )
               {
                  $lineCount += 1;
               }
               else
               {
                  close( $fh );
                  return;
               } 
               hcatUpdater( $lineCount, $fileSize );
            }
            case "m"
            {
               for my $i ( 1 .. $mDist )
               {
               if( hcatHelper( $lineCount, $fh, \@params ) )
                  {
                     $lineCount += 1;
                  }
                  else
                  {
                     print "\e[K" . "Finished!\n";
                     close( $fh );
                     return;
                  }
                  hcatUpdater( $lineCount, $fileSize );
                  select( undef, undef, undef, 0.025 );
               }
            }
            case "a"
            {
               while( 1 )
               {
                  if( hcatHelper( $lineCount, $fh, \@params ) )
                  {
                     $lineCount += 1;
                  }
                  else
                  {
                     print "\e[K" . "Finished!\n";
                     close( $fh );
                     return;
                  }              
                  hcatUpdater( $lineCount, $fileSize );  
                  #select( undef, undef, undef, 0.01 );
               }
            }
         } 
      }
   }
   else
   {
      print KCM::formatErr( "Failed to open file.\n" );
      return;
   }

   ReadMode 0;
}

# fn to change default values, like the progress bar icon.
sub constants
{
   if( @_ < 2 )
   {
      print KCM::formatErr( "Need more parameters.\n" );  # Proper usage: First param is the value to change second param is the new value
      print KCM::formatText( "Available options are: mDist, progressBar,  delineationChar, lineHistMax, and context.\n" );
      return;
   }
   switch( $_[0] )
   {
      case "mDist"
      {                          # This is the distance scrolled by presing m in hcat.
         if( looks_like_number( $_[1] ) &&
            ( $_[1] != "inf" ) &&
            ( $_[1] != "infinity" ) )
         {
            $mDist = $_[1];
         }
         else
         {
            print KCM::formatErr( "mDist must be set to a numeric value.\n" );
         }
      }
      case "progressBar" 
      {                          # This is the enabled state of the progress bar.
         if( ( $_[1] == 1 ) || ( $_[1] == 0 ) )
         {
            $progressBar = $_[1];
         }
         else
         {
            print KCM::formatErr( "progressBar must be set to either 1 (enabled) or 0 (disabled).\n" );
         }
      }
      case "progressChar" 
      {                          # This is the character for the progress bar.
         $progressChar = $_[1];
      }
      case "delineationChar" 
      {                          # This is the char used to group parameters.
         $delineationChar = $_[1];
      }
      case "lineHistMax"
      {                          # This is the maximum number of lines to maintain in history.
         if( looks_like_number( $_[1] ) &&
            ( $_[1] != "inf" ) &&
            ( $_[1] != "infinity" ) )
         {
            $lineHistMax = $_[1];
            if( @lineHistory > $lineHistMax )
            {
            }
         }
         else
         {
            print KCM::formatErr( "lineHistMax must be set to a numeric value.\n" );
         }
      }
      case "context"
      {                          # This is the amount of context to show after search results.
         if( looks_like_number( $_[1] ) &&
            ( $_[1] != "inf" ) &&
            ( $_[1] != "infinity" ) && 
            ( $_[1] >= 0 ) )
         {
            $context = $_[1];
         }
         else
         {
            print KCM::formatErr( "context must be set to a positive numeric value.\n" );
         }
      }
      else
      {
         print KCM::formatErr( "Not a valid parameter.\n" )
      }
      case "columns"
      {                          # This is the default number of columns to display when running ls.
         if( ( looks_like_number( $_[1] ) &&
               ( $_[1] != "inf" ) &&
               ( $_[1] != "infinity" ) && 
               ( $_[1] >= 0 ) ) ||
           $_[1] eq "auto" ) 
         {
            $context = $_[1];
         }
         else
         {
            print KCM::formatErr( "context must be set to either \"auto\" or a positive numeric value.\n" );
         }
      }
      else
      {
         print KCM::formatErr( "Not a valid parameter.\n" )
      }
   }
}

# helper fn to allow use of delineating chars to group parameters
sub separationOfVariables
{
   my @strsToProcess = @_;
   my @processArgs;
   my $i = 0;
   my $j = 0;
   my $limit = @_;
   
   my $validation = 0;
   for my $i ( 0 .. $limit - 1 )
   {
      $validation += ( $_[$i] =~ m/$delineationChar/g );
   }
   if( ( $validation % 2 ) != 0 )
   {
      print KCM::formatErr( "Odd number of delineation chars.\nMaybe you haven't spaced your terms correctly?\n" );
      return;
   }
   while ( $i < $limit ) #continue loop until end of given params
   {
      if( $strsToProcess[$i] =~ m/$delineationChar/ ) #if it contains a ", add to processArgs w/o incr. j
      {
         my $temp = $strsToProcess[$i];
         $temp =~ s#$delineationChar##;
         $processArgs[$j] = $temp;
         $i++;
         while ( !( $strsToProcess[$i] =~ m/$delineationChar/ ) && ( $i < $limit ) )
         {
            $processArgs[$j] .= " " . $strsToProcess[$i];
            $i++;
         }
         $temp = $strsToProcess[$i];
         $temp =~ s#$delineationChar##;
         $processArgs[$j] .= " " . $temp;
         $i++;
         $j++;
      }
      else
      {
         $processArgs[$j] = $strsToProcess[$i];
         $i++;
         $j++;
      }
   
   }


   return @processArgs;
}

sub processFindResults
{
   my @files;
   my $param = $_[0];
   my @results = @{$_[1]};
   $files[0] = ();
   @fileResults = ();
   @fileResultsTally = ();
   my $fileNum = 0;
   for my $file ( @results )
   {
      $file = file( $file )->absolute();
      $files[0][ $fileNum ] = $file;
      print KCM::formatNum( $fileNum ) . ".\t" . KCM::formatFile( $file ) . "\n";
      $fileNum++;
   }
   KFM::setFiles( \@files );
}

# fn to run find
sub find
{
   my @params = @_;
   if( @params == 0 )
   {
      print KCM::formatErr( "No search parameters provided.\n" );
      return;
   }
   my $searchParam = $params[0];
   my @results = `find -name \"$searchParam\"`;
   if ( 0 == @results )
   {
      print KCM::formatText( "No files found.\n" )
   }
   #chomp( @results );
   chomp( @results );
   processFindResults( $searchParam, \@results );
#TODO
}

# fns to check if specified files file lists exist
# these functions exist because in every file list related
# function, we need to check if we're accessing a file list
# or file that is out of bounds
sub fileListExists
{
   return KFM::fileListExists( @_ );
}

sub fileExists
{
   return KFM::fileExists( @_ );
}

# fn to print number of files known about
sub fileListList
{
   KFM::fileListList;
}

# fn to display current list of files from previous search or manual creation
sub fileList
{
   KFM::fileList;
}

# fn to display current list of files from a specified list of files
sub fileListNonPrimary
{
   KFM::fileListNonPrimary( @_ );
}

sub fileListType
{
   KFM::fileListType( $_ );
} 

# manually create a list of files
sub fileListCreate
{
   KFM::fileListCreate( @_ );
}

# create a list of files
sub fileListCreateNonPrimary
{
   KFM::fileListCreateNonPrimary( @_ );
}

# fn to add a file to current list of files
sub fileListAdd
{
   KFM::fileListAdd( @_);
}

# fn to add a file to a specified list of files
sub fileListAddNonPrimary
{
   KFM::fileListAddNonPrimary( @_ );
}

# fn to remove some files from the current list of files
sub fileListRemove
{
   KFM::fileListRemove( @_ );
}

# fn to remove some files to a specified list of files
sub fileListRemoveNonPrimary
{
   KFM::fileListRemoveNonPrimary( @_ );
}


# fn to bring up results from specific file
sub fileSpecific
{  
   KFM::fileSpecific( @_ );
}


# fn to set a specified list of files as primary list
sub useNonPrimary
{
   KFM::useNonPrimary( $_ );
}

# fn to quit from grepshell
sub quit
{
   exit;
}

# fn to ramble
sub about
{
   print "This script is basically grep, but prettier. There are some nice features, admittedly, but that's the gist.\n";
   print "It was written by me, Kevin Jayamanna, in 2014-2015 to help me out during my internships, which were my first real introduction to the world of linux.\n";
   print "It's nice to have a way to search for a number of things at once, highlight all of them, and keep a list of files I want to keep editing without having\n";
   print "to keep cd'ing back and forth between the same few locations. Plus, working on this was a pretty fun way to get the hang of perl.\n";
   print "I'd just add neat features whenever I thought of them, usually things I was doing at the moment in some boring and tedious way.\n";
   print "Got any suggestions? Email me at mercury0110111\@gmail.com. I'll add it, or just send you the source if you want, whatever.\n";
   print "Anyways, enjoy the script, hope it comes in handy! :D\n";
}

# fn to do random things
sub test
{

   print KCM::formatCustom( KCM::RGB000, "000\t" );
   print KCM::formatCustom( KCM::RGB001, "001\t" );
   print KCM::formatCustom( KCM::RGB002, "002\t" );
   print KCM::formatCustom( KCM::RGB003, "003\t" );
   print KCM::formatCustom( KCM::RGB004, "004\t" );
   print KCM::formatCustom( KCM::RGB005, "005\n" );
   print KCM::formatCustom( KCM::RGB010, "010\t" );
   print KCM::formatCustom( KCM::RGB011, "011\t" );
   print KCM::formatCustom( KCM::RGB012, "012\t" );
   print KCM::formatCustom( KCM::RGB013, "013\t" );
   print KCM::formatCustom( KCM::RGB014, "014\t" );
   print KCM::formatCustom( KCM::RGB015, "015\n" );
   print KCM::formatCustom( KCM::RGB020, "020\t" );
   print KCM::formatCustom( KCM::RGB021, "021\t" );
   print KCM::formatCustom( KCM::RGB022, "022\t" );
   print KCM::formatCustom( KCM::RGB023, "023\t" );
   print KCM::formatCustom( KCM::RGB024, "024\t" );
   print KCM::formatCustom( KCM::RGB025, "025\n" );
   print KCM::formatCustom( KCM::RGB030, "030\t" );
   print KCM::formatCustom( KCM::RGB031, "031\t" );
   print KCM::formatCustom( KCM::RGB032, "023\t" );
   print KCM::formatCustom( KCM::RGB033, "033\t" );
   print KCM::formatCustom( KCM::RGB034, "034\t" );
   print KCM::formatCustom( KCM::RGB035, "035\n" );
   print KCM::formatCustom( KCM::RGB040, "040\t" );
   print KCM::formatCustom( KCM::RGB041, "041\t" );
   print KCM::formatCustom( KCM::RGB042, "043\t" );
   print KCM::formatCustom( KCM::RGB043, "043\t" );
   print KCM::formatCustom( KCM::RGB044, "044\t" );
   print KCM::formatCustom( KCM::RGB045, "045\n" );
   print KCM::formatCustom( KCM::RGB050, "050\t" );
   print KCM::formatCustom( KCM::RGB051, "051\t" );
   print KCM::formatCustom( KCM::RGB052, "053\t" );
   print KCM::formatCustom( KCM::RGB053, "053\t" );
   print KCM::formatCustom( KCM::RGB054, "054\t" );
   print KCM::formatCustom( KCM::RGB055, "055\n" );
   
   
   
   print KCM::formatCustom( KCM::RGB100, "100\t" );
   print KCM::formatCustom( KCM::RGB101, "101\t" );
   print KCM::formatCustom( KCM::RGB102, "102\t" );
   print KCM::formatCustom( KCM::RGB103, "103\t" );
   print KCM::formatCustom( KCM::RGB104, "104\t" );
   print KCM::formatCustom( KCM::RGB105, "105\n" );
   print KCM::formatCustom( KCM::RGB110, "110\t" );
   print KCM::formatCustom( KCM::RGB111, "111\t" );
   print KCM::formatCustom( KCM::RGB112, "112\t" );
   print KCM::formatCustom( KCM::RGB113, "113\t" );
   print KCM::formatCustom( KCM::RGB114, "114\t" );
   print KCM::formatCustom( KCM::RGB115, "115\n" );
   print KCM::formatCustom( KCM::RGB120, "120\t" );
   print KCM::formatCustom( KCM::RGB121, "121\t" );
   print KCM::formatCustom( KCM::RGB122, "122\t" );
   print KCM::formatCustom( KCM::RGB123, "123\t" );
   print KCM::formatCustom( KCM::RGB124, "124\t" );
   print KCM::formatCustom( KCM::RGB125, "125\n" );
   print KCM::formatCustom( KCM::RGB130, "130\t" );
   print KCM::formatCustom( KCM::RGB131, "131\t" );
   print KCM::formatCustom( KCM::RGB132, "123\t" );
   print KCM::formatCustom( KCM::RGB133, "133\t" );
   print KCM::formatCustom( KCM::RGB134, "134\t" );
   print KCM::formatCustom( KCM::RGB135, "135\n" );
   print KCM::formatCustom( KCM::RGB140, "140\t" );
   print KCM::formatCustom( KCM::RGB141, "141\t" );
   print KCM::formatCustom( KCM::RGB142, "143\t" );
   print KCM::formatCustom( KCM::RGB143, "143\t" );
   print KCM::formatCustom( KCM::RGB144, "144\t" );
   print KCM::formatCustom( KCM::RGB145, "145\n" );
   print KCM::formatCustom( KCM::RGB150, "150\t" );
   print KCM::formatCustom( KCM::RGB151, "151\t" );
   print KCM::formatCustom( KCM::RGB152, "153\t" );
   print KCM::formatCustom( KCM::RGB153, "153\t" );
   print KCM::formatCustom( KCM::RGB154, "154\t" );
   print KCM::formatCustom( KCM::RGB155, "155\n" );

   print KCM::formatCustom( KCM::RGB200, "200\t" );
   print KCM::formatCustom( KCM::RGB201, "201\t" );
   print KCM::formatCustom( KCM::RGB202, "202\t" );
   print KCM::formatCustom( KCM::RGB203, "203\t" );
   print KCM::formatCustom( KCM::RGB204, "204\t" );
   print KCM::formatCustom( KCM::RGB205, "205\n" );
   print KCM::formatCustom( KCM::RGB210, "210\t" );
   print KCM::formatCustom( KCM::RGB211, "211\t" );
   print KCM::formatCustom( KCM::RGB212, "212\t" );
   print KCM::formatCustom( KCM::RGB213, "213\t" );
   print KCM::formatCustom( KCM::RGB214, "214\t" );
   print KCM::formatCustom( KCM::RGB215, "215\n" );
   print KCM::formatCustom( KCM::RGB220, "220\t" );
   print KCM::formatCustom( KCM::RGB221, "221\t" );
   print KCM::formatCustom( KCM::RGB222, "222\t" );
   print KCM::formatCustom( KCM::RGB223, "223\t" );
   print KCM::formatCustom( KCM::RGB224, "224\t" );
   print KCM::formatCustom( KCM::RGB225, "225\n" );
   print KCM::formatCustom( KCM::RGB230, "230\t" );
   print KCM::formatCustom( KCM::RGB231, "231\t" );
   print KCM::formatCustom( KCM::RGB232, "223\t" );
   print KCM::formatCustom( KCM::RGB233, "233\t" );
   print KCM::formatCustom( KCM::RGB234, "234\t" );
   print KCM::formatCustom( KCM::RGB235, "235\n" );
   print KCM::formatCustom( KCM::RGB240, "240\t" );
   print KCM::formatCustom( KCM::RGB241, "241\t" );
   print KCM::formatCustom( KCM::RGB242, "243\t" );
   print KCM::formatCustom( KCM::RGB243, "243\t" );
   print KCM::formatCustom( KCM::RGB244, "244\t" );
   print KCM::formatCustom( KCM::RGB245, "245\n" );
   print KCM::formatCustom( KCM::RGB250, "250\t" );
   print KCM::formatCustom( KCM::RGB251, "251\t" );
   print KCM::formatCustom( KCM::RGB252, "253\t" );
   print KCM::formatCustom( KCM::RGB253, "253\t" );
   print KCM::formatCustom( KCM::RGB254, "254\t" );
   print KCM::formatCustom( KCM::RGB255, "255\n" );

   print KCM::formatCustom( KCM::RGB300, "300\t" );
   print KCM::formatCustom( KCM::RGB301, "301\t" );
   print KCM::formatCustom( KCM::RGB302, "302\t" );
   print KCM::formatCustom( KCM::RGB303, "303\t" );
   print KCM::formatCustom( KCM::RGB304, "304\t" );
   print KCM::formatCustom( KCM::RGB305, "305\n" );
   print KCM::formatCustom( KCM::RGB310, "310\t" );
   print KCM::formatCustom( KCM::RGB311, "311\t" );
   print KCM::formatCustom( KCM::RGB312, "312\t" );
   print KCM::formatCustom( KCM::RGB313, "313\t" );
   print KCM::formatCustom( KCM::RGB314, "314\t" );
   print KCM::formatCustom( KCM::RGB315, "315\n" );
   print KCM::formatCustom( KCM::RGB320, "320\t" );
   print KCM::formatCustom( KCM::RGB321, "321\t" );
   print KCM::formatCustom( KCM::RGB322, "322\t" );
   print KCM::formatCustom( KCM::RGB323, "323\t" );
   print KCM::formatCustom( KCM::RGB324, "324\t" );
   print KCM::formatCustom( KCM::RGB325, "325\n" );
   print KCM::formatCustom( KCM::RGB330, "330\t" );
   print KCM::formatCustom( KCM::RGB331, "331\t" );
   print KCM::formatCustom( KCM::RGB332, "323\t" );
   print KCM::formatCustom( KCM::RGB333, "333\t" );
   print KCM::formatCustom( KCM::RGB334, "334\t" );
   print KCM::formatCustom( KCM::RGB335, "335\n" );
   print KCM::formatCustom( KCM::RGB340, "340\t" );
   print KCM::formatCustom( KCM::RGB341, "341\t" );
   print KCM::formatCustom( KCM::RGB342, "343\t" );
   print KCM::formatCustom( KCM::RGB343, "343\t" );
   print KCM::formatCustom( KCM::RGB344, "344\t" );
   print KCM::formatCustom( KCM::RGB345, "345\n" );
   print KCM::formatCustom( KCM::RGB350, "350\t" );
   print KCM::formatCustom( KCM::RGB351, "351\t" );
   print KCM::formatCustom( KCM::RGB352, "353\t" );
   print KCM::formatCustom( KCM::RGB353, "353\t" );
   print KCM::formatCustom( KCM::RGB354, "354\t" );
   print KCM::formatCustom( KCM::RGB355, "355\n" );

   print KCM::formatCustom( KCM::RGB400, "400\t" );
   print KCM::formatCustom( KCM::RGB401, "401\t" );
   print KCM::formatCustom( KCM::RGB402, "402\t" );
   print KCM::formatCustom( KCM::RGB403, "403\t" );
   print KCM::formatCustom( KCM::RGB404, "404\t" );
   print KCM::formatCustom( KCM::RGB405, "405\n" );
   print KCM::formatCustom( KCM::RGB410, "410\t" );
   print KCM::formatCustom( KCM::RGB411, "411\t" );
   print KCM::formatCustom( KCM::RGB412, "412\t" );
   print KCM::formatCustom( KCM::RGB413, "413\t" );
   print KCM::formatCustom( KCM::RGB414, "414\t" );
   print KCM::formatCustom( KCM::RGB415, "415\n" );
   print KCM::formatCustom( KCM::RGB420, "420\t" );
   print KCM::formatCustom( KCM::RGB421, "421\t" );
   print KCM::formatCustom( KCM::RGB422, "422\t" );
   print KCM::formatCustom( KCM::RGB423, "423\t" );
   print KCM::formatCustom( KCM::RGB424, "424\t" );
   print KCM::formatCustom( KCM::RGB425, "425\n" );
   print KCM::formatCustom( KCM::RGB430, "430\t" );
   print KCM::formatCustom( KCM::RGB431, "431\t" );
   print KCM::formatCustom( KCM::RGB432, "423\t" );
   print KCM::formatCustom( KCM::RGB433, "433\t" );
   print KCM::formatCustom( KCM::RGB434, "434\t" );
   print KCM::formatCustom( KCM::RGB435, "435\n" );
   print KCM::formatCustom( KCM::RGB440, "440\t" );
   print KCM::formatCustom( KCM::RGB441, "441\t" );
   print KCM::formatCustom( KCM::RGB442, "443\t" );
   print KCM::formatCustom( KCM::RGB443, "443\t" );
   print KCM::formatCustom( KCM::RGB444, "444\t" );
   print KCM::formatCustom( KCM::RGB445, "445\n" );
   print KCM::formatCustom( KCM::RGB450, "450\t" );
   print KCM::formatCustom( KCM::RGB451, "451\t" );
   print KCM::formatCustom( KCM::RGB452, "453\t" );
   print KCM::formatCustom( KCM::RGB453, "453\t" );
   print KCM::formatCustom( KCM::RGB454, "454\t" );
   print KCM::formatCustom( KCM::RGB455, "455\n" );
  
   print KCM::formatCustom( KCM::RGB500, "500\t" );
   print KCM::formatCustom( KCM::RGB501, "501\t" );
   print KCM::formatCustom( KCM::RGB502, "502\t" );
   print KCM::formatCustom( KCM::RGB503, "503\t" );
   print KCM::formatCustom( KCM::RGB504, "504\t" );
   print KCM::formatCustom( KCM::RGB505, "505\n" );
   print KCM::formatCustom( KCM::RGB510, "510\t" );
   print KCM::formatCustom( KCM::RGB511, "511\t" );
   print KCM::formatCustom( KCM::RGB512, "512\t" );
   print KCM::formatCustom( KCM::RGB513, "513\t" );
   print KCM::formatCustom( KCM::RGB514, "514\t" );
   print KCM::formatCustom( KCM::RGB515, "515\n" );
   print KCM::formatCustom( KCM::RGB520, "520\t" );
   print KCM::formatCustom( KCM::RGB521, "521\t" );
   print KCM::formatCustom( KCM::RGB522, "522\t" );
   print KCM::formatCustom( KCM::RGB523, "523\t" );
   print KCM::formatCustom( KCM::RGB524, "524\t" );
   print KCM::formatCustom( KCM::RGB525, "525\n" );
   print KCM::formatCustom( KCM::RGB530, "530\t" );
   print KCM::formatCustom( KCM::RGB531, "531\t" );
   print KCM::formatCustom( KCM::RGB532, "523\t" );
   print KCM::formatCustom( KCM::RGB533, "533\t" );
   print KCM::formatCustom( KCM::RGB534, "534\t" );
   print KCM::formatCustom( KCM::RGB535, "535\n" );
   print KCM::formatCustom( KCM::RGB540, "540\t" );
   print KCM::formatCustom( KCM::RGB541, "541\t" );
   print KCM::formatCustom( KCM::RGB542, "543\t" );
   print KCM::formatCustom( KCM::RGB543, "543\t" );
   print KCM::formatCustom( KCM::RGB544, "544\t" );
   print KCM::formatCustom( KCM::RGB545, "545\n" );
   print KCM::formatCustom( KCM::RGB550, "550\t" );
   print KCM::formatCustom( KCM::RGB551, "551\t" );
   print KCM::formatCustom( KCM::RGB552, "553\t" );
   print KCM::formatCustom( KCM::RGB553, "553\t" );
   print KCM::formatCustom( KCM::RGB554, "554\t" );
   print KCM::formatCustom( KCM::RGB555, "555\n" );
   #014 pale navy
   #025 nice blue
   #055 bright cyan 
   #030 not too bright green
   #102 vivid purple
   #205 bright purple
   #115 very pale lavenderish
   #310 orange
   #510 orange on fire
   #300 darkish red
   #404 missing pink
#--------------------------------------------------
#    print "\n";
#    print "kperl-v2: \n";
#    print KCM::formatCustom( KCM::RGB115, "kperl" );
#    print "-";
#    print KCM::formatCustom( KCM::RGB115, "v2" );
#    print ":\n";
#-------------------------------------------------- 
}

sub max ($$) { $_[$_[0] < $_[1]] }
sub min ($$) { $_[$_[0] > $_[1]] }
# with red/blue/purple progress bar
#sub repeat { for( 1 .. $_[1] ) { print "$_[0]"; } }
sub repeat { my $i = ""; for( 1 .. $_[1] ) { $i .= "$_[0]"; }; return $i }

# colors some subset of the progress bar
sub partColor
{
   my $color = $_[0];
   my $first = $_[1];
   my $last = $_[2];
   my @barArray = @{$_[3]};
   for my $i ( $first .. min( $last, @barArray - 1 ) ) {
      $barArray[ $i ] = KCM::formatCustom( $color, '#' );
   }
  return @barArray
}

sub progressBarSetup
{
   my @terminalSize = GetTerminalSize();
   my $width = $terminalSize[0];
   $width = floor( $width );
   my @barArray;
   my @emptySpace;
   for my $i ( 0 .. $width - 1 ) { $barArray[ $i ] = '#'; }
   for my $i ( 0 .. $width - 1 ) { $emptySpace[ $i ] = ' '; }
   return ( $width, \@barArray, \@emptySpace );
}



sub progressBar1
{
   my $i = $_[0];
   my $width = $_[1];
   my @barArray = @{$_[2]};
   my $end = abs( $width * sin( 3.14 * $i/800 ) );
   @barArray = partColor( KCM::RED, 0, $end, \@barArray );
   @barArray = partColor( KCM::BLUE, $width - $end, $width - 1, \@barArray );
   @barArray = partColor( KCM::YELLOW, 0, $width * $i / 1200 - 1, \@barArray );
   if( $end > $width/2 ) {
      @barArray = partColor( KCM::RGB205, $width - $end, $end, \@barArray );
   }
  return @barArray;
}

sub progressBar2
{
   my $i = $_[0];
   my $width = $_[1];
   my @barArray = @{$_[2]};
   my $end = abs( $width * sin( 3.14 * $i/1200 ) );
   @barArray = partColor( KCM::RED, 0, $end, \@barArray );
   #@barArray = partColor( BLUE, $width - $end, $width - 1, \@barArray );
   #@barArray = partColor( YELLOW, 0, $width * $i / 1200 - 1, \@barArray );
   #if( $end > $width/2 ) {
   #   @barArray = partColor( RGB205, $width - $end, $end, \@barArray );
   #}
  return @barArray;
}

sub test2
{
#   for my $i ( 0 .. 1 * $width - 1 ) {
#      print "#";
#      select( undef, undef, undef, 0.01 );
#   }
#   print "\r";
#   for my $i ( 0 .. 1 * $width - 1 ) {
#      print kcolor( 0, "#" );
#      select( undef, undef, undef, 0.01 );
#   }

# progress bar of one color filled by another
#   for my $i ( 0 .. $width - 1 )
#   {
#      for my $j ( 0 .. $i )
#      {
#         print kcolor( 0, '#' );
#      }
#      for my $j ( $i + 1 .. $width - 1 )
#      {
#         print kcolor( 1, '#' );
#      }
#      print "\r";
#      select( undef, undef, undef, 0.01 );
#   }

# progress bar starts out empty, red and blue come in from edges and intersection is purple
#   for my $x ( 1 .. $width )
#   {
#      my $k = LOCALCOLOR RED, '#';
#      print repeat( $k, min( $x, $width - $x ) );
#
#      if ( $x < $width/2 )
#      {
#         print repeat( " ", ( $width - ( 2 * min( $x, $width - $x ) ) ) );
#      } else {
#         my $j = LOCALCOLOR RGB205, "#";
#         print repeat( $j, ( $width - ( 2 * min( $x, $width - $x ) ) ) );
#      }
#
#      my $l = LOCALCOLOR BLUE, '#';
#      print repeat( $l, min( $x, $width - $x ) );
#
#      print "\r";
#      select( undef, undef, undef, 0.01 );
#   }
#   print repeat( " ", $width );
#   print "\r";
  
#   my $bar = repeat( '#', $width );
#   for my $i ( 0 .. 10 ) {
#      print repeat( '#', $width * sin( $i ) ) . "\r";
#      select( undef, undef, undef, 0.01 );
      #print $bar . "\r";
#   }

# slightly more complicated setup
# red from left and blue from right oscillate across bar at rate of sin(x)
# intersection is purple
# yellow slowly fills progressbar from left to right, overlapping red and blue, but underneath purple
# implemented in progressBar1()

   my ( $width, $barArrayRef, $emptySpaceRef ) = progressBarSetup();
   my @barArray = @$barArrayRef;
   my @emptySpace = @$emptySpaceRef;
   my ($thr) = threads->new( 
      sub { 
         sleep(10);my @results = `grep \"test\" . -nsrC 2`;
         return \@results; } );
   my @barArrayOld = @barArray;
   my $i = 0;
   while ( $thr->running ) {
      @barArray = progressBar2( $i, $width, \@barArrayOld );
      $i++;
      if ( $i >= 1200 ) {
         $i = 0;
      }
      select( undef, undef, undef, 0.002 );
      print @barArray;
      print "\r";
   }
   my @result = $thr->join();

   print @emptySpace;
   print "\rdone!\n";
   print @{$result[0]};
   print "\n";
   #print $width . "\n";
   #print "files:\n";
   ##print @files;
   #print "\nfileResults:\n";
   #print @fileResults;
}

sub test3
{
   print kcolor( 0, "first!" ) . "\n"; 
   print kcolor( 1, "second!" ) . "\n"; 
   print kcolor( 2, "third!" ) . "\n"; 
   print kcolor( 3, "fourth!" ) . "\n"; 
   print kcolor( 4, "fifth!" ) . "\n"; 
   print kcolor( 5, "sixth!" ) . "\n"; 
}

# fn to execute pwd
sub pwd
{
   print KCM::formatFile( `pwd` );
}

# fn to execute cd
sub cd
{
   chdir( $_[0] );
   &pwd;
}

sub fileHierarchy
{
   treeInit();
   useFileTree( $_[0] );
   treeDel();
}

sub ls
{
   my %month;
   $month{Jan} = 1;
   $month{Feb} = 2;
   $month{Mar} = 3;
   $month{Apr} = 4;
   $month{May} = 5;
   $month{Jun} = 6;
   $month{Jul} = 7;
   $month{Aug} = 8;
   $month{Sep} = 9;
   $month{Oct} = 10;
   $month{Nov} = 11;
   $month{Dec} = 12;
   my $col = $_[0];
   if ( !( looks_like_number( $col ) ) )
   {
      if( $defaultLsColNum eq "auto" )
      {
         my @terminalSize = GetTerminalSize();
         my $width = $terminalSize[0];
         $col = floor( $width / 30 ); 
         if ( $col > 4 )
         {
            $col = 4;
         }
      } 
      else 
      {
      $col = $defaultLsColNum;
      }
   }
   my $i = 0;
   my @results = `ls -l -F`;
   for my $file ( @results[ 1 .. $#results ] ) {
      my $fileName = $file;
      $fileName =~ s/.* (.*)/$1/;
      chomp( $fileName );
      my $fileDate = $file;
      $fileDate =~ s/.* (\w\w\w [\d\s]\d).*/$1/;
      chomp( $fileDate );
      my $len = length( $fileName );
      my $fileMon = $fileDate;
      $fileMon =~ s/(\w\w\w).*/$1/;
      my $fileDay = $fileDate;
      $fileDay =~ s/.*([\d\s]\d).*/$1/;
      if ( $fileName =~ m#.*/# )
      {
         print KCM::formatText( $fileDate . "  " . $fileName );
      }
      else
      {
         my $inList = KFM::listContains( 0, file( $fileName )->absolute() );
         my @time = localtime( time );
         my $mday = $time[3];
         my $mon = $time[4] + 1;
	 if( $inList == 1 ) {
	    print( KCM::kcolor( 0, "$fileDate  " ) );
	 } else {
	    print $fileDate . "  ";
	 }
         if( !( looks_like_number( $month{$fileMon} ) ) )
         {
            $month{$fileMon} = 0;
         }
         if( $mon eq $month{$fileMon} )
         {
            if( $mday == $fileDay )
            {
               print KCM::formatCustom( KCM::RGB115, $fileName );
            }
            elsif ( abs( $mday - $fileDay ) <= 7 )
            {
               print KCM::formatCustom( KCM::RGB114, $fileName );
            }
            elsif ( ( abs( $mday - $fileDay ) <= 14 ) && ( abs( $mday - $fileDay ) > 7 )  )
            {
               print KCM::formatCustom( KCM::RGB113, $fileName );
            }
            else
            {
               print KCM::formatCustom( KCM::RGB112, $fileName );
            }
         }
         else
         {
            print KCM::formatCustom( KCM::RGB111, $fileName );
         }
      }
      if( $len < 8 )
      {
         print "\t\t\t";
      }
      elsif( ( $len >= 8 ) && ( $len < 16 ) )
      {
         print "\t\t";
      }
      elsif( ( $len >= 16 ) && ( $len < 24 ) ) 
      {
         print "\t";
      }
      $i++;
      if ( $i >= $col )
      {
         print "\n";
         $i = 0;
      }
   }
   print "\n";   
}

# helper fn to pass a command along to shell
sub shellCmd
{  
   my $command = $_[0];
   my $output = `$command`;
   print $output . "\n";
}

sub autoComplete
{
   if( @_ <= 1 )
   {
      return \@completion_list;
   }
   elsif( $_[0] eq "cd" )
   {
      return 'dirnames';
   }
   elsif( ( $_[0] eq "vim" ) || 
         ( $_[0] eq "v" ) || ( $_[0] eq "hcat" ) || ( $_[0] eq "highlightcat" ) || 
         ( $_[0] eq "filespecific" ) || ( $_[0] eq "filelist" ) || ( $_[0] eq "fs" ) || 
         ( $_[0] eq "fl" ) || ( $_[0] eq "filelistnonprimary" ) || ( $_[0] eq "fls" ) || 
         ( $_[0] eq "filelistadd" ) || ( $_[0] eq "fa" ) || ( $_[0] eq "filelistaddnonprimary" ) || 
         ( $_[0] eq "fas" ) || ( $_[0] eq "filelistcreate" ) || ( $_[0] eq "fc" ) || 
         ( $_[0] eq "filelistcreatenonprimary" ) || ( $_[0] eq "fcs" ) || ( $_[0] eq "a4" ) )
   {
      return ( 'filenames', \@fileResults );
   }
   elsif( $_[0] eq "help" )
   {
      return \@completion_list;
   }
   #my @completion_list = ( "search", "help", "vim", "filelist", "filelistnonprimary", "filelistadd", "filelistaddnonprimary", "filelistcreate", "filelistcreatenonprimary", "filelisttype", "filespecific", "quit", "highlightcat", "constants" ); 
}

sub addHistory
{
   my $line = $_[0];
   while( @lineHistory > $lineHistMax )
   {
      shift( @lineHistory );
   }
   push( @lineHistory, $line );
}

sub showHistory
{
   my $i = @lineHistory - 1;
   for my $line ( @lineHistory )
   {
      my $iC = KCM::formatNum( $i );
      my $fileNameC = KCM::formatFile( $line ); 
      print $iC . ".\t" . $fileNameC . "\n";
      $i--;
   }
}

# main fn, to process commands
sub main
{
   if( @ARGV > 0 ) {
      $singleCommand = 1;
      &readFile();
      my @params = @ARGV[ 1 .. @ARGV-1];
      @params = separationOfVariables( @params );
      for my $key ( keys %functions )
      {
         if ( $ARGV[0] eq $key )
         {
            $functions{$ARGV[0]}->( @params );  
         }
      }
      &saveFile();
      exit;
   }
   print KCM::formatText( "Welcome to the grepshell console.\n" );
   print KCM::formatText( "Remember, s to search, and c and r to view and redo commands.\n" );
   print KCM::formatText( "And of course, help to get more detailed instructions.\n" );
   #$line = $prompt;
   my $oldLine = "";
   while (1)
   {
      print KCM::formatPrompt();
      my $line = prompt "", -complete => \&autoComplete, -echostyle => 'blue', -style => 'blue';
      chomp( $line );
      
      if( $line =~ m/^r (\d)/ )
      {
         my $i = @lineHistory - $1 - 1;
         $line = $lineHistory[$i]; 
         print KCM::formatPrompt() . KCM::formatText( $line ) . "\n";
      }
      if( $line ne "" )
      {
         my @command = split( ' ', $line );
         my @params = @command[ 1 .. @command-1];
         @params = separationOfVariables( @params );
         my $found = 0;
         for my $key ( keys %functions )
         {
            if ( $command[0] eq $key )
            {
               $found = 1;
               addHistory( $line );
               $functions{$key}->( @params );  
               if( ( $key eq "search" )||
                  ( $key eq "s" ) )
               {
                  $oldLine = $line;
               }
            }
         }
         if( $command[0] eq '\e[A' )
         {
            print "UP ARROW" . "\n";
            $oldLine = "TEST";
            $found = 1;
         } 
         if( $found == 0 )
         {
            &shellCmd( $line );
         }
         $line = "";
      }
   }
}
main();
sub addNode;
sub checkNode;
sub addNode
{
   my $index = $_[0];
   my @searchTerms = @{$_[2]};
   my $tree = $_[1];
   if( $index == @searchTerms )
   {
      my $leaf = $tree->new_daughter;
      $leaf->name( "END" );
      return 1;
   }
   #print "curr letter is $searchTerms[$index]\n";
   for my $leaf ( $tree->daughters() )
   {
      #print $leaf->name() . "\t" . $searchTerms[$index] . "\n";
      if ( $leaf->name() eq $searchTerms[$index] )
      {
         return addNode( ++$index, $leaf, \@searchTerms );
      }
   }
   my $leaf = $tree->new_daughter;
   $leaf->name( $searchTerms[$index] );
   #print "name is $searchTerms[$index]\n";
   return addNode( ++$index, $leaf, \@searchTerms );

}

sub checkNode
{
   my $index = $_[0];
   my @searchTerms = @{$_[2]};
   my $tree = $_[1];
   if( scalar( $tree->leaves_under() ) == 0 )
   {
   #print "reached leaf\n";
      return $tree;
   }
   if( $index == @searchTerms )
   {
      return $tree->leaves_under();
   }
   #print "curr letter is $searchTerms[$index]\n";
   for my $leaf ( $tree->daughters() )
   {
      if ( $leaf->name() eq $searchTerms[$index] )
      {
         return checkNode( ++$index, $leaf, \@searchTerms );
      }
   }
   return 0;
}

sub createResponse
{
   my $node = $_[0];
   if( !defined( $node ) )
   {
      return "NONE";
   }
   my $retStr = "";
   while( !( $node->name() eq "BEGIN" ) )
   {
      $retStr = $node->name() . $retStr;
      $node = $node->mother();
   }
   return $retStr;
}

sub treeInit
{
   $tree = Tree::DAG_Node->new();
   $tree->name( "BEGIN" ); 
}

sub treeTest
{
   my $test = "gmpls show";
   my @test = split //, $test;
   my $test2 = "gmpls hide";
   my @test2 = split //, $test2;
   my $test3 = "gmpls shape";
   my @test3 = split //, $test3;
   my $test4 = "other command";
   my @test4 = split //, $test4;
   my $test5 = "other comma";
   my @test5 = split //, $test5;
   my $test6 = "gmpls";
   my @test6 = split //, $test6;
   my $test7 = "gmpblooo";
   my @test7 = split //, $test7;
   my $test8 = "gmpls hit";
   my @test8 = split //, $test8;
   my $test9 = "gmpls hi";
   my @test9 = split //, $test9;

   my $test10 = "gmpls hat";
   my @test10 = split //, $test10;



   #print scalar( @test ) . "\n";
   $tree = Tree::DAG_Node->new();
   #for my $letter ( 'f' .. 'i' )
   #{
   #my $new_daughter = $tree->new_daughter;
   #  $new_daughter->name( $letter );
   #   $new_daughter->attributes->{"valid"} = "n";
   #   print $new_daughter->attributes->{"valid"};
   #}
   
   print "\n";
   $tree->name( "BEGIN" );
   addNode( 0, $tree, \@test );
   addNode( 0, $tree, \@test2 );
   addNode( 0, $tree, \@test3 );
   #addNode( 0, $tree, \@test4 );
   #addNode( 0, $tree, \@test5 );
   addNode( 0, $tree, \@test7 );
   addNode( 0, $tree, \@test8 );
   addNode( 0, $tree, \@test9 );
   addNode( 0, $tree, \@test10 );
   print $test . "\t" . checkNode( 0, $tree, \@test ) . "\n";
   print $test2 . "\t" . checkNode( 0, $tree, \@test2 ) . "\n";
   print $test3 . "\t" . checkNode( 0, $tree, \@test3 ) . "\n";
   print $test4 . "\t" . checkNode( 0, $tree, \@test4 ) . "\n";
   print $test5 . "\t" . checkNode( 0, $tree, \@test5 ) . "\n";
   print $test6 . "\t" . checkNode( 0, $tree, \@test6 ) . "\n";
   
  
   my $testSearch = "gmpls s\n";
   my @testSearch = split //, $testSearch;
   my @results = checkNode( 0, $tree, \@testSearch );
   my $numResults = scalar( @results );
   print "$numResults result(s)\n";
   for my $result ( @results )
   {
     print createResponse( $result->mother() ) . "\n"; 
   }
   
   
   print map( "$_\n", @{$tree->draw_ascii_tree} );
}

sub treeDel
{
   $tree->delete_tree();
}

sub addStrFileTree
{
   my $content = $_[0];
   my @searchParams = split /\//, $content;
   #print @searchParams;
   addNode( 0, $tree, \@searchParams );
}

sub useFileTree
{
   my @files = KFM::getFiles();
   for my $file ( @files )
   {
      my @fileSplit = split /\//, file( $file )->absolute();
      addNode( 0, $tree, \@fileSplit ); 
   }
#----------------------------------------------
#NO LONGER USED TO TRAVERSE FILE HIERARCHY
#   my $preStr = $_[0];
#   my $postStr = $_[0];
#   $preStr =~ s/(.+\/).+/$1/;
#   $postStr =~ s/$preStr//;
#   #print $preStr . "\n";
#   #print $postStr . "\n";
#   my $currDir = getcwd;
#   chdir( $preStr );
#   if( $postStr eq "" )
#   {
#      print `ls`;
#      return;
#   }
#   my @contents = `ls`;
#   chdir( $currDir );
#   for my $content ( @contents )
#   {
#      addStrFileTree( $content );
#   }
#   my @searchParams = split //, $postStr;
#   my @results = checkNode( 0, $tree, \@searchParams );
#   my $resultSingular = checkNode( 0, $tree, \@searchParams );
#   my $numResults = scalar( @results );
#   if( $numResults == 1 )
#   {
#--------------------------------------------------
#       if( $resultSingular->is_node() )
#       {
#          if( $resultSingular->is_root() )
#          {
#             print "No results\n";
#             return;
#          }
#          print "1 result\n";
#       }
#       else
#       {
#          print "No results\n";
#          return;
#       }
#-------------------------------------------------- 
#   }
#   else
#   {
#      print "$numResults result(s)\n";
#   }
#   if( $numResults == 0 )
#   {
#      return;
#   }   
#   if( $numResults == 1 )
#   {
#      print createResponse( $results[0]->mother() );
#   }
#   else
#   {
#      for my $result ( @results )
#      {
#         print createResponse( $result->mother() ); 
#      }
#   }
   
   
   print map( "$_\n", @{$tree->draw_ascii_tree} );
 
}
#treeInit();



#!/usr/local/bin/perl 
use feature "switch";
use Storable 'dclone';
use Getopt::Long;
use IO::Handle;
use POSIX qw(:sys_wait_h);
use Data::Dumper;
use List::Util qw[min max];
use List::MoreUtils qw(uniq);
use Date::Calc qw(Delta_Days);


BEGIN {
   # Update @INC based on SDSTLS paths
   @_add_to_INC=split(/:/,$ENV{SDSTLS},);
   foreach (@_add_to_INC) {s,^/sasgen/,/sas/,;}

   # Uncomment the next line(s) if your tool requires the htls or tls
   # branches in the search path for perl modules. Add other search
   # paths as needed, by pushing(or by using unshift to put them ahead
   # of the paths from sdstls).
   push @_add_to_INC, "/sas/dev/htls";
   push @_add_to_INC, "/sas/dev/tls";

}
print "@_add_to_INC\n" if @user_products;
use Time::Local;
use Date::Calc qw(Decode_Date_US Date_to_Time);
use DateTime;
use Term::ANSIColor qw(:constants);
use File::Basename;


sub print_usage ;
sub arg_check;
sub Get_Build_Status;
sub TraceProList;
sub get_platform ;

sub get_merge_flag;
sub get_onepm_id_merge_pair;

sub get_Time_slice;
sub onepm_command_generator ;
sub onepm_dir;

sub logpostRegexBybuildid;

sub mergekey_onepmids_hash;  #get reverse of the hash: host_buildids

#array API
sub delete_item_from_array;

#hash API
sub getSubHashByDepth; #get a subhash of hash by depth
sub getSubHashByTemplate; #get a subhash of hash by a template hash 

sub UnknownOption {
    print "ERROR: unknown option @_ \n";
    &print_usage;
    exit 1;
}

$basename = basename($0);
$thisprog = $0;
$rc=0;

( $dtime=`date '+%D %T'`) =~ chop $dtime;

print "$thisprog started at $dtime\n" if @user_products;
Getopt::Long::Configure qw(pass_through);
$rc = GetOptions("usage|help|?|h",                        	\&print_usage,
                 "branch=s{1,}",                        	\@userbranch,
                 "exclude_branches=s{1,}",                      \@user_excluded_branch,
 		 "check_all_branches|cab",                      \$check_all_branches,
 		 "consecutive",                                 \$consecutive,
                 "onepmid=s{1,}",                        	\@user_onepm_id,
                 "onepmdir=s",                        		\$user_onepm_dir,
                 "rebuildid=s",                        		\$rebuild_onepm_id,
                 "metalogid=s",                        		\$user_meta_id,
                 "metalogdir=s",                        	\$user_meta_dir,
                 "maxdepth=s",                        		\$user_max_depth,
                 "day",                               		\$day,
                 "dev",                               		\$dev,
                 "debug",                               	\$debug,
                 "detail",                               	\$detail,
                 "delimiter=s",                               	\$user_delimiter,
                 "exec_file=s{1,}",                             \@exec_files,
                 "lan=s",                               	\$userLan,
                 "hosts=s{1,}",                        		\@user_hosts,
                 "nomerge",                              	\$nomerge_flag,
                 "write_dir=s",                            	\$userLogDir,
                 "onepm_type=s{1,}",				\@user_onepm_types,		
                 "package=s{1,}",                          	\@user_package,
                 "pattern=s",                          		\$user_pattern,
                 "platform=s",                          	\$userplatform,
                 "products=s{1,}",                          	\@user_products,
                 "portdate=s",                          	\$userportdate,
                 "no_exec|noexec",                      	\$noexec,
                 "no_interactive|nointer|nointeractive",        \$nointeractive,
                 "no_rerun|norerun",                      	\$no_rerun,
                 "repo_update",                               	\$user_repo_update,
                 "sl_lan=s",                            	\$user_sl_lan,
                 "sdsenv=s",                            	\$user_sdsenv,
		 "showdiff",    				\$show_diff,
                 "source_logs=s{1,}",                          	\@user_sources,
                 "supp",                              		\$supplemental,
                 "targets=s{1,}",                          	\@user_targets,
                 "time=s",                              	\$start_end,
                 "task=s",                              	\$TASK,
                 "type=s{1,}",                        		\@user_buildtypes,
                 "showcmd",                              	\$usedcd,
                 "v",                       			\$verbose,
                 "wky",                       			\$wky,
                 "test",                       			\$test,
);

sub print_usage {

 print <<______printEnd;

${\show_color(01)}NAME${\end_color()}
     ${\show_color(01)}$basename${\end_color()} -- This program is used to help check onepm package errors and 
		               rebuild the failed tasks concurrently if any.

${\show_color(01)}SYNOPSIS${\end_color()}
     ${\show_color(01)}$thisprog${\end_color()}
     [${\show_color(01)}-usage${\end_color()} | ${\show_color(01)}-help${\end_color()} | ${\show_color(01)}-h${\end_color()} | ${\show_color(01)}-?${\end_color()}]
     [${\show_color(01)}-no_exec${\end_color()} | ${\show_color(01)}-noexec${\end_color()}]
     [${\show_color(01)}-metalogid${\end_color()} id] [${\show_color(01)}-onepmid${\end_color()} id] [${\show_color(01)}-rebuildid${\end_color()} id]
     [${\show_color(01)}-platform${\end_color()} unix | pc | mvs]
     [${\show_color(01)}-portdate${\end_color()} date]
     [${\show_color(01)}-package${\end_color()} yum rpm ...]
     [${\show_color(01)}-delimiter${\end_color()} characters	]
     [${\show_color(01)}-products${\end_color()} product1,product2 | product1 product2 | box1,box2=product1 box3=product2 | file ]
     [${\show_color(01)}-sdsenv${\end_color()} env]
     [${\show_color(01)}-branch${\end_color()} branch1..| file_containing_branches]
     [${\show_color(01)}-exclude_branches${\end_color()} branch1..]
     [${\show_color(01)}-check_all_branches${\end_color()}
     [${\show_color(01)}-hosts${\end_color()} lax . . .]
     [${\show_color(01)}-lan${\end_color()} language]
     [${\show_color(01)}-type${\end_color()} opt | dbg]
     [${\show_color(01)}-logdir${\end_color()} log_write_path]
     [${\show_color(01)}-time${\end_color()} time]
     [${\show_color(01)}-task${\end_color()} concurrent_tasknum]
     [${\show_color(01)}-debug${\end_color()}] [${\show_color(01)}-showcmd${\end_color()}] [${\show_color(01)}-v${\end_color()}]
     [${\show_color(01)}-dev${\end_color()}] [${\show_color(01)}-wky${\end_color()}] [${\show_color(01)}-day${\end_color()}]
     [${\show_color(01)}-v${\end_color()}]
     [${\show_color(01)}-exec_file${\end_color()}]
     [${\show_color(01)}-detail${\end_color()}]
     [${\show_color(01)}-repo_update${\end_color()}]
     [${\show_color(01)}-consecutive${\end_color()}]
     [${\show_color(01)}-nomerge${\end_color()}]
     [${\show_color(01)}-no_interactive${\end_color()} | ${\show_color(01)}-nointer${\end_color()} | ${\show_color(01)}-nointeractive${\end_color()}]
     [${\show_color(01)}-supp${\end_color()}]

${\show_color(01)}DESCRIPTION${\end_color()}
     This program has below four functionalities.

     1. Check OnePM package results of one or more buildids. (FUNCTIONALITY 1)

     2. Check merged OnePM package results of two or more buildids. (FUNCTIONALITY 2)

     3. Repackage one or more products. (FUNCTIONALITY 3)

     4. Execute commands concurrently from file(s). (FUNCTIONALITY 4)


     FUNCTIONALITY 1
     It achieves the functionality by parsing the OnePM package logs.
     The OnePM package logs are found by using the following primaries or options.
     a. ${\show_color(01)}portdate${\end_color()}
     b. build level -- dev, day, wky
     c. ${\show_color(01)}branch${\end_color()}
     d. ${\show_color(01)}hosts${\end_color()}
     e. build type -- opt, dbg
     f. ${\show_color(01)}onepmid${\end_color()}

     If you have already set the sdsenv, there is no need to set a & b & c.
     Generally speaking, There is no need to set hosts and platforms.
     The hosts of a branch will be parsed by parsing unx.bld, win.bld or mvs.bld.
     While the platform is automatically gotten by analyzing build bubbles on which the script is invoked.

     If build type not specified, both opt and dbg trace files will be searched.

     The program will try to set the right onepmid by itself, however, if the
     onepmid changed in any way, it should be specified.


     FUNCTIONALITY 2
     If a product has been packaged more than once (with more buildids), running the command with ${\show_color(01)}merge${\end_color()}
     option will give the result of the latest repackage, the ${\show_color(01)}onepmid${\end_color()} primary is also needed in this ca
     se, two or more onepmids needed be specified.


     FUNCTIONALITY 3
     Repackage one or more products by setting ${\show_color(01)}products${\end_color()} primary, the value could either be product names
     or a file containing products, one per line.


     FUNCTIONALITY 4
     You can also specify a file or files, containing commands, and let the script execute these commands
     concurrently. Primary ${\show_color(01)}exec_file${\end_color()} will be needed.

     Minimum command:
     ${\show_color(01)}$thisprog${\end_color()}

${\show_color(01)}PRIMARIES${\end_color()}
     ${\show_color(01)}-usage${\end_color()} | ${\show_color(01)}-help${\end_color()} | ${\show_color(01)}-h${\end_color()} | ${\show_color(01)}-?${\end_color()}
                Print this page.

     ${\show_color(01)}-time${\end_color()}     "start~end" | "start"
                Time point or time interval separated by '~'
                Time point: Check if there are trace files after the time specified,
                including the time point.  Time interval: Check if there are trace
                files between the time interval, including the start time point,
                excluding the end time point.

     ${\show_color(01)}-metalogid${\end_color()}        metabuild_log_id
                By specifying the metalogid, the program could figure out
                where to find metabuild logs. If this primarie not set, and
                ${\show_color(01)}-wky${\end_color()} or ${\show_color(01)}-day${\end_color()}

     ${\show_color(01)}-onepmid${\end_color()}  onepm_build_id
                By which the program to search trace files

     ${\show_color(01)}-merge${\end_color()}
                Merge package results of different buildids.
                The lastest result of a package will be the final result of the product.

     ${\show_color(01)}-detail${\end_color()}
                Show detailed information of the package results.

     ${\show_color(01)}-rebuildid${\end_color()}        rebuild_onepm_id
                The rebuilt the log will be adding the rebuildid as suffix.

     ${\show_color(01)}-platform${\end_color()} unix | pc| mvs
                Which platform to check.

     ${\show_color(01)}-branch${\end_color()}   branch1 branch2 ... | files_containing_branches
                Which branch(es) to check, the two para forms could be used together.

     ${\show_color(01)}-check_all_branches${\end_color()} 
                Check builds or rerun specified products for all branches defined in unx.bld/win.bld scheduled OnePM.

     ${\show_color(01)}-hosts${\end_color()}    lax ...
                Which hosts to check.

     ${\show_color(01)}-lan${\end_color()}      language
                Which language of the products to check.
                Default en.

     ${\show_color(01)}-type${\end_color()}     opt | dbg
                Which build type to check.
                Default: to check both.

     ${\show_color(01)}-package${\end_color()}   yum rpm ...
                Check builds of specified package type(s).

     ${\show_color(01)}-exec_file${\end_color()}   file1 file2...
                Execute commands from file(s) concurrently.

     ${\show_color(01)}-delimiter${\end_color()}   characters
                Define how long a command will be, one line or spanning multiple lines.

     ${\show_color(01)}-consecutive${\end_color()}
                The files specified by primary exec_file, will be executed one by one, while
                within each file, the command will be run concurrently.
                If this primary is not set, which is the default, the commands from files
                you specified will be put together and run at the same time

     ${\show_color(01)}-task${\end_color()}     concurrent_tasknum
		Set how many onepm tasks will be run concurrently.
                There will be 10 tasks running concurrently by default if failed
                tasks exceed 10, otherwise a number between [1, 10), depending
                on number failed tasks.

     ${\show_color(01)}-portdate${\end_color()} portdate
                Which will be used to decide the metabuild build log directory
                and search trace files.  portdate will be automatically set by
                the program by parsing sdsenv if this primarite not set.

     ${\show_color(01)}-products${\end_color()}  product1,product2 | product1 product2 | box1,box2=product1, product2 box3=product3 | file
                Deliver products specified or from file

     ${\show_color(01)}-dev${\end_color()} | ${\show_color(01)}-day${\end_color()} | ${\show_color(01)}-wky${\end_color()}
                To check dev, day or wky build.
                The build lev will be autumatically set by the program by parsing
                the sdsenv if this primarite not set.

     ${\show_color(01)}-sdsenv${\end_color()}   sdsenv
                This will be used to set build level (dev, day or wky), and ${\show_color(01)}branch${\end_color()},
                and in turn  ${\show_color(01)}metalogid${\end_color()} and  ${\show_color(01)}onepmid${\end_color()}. System sdsenv will be used
                if not set.

     ${\show_color(01)}-showcmd${\end_color()}
                Show find commands used to search trace files.

     ${\show_color(01)}-logdir${\end_color()}   log_write_path
                Where to write onepm rebuild commands and results.
                Default: unix: /u/osrmgr/Hardy/
                         pc:   /u/sasos2/Hardy/
                         mvs:  /u/mvssrv/Hardy/

     ${\show_color(01)}-no_interactive${\end_color()} | ${\show_color(01)}-nointer${\end_color()} | ${\show_color(01)}-nointeractive${\end_color()}
                If this primarie set, and there are also onepm build errors,
                rebuild commands will be both shown on the screen and written
                to a file.

     ${\show_color(01)}-debug${\end_color()}
                Print debug message.

     ${\show_color(01)}-v${\end_color()}
                Print verbose message.

     ${\show_color(01)}-supp${\end_color()}
                Check OnePM packages for supplemental builds. 

     ${\show_color(01)}-repo_update${\end_color()}
                Remove the three options and their values,--datetime, --wrapper_pid and --skip_repo_validation,from the OnePM command to use the latest yaml file. 

${\show_color(01)}EXAMPLES${\end_color()}
     The following examples are shown as given to the shell:
      $thisprog
                Check if there are onepm build errors for default settings
                set by sdsenv.

      $thisprog -usedcd
                Same to the above one, in addition to print used find commands.

      $thisprog -sdsenv  day/mva-vb025
                Check onepm build results for branch vb025 of day build.

      $thisprog -type opt
                Check opt onepm build results for default settings set by sdsenv.

      $thisprog -noexec
                Will not rerun failed onepm tasks, if any exists.

      $thisprog -sdsenv day/mva-vb025 -branch vbspre25 -hosts lax h6i

      $thisprog -sdsenv -hosts lax h6i -metalogid DAY -onepmid DAYRR1 DAYRR2

      $thisprog -rebuildid ONEPM_RE -metalogid DAY -onepmid DAY
                Set onepm rerun build id ONEPM_RE.

      $thisprog -logdir /tmp/
                onepm rebuild commands and rebuild results logs will be
                written to /tmp/.

      $thisprog -exec_file /u/sasos2/Hardy/rshrun_space_line -delimiter ''
                Use space/null line(s) as delimiter of commands.

      $thisprog -exec_file /u/osrmgr/Hardy/usmtest_v940m6a  /u/osrmgr/Hardy/usmtest_vbspre25
                Concurrently execute usmtest for the 5 hosts of v940m6 and vbspre25, the 10 commands will be executed concurrently

      $thisprog -exec_file /u/osrmgr/Hardy/usmtest_v940m6a  /u/osrmgr/Hardy/usmtest_vbspre25 -consecutive
                First execute usmtest for v940m6a, and then vbspre25, within each branch, the commands will be run concurrently

      $thisprog -sdsenv  day/mva-vb025  -onepmdir /u/sasos2/Hardy/OnePM_Test  -onepmid  MERGE1=DAY,DAYRR MERGE2=DAY_msi,DAY_msiRR  -portdate 20181018
                Get the final results of DAY and DAYRR, DAY_msi and DAY_msiRR for portdate 20181018, logs will be found in /u/sasos2/Hardy/OnePM_Test.

      $thisprog -sdsenv  day/mva-vb025  -onepmdir /u/sasos2/Hardy/OnePM_Test  -onepmid  -portdate 20181018
                The same as the above. 

      $thisprog -sdsenv  day/mva-vb025  -onepmdir /u/sasos2/Hardy/OnePM_Test  -onepmid  -portdate 20181018  -nomerge
                Show the separate results of each OnePM buildid . 

      $thisprog -sdsenv day/mva-vb025 -product txtminita  SAMPLESML
                Package two products.

      $thisprog -sdsenv day/mva-vb025 -product txtminita,samplesml -type opt -onepmid DAY
                Package two products of a specified buildid, only opt

      $thisprog -sdsenv day/mva-vb025 -product laxnd,laxno=txtminita,samplesml  -package rpm
                Package txtminita,samplesml for both laxno and laxnd, only rpm package

      $thisprog -time '2017-05-15 22:33'
                Search if there is any log file after 2017-05-15 22:33.

      $thisprog -time '2017-05-15 18:33~2017-05-15 22:33'
                Search if there is any log file between 2017-05-15 18:33 and 2017-05-15 22:33.


${\show_color(01)}HISTORY${\end_color()}

${\show_color(01)}BUGS${\end_color()}

______printEnd

exit();

}

sub show_color {
    my $color_code = $_[0];
    $color ="\e[01;${color_code}m";
}

sub end_color
{
        $NO= "\e[m";
}

sub dispose_leading_zeros {
    my $num = $_[0];
    if ( $num eq '000' ) {
       $num = 0;
    }
    else {
       $num =~ s/^0+//; 
    }
    return $num;
} 

sub add_leading_zeros {
    my $num = $_[0] + 1;
    $num = sprintf ("%03d", $num);
    return $num;
}

sub exists_zRR_log {
    my $log = $_[0];
    $log =~ s/_\d{8}_\d{6}_/*/;
    $log = "$log*zRR*";
    my $command = "ls -ltr $log  2>/dev/null | tail   -1 |  awk '{print \$NF}'";
    print "$command\n" if $debug && $verbose;
    my $zRR_log  = `$command 2>/dev/null`;
    my ( $zRR_part ) = ( $zRR_log =~ /(zRR-\d{3})/ );
    return $zRR_part;
}

sub onepm_command_generator {
    my (%args) = (@_);
    my ($logs_ref, $arr_ref) = ($args{values}, $args{user});
    my ($user_set_id, $merge_flag) = @$arr_ref;
    my ($level, $branch, $box, $onepm_type, $buildid);
    my @strings;
    @strings = ($level, $branch, $box, $onepm_type, $buildid) =  @{$args{keys}};
    my $pattern = '(Command:\s*.*onepm_packager.*)';
    my $regex =qr/$pattern/;
    my $flag = 0;
    print BOLD YELLOW "In onepm_command_generator, should be redeliverred log:\n", RESET if $debug;
    print Dumper $logs_ref if $debug;
    my $hash_ref = find_in_files_by_reg($logs_ref, $regex, "\n", $flag); # log name - cmd  hash
    my @strs_including_cmds = values %$hash_ref; # log - cmd  hash
    my $search_regex = "^Command:";
    my $replace_str = "export USER=osrmgr;suosrmgr";
    my $cmds = substitute(\@strs_including_cmds, $search_regex, $replace_str);
    $cmds = repo_update($cmds) if $user_repo_update;
    $cmds = ch_cmds($cmds, $user_set_id);
    push @strings, $cmds;
    return \@strings;
}

sub repo_update {
    my ($cmd_ref) = @_;
    my $pattern = "--datetime\\s{1,}\\d{8}_\\d{6}\\s|--wrapper_pid\\s{1,}\\d+\\s|--skip_repo_validation\\s";
    my $search_regex = qr/$pattern/;
    my $replace_str = "";
    my $cmds = substitute($cmd_ref, $search_regex, $replace_str);
    return $cmds;
}

sub ch_cmds {
    my ($cmds, $id) = @_;
    $cmds = ch_cmds_buildid($cmds, $id);
    $cmds = substitute($cmds, '$', ' >/dev/null 2>&1');
    return $cmds;
}

sub ch_cmds_buildid {
    my ( $cmds, $buildid )  = @_;
    my $search_regex = '--buildid\s+(?<original>[^\s]*)';
    for my $item (@$cmds) {
        if ($buildid) {
            my $replace_str = "--buildid $buildid";
            $item =~ s/$search_regex/$replace_str/;
        }
        else {
                $item =~ s[$search_regex]{
                                                my $original = $+{original}; ($original =~ /RR/) ?  "--buildid $original" : "--buildid ${original}RR";
                                         }e;
        }
    }
    return $cmds;
}

sub substitute {
    my ($arr, $search_regex, $replace_str) = @_;
    for my $item ( @$arr ) {
 	my $ref = ref($item);
	if (! $ref) { #$item is scalar
	    $item =~ s/$search_regex/$replace_str/g; 	
	}
	elsif ($ref eq "ARRAY") {
	    $_ =~ s/$search_regex/$replace_str/g for @$item;
	}

    }
    return $arr;
} 

sub get_delimiter {
    my ($delimiter) = @_;
    my $str;
    if (defined($delimiter)) {
	if ($delimiter) {
            $str = $delimiter;
 	}
	else {
            $str = "";
	}
    }
    else {
        $str = $/;
    }
    $str =~ s/\\n/\n/g; 
    return $str;
}

sub read_file_to_array {
    my ($file) = @_;
    my $delimiter = get_delimiter($user_delimiter);
    local $/ = $delimiter;
    my @lines;
    return [] unless -e $file;
    open my $handle, '<', $file;
    #chomp(@lines = <$handle>);
    while (<$handle>) {
	chomp;
	s/^\s+//;
	s/\s+$//;
	push @lines, $_;
    } 
    close $handle;
    return \@lines;
}

sub change_commands_zRR {
    my $cmds = $_[0];
    for my $cd ( @$cmds ) {
	if ( $cd =~ /--buildid .*zRR-(?<seq>[^\s]*)/ ) {	
	   my $seq = add_leading_zeros(dispose_leading_zeros($+{seq})) ;
	   my $zRR_part =  "zRR-$seq";
           $cd =~ s/--buildid (?<id>[^\s]*)zRR-\d{3}/--buildid $+{id}$zRR_part/;
        }
        else {
              $cd =~ s/--buildid\s+(?<bid>[^\s]*)/--buildid $+{bid}_zRR-000/;
	}
    }
    return $cmds;
}

sub get_platform {
    my %platforms = (
       'bb04'       =>      "unix",
       'bb03'       =>      "pc",
       'bb01'       =>      "mvs",
    );
    my $sys_name = `uname -n` ;
    my ( $name_index ) = ( $sys_name =~ /(.{4})/ );
    my $platform = (defined $userplatform ) ? $userplatform : $platforms{$name_index};
    return $platform;

}

sub getBuildType {
    my $build_type  = (@user_buildtypes)? \@user_buildtypes : [opt, dbg];
    return $build_type;
}

sub getOnePmType {
    my $onepm_types  = (@user_onepm_types)? \@user_onepm_types : ["release", ];
    return $onepm_types;
}

sub get_boxes {
    my ($hosts, $buildtype) = @_;
    my @boxes;
    for my $host  ( @$hosts ) {
        for my $bt ( @$buildtype ) {
	    my $box = box_generater($host, $bt); 
	    push @boxes, $box;
	}
    } 
    return \@boxes;
}

sub get_platform_bld {
    my ($platform) = @_;
    my $unx_bld  = '/sas/dev/tls-i1mb/bbtools/script/unx.bld';
    my $pc_bld   = '/sas/dev/tls-i1mb/bbtools/script/win.bld';
    my $mvs_bld  = '/sas/dev/tls-i1mb/bbtools/script/mvs.bld';
    my %platform_build = (
	'unix'     =>	$unx_bld,
	'pc'       =>	$pc_bld,
	'mvs'      =>	$mvs_bld,
    );
    my $build = $platform_build{$platform};
    return $build;
}

sub get_onepm_log_id {
    my (%args) = (@_);
    my ($level, $branch, $host) = @{$args{keys}}; 
    my ($metalogID, $arr_ref) = ($args{values}, $args{user}); 
    my ($hosts_onepmstrs_hash, $user_onepmid_ref, $buildtype, $onepm_types) = @$arr_ref;
    my $onepm_strs = $hosts_onepmstrs_hash->{$level}{$branch}{$host};
    print BOLD YELLOW "OnePM string in win.bld/unx.bld\n", RESET if $debug;
    print Dumper $onepm_strs if $debug;
    my @onepm_log_ids;
    my $hash_temp = {};
    my $boxes = get_boxes([$host], $buildtype);
    my @AOA = permute([$level],[$branch], $boxes, $onepm_types);
    if (@$user_onepmid_ref) {
	$hash_temp = getUserOnepmIds($user_onepmid_ref);
    } 
    elsif ($metalogID) {
	for my $package_str (@$onepm_strs) {
            $package_str =~ /onepm_package(?:(?<post>_\w+))?/;
            my $onepm_log_id = "${metalogID}$+{post}";
	    $hash_temp->{$onepm_log_id} = '';
        }
    }
    else {
	# get onepmid by appending substring from unx.bld/win.bld to metabuild ID
	$hash_temp = {};
    }
    map { push @$_, {%$hash_temp} }   @AOA;
    return \@AOA;
}

sub Tget_onepm_log_id {
    my (%args) = (@_);
    my ($level, $branch, $host) = @{$args{keys}};
    my ($metalogID, $arr_ref) = ($args{values}, $args{user});
    my ($hosts_onepmstrs_hash, $user_onepmid_ref, $buildtype, $onepm_types) = @$arr_ref;
    my $onepm_strs = $hosts_onepmstrs_hash->{$level}{$branch}{$host};
    my @onepm_log_ids;
    if (@$user_onepmid_ref) {  # user defined onepmid
        @onepm_log_ids = @$user_onepmid_ref;
    }
    elsif ($metalogID) { # get onepmid by appending substring from unx.bld/win.bld to metabuild ID
        for my $id (@$onepm_strs) {
            $id =~ /onepm_package(?:(?<post>_\w+))?/;
            my $onepm_log_id = "${metalogID}$+{post}";
            push @onepm_log_ids, $onepm_log_id;
        }
    }
    else { #This is where things become complex, metabuild ID could not be get, many reasons, not specified?, build not run? ...

    }
    my $boxes = get_boxes([$host], $buildtype);
    my @AOA = permute([$level],[$branch], $boxes, $onepm_types);
    for my $item (@AOA) {
        push @$item, [@onepm_log_ids];
    }
    print Dumper \@AOA;
    return \@AOA;
}

sub get_meta_dir {
    my (%args) = (@_);
    my ($level, $branch, $box, $onepm_type) = @{$args{keys}}; 
    my ($onepmID, $arr_ref) = ($args{values}, $args{user}); 
    my ($host_metalogIDs, $baseDir, $user_metalog_dir) = @$arr_ref;
    my ($host, $bt) = map_box_to_host_type($box);
    my $metalogID = $host_metalogIDs->{$level}{$branch}{$host};
    my $metalogDir = ($user_metalog_dir) ? $user_metalog_dir : "$baseDir/$metalogID"; 
    return [$level, $branch, $box, $onepm_type, $metalogDir];
}

sub get_hosts_meta_id {
    my ($hosts_onepmstr_pair, $metalog_baseDir, $user_metalog_id, $portdate) = @_;
    my $metalogID_strings = start_travel_any_do_any($hosts_onepmstr_pair, {process=>{code=>\&get_meta_id, args=>[$metalog_baseDir, $user_metalog_id, $portdate]}}, -1);
    my $host_metalogID_pair = constructHash($metalogID_strings,'', -1);
    return $host_metalogID_pair;
}

sub get_metaDir_hash {
    my ($host_buildids, $host_metalogIDs, $metalog_baseDir, $user_metalog_dir) = @_;
    my $metalogDir_strings = start_travel_any_do_any($host_buildids, {process=>{code=>\&get_meta_dir, args=>[$host_metalogIDs, $metalog_baseDir, $user_metalog_dir]}}, -1);
    my ($pattern, $regex);
    my $host_metaDir_hash;
    if (@$user_hosts) {
        $pattern = join('|', @$user_hosts);
        $regex =qr/$pattern/;
    }
    $host_metaDir_hash = constructHash($metalogDir_strings, $regex, -1);
    print BOLD GREEN "host_metalogDir:\n", RESET if $debug;
    print Dumper $host_metaDir_hash if $debug;
    return $host_metaDir_hash;
}

sub host_buildids {
    my ($hosts_onepmstr_pair, $host_metalogIDs, $metalog_baseDir, $user_onepmid_ref, $user_hosts, $buildtype, $onepm_types) = @_;
    my $args = [$hosts_onepmstr_pair, $user_onepmid_ref, $buildtype, $onepm_types];
    my $buildid_strings = start_travel_any_do_any($host_metalogIDs, {process=>{code=>\&get_onepm_log_id, args=>$args}});  
    print BOLD GREEN "host_metalogids:\n", RESET if $debug;
    print Dumper $host_metalogIDs if $debug;
    print BOLD GREEN "host_onepmstr:\n", RESET if $debug;
    print Dumper $hosts_onepmstr_pair if $debug;
    my ($pattern, $regex);
    if (@$user_hosts) {
        $pattern = join('|', @$user_hosts);
        $regex =qr/$pattern/;
    }
    my $host_buildids_pair = constructHash($buildid_strings, $regex, -2);
    print BOLD GREEN "host_buildids:\n", RESET if $debug;
    print Dumper $host_buildids_pair if $debug;
    return $host_buildids_pair;
}

sub permute {
    my $last = pop @_;
    unless(@_) {
           return map([$_], @$last);
    }
    return map {
                 my $left = $_;
                 map([@$left, $_], @$last)
               }
               permute(@_);
}

sub metalog_path_filter {
    my ($path, $onepmid) = @_;
    my $flag = 1;
    if ($path =~ /(?<=onepm_package)\.log$/) {
	$flag = 0 if ($onepmid =~ /_/);
    }
    else {
	$flag = 0 if ($onepmid !~ /_/);
    }
    return $flag;
}

sub generate_metalog {
    my (%args) = @_;
    my ($level, $branch, $box, $onepm_type, $onepmid) = @{$args{keys}};
    my ($host) = (map_box_to_host_type($box))[0];
    my ($hosts_onepmstr_pair, $metalogDir_hash, $lan) = @{$args{user}};
    my $metalogDir = $metalogDir_hash->{$level}{$branch}{$box}{$onepm_type};
    my $onepm_strs = $hosts_onepmstr_pair->{$level}{$branch}{$host};   #  $VAR1 = [  'onepm_package',  'onepm_package_msi'];
    my @targets;
    for my $op_str (@$onepm_strs) {
        my $log_path = metalog_path($level, $branch, $box, $lan, $op_str, $metalogDir);
        next if ! metalog_path_filter($log_path, $onepmid); 
        push @targets, [$level, $branch, $box, $onepm_type, $onepmid, $log_path];
        
    }
    return \@targets;
}

sub get_metabuild_logs {
    my ($lan, $host_buildids_pair, $metalogDir_hash, $hosts_onepmstr_pair) = @_;
    my $metalog_strings = start_travel_any_do_any($host_buildids_pair, {process=>{code=>\&generate_metalog, args=>[$hosts_onepmstr_pair, $metalogDir_hash, $lan]}});
    my @hash_list;
    for my $item (@$metalog_strings) {
	for my $sub_item (@$item) {
        	my $keys_str =  join('/', @{$sub_item}[0..@$sub_item-2]);
        	my $value = $sub_item->[-1];
        	my $hash = constructHashFromStr($keys_str, $value);
        	push @hash_list, $hash;
	}
    }
    my $host_metalogs = merge_hashes({}, \@hash_list);
    return $host_metalogs;
}

sub getInitialFailureLog  {
    my ($logs_of_all_boxes) = @_;
    my $error_msg = "ERROR FOUND DURING PACKAGING!";
    my $success_msg = "PACKAGING COMPLETED SUCCESSFULLY";
    my $error_msg_regex = qr/$error_msg/;
    my $logs_with_initial_failure = find_in_files_by_reg($logs_of_all_boxes, $error_msg_regex, "\n", 0);  #hash
    my @logs_with_error = keys %$logs_with_initial_failure; 
    return \@logs_with_error;
}

sub hosts_onepmstr_from_config {
    my ($platform, $level, $branch_ref, $user_hosts) = @_;
    my $branch_str = join('|', @$branch_ref);
    my $platform_bld = get_platform_bld($platform);
    my $non_supp_pattern = "^(?<!#)\\s*%metabuild.*?${level}.*?,\\s+(${branch_str}).*onepm_package.*\\/\\*\\s*supp\\s*\\*\\/\\s*\\)";
    my $supp_pattern = "^(?<!#)\\s*%metabuild.*?${level}.*?,\\s+(${branch_str}).*onepm_package.*supp\\s*\\)";
    my $pattern = ($supplemental) ? $supp_pattern : $non_supp_pattern;
    my $regex = qr/$pattern/;
    print "Branch and hosts info are gotten from $platform_bld\n\n" if ! @user_products;
    print "$pattern\n" if $debug;
    print "$regex\n" if $debug;
    my $target_lines_hash = find_in_files_by_reg([$platform_bld], $regex, "\n", 1);
    my ($targets_lines) = values %$target_lines_hash;
    print Dumper $targets_lines if $debug;
    my @hash_arr;
    my $pattern = join('|', @$user_hosts);
    my $filter =qr/$pattern/;
    for my $line (@$targets_lines) {
        my (@hosts, @onepm_str);
	next unless $line !~ /#/;
	my ($host_str, $config_str) = (split('\s*,\s*', $line))[4,6];
	@hosts = grep {! /com/} split('\s', $host_str);
	@onepm_str = grep {/onepm_package/} split(' ', $config_str);
	for my $branch (@$branch_ref) {
	    next unless $line =~ /$branch/;
	    for my $host (@hosts) {
	    	my $str = "${level}/${branch}/${host}";
	    	next unless $str =~ /$filter/;
	    	my $hash = constructHashFromStr($str, [@onepm_str]);
	    	push @hash_arr, $hash;
	    }
	}
    }
    my $onepmStr_hash = merge_hashes({}, \@hash_arr);
    return $onepmStr_hash;
}

sub portdate {
    my ($lookthrough) = @_;
    return $userportdate if $userportdate;
    for my $env (@$lookthrough) {
	my ($level, $branch) = (split(/-|\//, $env))[0, 2];
        my $cd = "/usr/local/bin/getportdate /sas/$level/mva-$branch/hostcm/h/wzport.h 2>/dev/null";
        print  "${\show_color(32)}portdate command is:${\end_color()} $cd\n" if $debug && ! $userportdate;
        my $portdate = `$cd`;
	return $portdate if $portdate;
    }
    print BOLD YELLOW "\nPlease check the sdsenv or branch option.\n", RESET; 
    exit(1);
}

sub diffdate {
    my ($earlier, $later) = @_;
    my $difference = Delta_Days( @$earlier, @$later );
    return $difference;
}

sub splitime {
    my $time = $_[0];
    my ( $y, $m, $d ) = ( $time =~ /(\d{4})-?(\d{2})-?(\d{2})/ );
    my @slice = ( $y, $m, $d );
    return \@slice;
}

sub lev_branch_helper {
    my $sdsenv = $_[0];
    my @lev_branch;
    my ($lev, $branch) = ($sdsenv =~ /(\w+)\/(?:\w+)-(\w+)/);
    push @lev_branch , $lev, $branch;
    return @lev_branch;
}


sub get_sdsenv {

    if ( defined $user_sdsenv ) {
       $sdsenv  =  $user_sdsenv;
    }
    else {
       $sdsenv  =  $ENV{SDSENV};
    }
    return  $sdsenv;
}

sub get_lookthrough {
    my ($sdsenv) = @_;
    my $cd = "sdsenv | grep SDSLOOK"; 
    my $ksh_cd = "ksh -c \'. /sas/tools/com/sdskshrc ; sdsenv $sdsenv; $cd\'";
    my $lookthrough_str = `$ksh_cd`;
    chomp $lookthrough_str;
    my @tmp = split(/=|:/, $lookthrough_str);
    my $length = @tmp;
    my @lookthrough = @tmp[1 .. $length-1];
    return \@lookthrough;
}

sub get_lev_branch {
    my $sdsenv = $_[0];
    @lev_branch = lev_branch_helper( $sdsenv );
    return @lev_branch;
}

sub map_buildtype_to_box {
    my $buildtype = $_[0]; 

    my %map_opt_debug_to_box = (
       "opt"	=>	"no",
       "dbg"	=>	"nd",
    ) ;
    return $map_opt_debug_to_box{$buildtype};
}

sub map_box_to_buildtype {
    my $box = $_[0]; 

    my %map_opt_debug_to_box = (
       "no"	=>	"opt",
       "do"	=>	"opt",
       "nd"	=>	"dbg",
       "dd"	=>	"dbg",
    ) ;
    return $map_opt_debug_to_box{$box};
}

sub split_string {
    my ($str, $num) = @_;
    my ($pre, $post) = ($str =~ /(\w+)(\w{$num})$/);
    return ($pre, $post);
}

sub get_Time_slice {
    my $time_slice;
    if (defined($start_end)) {
        if ( my ( $time_begin, $time_end ) = ($start_end =~ /(.*?)\s*~\s*(.*)$/) )  {
             $time_slice = "-newermt '$time_begin' -not -newermt '$time_end'";
        }
        else {
             $time_slice = " -newermt '$start_end'";
        }
    }
    return $time_slice; 
}

sub onepm_dir {
    my ($branch, $dev_or_wky) = @_;
    my $onepm_dir = "/sas/${dev_or_wky}/mva-$branch/LOG/PACKAGING/";
    return $onepm_dir; 
}

sub file_reg_alternative {
    print "@_\n" if $debug;
    my (%args) = @_;
    my ($portdate, $level, $branch, $host, $buildtype, $package_types, $buildid_reg, $onepm_types, $date_diff, $time_slice) = 
    ($args{portdate},$args{level},$args{branch},$args{host},$args{buildtype},$args{packagetypes},$args{buildid}, $args{ops}, $args{datediff}, $args{timeslice});
    my $products = $args{products};
    my $platform = get_platform();
    my %regex;
    my ($pre, $post);
    my $pre = ".*${portdate}\\.packager_${level}_mva_${branch}_${host}_";
    my $products_str = join('|', @$products) if @$products;
    $products_str = ($products_str && $platform =~ /pc/) ? "(msi)?($products_str)"  : $products_str;
    my $package_types_str = join('|', @$package_types) if @$package_types; 
    my $onepm_types_str = join('|', @$onepm_types) if @$onepm_types; 
    if ( $products_str ) {
        if ($package_types_str) {
      	    $post = "($products_str)([[:digit:]]{1,})?_(${package_types_str})_${buildtype}_";
	}
	else {
 	    $post = "($products_str)([[:digit:]]{1,})?_.*_${buildtype}_";
	}
    }
    else {
        if ($package_types_str) {
	    $post = ".*(${package_types_str})_${buildtype}_";
 	}
	else {
      		$post = ".*_${buildtype}_";
	}
    }
    if ($onepm_types_str) {
       	$post = $post . "(${onepm_types_str})_.*${buildid_reg}";
    }
    else {
        $post = $post . ".*${buildid_reg}";
    }
    my $main_reg = $pre . $post ;
    my $maxdepth = search_maxdepth($date_diff, $user_max_depth); #BE CAREFUL! $user_max_depth here IS  A GLOBAL VIRABLE!!!
    $regex{not_trace} = "'$main_reg' -maxdepth $maxdepth $time_slice" ;
    print "${\show_color(32)}Regex to match trace and non trace logs under directory of packaging for $buildtype:${\end_color()}:\n" if  $debug ;
    print Dumper \%regex if $debug;
    return \%regex;
}

sub retrieveValueByStr {
    my ($hash, $str) = @_;
    if (exists $hash->{$str}) {
	($hash->{$str}) ? return $hash->{$str} : return $str; 
    }
    else {
	for my $key (sort {$b cmp $a} keys %$hash) {
	    my @common_str = common_string($key, $str, -1);
	    if ($str =~ /$key/ || scalar @common_str >= 4) {
		($hash->{$key}) ?  return $hash->{$key} : return $key;
	    }
	}
    }
}

sub common_string {
    my ($str1, $str2, $direction) = @_;
    my (@arr1, @arr2);
    if ($direction == -1) {
	@arr1 = reverse split(//, $str1);
	@arr2 = reverse split(//, $str2);
    }
    else {
	@arr1 =  split(//, $str1);
	@arr2 =  split(//, $str2);
    }
    my $len1 = scalar @arr1;
    my $len2 = scalar @arr2;
    my $smaller = ($len1 <= $len2) ? $len1 : $len2;
    my @common;
    for $i (0 .. $smaller-1) {
	if ($arr1[$i] eq $arr2[$i]) {
	    push @common, $arr1[$i];
	}
	else {
	    last;
	}
    } 	
    return ($direction == -1 ) ? return reverse @common : return @common;
}

sub getUserOnepmIds {
    my ($user_onepmids) = @_;
    my $hash = {};
    for my $item (@$user_onepmids) {
	if ( match(['='], [$item]) ) {
	    my @arr = split(/=|,/,$item);
	    my $first = shift @arr;
	    for my $value (@arr) {
		$hash->{$value} = $first;
	    }
	}
	else {
	    $hash->{$item} = '';
	}
    }
    return $hash;
}

sub getSubHashByDepth {
    my ($hash, $depth) = @_; 
    my $sub_hashs = start_travel_any_do_any($hash, {process=>{code=>sub {my (%args) = @_; my $sub_hash = $args{values}; return $sub_hash;}}}, $depth-1); 
    return $sub_hashs;
}

sub getSubHashByTemplate {
    my ($hash, $template) = @_; 
    my $retrieved_string = start_travel_any_do_any($hash, {process=>{code=>\&getSubHashByTemplateHelper, args=>[$template]}}, -2);
    my $retrieved_hash = constructHash($retrieved_string, '', -3);
    print BOLD YELLOW "Retrieved OnePM logs using initail failed log hash as template:\n", RESET if $debug;
    print Dumper $retrieved_hash if $debug;
    return $retrieved_hash;
}

sub getSubHashByTemplateHelper {
    my (%args) = (@_);
    my ($level, $branch, $box, $onepm_type, $id_Key, $sub_hash) = (@{$args{keys}}, $args{values});
    my $user_arg = $args{user};
    my ($template) = @$user_arg;
    my $tmp = $template->{$level}{$branch}{$box}{$onepm_type}{$id_Key};
    my @keys = keys %$tmp;
    my %retrieved =  %{$sub_hash}{@keys};
    my $target = (keys %retrieved) ? [$level, $branch, $box, $onepm_type, $id_Key, \%retrieved] : [];
    return $target;
}

sub get_mergeFlag {
    my ($host_buildids, $user_nomerge_flag, $user_onepmid_arr) = @_;
    my ($onepm_ids_ref, $merge_keys_ref) = get_onepm_id_merge_pair($host_buildids);
    my @non_null_merge_keys = grep {$_} @$merge_keys_ref;
    print "non_null_merge_keys: @non_null_merge_keys\n" if $debug;
    print "user_onepmid_arr: @$user_onepmid_arr\n" if $debug;
    my $merge_flag;
    if ($user_nomerge_flag || (! @non_null_merge_keys && @$user_onepmid_arr)) {
	$merge_flag = 0;
    }
    else {
	$merge_flag = 1;
    }
    return $merge_flag;
}

sub get_onepmidAttri {
    my ($user_onepmid_arr) = @_;
    my $flag = (@$user_onepmid_arr) ? 1 : 0;
    return $flag;
}

sub reverse_hash {
    my (%args) = (@_);
    my ($level, $branch, $box, $onepm_type, $hash) = (@{$args{keys}}, $args{values});
    my $inverse = {};
    for my $key (keys %$hash) {
	if ($hash->{$key}) {
    	    push @{ $inverse->{ $hash->{$key} } }, $key;
	}
	else {
    	    push @{ $inverse->{$key} }, $key;
	}
    }
    my $target = [$level, $branch, $box, $onepm_type, $inverse];
    return $target; 
}

sub mergekey_onepmids_hash { #this is reverse of the hash: host_buildids
    my ($host_buildids) = @_;
    my $strings = start_travel_any_do_any($host_buildids, {process=>{code=>\&reverse_hash}}, -1); 
    my $mergekey_onepmids = constructHash($strings, '', -3);
    print BOLD YELLOW "this is reverse hash of a sub hash of host_buildids\n", RESET if $debug; 
    print Dumper $mergekey_onepmids if $debug;
    return $mergekey_onepmids;
}

sub buildIdRegString {
    my (%args) = (@_);
    my ($level, $branch, $box, $onepm_type, $id_Key) = @{$args{keys}};
    my ($onepm_ids_ref, $key_onepmid_hash);
    if ($id_Key) {
	$onepm_ids_ref = $args{values};
    }
    else {
	$key_onepmid_hash = $args{values};
	my @onepmids;
	for my $tmp (keys %$key_onepmid_hash) {
	    push @onepmids, @{$key_onepmid_hash->{$tmp}};
	}
	$onepm_ids_ref = \@onepmids;
    }
    my $tmp = $args{user};
    my ($user_onepmid_attri) = @$tmp;
    $onepm_ids_ref = sort_by_length($onepm_ids_ref, 1);
    my $onepmids_str = join('|', @$onepm_ids_ref);
    print "user_onepmid_attri: $user_onepmid_attri\n" if $debug;
    my $buildreg;
    if ($user_onepmid_attri == 0) {
	$buildreg =  "(($onepmids_str)[^.]*)(\\.gz)?\$"; 
    }
    elsif ($user_onepmid_attri == 1) {
	$buildreg = "($onepmids_str)(\\.gz)?\$"; 
    }
    else {
	print "undefined user_onepmid_attri: $user_onepmid_attri, variable \$buildreg not set\n";
    }
    my $target = ($id_Key) ? [$level, $branch, $box, $onepm_type, $id_Key, $buildreg]: [$level, $branch, $box, $onepm_type, $buildreg];
    return $target;
}

sub logpostRegexBybuildid {
    my ($mergekey_onepmids, $user_onepmid_attri, $depth) = @_;
    print BOLD YELLOW "mergekey_onepmids:\n", RESET if $debug;
    print Dumper $mergekey_onepmids if $debug;
    my $buildidreg_strings = start_travel_any_do_any($mergekey_onepmids, {process=>{code=>\&buildIdRegString, args=>[$user_onepmid_attri]}}, $depth);
    my $logpost_reg = constructHash($buildidreg_strings, '', -1);
    print "logpost_reg, this is the final hash used to generate the buildid regex to find OnePM logs:\n" if $debug;
    print Dumper $logpost_reg if $debug;
    return $logpost_reg;
}

sub get_onepm_id_merge_pair {
    my ($host_buildids) = @_;
    my $sub_hash_array = getSubHashByDepth($host_buildids, 5);
    my $sub_hash1 = $sub_hash_array->[0];  # onepmid=>merge_key
    my @onepm_ids = keys %$sub_hash1;
    my @merge_keys = values %$sub_hash1;
    return (\@onepm_ids, \@merge_keys);
}

sub sort_by_length {
    my ($list, $descend) = @_;
    my @tmp;
    if ($descend) {
        @tmp = sort {length($b) <=> length($a)} @$list ;
    }
    else {
        @tmp = sort {length($a) <=> length($b)} @$list ;
    }
    $list = \@tmp;
    return $list;
}

sub product_parser {
    my ($logs, $lan, $host_buildids, $merge_flag, $logpost_reg) = @_; 
    my %product_info;
    my $onepmid_regex_array = getSubHashByDepth($logpost_reg, 5);
    my $onepmid_regex = $onepmid_regex_array->[0]; 
    my $sub_hash_array = getSubHashByDepth($host_buildids, 5);
    my $onepmid_mergekey = $sub_hash_array->[0];  # onepmid=>merge_key
    print BOLD YELLOW "From OnePM ID to merge key:\n", RESET if $debug ;
    print Dumper $onepmid_mergekey if $debug;
    print "In function product_parser onepmid_regex: $onepmid_regex\n" if $debug;
    print "In function product_parser merge_flag = $merge_flag\n" if $debug;
    my $pattern = "\\d{8}\\.packager_(\\w+?)_mva_(\\w+?)_(\\w+?)_(\\w+?)_(\\w+?)_(\\w+?)_(\\w+?)_(\\d+_\\d+)_(?:\\w*?)(?:$onepmid_regex)";
    my $regex = qr/$pattern/;
    print BOLD GREEN "Regex used to parse OnePM logs:\n", RESET if $debug;
    print "$regex\n" if $debug;
    for my $item ( @$logs ) {
	next if $item =~ /\.trace|\.json/;
        next unless ( $item =~ /\d{8}\.packager_(\w+?)_mva_(\w+?)_(\w+?)_(\w+?)_(\w+?)_(\w+?)_(\w+?)_(\d+_\d+)_.*(\.trace)?/ ) ;
	#20171108.packager_wky_mva_vb010_hdl_sepcorehadp_rpm_dbg_milestone_20171121_184521_WKY-daily
        my @tmp = ($item =~ /$regex/);
	next if ! @tmp;
	my ($level,$branch,$host,$product,$pkg_type,$opt_debug,$type,$time,$onepmid) = @tmp;
        my $full_product = $product  . '__' . $lan . '__' . $pkg_type;
	my $box = box_generater($host, $opt_debug);
	if ($merge_flag) {
	    my $merge_key = retrieveValueByStr($onepmid_mergekey, $onepmid); 
	    print "=====$merge_key  $onepmid======(merge_key : onepmid)\n" if $debug;
            push @{ $product_info{$level}{$branch}{$box}{$type}{$merge_key}{$full_product} } ,  $item;
            @{ $product_info{$level}{$branch}{$box}{$type}{$merge_key}{$full_product} } = sort { (stat($a))[9] <=> (stat($b))[9] } 
											@{ $product_info{$level}{$branch}{$box}{$type}{$merge_key}{$full_product} } ;
	}
	else {
            push @{ $product_info{$level}{$branch}{$box}{$type}{$onepmid}{$full_product} }  , $item;
            @{ $product_info{$level}{$branch}{$box}{$type}{$onepmid}{$full_product} } = sort { (stat($a))[9] <=> (stat($b))[9] } 
											@{ $product_info{$level}{$branch}{$box}{$type}{$onepmid}{$full_product} } ;
        }
   }
   print "\n";
   start_travel_any_do_any(\%product_info, {print=>\&print_data}) if $debug && $verbose;
   return \%product_info;
}

sub metalog_path {
    my ($level, $branch, $box, $lan, $op_str, $metalogDir) = @_;
    my $item = "${metalogDir}/task.${level}.mva.${branch}.${box}.ne.${lan}.${op_str}.log";
    return $item;
}

sub onepm_wrapper_log_generater {
    my ($level, $branch, $portdate, $host, $buildtype, $onepm_type, $buildid_regex, $host_buildids, $user_onepmid_attri, $merge_key) = @_;
    my $basename_reg = ".*${portdate}.packager_wrapper_${branch}_${host}_${buildtype}_${onepm_type}_.*_${buildid_regex}"; 
    print "In onepm_wrapper_log_generater:\n" if $debug;
    print "basename regex: $basename_reg\n" if $debug;
    my $path = "/sas/${level}/mva-${branch}/LOG/PACKAGING/";
    my $cmd ;
    my ($onepm_ids_ref) = get_onepm_id_merge_pair($host_buildids);
    my $time_slice = get_Time_slice();

    my $today = `date "+%Y%m%d"`;
    my $pt = splitime($portdate);
    my $td = splitime($today);
    my $date_diff = diffdate( $pt, $td );
    my $maxdepth = search_maxdepth($date_diff, $user_max_depth); #BE CAREFUL! $user_max_depth here IS  A GLOBAL VIRABLE!!!
    my $depth_str = "-maxdepth $maxdepth" ;
    my $arr_num = @$onepm_ids_ref;
    if ($user_onepmid_attri) {
        $cmd = "find -E $path -regex '$basename_reg' $depth_str $time_slice";
    }
    elsif ($arr_num > 1) {
        $onepm_ids_ref = delete_item_from_array($onepm_ids_ref, $merge_key); #in this case, merge_key is equal to onepm buildid
	my $filter_str = join('|', @$onepm_ids_ref);
        $cmd = "find -E $path -regex '$basename_reg' $depth_str $time_slice | egrep -v '$filter_str(\\.gz)?\$' ";
    }
    else {
        $cmd = "find -E $path -regex '$basename_reg' $depth_str $time_slice";
    }
    print BOLD YELLOW "Commands used to find wrapper logs:\n", RESET if $debug || $usedcd;
    print "$cmd\n\n" if $debug || $usedcd;
    chomp(my @log = `$cmd`);
    return \@log;
}

sub delete_item_from_array {
    my ($arr_ref, $value_to_del) = @_;
    my $index = 0;
    for my $item (@$arr_ref) {
	if ($item !~ /^$value_to_del$/) {
	    $index++;
	}
	else {
	   last;
	}
    }
    my $num = @$arr_ref;
    splice(@$arr_ref, $index, 1) if $index <= $num - 1;
    return $arr_ref;
}

sub box_generater {
    my ($host, $buildtype) = @_;
    my $post = map_buildtype_to_box($buildtype);
    my $box = "$host$post";
    return $box;
} 

sub onepm_wrapper_logs {
    my ($logpost_reg, $portdate, $host_buildids, $user_onepmid_attri) = @_;
    my $onepm_wrapperLogs_strings = [];
    $onepm_wrapperLogs_strings = start_travel_any_do_any($logpost_reg, {process=>{code=>\&get_wrapper_logs, args=>[$portdate, $host_buildids, $user_onepmid_attri]}});
    my $wrapper_logs = constructHash($onepm_wrapperLogs_strings, '', -2 );
    print BOLD GREEN "wrapper_logs:\n", RESET if $debug;
    print Dumper $wrapper_logs if $debug;
    return $wrapper_logs;
}

sub get_wrapper_logs {
    my (%args) = (@_);
    my ($level, $branch, $box, $onepm_type, $mergekey) = @{$args{keys}};
    my $arr_ref = $args{user};
    my ($portdate, $host_buildids, $user_onepmid_attri) = @$arr_ref;
    my $regex = (! $user_onepmid_attri) ? $args{values} : $mergekey . '(\.gz)?';
    my ($host, $buildtype) = map_box_to_host_type($box);
    my $logs_ref = onepm_wrapper_log_generater($level, $branch, $portdate, $host, $buildtype, $onepm_type, $regex, $host_buildids, $user_onepmid_attri, $mergekey);
    my $target = [$level, $branch, $box, $onepm_type, $mergekey, $logs_ref] ;
    return $target; 
}

sub onepm_wrapper_times {
    my ($wrapper_logs) = @_;
    my $wrapper_timeStrings = start_travel_any_do_any($wrapper_logs, {process=>{code=>\&get_wrapper_times}}, -1);
    my $wrapper_times = constructHash($wrapper_timeStrings, '', -3 );
    print BOLD GREEN "wrapper times:\n", RESET if $debug;
    print Dumper $wrapper_times if $debug;
    return $wrapper_times;
}

sub extract_time {
    my ($string) = @_;
    my ($time) = ($string =~ /^(?:START|END) TIME .*-\s+(.*)/);
    return $time;
}

sub get_wrapper_times {
    my (%args) = (@_);
    my ($level, $branch, $box, $onepm_type, $mergekey, $wrapperlog_arr) = (@{$args{keys}}, $args{values});
    return [] unless @$wrapperlog_arr;
    my $times = [];
    my ($start_pattern, $end_pattern) = ('^START TIME .*-\s+(?<time>.*)$', '^END TIME .*-\s+(?<time>.*)$');
    my $start_end_pattern = '^START TIME .*-\s+(?<time>.*)$|^END TIME .*-\s+(?<time>.*)$';
    my ($start_regex, $end_regex, $start_end_reg) = (qr/$start_pattern/, qr/$end_pattern/, $start_end_pattern);
    print BOLD GREEN "start_regex:\n", RESET  if $debug;
    print "$start_regex\n"  if $debug;
    print BOLD GREEN "end_regex:\n", RESET  if $debug;
    print "$end_regex\n"  if $debug;
    my $start_end_time = find_in_files_by_reg($wrapperlog_arr, $start_end_reg, "\n", 1, '', '', \&extract_time);
    return [$level, $branch, $box, $onepm_type, $mergekey, $start_end_time];
}

sub retried_products {
    my $onepm_log = $_[0];
    my %retried_products;
    open( my $LOG, "<", $onepm_log ) or die "cannot open $onepm_log $!"; 
    while ( <$LOG> ) {
       chomp;
       if ( /^\*\*\*\s*RETRY PACKAGING FOR EXPORT TO (?<type>\w+):\s*\*\*\*$/../^$/ ) {
           push @{ $retried_products{$+{type}} }, $_ if $_ !~ /\*\*\*/;
       }
    }
    close $LOG;
    return \%retried_products;
}

sub find_in_files_by_reg {
    my ($files, $regex, $delimiter, $flag, $section_start, $section_end, $code) = @_;   #flag = 0 : find the first match and exit, $flag =1: find all matches
    local $/ = $delimiter;
    my %targets;
    for my $file (@$files) {
	my $LOG;
	if ($file =~ /\.gz$/) {
        	open( $LOG, "gunzip -c $file |" ) or die "cannot gunzip $file $!"; 
 	}
	else {
        	open( $LOG, "<", $file ) or die "cannot open $file $!"; 
	}
        while ( <$LOG> ) {
              chomp;
	      s/^\s+//;
	      if ($section_start && $section_end) {
	         if ( /$section_start/ .. /$section_end/) {
                     if (/($regex)/) {
			 if ($code) {
 	                 	($flag == 1) ?  push @{$targets{$file}}, $code->($1) : do {  $targets{$file} = $code->($1);last; };
			 }
			 else {
 	                 	($flag == 1) ?  push @{$targets{$file}}, $1 : do {  $targets{$file} = $1;last; };
			 }
                     }
	         }
	      }
	      else {
                     if (/($regex)/) {
			 if ($code) {
 	                 	($flag == 1) ?  push @{$targets{$file}}, $code->($1) : do {  $targets{$file} = $code->($1);last; };
			 }
			 else {
 	                 	($flag == 1) ?  push @{$targets{$file}}, $1 : do {  $targets{$file} = $1;last; };
			 }
                     }
	      }
        }
        close $LOG;
    }
    return \%targets;
}

sub succeed_item {
    my $line = $_[0];
    $line =~ /^SUCCEEDED PACKAGING\s+(?<product>(\w+))$/;
    return $+{'product'}; 
}

sub get_succeed_products {
    my $onepm_log = $_[0];
    my %succeed_products;
    open( my $LOG, "<", $onepm_log ) or die "cannot open $onepm_log $!"; 
    while ( <$LOG> ) {
       chomp;
       if ( /^\+\s*suosrmgr.*?(?<type>milestone|release)/ ../^exit status is \d+$/ ) {
          my $onepm_type = $+{type};
          if ( $_ =~ /^SUCCEEDED PACKAGING\s+(?<product>(\w+))$/ ) {
             push @{ $succeed_products{$onepm_type} }, $+{"product"} ;
          }
       }
    }
    close $LOG;
    return \%succeed_products;
}

##################SET API #################
sub difference_of_set {
    my @arr = @_; 
    my $ref1 = shift @arr;
    my @arr1 = @$ref1;
    my %tmp;
    @tmp{@arr1} = undef;
    for my $ref (@arr) {
	my @items = @$ref;
    	delete @tmp{@items};
    }
    my @diff = keys %tmp;
    return @diff;
}

sub sys_diffs {
   my ($a_ref, $b_ref) = @_;
   my %count;
   my @diff;
   foreach my $e (@$a_ref, @$b_ref) { $count{$e} = $count{$e} +1; }
   foreach my $e (keys %count) {
     if ($count{$e} == 1) {
        push @diff, $e ;
     }
   }
   return @diff;
}

sub intersection {
   my ($a_ref, $b_ref) = @_;
   my %count;
   my @inter;
   foreach my $e (@$a_ref, @$b_ref) { $count{$e} = $count{$e} +1; }
   foreach my $e (keys %count) {
     if ($count{$e} == 2) {
        push @inter, $e ;
     }
   }
   return \@inter;
}

sub get_failed_products_from_metalog {   #dead
    my ( $full_logpath, $trace_products_ref_of_type, $type, $branch, $box ) = @_;
    my $success_products = get_succeed_products($full_logpath); 
    my $success_products_of_type = $success_products->{$type}; 
    
    print "${\show_color(32)}Successful built products of box $box type $type:${\end_color()} \n" if $debug && $verbose;
    if ($debug && $verbose) { 
       print "$_\n" for @$success_products_of_type ;
    }
    if ( @$success_products_of_type ) {
      @failed_products = difference_of_set($trace_products_ref_of_type, $success_products_of_type); 
      return @failed_products;
    }
}

sub getTypedResults {
    my ($sub_retrieved, $sub_initFailed) = @_;
    my (@r1Fails, @r2Fails, @rP2Fails, @r1Success, @r2Success, @rP2Success, @remainFails);
    my  @argues = \(@r1Fails, @r2Fails, @rP2Fails, @r1Success, @r2Success, @rP2Success);
    while (my ($prod, $failed_logs) = each  %$sub_initFailed) {
        my $last_failed = $failed_logs->[-1];
    	my $files_run = $sub_retrieved->{$prod}; # all logs of the onepmids specified by $onepmids
	my ($run_num, $failed_num) = (scalar @$files_run, scalar @$failed_logs);# all log numbers and failed ones
	my $last_run = $files_run->[-1]; # last log of the runs
	if ($failed_num == $run_num) {  # there was no successfull runs in all the logs
	    push @remainFails, $last_failed;
	    setFailsSuccess(@argues, $files_run, $failed_logs);
	}
	else { # exists success in the runs
	    if ($last_failed eq $last_run) { # if the last run fails
		push @remainFails, $last_failed;
	        setFailsSuccess(@argues, $files_run, $failed_logs);
	    }
	    else { # if the last run succeeds
	        setFailsSuccess(@argues, $files_run, $failed_logs);
	    }
	}
    }
    return \(@r1Fails, @r2Fails, @rP2Fails, @r1Success, @r2Success, @rP2Success, @remainFails);
}

sub setFailsSuccess {
    my ($r1Fails, $r2Fails, $rP2Fails, $r1Success, $r2Success, $rP2Success, $files_run, $failed_logs) = @_;
    my $length = scalar @$files_run;
    my $index = 1;
    my ($last_fail, $last_success);
    for my $run_item (@$files_run) {              # here we find the successfull  and failed logs by:
	if (grep(/$run_item/, @$failed_logs)) {   # Traversing all the run logs, if the log:
	    if ($index == 1) {                    # 1: failed, we get the index of the log  and push it in the corresponding failed arrays
		push @$r1Fails, $run_item;	  # 2: succeed, we get the index of the log  and push it in the corresponding succeed arrays
	    }
	    elsif ($index == 2) {
		push @$r2Fails, $run_item;
	    }
	    elsif ($index > 2) {
   		push @$rP2Fails, $run_item; 
	    }
	}	
	else {
	    if ($index == 1) {
		push @$r1Success, $run_item;
	    }
	    elsif ($index == 2) {
		push @$r2Success, $run_item;
	    }
	    elsif ($index > 2) {
   		push @$rP2Success, $run_item; 
	    }
	}
	$index += 1;
    }
   #push @$rP2Fails, $last_fail if $last_fail; 
   #push @$rP2Success, $last_success if $last_success; 
}

sub get_diffs_between_trace_and_retried_prods {
    my ($retried_prods_from_log_of_type, $trace_prods_ref) = @_;
    my @Sysdiff = sys_diffs($retried_prods_from_log_of_type, $trace_prods_ref);
    my @Difference = difference_of_set($retried_prods_from_log_of_type, $trace_prods_ref);
    return (\@Sysdiff, \@Difference);
}

sub show_diffs_help {  #dead
    my ( $log_path, $trace_prods_ref, $box, $type ) = @_;
    
    my $retried_prods_from_log =  retried_products($log_path);
    my $retried_prods_from_log_of_type = $retried_prods_from_log->{$type};
    my ($Sysdiff, $Difference) = get_diffs_between_trace_and_retried_prods($retried_prods_from_log_of_type, $trace_prods_ref);

    print "${\show_color(32)}RETRIED products in metabuild log of $box $type:${\end_color()}\n" if $debug;
    print_arr($retried_prods_from_log_of_type) if $debug;
    print "\n\n" if $debug;
    
    print "${\show_color(31)}Symmetric difference diffs between original trace retried and the RETRIED in metabuild log of $box $type:${\end_color()}\n";
    print_arr($Sysdiff);
    print CYAN "\nPS: This diff is generated by caculating symmetric difference between sets. " , RESET if @$Sysdiff;
    print CYAN "For example, symmetric_difference({1,2,3} , {3,4}) = {1,2,4}.\n\n" , RESET if @$Sysdiff;

    print "${\show_color(31)}Difference between original trace retried and the RETRIED in metabuild log of $box $type:${\end_color()}\n";
    print_arr($Difference);
    print CYAN "\nPS: This diff is generated by caculating Difference between sets. " , RESET if @$Difference;
    print CYAN "For example, Difference({1,2,3} , {3,4}) = {1,2}.\n\n" , RESET if @$Difference;
}

sub getBuildResults {
    my ($product_info, $initFailed) = @_;   # $product_info : initail failed products info
    my $build_results_str = start_travel_any_do_any($product_info, {process=>{code=>\&builds_info_by_resultType,  args=>[$initFailed]}}, 5);
    my $hash = constructHash($build_results_str, $regex, -2);
    print Dumper $hash if $debug;
    return ($build_results_str, $hash);
}

sub resultByType {
    my ($build_results_str, $filter_arr) = @_;
    my %target;
    for my $filter (@$filter_arr) {
	my $regex = qr/$filter/;
	my $hash = constructHash($build_results_str, $regex, -2);
	$target{$filter} = $hash;
    }
    return \%target;
}

sub arr_to_hash {
    my ($arr, $pattern) = @_;
    my $regex = qr/$pattern/;
    print BOLD GREEN "regex in arr_to_hash:\n", RESET if $debug;
    print "$regex\n" if $debug;
    my %hash;
    for my $item (@$arr) {
	$tmp = $item;
	$tmp =~ s/$regex//;
	$hash{$tmp} = $item;
    }
    return \%hash;
}

sub getFinalFails {
    my @refs = @_;
    my $pattern = '(?=_\d\d\d\d\d\d\d\d_).*$';
    my (@hashs, @arrs);
    for my $arr_ref (@refs) {
	my $hash = arr_to_hash($arr_ref, $pattern);
	push @hashs, $hash;	
	my @tmp = keys %$hash;
	push @arrs, \@tmp;
    }
    my @fails = difference_of_set(@arrs);
    my %finalFails; 
    @finalFails{@fails} = @{$hashs[0]}{@fails};
    print "finalFails of old logs:\n" if $debug;
    print Dumper \%finalFails if $debug;
    return \%finalFails;
}

sub getLatestLog { #dead
    my ($hash, $round2Fails, $roundP2Fails) = @_;
    my %target;
    my $pattern = '(?=_\d\d\d\d\d\d\d\d_).*$';
    my $hash2Fails = arr_to_hash($round2Fails, $pattern);
    my $hashP2Fails = arr_to_hash($roundP2Fails, $pattern);
    for my $key (keys %$hash) {
	if (exists $hashP2Fails->{$key}) {
	    $target{$key} = $hashP2Fails->{$key};
	}
	elsif (exists $hash2Fails->{$key}) {
	    $target{$key} = $hash2Fails->{$key};
	}
	else {
	    $target{$key} = $hash->{$key};
	}
    }
    my @values = values %target; 
    return \@values;
}

sub builds_info_by_resultType {
    my (%args) = (@_);
    my ($level, $branch, $box, $onepmtype, $id_key) = @{$args{keys}}; #the id_key could be mergeky or onepmid
    my ($sub_hash) = ($args{values});
    my $tmp = $args{user};
    my ($initFailed) = @$tmp;
    my ($round1Fails, $round2Fails, $roundP2Fails, $round2Success, $roundP2Success); 
    my @targets;
    my $sub_initFailed = $initFailed->{$level}{$branch}{$box}{$onepmtype}{$id_key};
    my @initFailedProds = keys %$sub_hash;
    my @initFailedProds_NoDup = map {$_->[-1]} @{$sub_hash}{@initFailedProds};
    #push @targets, [$level, $branch, $box, $onepmtype, "FAILURE1", [@initFailedProds_NoDup]];
    ($round1Fails, $round2Fails, $roundP2Fails, $round1Success, $round2Success, $roundP2Success, $finalFails) = getTypedResults($sub_hash, $sub_initFailed); 
    #my $finalFails_hash = getFinalFails($round1Fails, $round2Success, $roundP2Success);
    #my $finalFails = getLatestLog($finalFails_hash, $round2Fails, $roundP2Fails); 
    push @targets, [$level, $branch, $box, $onepmtype, $id_key, "FAILURE1", $round1Fails] if @$round1Fails;
    push @targets, [$level, $branch, $box, $onepmtype, $id_key, "FAILURE2", $round2Fails] if @$round2Fails;
    push @targets, [$level, $branch, $box, $onepmtype, $id_key, "FAILURE3+", $roundP2Fails] if @$roundP2Fails;
    push @targets, [$level, $branch, $box, $onepmtype, $id_key, "SUCCESS2", $round2Success] if @$round2Success;
    push @targets, [$level, $branch, $box, $onepmtype, $id_key, "SUCCESS3+", $roundP2Success] if @$roundP2Success;
    push @targets, [$level, $branch, $box, $onepmtype, $id_key, "REMAINS_FAIL", $finalFails] if @$finalFails;
    return \@targets; 
}

sub error_product_parser {
    my ($remaining_errors, $rebuild_id) = @_;
    print BOLD RED "remaining_errors", RESET if $debug;
    print Dumper $remaining_errors if $debug;
    my $cmd_strings = start_travel_any_do_any($remaining_errors, {process=>{code=>\&onepm_command_generator, args=>[$rebuild_id]}}, -1);
    my $hash = constructHash($cmd_strings, '', -2);
    print Dumper $hash if $debug;
    return $hash;
}

sub cmpfunc {
    return(($a->[0] <=> $b->[0]) or
           ($a->[1] <=> $b->[1]) or
           ($a->[2] <=> $b->[2]));
}

sub print_item {
    if ( ref $_[1] eq 'ARRAY' ) {
       print " $_[0]: ";
       print_arr($_[1]);
       print "\n";
    }
    else {
       print " $_[0]: $_[1]\n";
    }
}

sub get_metalog_statusfile_ids {
    my ($dir, $level, $branch, $host, $portdate) = @_;
    my $file_regex = ".*status\\.${level}\\.mva\\.${branch}\.${host}\\.log";
    my $cmd = "find -E $dir -regex '$file_regex' 2>/dev/null ";
    print "The command used to get metabuild buildid:\n" if $debug;
    print "$cmd\n" if $debug;
    chomp(my @statusfile_paths = `$cmd`);
    my @statusfile_ids = map {  basename(dirname($_)) } @statusfile_paths;
    return \@statusfile_ids;
}


sub run_sdscrontab {
    print "Getting metabuild build(s) by parsing sdscrontab log and metabuild status files...\n" if $debug;
    my $cmd = "sdscrontab  -l   |  egrep   'metabuild.*buildid'";
    chomp(my @croned_lines = `$cmd`);
    return @croned_lines;
}

sub get_croned_lines {
    my @croned_lines;
    if (@CRONED_LINES)  {
        @croned_lines = @CRONED_LINES;
    }
    else {
        @croned_lines = run_sdscrontab();
        @CRONED_LINES = @croned_lines;
    }
    return \@croned_lines;
}

sub get_croned_buildids {
    my $croned_lines = get_croned_lines();
    my @croned_buildids = map {/--buildid\s+(\w+)/} @$croned_lines;
    my @uniqed = uniq(@croned_buildids);
    return \@uniqed;
}

sub get_actual_buildid {
    my ($dir, $level, $branch, $host, $portdate) = @_;
    my $statusfile_ids = get_metalog_statusfile_ids($dir, $level, $branch, $host, $portdate);
    my $actual_id ;
    if (@$statusfile_ids > 1) {
        my $croned_buildids = get_croned_buildids();
        my $tmp = intersection($statusfile_ids, $croned_buildids);
        $actual_id = $tmp->[0];
    }
    elsif (@$statusfile_ids == 1)  {
        $actual_id = $statusfile_ids->[0];
    }
    else {
        $actual_id = '';
    }
    return $actual_id;
}

sub get_meta_id {
    my (%args) = @_;
    my ($level, $branch, $host) = @{$args{keys}};
    my ($onepm_strs, $metalog_baseDir) = ($args{values}, $args{user});
    my ($dir, $user_metalog_id, $portdate) = @$metalog_baseDir;
    my $metalogID = ($user_metalog_id) ? $user_metalog_id : get_actual_buildid($dir, $level, $branch, $host, $portdate);
    return [$level, $branch, $host, $metalogID];
}

sub match {
    my ( $patterns, $arr_ref ) = @_;
    print "patterns: @$patterns; array: @$arr_ref\n" if $debug;
    #my @compiled = map qr/$_/i, @$patterns;
    my $flag = 0;
    for my $pat ( @$patterns) { 
	for my $target ( @$arr_ref ) {
	    if ( $target =~ /$pat/ ) {
		$flag =1;
		last;
	    } 
	} 
    }
    return $flag;
}

sub get_onepm_finished_str {
    my (%args) = @_;
    my ($level, $branch, $box, $onepmtype, $id_key) = @{$args{keys}}; #the id_key could be mergeky or onepmid
    my $sub_hash = $args{values};
    my $target;
    my $finished_flag = 'Y'; #assuming finished
    for my $wrapper_log (keys %$sub_hash) {
	my $time_arr = $sub_hash->{$wrapper_log};
	my $item_num = @$time_arr;
	if ($item_num != 2) {
	    $finished_flag = 'N';
	    last;
	}
    }
    $target = [$level, $branch, $box, $onepmtype, $id_key, 'FINISHED', $finished_flag];
    return $target;
}

sub onepmFinishedStatus {
    my ($wrapperStartEndTime) = @_;
    my $onepm_finished_str = start_travel_any_do_any($wrapperStartEndTime, {process=>{code=>\&get_onepm_finished_str}}, -2);
    my $status_hash = constructHash($onepm_finished_str, '', -1) ;
    return $status_hash;
}

sub get_files_by_ids {
    my ($log, $regex) = @_;
    my ($dir, $basename) = (dirname($log), basename($log));
    $basename =~ s/\./\\./g;
    $basename =~ s/(?=\d\d\d\d\d\d\d\d_).*$/.*$regex\$/;
    my $find_reg = "'.*$basename'";
    my $cmd = "find -E $dir -regex $find_reg | xargs ls -tr | egrep -v '\\.(json|trace)'";
    print "$cmd\n" if $debug;
    chomp(@files = `$cmd`);
    return \@files;
}

sub get_max_job_num {
    my @total_task = @_;
    my $task_number = (defined $TASK) ? $TASK : 10;
    my $max_job_num = ($task_number > @total_task) ? @total_task : $task_number;
    return $max_job_num;
}

sub write_dir {
    my $defaultdir = "/sastmp/";
    my $write_dir = (defined $userLogDir) ? $userLogDir : $defaultdir;
    return $write_dir;
}

sub process_choice {
    my ($choice, $delJobs, $writeDir) = @_;
    if ( $choice == 1 ) {
       print_arr($delJobs);   
    }
    elsif ( $choice == 2 ) {
       write_array_to_file($delJobs, $writeDir);
    }
    elsif ( $choice == 3 ) {
       print_arr($delJobs);
       write_array_to_file($delJobs, $writeDir);
    }
    elsif ( $choice == 4 ) {
       return 0;
    }
    else  {
       print "Error input, please input again:\n";
       return -1;
    }
}

sub write_array_to_file {
    my ($delJobs, $writedir) = @_;
    my $file_name = "$writedir/onepm_rebuild_commands_$$"; 
    
    open (FILE, ">> $file_name") || die "problem opening $file_name $!";
    print BOLD CYAN "\nonepm rerun commands will be written to $file_name\n", RESET;
    print FILE "$_\n" for @$delJobs;
    close FILE;
}

sub user_choice {
    my ($delJobs_ref, $writeDir) = @_;
    print "${\show_color(32)}Would you like commands:${\end_color()}\n1. shown on the screen\n2. written to a file \n3. both \n4. none\n";
    chomp (my $choice = <STDIN>);
    if ( process_choice($choice, $delJobs_ref, $writeDir) == -1 ) {
       user_choice($delJobs_ref, $writeDir);
    }
}

sub process_noexec {
    my ($delJobs_ref, $branch, $box, $type, $writeDir ) = @_;
    my $total =  @$delJobs_ref;
    interactive_mode($delJobs_ref, $writeDir) unless $total <= 0;
}

sub interactive_mode {
    my ($delJobs_ref, $writeDir) = @_;
    if ( $nointeractive ) {
	my $choice = 3;
        process_choice($choice, $delJobs_ref, $writeDir);
    }
    else {
        user_choice($delJobs_ref, $writeDir);
    }
}

sub dispatch_array {
    my ($cmds, $write_dir) = @_;
    my @optional_args = ();
    my @compulsory_args = ($write_dir);
    my $failed_tasks = threadDeliveryJobs($cmds, [@compulsory_args], [@optional_args]);#array ref 
    $failed_tasks = another_try($failed_tasks, [@compulsory_args], [@optional_args]) if @$failed_tasks && ! $no_rerun;
    return $failed_tasks;
}

sub travel_onepm_package_cmds {
    my ($cmds, $writeDir, $merge_flag) = @_;
    my $box_results_file = "$writeDir/box_results_file_$$";
    my $remaining_failures = start_travel_any_do_any($cmds, {process=>{code=>\&do_onepm_package, args=>[$writeDir, $merge_flag, $box_results_file]}}, -1);
    print Dumper $remaining_failures if $debug;
    if (@$remaining_failures) {
    	my $hash = constructHash($remaining_failures, '', -2);
        print Dumper $hash;
        open( my $RERUN_RESULT, "<", $box_results_file ) or die "cannot open $box_results_file $!"; 
	print BOLD RED "$_", RESET while(<$RERUN_RESULT>);
	close $RERUN_RESULT;
	unlink $box_results_file or warn "Could not unlink $box_results_file: $!";
 	print BOLD YELLOW "\nThere are still errors, Would you like to rerun the jobs YES or N\n", RESET;
        chomp (my $U_Order = <STDIN>);
        return $hash unless $U_Order =~ /\bYES\b/;
	$hash = travel_onepm_package_cmds($hash, $writeDir, $merge_flag);
	return $hash;
    }
    else {
	return {};
    }

}

sub do_onepm_package {
    my (%args) = @_;
    my ($cmds, $arr_ref) = ($args{values}, $args{user});
    my ($writeDir, $merge_flag, $box_results_file) = @$arr_ref;
    my ($level, $branch, $box, $onepmtype) = @{$args{keys}};
    my @strings;
    my $target = [];
    if ($merge_flag) {
       @strings = ($level, $branch, $box, $onepm_type) =  @{$args{keys}};
    }
    else {
       @strings = ($level, $branch, $box, $onepm_type, $buildid) =  @{$args{keys}};
    }
    my @optional_args = ($branch, $box, $onepm_type);
    my @compulsory_args = ($writeDir);
    my ($failed_tasks, $result_string) = threadDeliveryJobs($cmds, [@compulsory_args], [@optional_args]);#array ref 
    my $temp = writeDataToFile($result_string, $writeDir, $box_results_file); 
    if (@$failed_tasks) {
        push @strings, $failed_tasks;
	$target = [@strings];
    }
    print Dumper $target if $debug;
    return $target;
}

sub threadDeliveryJobs {
    my ($delJobs_ref, $compulsory_args, $optional_args) = @_;
    my $total = @$delJobs_ref;
    my $max_job_num = get_max_job_num(@$delJobs_ref);
    unshift  @$compulsory_args, $total, $max_job_num;
    my $finished_jobs = threadFork($delJobs_ref, $compulsory_args, $optional_args);
    splice @$compulsory_args, 0, 2;
    my $failed_tasks = check_results($finished_jobs, $compulsory_args->[-1], $optional_args); #array ref
    my $finished_num = @$finished_jobs;
    my $failed_num = @$failed_tasks;
    my $result_string =  "@$optional_args: $total jobs submitted,  $finished_num jobs finished, $failed_num jobs failed\n";
    return ($failed_tasks, $result_string);
}

sub another_try {
    my ($cmds, $compulsory_args, $optional_args) = @_;
    while ( @$cmds ) {
        print "another_try: @$compulsory_args\n";
	print RED "The following jobs failed to run:\n", RESET;
        print "$_\n" for @$cmds;
        print "\nWould you like to rerun the failed jobs Y or N\n";
        chomp (my $U_Order = <STDIN>);
        return $cmds unless $U_Order =~ /\bY\b/;
        $cmds = change_commands_zRR($cmds);
	$cmds = threadDeliveryJobs($cmds, $compulsory_args, $optional_args);
    }  
   return $cmds;
}

sub threadFork {
    my ($delJobs, $compulsory_args, $optional_args) = @_;
    my ( $total, $max_job_num, $writeDir ) = @$compulsory_args;

    ( $dtime=`date '+%D %T'`) =~ chop $dtime;
    if (@$optional_args) {
        print BOLD YELLOW "\nFailed tasks at @$optional_args will be run now...\n", RESET;
    }
    else {
        print BOLD YELLOW "\nTasks are starting now...\n", RESET;
    }
    print BOLD CYAN "\nSubmitting $total job_num job(s) at $dtime.\tMax concurrent running job num: $max_job_num.\n\n", RESET;
    my @finished_jobs = mfork($delJobs, $compulsory_args, $optional_args);

    ( $dtime=`date '+%D %T'`) =~ chop $dtime;
    print BOLD CYAN "Tasks completed at $dtime\n\n",  RESET; 

    return \@finished_jobs;
}

sub mfork ($$$$$$$) {
    my ($tasks, $compulsory_args, $optional_args) = @_;
    my ($count, $max, $logdir) = @$compulsory_args;
    my @finished_jobs;
    foreach my $c (1 .. $count) {
        unless ($c <= $max ) {
 	   my $job = wait;
	   push @finished_jobs, $job;
	}

        my $work;
        if( @$tasks ) {
           $work = shift @$tasks;
	   chomp $work;
        }
        else {
            last;
        }
        die "Fork failed: $!\n" unless defined (my $pid = fork);
        if ( $pid ) {
        }
        else {
           print "$$: " . localtime () . ": Starting\n";
	   my $result = submitDeliveryJobs($work, $logdir, $optional_args);
           print "$$: " . localtime () . ": Exiting\n\n";
           exit(0);
        }
    }

    while ((my $child = wait)  != -1 ) {
	push @finished_jobs, $child;
	
    }
    return @finished_jobs;
}

sub do_with_cmd {
    my ($cmd_str, $log_name) = @_;
    my $cmd = "echo 'Running:$cmd_str\n:END_OF_COMMAND\n' >>$log_name" ;
    print "$cmd\n";
    system($cmd);
}
# execute by child process;
sub submitDeliveryJobs {
    my ($work, $logdir, $optional_args)  = @_;
    ( $dtime=`date '+%D %T'`) =~ chop $dtime;
    my $log_post = join('_', @$optional_args);
    my ($unit_name) = ($work =~ /--package_unit\s+([^\s]+)/);
    my $logFile = ($unit_name) ? "$logdir/onepm_build_${log_post}_${unit_name}_$$" : "$logdir/onepm_build_${log_post}_$$";
    print YELLOW "$$ created,\t\t$work is to be run by process $$\n", RESET;
    print CYAN  "Log will be written to $logFile\n\n", RESET;
    open( my $RERUN_RESULT, ">", $logFile ) or die "cannot open $logFile $!";
    print $RERUN_RESULT "Running:$work\n:END_OF_COMMAND\n";
    close $RERUN_RESULT;
    execute_user_task($work, $logFile);
    checksys($?);
} # submitDeliveryJobs

sub execute_user_task {
    my ($task, $logFile) = @_;
    if ($task =~ /sdsenv/) {
        my $cmd = "ksh -c \'. /sas/tools/com/sdskshrc ; $task\'";
        ($test) ? do_with_cmd($cmd, $logFile) : do {print "Running $cmd\n"; system("$cmd >>$logFile")};
    }
    else {
        my $cmd = "ksh -c \' $task\'";
        ($test) ? do_with_cmd($cmd, $logFile) : do {print "Running $cmd\n"; system("$task >>$logFile")};
    }
}

sub checksys {
   my $rc = $_[0];
   if ($rc == -1) {
       print "failed to execute: $!\n";
   }
   elsif ($rc & 127) {
       printf "child died with signal %d, %s coredump\n",
       ($rc & 127),  ($rc & 128) ? 'with' : 'without';
   }
   else {
       printf "\nchild $$ exited with value %d\n", $rc >> 8;
   }
}

sub errors_after_run {
    #incomplete;
}

sub task_log_name_reg {
    my ($jobs_reg, $mid_reg) = @_;
    my $log_name_reg;
    if ( $mid_reg ) {
        $log_name_reg = "onepm_build_${mid_reg}_.*($jobs_reg)" ;# "/u/osrmgr/Hardy/onepm_build_${branch}_${box}_${type}_$$";
    }
    else {
        $log_name_reg = "onepm_build_.*($jobs_reg)" ;# "/u/osrmgr/Hardy/onepm_build_${branch}_${box}_${type}_$$";
    }
    return $log_name_reg;
} 

sub last_lines_of_files {
    my ($files, $num) = @_;
    my $pattern = 'Running:[[:space:]]{0,}.*';
    my $regex = qr/$pattern/s;
    print BOLD GREEN "pattern in last_lines_of_files:\n", RESET if $debug;
    print "$pattern\n"if $debug;
    print BOLD GREEN "regex in last_lines_of_files:\n", RESET if $debug;
    print "$regex\n"if $debug;
    my $flag = 0;
    my $file_target_hash = find_in_files_by_reg($files, $regex, ":END_OF_COMMAND", $flag);
    my %last_lines_of_file;
    while (($key, $value) = each %$file_target_hash) {
	   $value =~ s/Running:\s*//;
           chomp($last_lines_of_file{$value}= `tail -${num} $key`);
    }    
    print Dumper \%last_lines_of_file;
    return \%last_lines_of_file;
}

sub find_files {
    my ($dir, $reg) = @_;
    my @files;
    my $cmd = "find -E $dir -regex $reg -maxdepth 1 | xargs ls -tr 2>/dev/null";
    print "Find result logs:\n" if $debug || $usedcd;
    print "$cmd\n" if $debug || $usedcd;
    chomp(@files = `$cmd`);
    return \@files;
}

sub travel_hash_and_do {
    my ($hash_ref, $regex, $code) = @_;
    my $targets = [];
    while ( my ($key, $value) = each  %$hash_ref ) {
	   $targets = $code->($targets, $key, $value, $regex);
    }
    return $targets;
}


sub search_hash_item {
    my ($targets, $key, $value, $regex) = @_;
    if ($value !~ /$regex/) {
	push @$targets, $key;
    }
    return $targets;
}

sub search_hash_values {
    my ($hash_ref, $reg) = @_;
    my @targets;
    for my $cmd ( keys %$hash_ref ) {
        if ( $hash_ref->{$cmd} !~ /\s$reg\s*$/ ) {
           push @targets, $cmd;
        }
    }
    return \@targets;
}

sub failed_tasks {
    my ($logdir, $find_reg, $grep_str) = @_;
    my $pattern = 'Running:[[:space:]]{0,}.*onepm_packager.*';
    my $regex = qr/$pattern/;
    my $cmd_failed_logs = "find -E $logdir -regex $find_reg -maxdepth 1 | xargs grep $grep_str -L ";  #test
    my $del_cmd = "find -E $logdir -regex $find_reg | xargs rm";  #test
    print "${\show_color(32)}Now checking results for rebuild of onepm with command:${\end_color()}\n"; 
    print "$cmd_failed_logs\n"; 
    chomp(my @failed_logs = `$cmd_failed_logs`); 
    my $flag = 0; #only find the first match
    my $hash_ref = find_in_files_by_reg(\@failed_logs, $regex, ":END_OF_COMMAND", $flag);
    print Dumper $hash_ref if $debug;
    my @cmd_strings = values %$hash_ref;
    my $search_regex = "Running:\s*";
    my $replace_str = "";
    my $failed_cmds = substitute(\@cmd_strings, $search_regex, $replace_str);
    #find_delete_files($logdir, $find_reg);
    return $failed_cmds;
}

sub find_delete_files {
    my ($dir, $regex) = @_;
    my $cmd = "find -E $dir -regex $regex -maxdepth 1 | xargs rm";
    print "Now deleting result logs:\n" if $debug || $usedcd;
    print "$cmd\n" if $debug || $usedcd;
    system($cmd); 
}

sub check_results {
    my ($finished_jobs_ref, $logdir, $optional_args) = @_;
    my $job_ids_reg = join("|", @$finished_jobs_ref);
    my $mid_reg = join('_', @$optional_args);
    my $log_name_reg = task_log_name_reg($job_ids_reg, $mid_reg);# "/u/osrmgr/Hardy/onepm_build_${branch}_${box}_${type}_$$";
    my $grep_str = ( $mid_reg ) ? "'exit status is 0'" : '0';
    my $reg = "'.*$log_name_reg'";
    my $failed_tasks;
    if ( @$optional_args ) {
       $failed_tasks = failed_tasks($logdir, $reg, $grep_str);
    }
    else {
       my $logs = find_files($logdir, $reg);
       my $num = 30;
       my $logs_lastlines = last_lines_of_files($logs, $num);
       print BOLD YELLOW "Do you want to delete the following results logs, Y or N?\n", RESET;
       print "$_\n" for @$logs;
       chomp (my $U_Order = <STDIN>);
       find_delete_files($logdir, $reg) if $U_Order =~ /\bY\b/;
       my $pattern = '(Code: 0|SUCCESS|SDSBUILD RC: 0)';
       my $regex = qr/$pattern/m;
       #$failed_tasks = search_hash_values($logs_lastlines, $grep_str); 
       $failed_tasks = travel_hash_and_do($logs_lastlines, $regex, \&search_hash_item); 
    }
    shift @$failed_tasks if $test; #test 
    return $failed_tasks;

}

sub print_arr {
    my $arr_ref = $_[0];
    print "NULL\n\n" if ( ! @$arr_ref);
    for my $item ( @$arr_ref ) {
        if ( ref $item eq 'ARRAY' ) {
           print_arr($item);
        }
        else {
           print "$item\n";
        }
    }
}

sub only_scalar {
    my $arr = $_[0];
    my $scalar_flag = 1;
    for my $item ( @$arr ) {
	my $ref = \$item;
 	unless ($ref =~ /SCALAR/) {
	   $scalar_flag = 0;
	   return $scalar_flag;
	}
    }
    return $scalar_flag;
}

sub have_scalar {
    my $arr = $_[0];
    my $scalar_flag = 0;
    for my $item ( @$arr ) {
	my $ref = \$item;
 	if ($ref =~ /SCALAR/) {
	   $scalar_flag = 1;
	   return $scalar_flag;
	}
    }
    return $scalar_flag;
}

#*********  TESTING TRAVEL ANYTHING AND DO ANYTHING ************
#start_travel_any_do_any($prods_info, {"print"=>\&print_data});
sub print_data {
    my ($data, $depth, $is_value) = @_; 
    my $ref = ref $data;
    my $indent = '...' x $depth;
    my $indent_space = '   ' x $depth;
    if ($is_value) {
	if (! $ref)  {
            print $indent_space;
       	    print  "$data\n";
	}
	elsif ($ref =~ /ARRAY/){
            print  "${indent_space}$_\n" for @$data;
	}
    }
    else {
       print RED BOLD  "${indent}$data\n", RESET if ! $ref;
    }
}

sub process_data {
    my ($keys, $values, $accumulate_data, $code, $caller_args) = @_;
    my $rc = $code->(keys=>$keys, values=>$values, user=>$caller_args);
    my $ref = ref($rc);
    if ($ref eq 'ARRAY') {
        push @$accumulate_data, $rc if @$rc; 
    }
    elsif ($ref eq 'HASH') {
        push @$accumulate_data, $rc if %$rc; 
    }
    else {
    	push @$accumulate_data, $rc if $rc; 
    }
    return [@$accumulate_data];
}

sub count_level {
	my ($data) = @_;
	if (ref($data) eq 'ARRAY') {
		return 1 + max(map {count_level($_)} @$data);
	}
	elsif(ref($data) eq 'HASH') {
		return 1 + max(map {count_level($_)} values %$data);
	}
	else {
		return 0;
	}
}

sub start_travel_any_do_any {
    #start_travel_any_do_any($prods_info, {"print"=>\&print_data});
    my ($data_with_some_type, $code_hash, $to_where) = @_;
    my $depth = 0;
    my @hash_keys;
    my $accumulate_data = [];
    $accumulate_data = travel_any_do_any($data_with_some_type, [@$accumulate_data], $code_hash, $depth, [@hash_keys], $to_where);
    return $accumulate_data;
}

sub apply_code {
    my ($code_hash, $data_with_some_type, $hash_keys, $accumulate_data, $depth, $flag) = @_;
    if ($code_hash->{print}) {
       ($code_hash->{print})->($data_with_some_type, $depth, $flag);
    }
    elsif ($code_hash->{process}) {
 	my ($code, $caller_args) = ($code_hash->{process}{code}, $code_hash->{process}{args});
        $accumulate_data = process_data([@$hash_keys], $data_with_some_type, [@$accumulate_data], $code, $caller_args);
    }
    return $accumulate_data;
}

sub travel_by_datatype {
    my ($data_with_some_type, $accumulate_data, $code_hash, $depth, $hash_keys, $to_where) = @_;
    my $ref = ref( $data_with_some_type );
    if ( $ref eq 'HASH' ) {
         $accumulate_data = hash_trl_do($data_with_some_type, [@$accumulate_data], $code_hash, $depth, [@$hash_keys], $to_where);
    }
    elsif ( $ref eq 'ARRAY' ) {
         $accumulate_data = arr_trl_do($data_with_some_type, [@$accumulate_data], $code_hash, $depth, [@$hash_keys], $to_where);
    }
    elsif ( $ref eq 'CODE' ) {
         $data_with_some_type->();
    }
    else {
         $depth -= 1;
	 my $is_value = 1;
	 $accumulate_data = apply_code($code_hash, $data_with_some_type, [@$hash_keys], [@$accumulate_data], $depth, $is_value);
    }
    return $accumulate_data;
}

sub travel_any_do_any {
    my ($data_with_some_type, $accumulate_data, $code_hash, $depth, $hash_keys, $to_where) = @_;
    my $ref = ref( $data_with_some_type );
    my $level_to_end = count_level($data_with_some_type);
    my $is_value = 0;
    if (defined($to_where)) {
	if ($to_where <= 0 ) {
	    my $abs_where = abs($to_where);
	    if ($abs_where == $level_to_end && $abs_where <= 1) {
		$is_value = 1;	
		$accumulate_data = apply_code($code_hash, $data_with_some_type, [@$hash_keys], [@$accumulate_data], $depth, $is_value);
	    }	
	    elsif ($abs_where == $level_to_end) {
		$accumulate_data = apply_code($code_hash, $data_with_some_type, [@$hash_keys], [@$accumulate_data], $depth, $is_value);
	    }
	    else {
		$accumulate_data = travel_by_datatype($data_with_some_type, [@$accumulate_data], $code_hash, $depth, [@$hash_keys], $to_where);	
	    }
	} 
	else {
	   if ($to_where == $depth && $level_to_end == 1) {
		$is_value = 1;	
		$accumulate_data = apply_code($code_hash, $data_with_some_type, [@$hash_keys], [@$accumulate_data], $depth, $is_value);
	   }
	   elsif ($to_where == $depth) {
		$accumulate_data = apply_code($code_hash, $data_with_some_type, [@$hash_keys], [@$accumulate_data], $depth, $is_value);
	   }
	   else {
		$accumulate_data = travel_by_datatype($data_with_some_type, [@$accumulate_data], $code_hash, $depth, [@$hash_keys], $to_where);	
	   }
	}
   }
   else {
         $accumulate_data = travel_by_datatype($data_with_some_type, [@$accumulate_data], $code_hash, $depth, [@$hash_keys], $to_where);
   }
    return $accumulate_data;
}

sub hash_trl_do {
    my ($hash_ref, $accumulate_data, $code_hash, $depth, $hash_keys, $to_where) = @_;
    #while ( my ($k, $v) = each( %$hash_ref ) ) {
    for my $k (sort {$a cmp $b } keys %$hash_ref ) {
	my $v = $hash_ref->{$k};
	push @$hash_keys, $k;
	($code_hash->{print})->($k, $depth) if $code_hash->{print};
        $accumulate_data = travel_any_do_any($v, [@$accumulate_data], $code_hash, $depth+1, [@$hash_keys], $to_where);
        pop @$hash_keys;
    }
    return $accumulate_data;
}

sub arr_trl_do {
   my ($arr_ref, $accumulate_data, $code_hash, $depth, $hash_keys, $to_where) = @_;
   for my $item  ( @$arr_ref ) {
       $accumulate_data = travel_any_do_any($item, [@$accumulate_data], $code_hash, $depth+1, [@$hash_keys], $to_where);
   }
   return $accumulate_data; 
}

sub show_item {
    my $item = $_[0];
    print  "\t$item\n" ;
    print $LOG  "\t$item\n" if $mail;
}
#*********  TESTING TRAVEL ANYTHING AND DO ANYTHING ************

sub get_build_level {
    my $env_lev = $_[0];
    my $level; 
    if ( defined $day ) {
       $level = 'day';
    }
    elsif ( defined $wky ) {
       $level = 'wky';
    }
    elsif ( defined $dev ) {
       $level = 'dev';
    }
    else {
       $level = $env_lev ;
    }
    return $level;
}

sub parse {
    my $item = $_[0];  #laxno,laxnd=base,tk
    my ($pre, $post) = split(/=/, $item); 
    my @keys = split(/,/, $pre); 
    my @values = split(/,/, $post); 
    return (\@keys, \@values);
}

sub transpose {
    my ($AOA) = @_;
    my @transposed;
    for my $row (@AOA) {
  	for my $column (0 .. $#{$row}) {
    	    push(@{$transposed[$column]}, $row->[$column]);
  	}
    }
    return \@transposed;
}

sub refactor_user_products_dead {
    my ($boxes, $products) = @_;
    my $boxes_str  = join(',', @$boxes);
    my @new_products;
    for my $item ( @$products ) {
	if ( match(['='], [$item]) ) {
	   push @new_products, $item;
	}
	else {
	   push @new_products, "$boxes_str=$item"; 
	}
    }
    return \@new_products;
}

sub refactor_user_products {
    my ($host_buildids, $user_products) = @_;
    my $host_products_str = start_travel_any_do_any($host_buildids, {process=>{code=>\&refactor_helper, args=>[$user_products]}}, -1);
    my $host_products_hash = constructHash($host_products_str, '', -2);
    return $host_products_hash;
}

sub convert_12byte_to_duName {
    my ($branch, $host, $name_12byte_ref) = @_;
    my $duName = [];
    for my $name_12byte (@$name_12byte_ref) {
        my $cmd = "updatebuildstatus -action query -branch $branch -host $host -tbyte $name_12byte -csv| tr ',' '\\n'| sort | uniq | egrep duName |tr [:upper:] [:lower:] |awk -F= '{print \$2}'";
        print "The command used to convert 12byte to duName:\n" if $debug;
        print "$cmd\n" if $debug;
        chomp(my $du = `$cmd`);
	push @$duName, $du if $du;	
    } 
    return $duName;
}

sub refactor_helper {
    my (%args) = (@_);
    my ($level, $branch, $box, $onepmtype) = @{$args{keys}};
    my ($host) = (map_box_to_host_type($box))[0];
    my ($arr_ref) = ($args{user});
    my ($products) = @$arr_ref;
    my $target = [];
    for my $prod (@$products) {
	if (match(['='], [$prod])) {
	    my @items = split(/=/, $prod);
	    my ($left, $right) = @items;
	    if ($left =~ /$box/) {
		my @right_items = split(/,/, $right);
		my $duName = convert_12byte_to_duName($branch, $host, [@right_items]);
	        push @$target, @right_items, @$duName;
	    }
	}
	else {
	    my @split_prods =  split(/,/, $prod);
    	    my $tmp = array_items_contains_files([@split_prods]);
    	    my @products_tmp = grep {/\S/} @$tmp;
    	    my @products = map {lc $_} @products_tmp;
	    my $duName = convert_12byte_to_duName($branch, $host, [@products]);
	    push @$target, @products, @$duName;
	}
    }
    @$target = uniq(@$target);
    my $string  = (@$target) ? [$level, $branch, $box, $onepmtype, 'products', $target] : [];
    return $string;
} 

sub pair2Hash {
    my ($pair_arr) = @_;
    my $hash = {};
    for my $pair (@$pair_arr) {
	my @items = split(/=/, $pair);
	my ($left, $right) = @items;
	my @left_items = split(/,/, $left);
	my @right_items = split(/,/, $right);
	for my $key (@left_items) {
 	    push @{$hash->{$key}}, @right_items;
	}
    }
    return $hash;
}
 
sub parse_helper {
    my (%args) = (@_);
    my ($level, $branch, $box, $onepmtype) = @{$args{keys}};
    my ($arr_ref) = ($args{user});
    my ($box_products) = @$arr_ref;
    my $value = $box_products->{$box};
    my $tmp = array_items_contains_files($value);
    my @products = grep {/\S/} @$tmp;
    @products = map {lc $_} @products;
    my $target = (@products) ? [$level, $branch, $box, $onepmtype, 'products', \@products] : [];
    return $target;
}

sub productsToDeliver {
    my ($host_buildids, $products_pair) = @_;
    my $prods_strings = start_travel_any_do_any($host_buildids, {process=>{code=>\&parse_helper, args=>[$products_pair]}}, -1); 
    my $prods_hash = constructHash($prods_strings, '', -2);
    return $prods_hash;
}

sub execute_cmds {
    my (%args) = @_;
    my $cmd = $args{values};
    print "${\show_color(32)}\nCommands used to find error logs: ${\end_color()}\n" if  $usedcd || $debug;
    print "$cmd\n" if  $usedcd || $debug;
    my @logs = `$cmd`;
    chomp @logs;
    return \@logs;
}

sub uniq_array_item {
    my ($hash) = @_;
    print BOLD GREEN "in uniq_array_item\n", RESET if $debug;
    print Dumper $hash if $debug;
    return {} unless %$hash;
    my $strs = start_travel_any_do_any($hash, {process=>{code=>\&reduceDim}}, -1);
    my $reduced_hash = constructHash($strs, '', -2);
    print Dumper $strs if $debug;
    print Dumper $reduced_hash if $debug;
    print BOLD GREEN "the should be redelivererd logs:\n", RESET if $debug;
    print Dumper $reduced_hash if $debug;
    start_travel_any_do_any($reduced_hash, {print=>\&print_data}) if $debug;
    return $reduced_hash;
}

sub reduceDim {
    my (%args) = @_;
    my ($level, $branch, $box, $onepm_type, $onepmid, $full_product) = @{$args{keys}};
    my $logs_ref= $args{values};
    $latest_log = $logs_ref->[-1];
    my $target = ($latest_log) ? [$level, $branch, $box, $onepm_type, $onepmid, [$latest_log]] : [];
    return $target;
}

sub get_Logfind_cmds {
    my ($portdate, $pattern, $user_packages, $logpost_reg, $prods_hash) = @_; 
    my $cmd_strs = start_travel_any_do_any($logpost_reg,
					   {process=>{code=>\&generate_find_cmds, args=>[$pattern, $portdate, $user_packages, $prods_hash]}}); 
    my $cmd_hash = constructHash($cmd_strs, '', -1);
    print BOLD GREEN "cmds used to find logs:\n", RESET if $debug;
    print Dumper $cmd_hash if $debug;
    start_travel_any_do_any($cmd_hash, {print=>\&print_data}) if $debug;
    return $cmd_hash;
}

sub get_OnePM_Log {
    my ($cmd_hash) = @_;
    my $AOA = start_travel_any_do_any($cmd_hash,{process=>{code=>\&execute_cmds}}); 
    my @logs;
    for my $arr_ref (@$AOA) {
	push @logs, @$arr_ref;	
    }
    print BOLD YELLOW "The following OnePM logs found:\n", RESET if $debug && $verbose;
    print Dumper \@logs if $debug && $verbose;
    #print BOLD RED "\nNo logs found, please check the arguments!\n", RESET unless @logs;
    #exit unless @logs;
    return \@logs;
}

sub generate_find_cmds {
    my (%args) = @_;
    my ($level, $branch, $box, $onepm_type) = @{$args{keys}};
    my $arr_ref = $args{user};
    my ($pattern, $portdate, $package_types, $prods_hash) = @$arr_ref;
    my $onepmDir = ($user_onepm_dir) ? $user_onepm_dir : onepm_dir($branch, $level);
    my $onepmid_reg = $args{values};  
    $pattern =~ s/\./\./g;
    $pattern =~ s/\*/.*/g;
    $pattern =~ s/^/.*/g if $pattern && $pattern !~ /^\.\*/;
    $onepmDir =~ s/$/\// if $onepmDir !~ /\/$/;
    my ($host, $buildtype) = map_box_to_host_type($box);
    my $time_slice = get_Time_slice();
    my $products;
    if (%$prods_hash) {
 	$products = $prods_hash->{$level}{$branch}{$box}{$onepm_type}{'products'} if exists $prods_hash->{$level}{$branch}{$box}{$onepm_type}{'products'};
        return [] unless @$products;
    }
    my $today = `date "+%Y%m%d"`;
    my $pt = splitime($portdate);
    my $td = splitime($today);
    my $date_diff = diffdate( $pt, $td );

    my %tmp_hash = (	portdate=>$portdate,level=>$level,branch=>$branch,host=>$host,products=>$products,
			packagetypes=>$package_types,buildtype=>$buildtype,buildid=>$onepmid_reg,ops=>[$onepm_type],
			datediff=>$date_diff, timeslice=>$time_slice,
		   );
    my $reg_hash = file_reg_alternative(%tmp_hash);
    my $target_regex =  ($pattern) ? "'$pattern'" : $reg_hash->{not_trace};
    my $cmd_to_find = "find -E $onepmDir -regex $target_regex ";
    return [$level, $branch, $box, $onepm_type, $cmd_to_find];
}

sub search_maxdepth {
    my ($date_diff, $user_max_depth) = @_;
    my $maxdepth;
    if ($user_max_depth) {
	$maxdepth = $user_max_depth;
    }
    else {
	$maxdepth = ($date_diff< 2 ) ? 1 : 2;
    }
    return $maxdepth;
}

sub set_build_num {
    my (%args) = @_;
    my ($level, $branch, $box, $onepmtype, $mergeID_OnePMID) = @{$args{keys}};
    my $sub_hash = $args{values};
    my @target;
    my @product = keys %$sub_hash;
    my $num =  (@product) ? scalar @product : '-';
    push @target, [$level, $branch, $box, $onepmtype, $mergeID_OnePMID, 'STARTED', $num];
    return \@target;
}

sub started_info_of_builds {
    my ($products_info) = @_;
    my $build_process_info_str = start_travel_any_do_any($products_info, {process=>{code=>\&set_build_num }}, -2);
    my $build_process_info = constructHash($build_process_info_str, '', -1);
    return $build_process_info;
}

sub array_items_contains_files {
    my ($arr_ref) = @_;
    my @targets;
    for my $item (@$arr_ref) {
	chomp(my $file = `ls $item 2>/dev/null`);
	if ($file) {
	    my $temp = read_file_to_array($file);
	    push @targets, @$temp;
	}
	else {
	    push @targets, $item;
	}
    }
    return \@targets;
}

sub what_branches_to_check_backup {
    my ($env_branch, $userbranch_ref) = @_;
    my $branch = [];
    if (@$userbranch_ref) {
	$branch = $userbranch_ref;
    }
    else {
	push @$branch, $env_branch;
    }
    return $branch;
}

sub generate_regex {
    my ($level) = @_;
    my $branches_ref = ['vb\w+', 'ds\w+', 'db\w+'];
    my $branch_str = (@$branches_ref) ? join('|', @$branches_ref) : '';
    my $non_supp_pattern = "^(?<!#)\\s*%metabuild.*?${level}.*?,\\s+(${branch_str}).*onepm_package.*\\/\\*\\s*supp\\s*\\*\\/\\s*\\)";
    my $supp_pattern = "^(?<!#)\\s*%metabuild.*?${level}.*?,\\s+(${branch_str}).*onepm_package.*supp\\s*\\)";
    my $pattern = ($supplemental) ? $supp_pattern : $non_supp_pattern;
    print "$pattern\n" if $debug;
    my $regex = qr/$pattern/;
    return $regex;
}

sub parse_platform_bld_lines {
    my ($lines) = @_;
    my $branch = [];
    for my $line (@$lines) {
        next unless $line !~ /#/;
        my ($br) = (split('\s*,\s*', $line))[3];
	push @$branch, $br;
    }
    @$branch = uniq(@$branch);
    return $branch;
}

sub what_branches_to_check {
    my ($platform, $level, $env_branch, $userbranch_ref) = @_;
    my $branch = [];
    if (@$userbranch_ref) {
	$branch = array_items_contains_files($userbranch_ref);
    }
    elsif ($check_all_branches) {
	my $regex = generate_regex($branch_ref, $user_hosts, $level, $user_ids);
        my $platform_bld = get_platform_bld($platform);
        my $temp = find_in_files_by_reg([$platform_bld], $regex, "\n", 1);
        my ($lines_from_script) = values %$temp;
	$branch = parse_platform_bld_lines($lines_from_script);
    }
    else {
	push @$branch, $env_branch;
    }
    $branch = delete_user_excluded_branches($branch, \@user_excluded_branch) if @user_excluded_branch;
    return $branch;
}

sub delete_user_excluded_branches {
    my ($arr_ref, $to_delete_items_ref) = @_;
    for my $item (@$to_delete_items_ref) {
        $arr_ref = delete_item_from_array($arr_ref, $item);
    }
    return $arr_ref;
}

sub init_sys {
    my ($platform, $sdsenv) = @_;
    my $lang = $userLan // 'en';
    my ($env_lev, $env_branch) = get_lev_branch($sdsenv);
    my $level = get_build_level($env_lev);
    my $branch_ref = what_branches_to_check($platform, $level, $env_branch, \@userbranch);
    my $lookthrough = get_lookthrough($sdsenv);
    my $portdate = portdate($lookthrough);
    my $sl_lan = ( defined $user_sl_lan) ? $user_sl_lan: "en";
    my $onepm_types = getOnePmType();
    my $buildtype = getBuildType();
    my $metalog_baseDir = "/sas/dev/tls-i1mb/LOG/METABUILD/${portdate}";
    my $hosts_onepmstr = hosts_onepmstr_from_config($platform, $level, $branch_ref, \@user_hosts); #hash
    my $not_scheduled_branches = if_builds_scheduled($hosts_onepmstr, $branch_ref);
    my $host_metalogIDs = get_hosts_meta_id($hosts_onepmstr, $metalog_baseDir, $user_meta_id, $portdate);
    my $host_buildids = host_buildids($hosts_onepmstr, $host_metalogIDs, $metalog_baseDir, \@user_onepm_id, \@user_hosts, $buildtype, $onepm_types);  #hash
    if_onepmid_found($host_buildids, $portdate);

    my $metalogDir_hash = get_metaDir_hash($host_buildids, $host_metalogIDs, $metalog_baseDir, $user_meta_dir);
    my $metabuild_logs = get_metabuild_logs($lang, $host_buildids, $metalogDir_hash,$hosts_onepmstr);
    return ($branch_ref, $level, $portdate, $buildtype, $onepm_types, $metalogDir_hash, $metabuild_logs, $hosts_onepmstr, $sl_lan, $lang, $host_buildids, $not_scheduled_branches);
}

sub write_hash {
    my ($results_hash, $write_Dir) = @_;
    my $result = "$write_Dir/onepm_rerun_result_$$.log"; 
    open( my $RERUN_RESULT, ">", $result ) or die "cannot open $result $!"; 
    print BOLD CYAN "onepm tasks results will be written to file $result\n", RESET;

    if ( ! %$results_hash ) {
       print $RERUN_RESULT "All tasks were successfull\n"; 
       print  "All tasks were successfull\n"; 
    }
    else {
       print $RERUN_RESULT "The following tasks failed to rerun:\n";
       for my $level ( keys %$results_hash ) {
           for my $branch ( keys %{$results_hash->{$level}} ) {
               for my $box ( keys %{ $results_hash->{$level}{$branch} } ) {
                   for my $build_type ( keys %{ $results_hash->{$level}{$branch}{$box} } ) {
            	       print $RERUN_RESULT "\n$level :: $branch :: $box :: $build_type\n\n";
            	       print $RERUN_RESULT  "$_\n" for @{ $results_hash->{$level}{$branch}{$box}{$build_type} };
                   }
               }
           }
       }
    }
    close $RERUN_RESULT;
    return $result;
}  

sub write_array {
    my ($results_arr, $write_Dir) = @_;
    my $result = "$write_Dir/rerun_result_$$.log"; 
    open( my $RERUN_RESULT, ">", $result ) or die "cannot open $result $!"; 
    print BOLD CYAN "Tasks results will be written to file $result\n", RESET;
    if ( ! @$results_arr ) {
       print $RERUN_RESULT "All tasks were successfull\n"; 
       print  "All tasks were successfull\n"; 
    }
    else {
       print $RERUN_RESULT "\nThe following cmds failed to rerun:\n\n";
       print $RERUN_RESULT  "$_\n" for @$results_arr;
    }
    close $RERUN_RESULT;
    return $result;
}

sub dispatch_results_write {
    my ($results, $write_Dir) = @_;
    my $write_log;
    if ( ref($results) eq "HASH" ) {
	$write_log = write_hash($results, $write_Dir);
    }
    elsif (ref($results) eq "ARRAY") {
	$write_log = write_array($results, $write_Dir);
    }
    return $write_log;
}

sub process_noexec_mode {
}

sub if_builds_scheduled {
    my ($host_buildids_pair, $branch_ref) = @_;
    my @level = keys %$host_buildids_pair;
    my @non_null = grep {/\S/} @level;
    my @diff;
    if (! @non_null) {
        print BOLD RED "Please check the arguments, branch and level or sdsenv is compulsory!\n", RESET;
        print BOLD RED "Or There is no onepm scheduled for branch $branch and level $level and host $host\n\n", RESET;
        print BOLD YELLOW "Exapmple:\n", RESET;
        print BOLD GREEN "To check status of all OnePM tasks of branch vb025:\n", RESET;
        print YELLOW "$0 -sdsenv day/mva-vb025\n", RESET;
        print "\n";
        print BOLD GREEN "To check status of all OnePM tasks of branch vb025 of DAYRR and DAY_msiRR builds:\n", RESET;
        print YELLOW "$0 -sdsenv day/mva-vb025 -onepmid DAYRR DAY_msiRR\n", RESET;
        print "\n";
        print BOLD GREEN "To check status of all rpm OnePM tasks of branch vb025 for host lax:\n", RESET;
        print YELLOW "$0 -sdsenv day/mva-vb025 -host lax -package rpm\n", RESET;
        print "\n";
        print BOLD GREEN "To redeliver products(s), the rebuild id will be DAYRR and DAY_msiRR, for DAY and DAY_msi builds respectively:\n", RESET;
        print YELLOW "$0 -sdsenv day/mva-vb025 -product txtminita samplesml\n", RESET;
        print YELLOW "$0 -sdsenv day/mva-vb025 -product TXTMINITA SAMPLESML\n", RESET;
        print YELLOW "$0 -sdsenv day/mva-vb025 -product txtminita,samplesml\n", RESET;
        print YELLOW "$0 -sdsenv day/mva-vb025 -product txtminita,samplesml -host lax al6  -type opt  (on UNIX)\n", RESET;
        print YELLOW "$0 -sdsenv day/mva-vb025 -product txtminita,samplesml -host lax al6  -type opt -package rpm sles12 (on UNIX)\n", RESET;
        print YELLOW "$0 -sdsenv day/mva-vb025 -product txtminita,samplesml -host wx6 -type opt  (on PC)\n", RESET;
        print YELLOW "$0 -sdsenv day/mva-vb025 -product txtminita,samplesml -host wx6 -type opt -package msm (on PC)\n", RESET;
        exit();
    }
    else {
	my @scheduled_branches = keys %{$host_buildids_pair->{$non_null[0]}};
	@diff = difference_of_set($branch_ref, \@scheduled_branches);  
	return \@diff;
    }
}

sub if_onepmid_found {
    my ($host_buildids, $portdate) = @_;
    my $onepmids= start_travel_any_do_any($host_buildids, {process=>{code=>\&check_onepmid, args=>[$portdate]}}, -1);
}

sub check_onepmid {
    my (%args) = (@_);
    my ($portdate) = @{$args{user}};
    my ($level, $branch, $box, $onepmtype) = @{$args{keys}};
    my @id = keys %{$args{values}};
    if (! @id) {
        print BOLD RED "There is no metabuild task run for $level/$branch!\n", RESET ;
        print BOLD RED "Builds might be not started or something fatal happens!\n", RESET ;
        print BOLD RED "Or you might specified wrong arguments, please check:\n", RESET ;
        print YELLOW "\nportdate: $portdate; level: $level;  branch: $branch\n", RESET ;
        print BOLD YELLOW "\nYou will probably need to specified the onepmid option.\n", RESET ;
        die BOLD RED "\nExit the script!\n";
    }
}

sub writeDataToFile {
    my ($data, $writeDir, $basename) = @_;
    my $file;
    if ($basename) {
    	$file = ($basename =~ /\//) ? $basename : "$writeDir/${basename}";
    }
    else {
    	$file = "$writeDir/data_$$";
    }
    open (FILE, ">> $file") || die "problem opening $file $!";
    (ref($data)) ?  do {print FILE Dumper $data; }: do {print FILE $data;};
    close FILE;
    return $file;
}

sub products_rebuilding {
    my ($remaining_errors,  $rebuild_id, $writeDir)  = @_;
    if ( %$remaining_errors ) {
        my $cmds = error_product_parser($remaining_errors, $rebuild_id);#hash ref
        print "\nDo you want the commands written to a file, Y or N?";
        chomp (my $choice = <STDIN>);
        if ( $choice =~ /\bY\b/ ) {
            my $basename = "onepm_rebuild_cmds_$$";
            my $file_name = writeDataToFile($cmds, $writeDir, $basename);
            print "Commands have been written to file ${\show_color(32)}$file_name${\end_color}\n";
        }
        if (! $noexec) {
           print "\nWould you like to run the jobs YES or N\n";
           chomp (my $U_Order = <STDIN>);
           exit(0)  unless $U_Order =~ /\bYES\b/;
           my $onepm_rebuild_results = travel_onepm_package_cmds($cmds, $writeDir, $merge_flag);  #finally failed onepm cmds
           print Dumper $onepm_rebuild_results;
           if (%$onepm_rebuild_results) {
                my $basename = "onepm_rebuild_remaining_errors_$$";
                my $results_file = writeDataToFile($onepm_rebuild_results, $writeDir, $basename);
                return $results_file;
           }
           else {
                return 0;
           }
        }
        else {
           process_noexec_mode($remaining_errors);
        }
    }
}

sub map_box_to_host_type {
    my $box = $_[0];
    my ($host, $encode) = split_string($box, 2);
    my $type = map_box_to_buildtype($encode);
    return ($host, $type);
}

sub printResultsTable {
    my ($allBuildStatInfo, $table_head) = @_;
    print BOLD YELLOW "allBuildStatInfo:\n", RESET if $debug;
    print Dumper $allBuildStatInfo if $debug;
    my $space = ' ' x 45;
    print "${\show_color(01)}SUMMARY${\end_color()}$space" ;
    print join('    ', @$table_head), "\n"; 
    start_travel_any_do_any($allBuildStatInfo, {process=>{code=>\&print_table, args=>[$table_head]}}, 5);
    print "\n";
}

sub serializa_hash {
    my ($hash_arr) = @_;
    my @target;
    for my $hash (@$hash_arr) {
	my @item = map {"$_:$hash->{$_}"} keys %$hash;
	my $str = join(",", @item);
	push @target, $str;
    }
    my $target_str = join(",", @target);
    return $target_str;
}

sub print_table {
    my (%args) = (@_);
    my ($level, $branch, $box, $onepmtype, $id_key) = @{$args{keys}}; #the id_key could be mergeky or onepmid
    my ($sub_hash, $arr_ref) = ($args{values}, $args{user});
    my $started_num = $sub_hash->{'STARTED'};
    my ($table_head) = @$arr_ref;
    my $line_key = join('::', @{$args{keys}});
    printf "%-52s", $line_key;
    for my $key (@$table_head) {
        my $value = (exists $sub_hash->{$key}) ?  $sub_hash->{$key} : [];
        print_format($value, $key, $started_num);
    }
    print "\n";
}

sub exist_fatal_error {
    my ($started, $finished) = @_;
    my $error = 0;
    if ($started == 0 && $finished eq 'Y' ) {
	$error = 1;
    }
    elsif ($started == 0 && $finished eq 'N') {
	$error = 2;
    }
    return $error;
}

sub print_format {
    my ($value, $key, $started_num) = @_;
    my $type = ref($value);
    my $print_value;

    if ($key =~ /FATAL/) {
	if (@$value) {
	    $print_value = 'Y';
	}
	elsif ($started_num) {
	    $print_value = 'N';
	}
	else {
	    $print_value = '-';
	}
        printf "%-12s", $print_value;
    }
    else {
        if ($type eq 'ARRAY') {
            $print_value =  (@$value) ? scalar @$value : '-'; 
        }
        else {
            $print_value = $value;
        }

        if ($key =~ /STARTED/) {
            printf "%-11s", $print_value;
	}
        if ($key =~ /FAILURE1|FAILURE2|SUCCESS2/) {
            printf "%-12s", $print_value;
        }
        elsif ($key =~ /FAILURE3\+|SUCCESS3\+/) {
            printf "%-13s", $print_value;
        }
        elsif ($key =~ /REMAINS_FAIL/) {
            printf "%-16s", $print_value;
        }
        elsif ($key =~ /FINISHED/) {
            printf "%-12s", $print_value;
        }
    }
}

sub serialization {
    my ($data) = @_;
    my $serial_str = start_travel_any_do_any($data, {process=>{code=>\&setValue}});
    return $serial_str;
}

sub  setValue {
     my (%args) = @_;
     my @keys = @{$args{keys}};
     my $value  = $args{values};
     my $str = join('&&~', @keys) . "&&~$value";
     return $str;
}

sub getWhatToPrint {
    my ($table_hash) = @_;
    print BOLD RED "table_hash before filter:\n", RESET if $debug;
    print Dumper $table_hash if $debug;
    my %target_hash;
    for my $table_key (keys %$table_hash) {
        my $hash = $table_hash->{$table_key};
        if (%$hash)  {
            my $serized = serialization($hash);
	    print YELLOW "serized results of what to print before filter\n", RESET if $debug;
	    print Dumper $serized if $debug;
            next unless @$serized && $serized->[-1] !~ /^0$/;   #only print items whoes value is no 0;
            for my $item (@$serized) {
                #my ($fourth, $last, $sub_last)  = (split(/&&~/, $item))[4, -1, -2];
                my ($key, $value)   = (split(/&&~/, $item))[5, -1];
                next unless $value !~ /^0$/;
                $target_hash{$key} = $hash unless exists $target_hash{$key};
            }
        }
    }
    print "Details to print after filter\n" if $debug;
    print Dumper \%target_hash if $debug;
    return \%target_hash;
}

sub reduce_wrapper_time_dimension {
    my ($wrapper_times) = @_; 
    my $wrapper_list =getSubHashByDepth($wrapper_times, -1);
    my $tmp = merge_hashes({}, $wrapper_list);
    my $time_wrapper = {};
    for my $wrapper (keys %$tmp) {
	my $times = $tmp->{$wrapper}; #array
	my $time_str = (@$times == 2) ? "$times->[0] ~ $times->[1]" : "$times->[0] ~ ";
        my $bn = basename($wrapper);
	push @{$time_wrapper->{$time_str}} , $bn;
    }
    return $time_wrapper;
}

sub printWrapperTimes {
    my ($wrapper_times) = @_; 
    my $dimension_reduced_time_wrapper = reduce_wrapper_time_dimension($wrapper_times);
    for my $time_str (sort {$a cmp $b}  keys %$dimension_reduced_time_wrapper) {
	my $wrapper = $dimension_reduced_time_wrapper->{$time_str}; #array
	if (@$wrapper == 1)  {
	    printf "%-52s%-30s", "$time_str:", "@$wrapper\n";
	}
	else {
	    for my $item (@$wrapper) {
	    	printf "%-52s%-30s", "$time_str:", "$item\n";
	    }
	}
    }
}

sub printTypeResults {
    my ($hash) = @_;
    my %print_hash = (  'FAILURE1'      =>      sub { print BOLD YELLOW "FAILURES IN THE FIRST RUNNING:\n", RESET;},
                        'FAILURE2'      =>      sub { print BOLD YELLOW "FAILURES IN THE SECOND RUNNING:\n", RESET;},
                        'FAILURE3+'     =>      sub { print BOLD YELLOW "FAILURES IN THE THIRD OR MORE RUNNING:\n", RESET;},
                        'SUCCESS2'      =>      sub { print BOLD GREEN "SUCCESS IN THE SECOND RUNNING:\n", RESET;},
                        'SUCCESS3+'     =>      sub { print BOLD GREEN "SUCCESS IN THE THIRD OR MORE RUNNING:\n" , RESET;},
                        'REMAINS_FAIL'  =>      sub { print BOLD RED "REMAINING FAILURES:\n", RESET; },
                        'FATAL'         =>      sub { print BOLD RED "FATAL ERROR MESSAGE:\n", RESET;},
                );
    print "${\show_color(01)}\n\nDETAILS\n\n${\end_color()}$space" ;
    print YELLOW "Detailed results:\n", RESET if $debug;
    print Dumper $hash if $debug;
    for my $table_key  (sort(keys %$hash)) {
        print "$table_key:\n" if $debug;
        $print_hash{$table_key}->();
        start_travel_any_do_any($hash->{$table_key}, {process=>{code=>\&printResults, args=>[$table_key]}}, -1);
    }
}

sub printResults {
    my (%args) = @_;
    my @keys = @{$args{keys}};
    my $value  = $args{values};
    my ($table_key) = @{$args{user}};
    my $length = scalar @keys;
    my $ref = ref($value);
    print Dumper $value if $debug;
    if ($ref eq 'ARRAY') {
        print join(":", @keys[0..$length-2]) . "\n" if @$value;
        #(ref($value)) ? do {print "$_\n" for @$value; } : print "$value\n" if @$value ;
        if (ref($value)) {
	     if (@$value && @$value <= 20) {
		print "$_\n" for @$value;
	     }
	     elsif (@$value && @$value > 20) {
		print "Items are more than 20 and will be written to a file.\n";
		my $write_dir = write_dir(get_platform());
        	my $file_name_mid = join("_", @keys[0..$length-2]);
		my $file = "$write_dir${table_key}_${file_name_mid}_$$";
    		open my $handle, '>', $file;
		print $handle "$_\n" for @$value;
		print "$file\n";
	     }
	}
	else {
	    print "$value\n";
	}
        print "\n" if @$value;
    }
    elsif ($ref eq 'HASH') {
        my $print_flag = 0;
        print join(":", @keys[0..$length-1]) . "\n" if %$value && $value->{'FATAL'};
        if ($value->{'FATAL'}) {
            print  RED "$value->{'FATAL'}\n", RESET ;
            $print_flag = 1;
        }
        print "\n" if %$value && $print_flag;
    }
}

sub constructHashFromStr {
    my ($line, $value) = @_;
    my ($first, $remainder) = split(/\//, $line,2);
    if ($remainder) {
        return { $first => constructHashFromStr($remainder, $value) } ;
    } 
    else {
        return { $first => $value };
    }
}

sub constructHashFromArray {
    my (%args) = @_;
    my $arr = $args{values};
    return {} unless @$arr;
    my ($regex_ref) = ($args{user});
    my $keys_str =  join('/', @{$arr}[0..@$arr-2]);
    my $value = $arr->[-1];
    my $hash = {};
    if ($regex_ref->[0]) {
	if ($keys_str =~ /$regex_ref->[0]/) {
    	    $hash = constructHashFromStr($keys_str, $value);
	} 
    }
    else {
    	$hash = constructHashFromStr($keys_str, $value);
    }
    return $hash;
}

sub constructHash {
    my ($arr_ref, $filter_reg, $to_where) = @_;
    my $hash = {};
    if (@$arr_ref) {
    	my $hash_list = start_travel_any_do_any($arr_ref, {process=>{code=>\&constructHashFromArray, args=>[$filter_reg]}}, $to_where) if @$arr_ref;
    	$hash = merge_hashes({}, $hash_list);
    }
    return $hash;
}

sub deep_merge_help {
    my ($data1, $data2) = @_;
    my $type1 = ref($data1);
    my $type2 = ref($data2);
    my @target;
    if (! $type1 && ! $type2 ) {
        push @target, $data1, $data2;
    }
    elsif( $type1 && ! $type2 ) {
        if ( $type1 eq 'HASH' ) {
           push @target, %$data1, $data2;
        }
        elsif ( $type1 eq 'ARRAY' ) {
           push @target, @$data1, $data2;
        }
    }
    elsif( ! $type1 && $type2 ) {
        if ( $type2 eq 'HASH' ) {
           push @target, $data1, %$data2;
        }
        elsif ( $type2 eq 'ARRAY' ) {
           push @target, $data1, @$data2;
        }
    }
    elsif( $type1 && $type2 ) {
        if ( $type1 eq 'ARRAY' && $type2 eq 'ARRAY') {
             push @target, @$data1, @$data2;
        }
        elsif ( $type1 eq 'ARRAY' && $type2 eq 'HASH' ) {
             push @target, @$data1, %$data2;
        }
        elsif ( $type1 eq 'HASH' && $type2 eq 'ARRAY' ) {
             push @target, %$data1, @$data2;
        }
    }
    return \@target;
}

sub deep_merge {
    my ( $dest_hash, $src_hash ) = @_;
    foreach my $key ( keys %$src_hash ) {
        if ( exists $dest_hash->{$key} ) {
            my $dest_ref = $dest_hash->{$key};
            my $src_ref = $src_hash->{$key};
            my $dest_typ = ref( $dest_ref );
            my $src_typ = ref( $src_ref );
            if ( $dest_typ eq 'HASH' && $src_typ eq 'HASH') {
                deep_merge( $dest_ref, $src_hash->{$key} );
            }
            else{
                $dest_ref_tmp = $dest_ref;
                my $temp_value = [];
                #push @$temp_value, $dest_ref_tmp, $src_ref ;
                $temp_value = deep_merge_help($dest_ref_tmp, $src_ref);
                $dest_hash->{$key} = $temp_value;
            }
        }
        else {
            $dest_hash->{$key} = $src_hash->{$key};
        }
    }
    return $dest_hash;
}

sub merge_hashes {
    my ($target_hash, $hash_arr) = @_;
    for my $hash (@$hash_arr) {
	$target_hash = deep_merge($target_hash, $hash);
    } 
    return $target_hash;
}

sub fatalErrorStat {
    my ($wrapper_logs, $started, $finished) = @_;
    my $fatal_error_str = start_travel_any_do_any($wrapper_logs, {process=>{code=>\&get_fatal_error, args=>[$started, $finished]}}, -1);
    my $hash = constructHash($fatal_error_str, '', -2);
    return $hash;
}

sub get_fatal_error {
    my (%args) = @_;
    my ($level, $branch, $box, $onepmtype, $id_key) = @{$args{keys}}; #the id_key could be mergeky or onepmid
    my $wrapperlog_arr = $args{values};
    my ($started, $finished) = @{$args{user}};
    my ($started_flag, $finished_flag);
    my $regex = '(\*\*\*\s+NOTHING\s+TO\s+PACKAGE!\s+\*\*\*|fatal:|INCOMPLETE|[Tt]imed?\s*out|Too many open files|^GitCommandError|Unknown Exception running).*' ;
    my $section_start = "^Command:.*packager_wrapper\\.py.*--configfile\\s+\\S+?(?:$onepmtype)";
    my $section_end = '^END TIME .*\d$';
    my $match_all = 1;
    my $target = [];
    my $value = []; # firstly assuming no fatal error 
    for my $wrapper_log (@$wrapperlog_arr) {
        $started_flag = $started->{$level}{$branch}{$box}{$onepmtype}{$id_key}{'STARTED'};
        $finished_flag = $finished->{$level}{$branch}{$box}{$onepmtype}{$id_key}{'FINISHED'};
    	my $fatal_flag = exist_fatal_error($started_flag, $finished_flag);
    	my $fatal_msg = find_in_files_by_reg([$wrapper_log],$regex, "\n", $match_all, $section_start, $section_end ) if -e $wrapper_log;
	#$value = (%$fatal_msg) ? join("\n", @{$fatal_msg->{$wrapper_log}}) : (($fatal_flag) ? '1' : '0');
	if (%$fatal_msg) {
	   $value = [@{$fatal_msg->{$wrapper_log}}]; 
	}
	elsif ($fatal_flag == 1) {
	   $value = ['Y'];
	}
	last if @$value;
    }
    $target = [$level, $branch, $box, $onepmtype, $id_key, 'FATAL', $value] ; #if no fatal error,  still set up the value for the onepmid 
    return $target;
}

sub execute_cmds_concurrent {
    my ($cmds, $writeDir, $rebuild_id) = @_;
    $cmds = ch_cmds_buildid($cmds, $rebuild_id);
    my $results = dispatch_array($cmds, $writeDir);
    my $results_log = dispatch_results_write($results, $writeDir);
    return ($results, $results_log);
}

sub execute_cmds_files {
    my ($cmd_files, $run_file_mode, $platform, $rebuild_id, $writeDir) = @_;
    my @all_files_executed_results;
    print "The program is running on platform $platform\n\n";
    if ($run_file_mode) { #run file one by one
        print BOLD GREEN "The file(s) @$cmd_files will be executed consecutively, while commands in a file concurrently.\n", RESET;
        for my $cmd_file (@$cmd_files) {
	    do {print "The file $cmd_file does not exist!\n"; next;} unless -e $cmd_file;
            print GREEN "Executing commands from $cmd_file now...\n", RESET;
            my $cmds =read_file_to_array($cmd_file);
            my @tmp = grep {/\S/} @$cmds;
            my ($results, $results_log) = execute_cmds_concurrent(\@tmp, $writeDir, $rebuild_id);
            push @all_files_executed_results, $results_log if @$results;
        }
		
    }
    else {#run files concurrently 
          my @cmds_from_all_files;
          print BOLD GREEN "Commands from files @$cmd_files will be put into together and executed concurrently.\n", RESET;
          for my $cmd_file (@$cmd_files) {
	      do {print "The file $cmd_file does not exist!\n"; next;} unless -e $cmd_file;
              my $cmds =read_file_to_array($cmd_file);
              my @tmp = grep {/\S/} @$cmds;
              push @cmds_from_all_files, @tmp;
          }
          my ($results, $results_log) = execute_cmds_concurrent(\@cmds_from_all_files, $writeDir, $rebuild_id) if @cmds_from_all_files;
          push @all_file_executed_results, $results_log if @$results;
    }
    if (@all_files_executed_results) {
        print "Errors exist after running, please refer the file below for details:\n";
        print "$_\n" for my @all_files_executed_results;
    }
}

sub onepmid_must_be_set {
    my ($platform, $user_onepm_id_arr) = @_;
    my $set_on_pc = 0;
    if ($platform =~ /win|pc/ && ! @$user_onepm_id_arr ) {
	$set_on_pc = 1;
    } 
    return $set_on_pc;
}

sub run {
    my $platform = get_platform();
    my $sdsenv = get_sdsenv();
    my $writeDir = write_dir($platform);
    #print "writeDir is $writeDir\n";
    my $rebuild_id = ($rebuild_onepm_id) ? $rebuild_onepm_id : ''; #error exists
    if  (@exec_files) {
	 execute_cmds_files(\@exec_files, $consecutive, $platform, $rebuild_id, $writeDir);
    }
    else {
    	 my @inited = init_sys($platform, $sdsenv);
	 my ($branch_ref,$level,$portdate,$buildtype,$onepm_types,$metalogDir_hash,$metabuild_logs,$hosts_onepmstr,$sl_lan,$lang,$host_buildids, $not_scheduled_branches) = @inited;
	 my $merge_flag = get_mergeFlag($host_buildids, $nomerge_flag, \@user_onepm_id);
	 my $user_onepmid_attri = get_onepmidAttri(\@user_onepm_id);
	 print_checkwhat_section($platform, $portdate, $level, $branch_ref, $buildtype, $not_scheduled_branches, $metabuild_logs);
    	 my $mergekey_onepmids = mergekey_onepmids_hash($host_buildids);
    	 if (@user_products) {  #user driven mode 
	     my $if_onepmid_set_on_pc = onepmid_must_be_set($platform, \@user_onepm_id);
	     do { print BOLD RED "\nYou are running on windows platform, option ${\show_color(33)}onepmid ${\end_color()}", RESET;
                  print BOLD RED "must be set to repackage products!\n", RESET; exit(2);
		} if $if_onepmid_set_on_pc; 
             my $results_log =  
                do_user_driven_products($host_buildids, \@user_products, $mergekey_onepmids, $portdate, $lang, $merge_flag, $user_pattern, \@user_package, $rebuild_id, $writeDir);
    	 }
         else {
    	     my $logpost_reg 	     =  logpostRegexBybuildid($mergekey_onepmids, $user_onepmid_attri, -2);
    	     my $wrapperpost_reg     =  logpostRegexBybuildid($mergekey_onepmids, $user_onepmid_attri, -1);
	     my $Logfind_cmds        = 	get_Logfind_cmds($portdate, $user_pattern, \@user_package, $logpost_reg, {});
	     my $logs_of_all_boxes   = 	get_OnePM_Log($Logfind_cmds);
	     my $initFailedLogs      = 	getInitialFailureLog($logs_of_all_boxes);
    	     my $all_products_info   = 	product_parser($logs_of_all_boxes, $lang, $host_buildids, $merge_flag, $logpost_reg);
             my $initFailed          = 	product_parser($initFailedLogs, $lang, $host_buildids, $merge_flag, $logpost_reg);
	     my $retrieved_Log       =  getSubHashByTemplate($all_products_info, $initFailed); 
    	     my $wrapper_logs        =  onepm_wrapper_logs($wrapperpost_reg, $portdate, $host_buildids, $user_onepmid_attri);
    	     my $wrapperStartEndTime = 	onepm_wrapper_times($wrapper_logs);
             my $started             = 	started_info_of_builds($all_products_info);
	     my $finishedStat        = 	onepmFinishedStatus($wrapperStartEndTime);
             my $fatalError          = 	fatalErrorStat($wrapper_logs, $started, $finishedStat);

	     my ($buildResultsArr, 
		 $failureSuccess  )  = 	getBuildResults($retrieved_Log, $initFailed);
	     my $allBuildStatInfo    = 	merge_hashes({}, [$failureSuccess, $started , $finishedStat, $fatalError]);

	     my $detail_result_key   = 	['FAILURE1', 'FAILURE2', 'FAILURE3+', 'SUCCESS2', 'SUCCESS3+', 'REMAINS_FAIL'];	
	     my $sketch_result_key   = 	['FAILURE1', 'SUCCESS2', 'SUCCESS3+', 'REMAINS_FAIL'];	
	     my $detail_table_head   = 	['STARTED', 'FINISHED', 'FAILURE1', 'FAILURE2', 'FAILURE3+', 'SUCCESS2', 'SUCCESS3+', 'REMAINS_FAIL', 'FATAL'];	
	     my $sketch_table_head   = 	['STARTED', 'FINISHED', 'FAILURE1', 'SUCCESS2', 'SUCCESS3+', 'REMAINS_FAIL', 'FATAL'];	
	     my $filter_reg          = 	($detail) ? $detail_result_key : $sketch_result_key;
	     my $table_head          = 	($detail) ? $detail_table_head : $sketch_table_head;
	     my $result_hash         = 	resultByType($buildResultsArr, $filter_reg);
	     $result_hash->{'FATAL'} = 	$fatalError;
	     my $resultToPrint       = 	getWhatToPrint($result_hash);
	     printResultsTable($allBuildStatInfo, $table_head); 
	     printWrapperTimes($wrapperStartEndTime);
	     printTypeResults($resultToPrint) if %$resultToPrint ; 
	     process_remaining($resultToPrint, $rebuild_id, $writeDir);
          }
   }
}

sub do_user_driven_products {
    my ($host_buildids, $user_products, $mergekey_onepmids, $portdate, $lang, $merge_flag, $user_log_pattern, $user_packages, $rebuild_id, $writeDir) = @_;
    my $deliverables = refactor_user_products($host_buildids, $user_products);
    print BOLD YELLOW "Reliverables:\n", RESET if $debug;
    print Dumper $deliverables if $debug;
    do {print BOLD RED "\nNo products found, exiting\n", RESET; exit(0);} unless %$deliverables;
    my $logpost_reg  =  logpostRegexBybuildid($mergekey_onepmids, 1, -2);
    my $Logfind_cmds = get_Logfind_cmds($portdate, $user_log_pattern, $user_packages, $logpost_reg, $deliverables);
    my $logs = get_OnePM_Log($Logfind_cmds);
    my $products_info = product_parser($logs, $lang, $host_buildids, $merge_flag, $logpost_reg);
    $products_info = uniq_array_item($products_info);
    if (%$products_info) {
       print  BOLD RED  "\nFollowing products will be redelivered:\n\n", RESET ;
       start_travel_any_do_any($products_info, {print=>\&print_data}) ;
       my $results_log = products_rebuilding($products_info, $rebuild_id, $writeDir); #failed cmd hash ref
       if ($results_log) {
           print BOLD RED"Failures exist, results have been written to:\n", RESET;
           print BOLD YELLOW "$results_log\n", RESET;
       }
       else {
          print  BOLD GREEN "All tasks were run successfully\n", RESET;
       }
    }
    else {
       print BOLD YELLOW "No products were found to repackage.\n", RESET;
       print BOLD YELLOW "Pleasure check if the specified products have been scheduled, or\n", RESET;
       print BOLD RED "Make sure you specified the right ${\show_color(36)}onepmid option${\end_color()}.\n", RESET;
    }

}

sub process_remaining {
    my ($resultToPrint, $rebuild_id, $writeDir) = @_;
    if ($resultToPrint->{'REMAINS_FAIL'}) {
       my $REMAINS_FAIL_log = "$writeDir/REMAINS_FAIL*$$";
       my $cmd = "ls $REMAINS_FAIL_log 2>/dev/null";
       my $exists_flag  = `$cmd`;
       my $remaining = $resultToPrint->{'REMAINS_FAIL'};
       if ($exists_flag) {
           print  BOLD RED "\nOnePM error exists and the number is bigger then 20.\n", RESET;
           print BOLD RED "Please refer to the file(s) listed under 'REMAINING FAILURES:' section for detail.\n\n", RESET;
       }
       else {
           print  BOLD RED  "\nOnePM package errors exist and list below:\n\n", RESET;
           start_travel_any_do_any($remaining, {print=>\&print_data});
       }
       my $results_log = products_rebuilding($remaining, $rebuild_id, $writeDir); #failed cmd hash ref
       if ($results_log) {
           print BOLD RED"Failures still exist after rebuilding, results have been written to:\n", RESET;
           print BOLD YELLOW "$results_log\n", RESET;
       }
       else {
          print  BOLD GREEN "All tasks were run successfully\n", RESET;
       }
    }
}

sub print_checkwhat_section {
    my ($platform, $portdate, $level, $branch_ref, $buildtype, $not_scheduled_branches, $metabuild_logs) = @_;
    my $branches_str = join('|', @$branch_ref);
    my $branch_str = (@$branch_ref > 1) ? "+($branches_str)"  : $branch_ref->[0];
    my $print_OnePMdir = onepm_dir($branch_str, $level);
    if (! @user_products) {
        print "${\show_color(01)}CHECK WHAT${\end_color()}\n";
        print "The program is running on platform $platform, portdate is $portdate\n";
        print "OnePM log directory is: $print_OnePMdir \n";
    }
    print "$level $branch_str @$buildtype will be checked\n";
    print BOLD YELLOW "\nBranches @$not_scheduled_branches are not scheduled for OnePM builds!\n" , RESET if @$not_scheduled_branches;
    print BOLD GREEN "metabuild logs:\n", RESET if $debug;
    print Dumper $metabuild_logs if $debug;
}

run();

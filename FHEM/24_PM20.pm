# $Id$
################################################################################
#
#  24_PM20.pm is a FHEM Perl module that provides access and control to
#  Avocents Power Distribution Unit 10/20 Series (PM10/20 PDUs) in conjunction
#  with Avocents Advanced Console Server (ACS16/32/48) 
#  (see: href="http://bit.ly/1SQ4vL6)
#
#  Copyright 2016 by dev0 (http://forum.fhem.de/index.php?action=profile;u=7465)
#
#  This file is part of FHEM.
#
#  Fhem is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 2 of the License, or
#  (at your option) any later version.
#
#  Fhem is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
################################################################################
#
# PM20 change log:
#
# 2016-02-14  0.1    - initial release
# 2016-03-08  0.2    - all necessary functions written
# 2016-03-10  0.2.4  - removed PM20_getIP function
# 2016-03-12  0.2.5  - corrected attr creation on first run
#                    - cmd queue: lower/higher priority for statusRequests
# 2016-03-28  0.3.0  - use of Dispatch
#                    - new cmds: cycle, buzzer, alarm, currentprotection
#                    - internal improvements
#
#
################################################################################

# ------------------------------------------------------------------------------
my $PM20_version = "0.3.0";
my $PM20_desc = 'Avocent Cyclade PDU 10/20 Series (PM10/PM20)';

package main;

use v5.14; #smartmatch, splice
use strict;
use warnings;
use IO::Socket;
use Data::Dumper;
use SetExtensions;
use Blocking;

no warnings 'experimental::smartmatch';

#grep ^sub 24_PM20.pm | awk '{print $1" "$2";"}'
sub PM20_Initialize($);
sub PM20_IORead($$@);
sub PM20_Define($$);
sub PM20_Undef($$);
sub PM20_Delete($$);
sub PM20_Rename();
sub PM20_Shutdown($);
sub PM20_Set($$@);
sub PM20_Write($$$$);
sub PM20_dispatch_SocketStatus($$);
sub PM20_dispatch_PduStatus($$);
sub PM20_dispatch($$$$);
sub PM20_getReadingPrefixBySocket($$);
sub PM20_notReadyToSend($$);
sub PM20_Get($@);
sub PM20_getAliases($);
sub PM20_checkSocketGroups($$);
sub PM20_Attr(@);
sub PM20_defineAttr($);
sub PM20_resetTimer($$;$);
sub PM20_timedStatusRequest($);
sub PM20_telnetRequest($@);
sub PM20_doTelnetRequest($);
sub PM20_doTelnet($@);
sub PM20_doTelnetRequest_Aborted($);
sub PM20_doTelnetRequest_Parse($);
sub PM20_PduRedefine($$$);
sub PM20_defineClientDevices($);
sub PM20_timedDefineClientDevices($);
sub PM20_isClientSocketDefined($$);
sub PM20_syntaxCheck($$@);
sub PM20_doSyntaxCheck($$@);
sub PM20_isSocketAlias($);
sub PM20_isOnOff($);
sub PM20_isIPv4($);
sub PM20_isIPv6($);
sub PM20_isFqdn($);
sub PM20_isMinMax($$$);
sub PM20_isSocketNameDefined($$);
sub PM20_isKnownCmd($);
sub PM20_runningCmd($$);
sub PM20_addQueue($$);
sub PM20_checkQueue($);
sub PM20_isDefinedNotConnected($);
sub PM20_isSocketNotDefined($$;$);
sub PM20_isPduNotDefined($$;$);
sub PM20_modifyReadingName($$);
sub PM20_modifyUserInput($$$);
sub PM20_modifyCommands($$@);
sub PM20_modifyStateToLowerCase($);
sub PM20_internalSocketStates($);
sub PM20_replaceAliases($$);
sub PM20_replaceGroups($$);
sub PM20_adjustReadingsMode($);
sub PM20_delReadings($;$);
sub PM20_BlockingKill($$;$);
sub PM20_isPmInstalled($$);
sub PM20_range2num($$$);
sub PM20_num2range($);
sub PM20_maxVal(@);
sub PM20_minVal(@);
sub PM20_whoami();
sub PM20_reportToAuthor($$$);
sub PM20_log($$;$);

# ------------------------------------------------------------------------------
# set cmds to use: "setCmds" => "telnet_command or http"
# ------------------------------------------------------------------------------
my %PM20_setCmds = (
  "off"               => "pmCommand off",
  "on"                => "pmCommand on",
  "powerondelay"      => "pmCommand powerondelay",
  "cycle"             => "pmCommand cycle",
  "name"              => "pmCommand name",
  "lock"              => "pmCommand lock",
  "unlock"            => "pmCommand unlock",
  "id"                => "pmCommand id",
  "reboot"            => "pmCommand reboot",
  "buzzer"            => "pmCommand buzzer",
  "alarm"             => "pmCommand alarm",
  "currentprotection" => "pmCommand currentprotection",
  "display"           => "pmCommand display",
  "status"            => "status",
  "statusRequest"     => "statusRequest",
  "defineClients"     => "defineClients",
  "help"              => "help"
);


# ------------------------------------------------------------------------------
# params for set cmds: "setCmd" => "params"
# ------------------------------------------------------------------------------
my %PM20_setParams = (
  "powerondelay"      => "0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,".
                         "1,2,3,4,5,6,7,8,9,10,20,30,45,".
                         "60,120,180,240,300,600,1200,1800,3600",
  "reboot"            => "noArg",
  "defineClients"     => "noArg",
);


# ------------------------------------------------------------------------------
# corresponding usage for set cmds: "setCmds" => "usage"
# ------------------------------------------------------------------------------
my %PM20_setCmdsUsage = (
  "status"            => "status",
  "buzzer"            => "buzzer <on|off> <PDU>",
  "currentprotection" => "currentprotection <on|off> <PDU>",
  "display"           => "display <PDU> <0|180>",
  "statusRequest"     => "statusRequest",
  "off"               => "off [<socket>]",
  "on"                => "on [<socket>]",
  "cycle"             => "cycle <socket>",
  "powerondelay"      => "powerondelay <socket> <value>",
  "name"              => "name <socket> <alias name>",
  "id"                => "id <old name> <new name>",
  "lock"              => "lock <sockets>",
  "unlock"            => "unlock <sockets>",
  "reboot"            => "reboot <PDU>",
  "defineClients"     => "defineClients",
  "help"              => "help <".join("|", sort keys %PM20_setCmds).">",
);


# ------------------------------------------------------------------------------
sub PM20_Initialize($)
{
  my ($hash) = @_;
  require "$attr{global}{modpath}/FHEM/DevIo.pm";

# Provider
  $hash->{IOReadFn}     = "PM20_IORead";
  $hash->{WriteFn}      = "PM20_Write"; # will be called from IOWrite 
  $hash->{Clients}      = ":PM20C:"; #used by dispatch(), $hash->{TYPE} of receiver
  #my %matchList         = ( "1:PM20C" => "PWR_.*" );
  my %matchList         = ( "1:PM20C" => ".*" );
  $hash->{MatchList}    = \%matchList;
  #$hash->{ReadFn}       = "PM20_Read";
  #$hash->{ReadyFn}      = "PM20_Ready";

  $hash->{SetFn}        = "PM20_Set";
  $hash->{GetFn}        = "PM20_Get";
  $hash->{DefFn}        = "PM20_Define";
  $hash->{AttrFn}       = "PM20_Attr";
  $hash->{UndefFn}      = "PM20_Undef";
  $hash->{ShutdownFn}	  =	"PM20_Shutdown";
  $hash->{DeleteFn}	    = "PM20_Delete";
	$hash->{RenameFn}	    =	"PM20_Rename";

  $hash->{AttrList}     = "do_not_notify:0,1 ".
                          "disable_fork:1,0 ".
                          "disable:1,0 ".
                          "intervalPresent ".
                          "intervalAbsent ".
                          "multiPduMode:1,0 ".
                          "socketGroups ".
                          "socketsOnOff ".
                          "autocreate:1,0 ".
                          "autosave:1,0 ".
                          "standalone:0,1 ".
                          $readingFnAttributes;
}


# ------------------------------------------------------------------------------
sub PM20_IORead($$@)
{
  my ($hash,$what,$args) = @_;
  my $name = $hash->{NAME};
  my @args = split(" ",$args);
  my $ret;

  if ($what eq "reading") {
#    return $hash->{READINGS}{$args[0]}{VAL}
    return ReadingsVal($name,$args[0],"unknown");
  }

  elsif ($what eq "attr") {
#    return $attr{$args[0]}{$args[1]}
    return AttrVal($name,$args[0],"unknown");
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub PM20_Define($$)  # only called when defined, not on reload.
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  # check needed perl modules

  return "ERROR: 'Perl modul Net::Telnet not installed'" 
    if (PM20_isPmInstalled($hash,"Net::Telnet"));

  my $usg = "Use 'define <name> PM20 <host> ".
            "[s:<socket>] [s:<socket>] [t:<telnetPort>] ".
            "[u:<username>] [p:<password>]'";

  return "Wrong syntax: $usg" if(int(@a) < 3);

  my $name = $a[0];
  my $type = $a[1];
  my $host   = $a[2];
  my $err;
  my $s = "";
  
  #defaults
  $hash->{TELNET_PORT}  = 23;
  $hash->{INTERVAL}     = 300;
  $hash->{USER}         = "admin";
  $hash->{PASS}         = "admin";


  if (not( PM20_isIPv4($host) || PM20_isIPv6($host) || PM20_isFqdn($host) )) {
    return "ERROR: [invalid IP or FQDN: '$host']"}
#  if (not PM20_getIP($host)) {
#    return "ERROR: [unresolvable hostname: '$host'] - Check hostname or dns service."}
  $hash->{HOST} = $host;
#  $hash->{AFTYPE} = PM20_getAFtype($host);
  splice(@a,2,1);

  foreach my $item (@a) {
    next if (not $item =~ /:/);

    my ($what,$val) = split(":",$item);
    return "ERROR: [invalid argument: '$what:'] - $usg" if ((!defined $val) || $val eq "");
    if ($val =~ /^\d+$/ && $what eq "t") {
      if ($val > 1 && $val <= 65535) {
        $hash->{TELNET_PORT} = $val;
      } else { $err = "telnet port: '$val'" }

    } elsif ($what eq "i") {
      if ($val =~ /^\d+$/ && $val >= 60) {
        $hash->{INTERVAL} = $val;
      } else { $err = "interval: '$val'" }

    } elsif ($what eq "u") {
      if ($val =~ /^[a-zA-Z\d\._-]+$/) {
        $hash->{USER} = $val;
      } else { $err = "username: '$val'" }

    } elsif ($what eq "p") {
      if ($val =~ /.+/) {
        $hash->{PASS} = $val;
      } else { $err = "password: '$val'" }

    } elsif ($what eq "s") {
      # s:PDU1[1,2,3,4-11] s:PDU2[1,2,3,10-20]
      if ($val =~ /(.*)\[(.*)\]/) {
        if (defined PM20_range2num($2,1,20)) {
          $hash->{SOCKETS}{DEFINED}{$1} = PM20_range2num($2,1,20);
          $s .= "," if (length($s) > 1); #just optical
          $s .= $1."[".PM20_num2range($hash->{SOCKETS}{DEFINED}{$1}."]"); 
        } else { $err = "s: '$val'" }
      } else { $err = "s: '$val'" }
    } else {
      $err = "argument: '$what:$val'";
    }

    return "ERROR: [invalid $err] - $usg" if (defined $err);
  }

  if ($s eq "") { #cp connected -> defined after statusRequest
    $hash->{helper}{USEALLPDUS} = 1;
    $s = "all";
  }
  
  Log3 $hash->{NAME}, 2, "PM20: Device $name opened -> Host:$hash->{HOST} ".
                         "Port:$hash->{TELNET_PORT} ".
                         "Interval:$hash->{INTERVAL} ".
                         "Sockets:$s ";

  readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, 'state', 'opened');
 	readingsBulkUpdate($hash, 'presence', "unknown");
  readingsEndUpdate($hash,1);
  PM20_resetTimer($hash,"start",int(rand(5))+int(rand(10))/10+int(rand(10))/100 );

  return undef;
}


# ------------------------------------------------------------------------------
#UndefFn: called while deleting device (delete-command) (wrong: while rereadcfg)
sub PM20_Undef($$)
{
  my ($hash, $arg) = @_;
  #Log3 $hash->{NAME}, 1, "$hash->{NAME}: undefFn";
  BlockingKill($hash->{helper}{RUNNING_PID}) if (defined($hash->{helper}{RUNNING_PID}));
  delete $hash->{helper} if (defined($hash->{helper}));
  RemoveInternalTimer($hash);
  return undef;
}


# ------------------------------------------------------------------------------
#DeleteFn: called while deleting device (delete-command) but after UndefFn
sub PM20_Delete($$)
{
  my ($hash, $arg) = @_;
  Log3 $hash->{NAME}, 1, "$hash->{TYPE}: Device $hash->{NAME} deleted";
  setKeyValue($hash->{TYPE}."_".$hash->{NAME},undef);
  return undef;
}


# ------------------------------------------------------------------------------
sub PM20_Rename() {
	my ($new,$old) = @_;
	my $ll = 2;
  my $i = 1;
	my $type = $defs{"$new"}->{TYPE};
	my $name = $defs{"$new"}->{NAME};
	setKeyValue($type."_".$new,getKeyValue($type."_".$old));
	setKeyValue($type."_".$old,undef);
  Log3 $name, $ll, "$type: Device $old renamed to $new";
  #readingsSingleUpdate($new,"_lastNotice","Device $old renamed to $new",1);
  
  foreach my $pm20c (devspec2array("TYPE=$type"."C")) {
    my $dhash = $defs{$pm20c};
    my $dname = $dhash->{NAME};
    my $dtype = $dhash->{TYPE};
    my $ddef  = $dhash->{DEF};
    my $oddef = $dhash->{DEF};
    $ddef =~ s/^$old /$new /;
    if ($oddef ne $ddef){
      $i++;
      Log3 $type, $ll, "$dtype: Redefined device $dname -> DEF -> $ddef";
      #readingsSingleUpdate($dname,"_lastNotice","DEF modified -> $ddef",1);
      CommandModify(undef, "$dname $ddef");
    }
  }
  Log3 $type, $ll, "$type: There are $i structural changes. Don't forget to save chages.";

	return undef;
}


# ------------------------------------------------------------------------------
#ShutdownFn: called before shutdown-cmd
sub PM20_Shutdown($)
{
	my ($hash) = @_;
  #Log3 $hash->{NAME}, 1, "$hash->{NAME}: shutdownFn";

  BlockingKill($hash->{helper}{RUNNING_PID}) if (defined($hash->{helper}{RUNNING_PID}));
  delete $hash->{helper} if (defined($hash->{helper}));
  RemoveInternalTimer($hash);
  Log3 $hash->{NAME}, 1, "$hash->{TYPE}: Device $hash->{NAME} shutdown requested";
	return undef;
}


# ------------------------------------------------------------------------------
sub PM20_Set($$@)
{
  my ($hash, $name, $cmd, @params) = @_;
  my $self = PM20_whoami();

  $params[0] = "" if !$params[0];
  $params[1] = "" if !$params[1];

  if (IsDisabled $name) {
    PM20_resetTimer($hash,"start");
    return;
  }


  Log3 $hash->{NAME}, 5, "$name: $self() got: hash:$hash, name:$name, cmd:$cmd, ".
                         "params:".join(" ",@params) if ($cmd ne "?");

  # get setCommands from hash
  my @cList = sort keys %PM20_setCmds;

  if(!$PM20_setCmds{$cmd}) {
    my $clist = join(" ", @cList);
    my @pList = keys %PM20_setParams;
    foreach my $cmd (@pList) {
      $clist =~ s/$cmd/$cmd:$PM20_setParams{$cmd}/
    }
    my $hlist = join(",", @cList);
    $clist =~ s/help/help:$hlist/; # add all cmds as params to help cmd
    return SetExtensions($hash, $clist, $name, $cmd, @params);
  }

  # check that all necessary attrs are defined
  PM20_defineAttr($hash);
  # add option to enter values in sec/min/etc...
  $params[1] = PM20_modifyUserInput($hash,$cmd,$params[1]) if defined $params[1];
  # replace alias names by real socket names
  $params[0] = PM20_replaceAliases($hash,$params[0]) if defined $params[0];
  # replace group names by real socket names
  $params[0] = PM20_replaceGroups($hash,$params[0]) if defined $params[0];
  # modify some commands. eg. "set x on" -> "set x on PDU1[1-20],PDU2[1-20]"
  ($cmd,@params) = PM20_modifyCommands($hash,$cmd,@params);

  # do syntax check
  my $sc = PM20_syntaxCheck($hash,$cmd,@params);
  return $sc if (defined $sc);

  if ($cmd eq "help") {
#		Dispatch($hash, "xxxx", undef);  # dispatch to PM20Cs
    my $usage = $PM20_setCmdsUsage{$params[0]};
    $usage     =~ s/Note:/\nNote:/g;
    return "Usage: set $name $usage";
  }
  elsif ($cmd eq "defineClients") {
    my $defines = PM20_defineClientDevices($hash);
    return "$defines new $hash->{TYPE}C devices defined.";
  }
#  elsif ($cmd eq "getStatus") {
#    Log3 $name, 3, "$name: set $name $cmd $params[1]";
##    PM20C_dispatch($hash,dev,"");
#    return undef;
#  }

  if (defined PM20_notReadyToSend($hash,$cmd)) {
    PM20_addQueue($hash,"$cmd ".join(" ",@params));
    Log3 $name, 5, "$name: $self queued: $cmd";
    return undef;
  }
  Log3 $name, 5, "$name: $self not queued: $cmd";

  # notify that device is unreachable
  PM20_log($name,"offline: set $name $cmd @params") if (defined $hash->{helper}{absent});

  # exec all other commands via telnetRequest
  my $plist = join(" ", @params);
  my $qs = defined $hash->{helper}{QUEUE_NOW} ? "(queue id: $hash->{helper}{QUEUE_NOW})" : "";
  delete $hash->{helper}{QUEUE_NOW};

  PM20_log($name,"set $name $cmd $plist $qs");# if (!defined $hash->{helper}{RUNNING_PID}); 
  PM20_telnetRequest($hash,"set $cmd $plist");

  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_Write($$$$) # redir to SetFn
{
  my ($hash,$cmd,$socket,$param) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 5, "$hash->{TYPE}: $name PM20_Write() call PM20_Set($hash, $cmd, $socket)";

  if ($cmd eq "status") {
    $socket =~ m/(.*)(\[\d+\])/;
    PM20_dispatch_SocketStatus($hash,$socket) if $2;
    PM20_dispatch_PduStatus($hash,$socket) if !$2;
    return undef;
  }
  PM20_Set($hash,$name,$cmd,$socket,$param);
}

# ------------------------------------------------------------------------------
sub PM20_dispatch_SocketStatus($$)
{
  my($hash,$socket) = @_;
  my $name = $hash->{NAME};
  my @msg;
  $socket =~ m/(.*)\[(\d+)\]/;
  my $pdu = $1;
  my @socketReadings = sort keys $hash->{helper}{pdus}{$pdu}{sockets}{$socket};

  foreach my $reading (@socketReadings) {
    my $value = $hash->{helper}{pdus}{$pdu}{sockets}{$socket}{$reading};
    push( @msg, "$reading|".$value );
  }
  push( @msg, "presence|".ReadingsVal($name,"presence","unknown") );
  push( @msg, "pdu|$pdu" );
 
  my $as = PM20C_isAutosaveEnabled($hash);
  my $ac = PM20C_isAutocreateEnabled($hash);

  my $msg = "$socket:$ac:$as:".join("||",@msg);
  Dispatch($hash, $msg, undef);

  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_dispatch_PduStatus($$)
{
  my($hash,$pdu) = @_;
  my $name = $hash->{NAME};

  my @msg;
#  return undef;
  my @pduReadings = sort keys $hash->{helper}{pdus}{$pdu};
  foreach my $reading (@pduReadings) {
    next if $reading =~ m/aliases|sockets/; #skip aliases and sockets
    if (ref($hash->{helper}{pdus}{$pdu}{$reading}) eq "HASH") {
      foreach my $subreading (keys $hash->{helper}{pdus}{$pdu}{$reading}) {
        push( @msg, "$reading"."_$subreading|".$hash->{helper}{pdus}{$pdu}{$reading}{$subreading} );
      }
    }
    else {
      push( @msg, "$reading|".$hash->{helper}{pdus}{$pdu}{$reading} );
    }
  }
  push( @msg, "presence|".ReadingsVal($name,"presence","error") );
  push( @msg, "state|".ReadingsVal($name,"state","error") );
 
  my $as = PM20C_isAutosaveEnabled($hash);
  my $ac = PM20C_isAutocreateEnabled($hash);
  my $msg = "$pdu:$ac:$as:".join("||",@msg);
  Dispatch($hash, $msg, undef);

  return undef;
}

# ------------------------------------------------------------------------------
# 1:hash 2:dev 3:reading 4:value
sub PM20_dispatch($$$$) 
{
  my ($hash,$socket,$r,$v) = @_;
  my $name = $hash->{NAME};
  $r = "state" if $r =~ m/_state$/;
  my $as = PM20C_isAutosaveEnabled($hash);
  my $ac = PM20C_isAutocreateEnabled($hash);
  my $msg = "$socket:$ac:$as:$r|$v";
	Dispatch($hash, $msg, undef);  # dispatch result to PM20 client devices
}

# ------------------------------------------------------------------------------
sub PM20_getReadingPrefixBySocket($$)
{
  my ($hash,$socket) = @_;
  $socket =~ m/(.*)\[(\d+)\]/;
  my $pdu = $1;
  my $snum = ($2 < 10) ? "0".$2 : $2;   # add leading 0
  my $ports = ($hash->{READINGS_MODE} eq "single") ? "socket".$snum : $pdu.$snum;
  $pdu      = ($hash->{READINGS_MODE} eq "single") ? "" : $pdu;
  return ($ports, $pdu);
#  return ($hash->{READINGS_MODE} eq "single") ? "socket".$snum : $1.$snum;
}

# ------------------------------------------------------------------------------
sub PM20_notReadyToSend($$)
{
  my ($hash,$cmd) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami()."()");

  # DO NOT QUEUE statusRequest while telnet failed, no fork active. Without
  # statusRequest no return to normal state (telnetFailed will be reseted after
  # good statusRequest
  return undef if ((defined $hash->{helper}{telnetFailed}) 
               && (not defined $hash->{helper}{RUNNING_PID})
               && $cmd =~ /statusRequest/);

  return 1 if $hash->{helper}{RUNNING_PID};
  return 1 if (ReadingsVal($name,"state","") ne "initialized" && not($cmd =~ /help|statusRequest/));
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_Get($@)
{
  my ($hash, @a) = @_;
  return "argument is missing" if(int(@a) != 2);

  my $reading = $a[1];
  my $ret;

  if ($reading eq "aliases") {
    $ret = PM20_getAliases($hash);
  }
  if ($reading eq "modul_version") {
    $ret = $PM20_version;
  }
  
  elsif (exists($hash->{READINGS}{$reading})) {
    if (defined($hash->{READINGS}{$reading})) {
      return $hash->{READINGS}{$reading}{VAL};
    }
    else {
      return "no such reading: $reading";
    }
  }

  else {
    $ret = "unknown argument $reading, choose one of";
    $ret .= " aliases:noArg";
    $ret .= " version:noArg";
    foreach my $reading (sort keys %{$hash->{READINGS}}) {
      $ret .= " $reading:noArg" if ($reading ne "firmware");
    }
    return "$ret";
  }
}

# ------------------------------------------------------------------------------
sub PM20_getAliases($) {
  my ($hash) = @_;
  my $ret = "";
  my @aliases = sort keys $hash->{ALIASES};
  foreach my $alias (@aliases) {
    $ret .= "$alias -> $hash->{ALIASES}{$alias}\n"
  }
  $ret =~ s/\n$//;
  return $ret;
}

sub PM20_checkSocketGroups($$) {
  my ($hash,$groups) = @_;
  my @groups = split(" ",$groups);
  
  delete $hash->{GROUPS} if $hash->{GROUPS};
  foreach (@groups) {
    my ($group,$members) = split(":",$_);
    $hash->{GROUPS}{$group} = $members;
  }
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  my $ret = undef;
  my $state = $hash->{READINGS}{state}{VAL};

  # InternalTimer will be called from notifyFn if disabled = 0
  if ($aName eq "disable") {
    $ret="0,1" if ($cmd eq "set" && not $aVal =~ /(0|1)/);
    if ($cmd eq "set" && $aVal eq "1") {
      Log3 $name, 3, "$type: Device $name is disabled";
      PM20_delReadings($hash,1);
      readingsSingleUpdate($hash, "state", "disabled",1);
    }
    elsif (($cmd eq "set" && $aVal eq "0") || $cmd eq "del") {
      Log3 $name, 4, "$type: Device $name is enabled";
      readingsSingleUpdate($hash, "state", "opened",1);
      PM20_resetTimer($hash,'start',rand(5));
    }
  }

  elsif ($aName eq "disable_fork") {
    $ret = "0,1" if ($cmd eq "set" && not $aVal =~ /(0|1)/)
  }

  elsif ($aName eq "multiPduMode") {
    $ret = "0,1" if ($cmd eq "set" && not $aVal =~ /(0|1)/);
    if ($cmd eq "set" && $aVal =~  /^(0|1)$/) {
      if (ReadingsVal($name,"state","") ne "opened") { #not at startup
        PM20_delReadings($hash);
        PM20_resetTimer($hash,'start',rand(5));
      }
    }
    elsif ($cmd eq "del" && $attr{$name}{multiPduMode} eq  "1") {
      PM20_delReadings($hash);
      PM20_resetTimer($hash,'start',rand(5));
    }
  }

  elsif ($aName eq "autocreate") {
    $ret = "0,1" if ($cmd eq "set" && not $aVal =~ /(0|1)/);
  }
  
  elsif ($aName eq "autosave") {
    $ret = "0,1" if ($cmd eq "set" && not $aVal =~ /(0|1)/);
  }

  elsif ($aName eq "standalone") {
    $ret = "0,1" if ($cmd eq "set" && not $aVal =~ /(0|1)/);
    if ($init_done == 1) {
      if (($cmd eq "set" && $aVal eq "0") || $cmd eq "del"){
        PM20_delReadings($hash);
      }
      elsif ($cmd eq "set" && $aVal eq "1") {
        foreach (devspec2array("TYPE=PM20C")) {
          fhem("delete $_");
        }
      }
      InternalTimer(gettimeofday()+1,"PM20_timedStatusRequest", $hash, 0);
    } # init_done
  }
  
  elsif ($aName eq "socketGroups") {
    if    ($cmd eq "set") { PM20_checkSocketGroups($hash,$aVal) }
    elsif ($cmd eq "del") { delete $hash->{GROUPS} if $hash->{GROUPS} }
  }

  elsif ($aName eq "socketsOnOff") {
    if ($cmd eq "set")    { }
    elsif ($cmd eq "del") { }
  }

  elsif ($aName eq "intervalPresent") {
    $ret = ">=60" if ($cmd eq "set" && int($aVal) < 60)
  }

  elsif ($aName eq "intervalAbsent") {
    $ret = ">=60" if ($cmd eq "set" && int($aVal) < 60)
  }

  # do some loggin if there are errors...
  if (defined $ret) {
    PM20_log($name,"attr $aName $aVal != $ret");
    return "$aName must be: $ret";
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub PM20_defineAttr($)
{
  my $name = $_[0]->{NAME};
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  
  return undef if (defined getKeyValue($hash->{TYPE}."_".$hash->{NAME}));

  my %as = (
    "room"   => "Avocent",
    "group"  => "Gateway",
    "webCmd" => ":",
    "event-on-change-reading" => ".*"
  );

  my @al = sort keys %as;
  foreach my $a (@al) {
    if(!defined($attr{$name}{$a})) {
	  	$attr{$name}{$a} = $as{$a};
      PM20_log($name, "attr $name $a $as{$a}");
    }
  }
  unless(defined getKeyValue($hash->{TYPE}."_".$hash->{NAME})){
    setKeyValue($hash->{TYPE}."_".$hash->{NAME},"attr=1")
  }
  
  return undef;
}


# ------------------------------------------------------------------------------
sub PM20_resetTimer($$;$)
{
  my ($hash,$cmd,$interval) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami());
  return if (IsDisabled $name);

  Log3 $hash->{NAME}, 5, "$name: $self() RemoveInternalTimer($hash)";
  RemoveInternalTimer($hash);

  if ($cmd ne "stop") {
    if (defined $interval) {
      # use opt. parameter as interval
    }
    elsif (defined $hash->{READINGS}{presence}{VAL}
      && $hash->{READINGS}{presence}{VAL} eq "absent"
      && defined $attr{$name}{intervalAbsent})
        { $interval = $attr{$name}{intervalAbsent}+rand(6)-3; }

    elsif (defined $hash->{READINGS}{presence}{VAL} 
      && $hash->{READINGS}{presence}{VAL} ne "absent"
      && defined $attr{$name}{intervalPresent})
      { $interval = $attr{$name}{intervalPresent}+rand(6)-3; }

    else
      { $interval = $hash->{INTERVAL}+rand(6)-3; }

    Log3 $name, 5, "$name: $self() InternalTimer(+$interval,\"PM20_timedStatusRequest\",".' $hash, 0)';
    InternalTimer(gettimeofday()+$interval,"PM20_timedStatusRequest", $hash, 0);
  }
  else {
    Log3 $name, 5, "$name: $self() InternalTimer() deleted";
  }

  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_timedStatusRequest($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  unless(IsDisabled($name)) {
    PM20_Set($hash,$name,"statusRequest","")
  }
}


# ------------------------------------------------------------------------------
# --- PM20_telnetRequest (split between blocking and non-blocking telnet) --
# ------------------------------------------------------------------------------
sub PM20_telnetRequest($@)
{
  my ($hash,$param) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami()."()");

#  $hash->{helper}{RUNNING}{TELNET} = 1;

  my $host =  $hash->{HOST};
  Log3 $name, 5, "$name: $self got: $param";

  if (defined $attr{$hash->{NAME}}{disable_fork}
     && ($attr{$hash->{NAME}}{disable_fork} == 1))
  {
    $hash->{helper}{RUNNING_PID} = 1; # used in parseFN, to check if devices was deleted and avoid errors
    Log3 $name, 5, "$name: $self call: PM20_doTelnetRequest($hash->{NAME}|$host|$param)";
    PM20_runningCmd($hash,$param);
    my $ret = PM20_doTelnetRequest($hash->{NAME}."|".$host."|".$param);
    Log3 $name, 5, "$name: $self call: PM20_doTelnetRequest_Parse($ret)";
    PM20_doTelnetRequest_Parse($ret);
  }
  else
  {
    Log3 $name, 5, "$name: $self call: BlockingCall(\"PM20_doTelnetRequest\", $hash->{NAME}|$host|$param)";
    if (not defined($hash->{helper}{RUNNING_PID})) {
      PM20_reportToAuthor($hash,$self,$param);
      PM20_runningCmd($hash,$param); #Display Internals: RUNNING_CMD
      $hash->{helper}{RUNNING_PID} = BlockingCall(
      "PM20_doTelnetRequest", $hash->{NAME}."|".$host."|".$param,
      "PM20_doTelnetRequest_Parse", 30,
      "PM20_doTelnetRequest_Aborted", $hash);
      Log3 $name, 5, "$name: $self running PID: $hash->{helper}{RUNNING_PID}";
    }
    else { #should not happen
      PM20_reportToAuthor($hash,$self,$param);
    }

  }
  return undef;
}


# ------------------------------------------------------------------------------
# --- get/set via telnet
# ------------------------------------------------------------------------------
sub PM20_doTelnetRequest($)
{
  my ($string) = @_;
  my ($name, $host, $param) = split("\\|", $string);
  my ($what,$command) = split(" ",$param,2);
  my $self = PM20_whoami();
  my $hash = $defs{$name};
  my $tRet;
  my $ret;
  my @r;
  my $r;
  $command = "" if (!defined $command);
  Log3 $name, 5, "$name: $self() got: $string";
  Log3 $name, 5, "$name: $self() got: what:$what command:$command";

  my $tPort = $hash->{TELNET_PORT};
  my $telnet = new Net::Telnet (Port=>$tPort,
                                Timeout=>120,
                                Errmode=>'return',
                                Prompt=>"/.$hash->{USER}.*$hash->{USER}]/",
                                Output_record_separator=>"\n",
                                Family=>'any',);
   Log3 $name, 5, "$name: $self() call: PM20_doTelnet($hash,$telnet,\"open\")";
  # --- open telnet connect
  $tRet = PM20_doTelnet($hash,$telnet,"open");
  if ($tRet ne "OK") {
    Log3 $name, 5, "$name: $self() return: $name||failed::$tRet";
#    return $name."||||failed||||".$tRet;
#    return $name."||||failed||||".$tRet."|||$param";
    return $name."||||failed||||".$tRet."|||$command"; #without /^set /
  }

  Log3 $name, 5, "$name: $self() call: PM20_doTelnet($hash,$telnet,\"$what\")";

#  if ($what eq "statusRequest") #GET all system parameters
  if ($command =~ /^statusRequest/) #GET all system parameters

  {
    # listipdus has to be the first command, to be able to check in _parse PDUs
    @r = PM20_doTelnet($hash,$telnet,"set","listipdus","");
    $r = join("",@r);
    $r =~ s/IPDU.*ID.*Location.*\r?\n//; # remove 1st line that start with "IPDU"
    $r =~ s/^\r?\n//mg;     # remove empty lines
    $r =~ s/\x20+/:/g;      # replace spaces between values with ":"
    $r =~ s/\r?\n/|/g;      # replace cr+lf with "|"
    $r =~ s/\|$//g;         # remove tailing "|"
    $ret = "listipdus||".$r;
    
    @r = PM20_doTelnet($hash,$telnet,"set",'status','all');
    #@r = PM20_doTelnet($hash,$telnet,"configRequest",'pmCommand status all | awk \'{if (length($0) > 5 && $1 != "Outlet") print $1"|"$2"|"$3"|"$4}\'');
    $r = join("",@r);
    $r =~ s/Outlet.*\r?\n//; # remove 1st line that start with "Outlet"
    $r =~ s/^\r?\n//mg;      # remove empty lines
    $r =~ s/\x20+/:/g;       # replace spaces between values with ":"
    $r =~ s/\r?\n/|/g;       # replace cr+lf with "|"
    $r =~ s/\|$//g;          # remove tailing "|"
    $ret .= "|||status||".$r;

    @r = PM20_doTelnet($hash,$telnet,"set",'current','|awk \'{if (length($0) > 5) print $1$4":"$7":"$10":"$13}\'');
    $r = join("",@r);
    $r =~ s/\r?\n/|/g;       # replace cr+lf with "|"
    $r =~ s/(\d)A\./$1/g;    # remove unit incl. trailing dot
    $r =~ s/\|$//g;          # remove tailing "|"
    $ret .= "|||current||".$r;

    @r = PM20_doTelnet($hash,$telnet,"set",'temperature','| awk \'{if (length($0) > 5) print $1$5":"$10":"$15":"$20}\'');
    $r = join("",@r);
    $r =~ s/\r?\n/|/g;       # replace cr+lf with "|"
    $r =~ s/\|$//g;          # remove tailing "|"
    $ret .= "|||temperature||".$r;

    @r = PM20_doTelnet($hash,$telnet,"set",'voltage','| awk \'{if (length($0) > 5) print $1$4}\'');
    $r = join("",@r);
    $r =~ s/\r?\n/|/g;       # replace cr+lf with "|"
    $r =~ s/\|$//g;          # remove tailing "|"
    $r =~ s/(\d\.\d)V/$1/g;    # remove unit incl. trailing dot
    $ret .= "|||voltage||".$r;

    @r = PM20_doTelnet($hash,$telnet,"set",'power','| awk \'{if (length($0) > 5) print $1$4}\'');
    $r = join("",@r);
    $r =~ s/\r?\n/|/g;       # replace cr+lf with "|"
    $r =~ s/(\d)W/$1/g;      # remove unit
    $r =~ s/\|$//g;          # remove tailing "|"
    $ret .= "|||power||".$r;

    @r = PM20_doTelnet($hash,$telnet,"set",'buzzer','status | awk \'{if (length($0) > 5) print $1$4}\'');
    $r = join("",@r);
    $r =~ s/\r?\n/|/g;       # replace cr+lf with "|"
    $r =~ s/\|$//g;          # remove tailing "|"
    $ret .= "|||buzzer||".$r;

    @r = PM20_doTelnet($hash,$telnet,"set",'currentprotection','status | awk \'{if (length($0) > 5) print $1$5}\'');
    $r = join("",@r);
    $r =~ s/\r?\n/|/g;       # replace cr+lf with "|"
    $r =~ s/\.//g;           # remove point after unit
    $r =~ s/\|$//g;          # remove tailing "|"
    $ret .= "|||currentprotection||".$r;

    @r = PM20_doTelnet($hash,$telnet,"set",'ver','| awk \'{if (length($0) > 5) print $1$10}\'');
    $r = join("",@r);
    $r =~ s/\r?\n/|/g;       # replace cr+lf with "|"
    $r =~ s/\|$//g;          # remove tailing "|"
    $ret .= "|||ver||".$r;

    @r = PM20_doTelnet($hash,$telnet,"set",'alarm','| awk \'{if (length($0) > 5) print $1$5}\'');
    $r = join("",@r);
    $r =~ s/\r?\n/|/g;       # replace cr+lf with "|"
    $r =~ s/A\.//g;         # remove point after unit
    $r =~ s/\|$//g;          # remove tailing "|"
    $ret .= "|||alarm||".$r;

    @r = PM20_doTelnet($hash,$telnet,"set",'display','| awk \'{if (length($0) > 5) print $0}\'');
    $r = join("",@r);
    $r =~ s/\r?\n/|/g;       # replace cr+lf with "|"
    $r =~ s/Display mode set to //g;   # remove point after unit
    $r =~ s/ and cycle manually\.//g;           #
    $r =~ s/^\s*//;          # remove leading \s
    $r =~ s/\|$//g;          # remove tailing "|"
    $ret .= "|||display||".$r;

    @r = PM20_doTelnet($hash,$telnet,"set",'powerfactor','| awk \'{if (length($0) > 5) print $1$4}\'');
    $r = join("",@r);
    $r =~ s/.\r?\n/|/g;      # replace cr+lf with "|" and remove last dot
    $r =~ s/\|$//g;          # remove tailing "|"
    $ret .= "|||powerfactor||".$r;

    $ret = $name."||||statusRequest||||".$ret;
  }

  elsif ($what eq "get") #GET system parameters
  {
    $tRet = PM20_doTelnet($hash,$telnet,"get",$command);
    $ret = $name."||||getCmd||||".$tRet;
  }

  elsif ($what eq "set") # SET system parameter
  {
#    Log3 $name, 1, "$name: $self() set command:'$command'";
    my @r = PM20_doTelnet($hash,$telnet,"set",$command);
    $r = join("",@r);
    $r =~ s/^\r?\n//mg;      # remove empty lines
    $r =~ s/.\r?\n/|/g;       # replace cr+lf with "|" and remove last dot
    $r =~ s/\|$//g;           # remove tailing "|"
    $ret = "$command||".$r;

    $ret = $name."||||setCmd||||".$ret; #eg. device||||setCmd||||pmCommand_off NetB[01]||NetB[1]: Outlet turned off
    #Log3 $name, 5, "$name, $self() ret:$ret";
  }

  # --- close telnet connect
  $tRet = PM20_doTelnet($hash,$telnet,"close");
  if ($tRet ne "OK") {
    Log3 $name, 5, "$name: $self() return: $name||||failed||||$tRet";
    return $name."||||failed||||".$tRet;
  }

  return $ret;
}


# ------------------------------------------------------------------------------
# --- telnet functions: open, single, bulk, close (return: error code or data)
# ------------------------------------------------------------------------------
sub  PM20_doTelnet($@)
{
  my ($hash,$telnet,$what,$cmd,$param) = @_;  #$what = open,single,bulk,close
  my ($name,$self) = ($hash->{NAME},PM20_whoami());
  my @lines;
  $cmd = "" if !$cmd;
  $param = "" if !$param;
    
  Log3 $name, 5, "$name: $self() got: \$hash, \$telnet, what:$what, cmd:$cmd";

  if ($what eq "open") {
    #$telnet->dump_log('tdump.txt');
    unless($telnet->open($hash->{HOST})) {
      return "failed: telnet open"};
    unless($telnet->login(Name => $hash->{USER}, Password => $hash->{PASS})){
      return "failed: telnet login";
    }
    return "OK";

  } elsif ($what =~ /(set|get)/) {
    my $tCmd = $cmd; 
    $tCmd =~ s/(.*)/pmCommand $1 $param/;
    Log3 $name, 5, "$name: $self() $what: $tCmd";
    @lines = $telnet->cmd($tCmd);
    return @lines;

  } elsif ($what eq "close") {
    unless($telnet->close) {return "failed: telnet close"};
    return "OK";

  } else {
    Log3 $name, 5, "$name: $self() ??? unexpected what:$what";
  }
}


# ------------------------------------------------------------------------------
sub PM20_doTelnetRequest_Aborted($)
{
  my ($hash) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami());
  return if (!defined $hash->{helper}{RUNNING_PID});
  Log3 $name, 5, "$name: $self() got: $hash";
  delete $hash->{helper}{RUNNING_PID};
  PM20_log($name,"failed: BlockingCall");
  PM20_resetTimer($hash,'start');
  return undef;
}


# ------------------------------------------------------------------------------
sub PM20_doTelnetRequest_Parse($)
{
  my ($string) = @_;
  return unless(defined($string));

#  Log3 undef, 1, "PM20_doTelnetRequest_Parse: got string: $string";

  my ($name, $what, $value) = split("\\|\\|\\|\\|", $string);
  my $hash = $defs{$name};
  my $self = PM20_whoami();

  if (!defined $hash->{helper}{RUNNING_PID}) { #was deleted by deleteFn or undefFn
    Log3 $name, 2, "$name: {RUNNING_PID} do not exists";
#    delete $hash->{helper}{RUNNING_PID};
    PM20_resetTimer($hash,'start') if (defined $defs{$name});
    return undef;
  }
  PM20_runningCmd($hash,"none"); # display i:RUNNING_CMD
  delete $hash->{helper}{RUNNING_PID};

  Log3 $name, 5, "$name: $self() got: $string";
  Log3 $name, 5, "$name: $self() -> what:'$what'";

  # failed while open port or login to device
  if ($what eq "failed") {
    Log3 $name, 1, "$name: telnet failed (open/login)";

    # add failed commands to queue
    # eg. "failed: telnet login|||powerondelay Prod[1] 0.1"
    my ($terr,$failedCmd) = split("\\|\\|\\|",$value);
    PM20_addQueue($hash,$failedCmd) if ($failedCmd && $failedCmd !~ /statusRequest/);       # statusRequest will not be queued

    # if not in failed state, do so...
    if (!defined $hash->{helper}{telnetFailed}) {
      PM20_log($name,"$value");
      $hash->{helper}{telnetFailed} = 1;
      PM20_delReadings($hash);
     	readingsSingleUpdate($hash, 'presence', "absent",1);
    }
    PM20_resetTimer($hash,'start'); #use intervalAbsent if defined
    return undef;
  } # if ($what eq "failed")

  # if current state == failed, get back to normal operation
  elsif ( defined $hash->{helper}{telnetFailed} ) {
    delete $hash->{helper}{telnetFailed};
    PM20_log($name,"OK: telnet");
  }
	readingsSingleUpdate($hash, 'presence', "present",1);

   
  if ($what eq "statusRequest")
  {
    delete $hash->{ALIASES} if (exists $hash->{ALIASES});
    my (@cmdStrings) = split("\\|\\|\\|",$value);

#    # get available PDUs ($hash->{helper}{pdus})
#    foreach my $commandString (@cmdStrings) {
#      my($command,$values) = split("\\|\\|",$commandString);
#      next if ($command ne "listipdus");
#      my (@pValues) = split("\\|",$values);
#      foreach (@pValues) {
#        my (@p) = split(":",$_);
#        $hash->{helper}{pdus}{$p[0]} = "connected";
#      } #foreach @pValues
#    } #foreach @cmdString

    # sort all values from statusRequest into $hash->{helper}{pdus}...
    foreach my $commandString (@cmdStrings)
    {
      my($command,$values) = split("\\|\\|",$commandString);
      my (@pValues) = split("\\|",$values);
      foreach (@pValues) {
        my (@p) = split(":",$_);
        my $pdu = $p[0];
        $pdu =~ s/\[\d+\]$//;
        $p[1] =~ s/^\s//;

        if ($command eq "listipdus") { #eg: NetB:ttyS47-A:Cyclades:20
          $hash->{helper}{pdus}{$p[0]}{$command}{location} = $p[1];
          $hash->{helper}{pdus}{$p[0]}{$command}{type}     = $p[2];
          $hash->{helper}{pdus}{$p[0]}{$command}{outlets}  = $p[3];
        }

        elsif ($command eq "status") { #eg. NetB[2]:NetB_2:OFF:0.5
    # check aliases / names
          $p[2] =~ s/(\(locked\))//;                # remove (locked) from state
          my $locked = defined $1 ? "lock" : "unlock";   # port is locked if removed
          $hash->{helper}{pdus}{$pdu}{sockets}{$p[0]}{alias} = $p[1];
          $hash->{helper}{pdus}{$pdu}{sockets}{$p[0]}{state} = lc($p[2]);
          $hash->{helper}{pdus}{$pdu}{sockets}{$p[0]}{delay} = $p[3];
          $hash->{helper}{pdus}{$pdu}{sockets}{$p[0]}{locked} = $locked;
          $hash->{ALIASES}{$p[1]} = $p[0];
          $hash->{helper}{pdus}{$pdu}{"aliases"}{$p[1]} = $p[0];
        }

        elsif ($command =~ /^(current|temperature)$/) { #eg. NetB:0.0A:0.4A:0.0A:0.0A
          $hash->{helper}{pdus}{$pdu}{$command}{act} = $p[1];
          $hash->{helper}{pdus}{$pdu}{$command}{max} = $p[2];
          $hash->{helper}{pdus}{$pdu}{$command}{min} = $p[3];
          $hash->{helper}{pdus}{$pdu}{$command}{avg} = $p[4];
        }
        elsif ($command =~ /^(voltage|power|buzzer|ver|alarm|display|powerfactor|currentprotection)$/) { #eg. PDU:singleValue
          $hash->{helper}{pdus}{$pdu}{$command} = lc($p[1]);
        }
      } #foreach @pValues
    } #foreach @cmdStrings

    
    # Find all Sockets from "pmCommand status" command
    my $i = 0;
    foreach my $pdu (sort keys $hash->{helper}{pdus}) {
      my @sockets;
      $i++;
      foreach (sort keys $hash->{helper}{pdus}{$pdu}{sockets}) {
        m/$pdu\[(\d+)\]/;
        push(@sockets,$1) if defined $1;
      }
      $hash->{SOCKETS}{CONNECTED}{$pdu} = join(",",sort {$a <=> $b} @sockets);
      $hash->{"PDU$i"} = "$hash->{helper}{pdus}{$pdu}{listipdus}{location}: ".
        " $hash->{helper}{pdus}{$pdu}{listipdus}{type}".
        " PM".PM20_maxVal(@sockets)." ($pdu)";
    }

    # no attached PDUs found (powered off, not connected ?)
    if (!defined $hash->{SOCKETS}{CONNECTED}) {
      my $err = "ERROR: No PDUs found";
      Log3 $name, 2, "$name: $err" if ($hash->{READINGS}{state} ne $err);
    	readingsSingleUpdate($hash, 'state', $err,1);
      PM20_resetTimer($hash,'start');
      return undef;
    }

    #Remove PDUs/Sockets that are not connected from $hash->{SOCKETS}{DEFINED}
    PM20_isDefinedNotConnected($hash);
    # if no sockets are defined -> use all
    $hash->{SOCKETS}{DEFINED} = $hash->{SOCKETS}{CONNECTED} if $hash->{helper}{USEALLPDUS};
    # determine readings mode (single or multi)
    PM20_adjustReadingsMode($hash);


#if ($attr{$name}{standalone} && $attr{$name}{standalone} eq "1")
if (PM20_isStandalone($hash))
{

    # start evaluate returned string -> fill readings
    readingsBeginUpdate($hash);
   
    foreach my $commandString (@cmdStrings)
    {
      my($command,$values) = split("\\|\\|",$commandString);
      Log3 $name, 5, "$name: $self() \$command:$command \$valueS:$values";
      my (@pValues) = split("\\|",$values);
      foreach (@pValues) {
        my (@p) = split(":",$_);
        next if ($command ne "status" && PM20_isPduNotDefined($hash,$p[0]));
        next if ($command eq "status" && PM20_isSocketNotDefined($hash,$p[0]));
        Log3 $name, 5, "$name: $self() \$command:$command \$value:$_";

        my $port = $p[0]; # original port name for use with port aliases below
        # strip square brackets from reading names
        $p[0] = PM20_modifyReadingName($hash,$p[0]) if ($hash->{READINGS_MODE} ne "single");
        $p[1] = PM20_modifyStateToLowerCase($p[1]);

        # Include PDU name in reading names if there is more than 1 pdu defined
        my $prefix = $hash->{READINGS_MODE} ne "single" ? $p[0]."_" : "";
             
        if ($command eq "status") { #eg. NetB[2]:NetB_2:OFF:0.5 / NetB[2]:NetB_2:OFF(locked):0.5
          if ($hash->{READINGS_MODE} eq "single") {
            $p[0] =~ /.*\[(\d+)\]$/;
            $p[0] = $1;
            $hash->{ALIASES}{"socket".$p[0]} = $port; # without leading 0
            $p[0] = "0".$1 if (int($1) < 10);
            $p[0] = "socket".$p[0];
            $hash->{ALIASES}{$p[0]} = $port;          # with leading 0
          }
          $p[2] =~ s/(\(locked\))//;                # remove (locked) from state
          my $locked = defined $1 ? "lock" : "unlock";   # port is locked if removed
          readingsBulkUpdate($hash, $p[0]."_alias",  $p[1]);
          readingsBulkUpdate($hash, $p[0]."_state",  lc($p[2]));
          readingsBulkUpdate($hash, $p[0]."_delay",  $p[3]);
          readingsBulkUpdate($hash, $p[0]."_locked", $locked);
          readingsBulkUpdate($hash, $p[0]."_name",   $port);
          $hash->{ALIASES}{$p[1]} = $port;
        }
        elsif ($command =~  /^(current|temperature)$/) { #eg. NetB:0.0A:0.4A:0.0A:0.0A
          readingsBulkUpdate($hash, $prefix.$command."_act", $p[1]);
          readingsBulkUpdate($hash, $prefix.$command."_max", $p[2]);
          readingsBulkUpdate($hash, $prefix.$command."_min", $p[3]);
          readingsBulkUpdate($hash, $prefix.$command."_avg", $p[4]);
        }
        elsif ($command =~ /voltage|power|buzzer|ver|alarm|display|powerfactor|currentprotection/) { #eg. PDU:singleValue
          readingsBulkUpdate($hash, $prefix.$command, lc($p[1]));
        }
      } #foreach @pValues
    } #foreach @cmdStrings
    readingsBulkUpdate($hash, 'state', 'initialized') if (ReadingsVal($name,"state","") ne "initialized");
    readingsEndUpdate($hash, 1);
    delete $hash->{helper}{pdus};

} #standalone
else
{
    readingsSingleUpdate($hash, 'state', 'initialized',1) if (ReadingsVal($name,"state","") ne "initialized");

    #dispatch pdus
    foreach my $pdu (keys $hash->{SOCKETS}{DEFINED}) {
      #Log3 $name, 5, "$name: dispatch statusRequest results for PDU $pdu.";
      PM20_dispatch_PduStatus($hash,$pdu);
    }
    
    #dispatch sockets
    foreach my $pdu (keys $hash->{SOCKETS}{DEFINED}) {
      my @sockets = split(",",$hash->{SOCKETS}{DEFINED}{$pdu});
      foreach my $sNum (@sockets) {
        my $socket = $pdu."[".$sNum."]";
        #Log3 $name, 5, "$name: dispatch statusRequest results for socket $socket.";
        PM20_dispatch_SocketStatus($hash,$socket);
      }
    }

} #else standalone

  } #statusRequest


  elsif ($what eq "getCmd")
  {
    my ($command,$values) = split("\\|\\|",$value);
    my (@pValues) = split("\\|",$values);
    # no used right now
  }

  # analyze answer and set corresponding readings, device is too slow to ask again...
  elsif ($what eq "setCmd")
  {
    my ($command,$values) = split("\\|\\|",$value);
    my (@pValues) = split("\\|",$values);
    readingsBeginUpdate($hash);
    foreach my $value (@pValues) {
      if ($value =~ /^\[(Error|WARN)\]/) {
        PM20_log($name,$value,1);
        readingsEndUpdate($hash,1);
        PM20_resetTimer($hash,'start');
        return undef;
      }
      else { # No errors, keep on processing....
        my $reading;
        my $prefix;
        my ($pdu,$socket,$val);
        
        if ($command =~ /^(on|off|cycle).*/) {
          $value =~ /(.*)(\[\d+\]): Outlet (is|turned) (on|off|locked)/;
         ($pdu,$socket,$val) = ($1,$1.$2,$4);
          $reading = PM20_modifyReadingName($hash,$socket);
          if ($val eq "on" || $val eq "off") {
            if (PM20_isStandalone($hash)) {
              readingsBulkUpdate($hash, $reading."_state", $val);
            }
            else {
              PM20_dispatch($hash,$socket,"state",$val) ;
              $hash->{helper}{pdus}{$pdu}{sockets}{$socket}{state} = $val;
            }
          } 
          elsif ($val eq "locked") {
            my $sr = $reading."_state";
            my $srVal = $hash->{READINGS}{$sr}{VAL};
            DoTrigger($name, "$reading"."_state: $srVal", 1);
            Log3 $name, 1, "$name: ERROR: Output is locked and can't be switched.";
          }
        }

        elsif ($command =~ /^powerondelay.*/) {
          if ($value =~ m/^(.+): Not possible/) {
            Log3 $name, 2, "$name: Error: Socket $1 is locked. Modifing powerondelay is not possible.";
            PM20_dispatch_SocketStatus($hash,$1);
          }
          else {
            $value =~ /(.*)(\[\d+\]): Outlet power on interval set to (\d+\.?+\d?+) seconds/;
            ($pdu,$socket,$val) = ($1,$1.$2,$3);
            if (PM20_isStandalone($hash)) {
              $reading = PM20_modifyReadingName($hash,$socket);
              readingsBulkUpdate($hash, $reading."_delay", $val);
            } 
            else {
              PM20_dispatch($hash,$socket,"delay",$val);
              $hash->{helper}{pdus}{$pdu}{sockets}{$socket}{delay} = $val;
            }
          } # if not possible
        }

        elsif ($command =~ /^name.*/) {
          $value =~ /(.*)(\[\d+\]): Outlet now named (.+)/;
          ($pdu,$socket,$val) = ($1,$1.$2,$3);
          $hash->{ALIASES}{$val} = $socket;
          if (PM20_isStandalone($hash)) {
            $reading = PM20_modifyReadingName($hash,$socket);
            readingsBulkUpdate($hash, $reading."_alias", $val);
          }
          else {
            PM20_dispatch($hash,$socket,"alias",$val);
            $hash->{helper}{pdus}{$pdu}{sockets}{$socket}{alias} = $val;
          }
        }
        
        elsif ($command =~ /^(un)*lock.*/) {
          $value =~ /(.*)(\[\d+\]): Outlet (.+)/;
          ($pdu,$socket,$val) = ($1,$1.$2,$3);
          my $state = $val eq "locked" ? "lock" : "unlock";
          if (PM20_isStandalone($hash)) {
            $reading = PM20_modifyReadingName($hash,$socket);
            readingsBulkUpdate($hash, $reading."_locked", $state); # $state was $2
          }
          else {
            PM20_dispatch($hash,$socket,"locked",$state);
            $hash->{helper}{pdus}{$pdu}{sockets}{$socket}{locked} = $state;
          }
        }

        elsif ($command =~ /^buzzer/) {
          $value =~ /(.+): Buzzer turned (ON|OFF)/;
          ($pdu,$val) = ($1,$2);
          if (PM20_isStandalone($hash)) {
            $prefix = ($hash->{READINGS_MODE} eq "single") ? "" : $pdu."_";
            readingsBulkUpdate($hash, $prefix."buzzer", lc($val));
          } 
          else {
            PM20_dispatch($hash,$pdu,"buzzer",lc($val));
            $hash->{helper}{pdus}{$pdu}{buzzer} = lc($val);
          }
        }

        elsif ($command =~ /^display/) {
          $value =~ /(.+): Display mode set to (normal|180 degrees rotated) and cycle manually/;
          ($pdu,$val) = ($1,$2);
          if (PM20_isStandalone($hash)) {
            $prefix = ($hash->{READINGS_MODE} eq "single") ? "" : $pdu."_";
            readingsBulkUpdate($hash, $prefix."display", lc($val));
          } 
          else {
            PM20_dispatch($hash,$pdu,"display",lc($val));
            $hash->{helper}{pdus}{$pdu}{display} = lc($val);
          }
        }

        elsif ($command =~ /^currentprotection/) {
          $value =~ /(.+): Overcurrent protection turned (ON|OFF)/;
          ($pdu,$val) = ($1,$2);
          if (PM20_isStandalone($hash)) {
            $prefix = ($hash->{READINGS_MODE} eq "single") ? "" : $pdu."_";
            readingsBulkUpdate($hash, $prefix."currentprotection", lc($val));
          } 
          else {
            PM20_dispatch($hash,$pdu,"currentprotection",lc($val));
            $hash->{helper}{pdus}{$pdu}{currentprotection} = lc($val);
          }
        }

        elsif ($command =~ /^alarm/) {
          $value =~ /(.+): Setting high critical threshold to (\d+\.\d)A/;
          ($pdu,$val) = ($1,$2);
          if (PM20_isStandalone($hash)) {
            $prefix = ($hash->{READINGS_MODE} eq "single") ? "" : $pdu."_";
            readingsBulkUpdate($hash, $prefix."alarm", lc($val));
          } 
          else {
            PM20_dispatch($hash,$pdu,"alarm",lc($val));
            $hash->{helper}{pdus}{$pdu}{alarm} = lc($val);
          }
        }

        elsif ($command =~ /^id.*/) {
          if ($value =~ /(.+): ID is set to (.+)$/) {
            Log3 $name, 2, "renamed PDU $1 to $2, structural changes may follow...";
            readingsEndUpdate($hash, 1);
            PM20_PduRedefine($hash,$1,$2);
            return undef;
          }
        }
        
        elsif ($command =~ /^reboot.*/) {
          $value =~ /(.*): (Unit is rebooting.)/;
          PM20_log($name,$value,1);
          #readingsBulkUpdate($hash, "_lastNotice", $value); # $state was $2
        }

      } #else $value
    } #foreach
    readingsEndUpdate($hash, 1);
  } #elsif setCmd


  # update internals
  PM20_internalSocketStates($hash);
  # are there any queued cmds?
  my $q = PM20_checkQueue($hash);
  # restart timer if no cmds in queue
  PM20_resetTimer($hash,'start');
  
  return undef;
}

sub PM20_isStandalone($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return 1 if ($attr{$name}{standalone} && $attr{$name}{standalone} eq "1");
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_PduRedefine($$$)
{
  my ($hash,$old,$new) = @_;;
  return if $old eq $new;

  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
  my $ll = 2;
  my ($i,$id,$ia) = (0,0,0);
  
  foreach my $pm20 (devspec2array("TYPE=$type.*"))
  {
    my $dhash = $defs{$pm20}; # my device hash
    my $dname = $dhash->{NAME};
    my $dtype = $dhash->{TYPE};
    my $ddef  = $dhash->{DEF};
    my $oddef = $dhash->{DEF};
    $ddef =~ s/(s:$old\[)/s:$new\[/g if $dtype eq $type;
    $ddef =~ s/( $old\[)/ $new\[/g   if $dtype eq $type."C";
    Log3 $type, $ll, "$dtype: Redefined device $dname -> DEF -> $ddef" if $ddef ne $oddef;
    $id++ if $ddef ne $oddef;
    
    PM20_delReadings($hash,"silent");
    delete $dhash->{RUNNING_CMD};
    delete $dhash->{ALIASES};
    delete $dhash->{GROUPS};
    delete $dhash->{SOCKETS};
    delete $dhash->{"SOCKETS_STATE_".uc($old)};

    if ($attr{$dname}{socketGroups}) {
      my $oa = $attr{$dname}{socketGroups};
      $attr{$dname}{socketGroups} =~ s/([:,]?+)$old\[/$1$new\[/g;
      $ia++ if $attr{$dname}{socketGroups} ne $oa;
      Log3 $type, $ll, "$dtype: Redefined device $dname -> Attribut -> socketGroups $attr{$dname}{socketGroups}";
      CommandAttr(undef, "$dname socketGroups $attr{$dname}{socketGroups}");
    }
    CommandModify(undef, "$dname $ddef");
    $i = $i+$ia+$id;
    $ia=0;
    $id=0;    
  }
  if (AttrVal( "global", "autosave", 1)) {
    CommandSave(undef,undef);
    Log3 $type, $ll, "$type: $i structural changes saved (attr global autosave 1)";
  }
  else {
    Log3 $type, $ll, "$type: There are $i structural changes. Don't forget to save chages.";
  }
  readingsSingleUpdate("TYPE=$type.*","_lastNotice","PDU $old renamed to $new",1);
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_defineClientDevices($)
{
  my ($hash) = @_;
  my ($name,$type,$self) = ($hash->{NAME},$hash->{TYPE},PM20_whoami()."()");
  my $ctype = $type."C";
  my @defines;
  my $i=0;
  foreach my $pdu (keys $hash->{SOCKETS}{DEFINED}) {
    my @sockets = split(",",$hash->{SOCKETS}{DEFINED}{$pdu});
    foreach my $socket (@sockets) {
      $socket = "0".$socket if $socket <10;
      my $socketAlias = ReadingsVal($name,$pdu.$socket."_alias","");
      my $socketName  = ReadingsVal($name,$pdu.$socket."_name","");
      my $client = PM20_isClientSocketDefined($hash,$socketName);
      if ($client) {
        Log3 $name, 4, "$type: Device $client ($name $socketName) already defined";
      }
      else {
        my $cdev = "PDU_".uc($pdu)."_".$socket;
        $cdev = "PWR_$socketAlias" if $socketAlias;
        $cdev =~ s/_(\d)$/_0$1/ if $socketAlias;
        $cdev =~ s/[:-]/_/g if $socketAlias;
        InternalTimer(gettimeofday()+$i,"PM20_timedDefineClientDevices", "$name:$cdev:$ctype:$type:$socketName", 0);
        $i += .5;
        push(@defines,$cdev);
      }
    }
  }
  Log3 $name, 3, "$type: ".scalar @defines." new $ctype devices defined.";
  return @defines;
}

sub PM20_timedDefineClientDevices($)
{
  my ($name,$cdev,$ctype,$type,$socketName) = split(":",$_[0]);
  my ($self) = PM20_whoami()."()";

  fhem("define $cdev $ctype $name $socketName");
#      CommandAttr(undef,"$name alias $new_name");

  fhem("attr $cdev room $type");
  fhem("attr $cdev comment autocreated");
  fhem("attr $cdev devStateIcon on:ios-on-green:off off:ios-off:on set_on:ios-set_on:statusRequest set_off:ios-set_off-green:statusRequest unknown:ios-NACK:statusRequest set_statusRequest:ios-NACK:statusRequest startup:ios-NACK:statusRequest");
  #fhem("attr $cdev devStateIcon on:ios-on-green:off off:ios-off:on set_on:ios-set_on:statusRequest set_off:ios-set_off-green:statusRequest unknown:ios-NACK:statusRequest set_statusRequest:ios-NACK:statusRequest startup:ios-NACK-blue:statusRequest");
  fhem("attr $cdev webCmd :");
        
  Log3 $name, 5, "$name: $self 'define $cdev $ctype $name $socketName'";

}

sub PM20_isClientSocketDefined($$)
{
  my ($hash,$socket) = @_;
  my ($name,$type,$self) = ($hash->{NAME},$hash->{TYPE},PM20_whoami()."()");
  my @c = devspec2array("TYPE=$type"."C");
  foreach my $c (@c) {
    return $c if InternalVal($c,$type."_SOCKET","") eq $socket;
  }
  return undef;
}

# ##############################################################################
# --- systax check -------------------------------------------------------------
# ##############################################################################

sub PM20_syntaxCheck($$@)
{
  my ($hash,$cmd,@p) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami());
  my $sc = PM20_doSyntaxCheck($hash,$cmd,@p);
  if (defined $sc) {
    my ($e_txt,$e_p) = split("\\|\\|",$sc); # eg. "Unknown command:||cmd"
    my $err = "Wrong syntax: 'set $name $cmd ".join(" ", @p)."' - $e_txt $e_p";
    PM20_log($name,$err);
    my $usage = "set $name $PM20_setCmdsUsage{$cmd}";
    $usage =~ s/<dev>/$name/g;
    Log3 $name, 2, "$name: USAGE: $usage";
    $usage =~ s/Note:/\nNote:/g;
    return "$err\nUsage: $usage";
  }
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_doSyntaxCheck($$@)
{
  no warnings;
  my ($hash,$cmd,@p) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami()."()");

  Log3 undef, 5, "$name $self cmd:'$cmd' p:".join(",",@p);

  my $e_moi    = "Invalid or missing";
  my $e_tma    = "Touch too much:";
  my $e_cmd    = "Unknown command:";
  my $e_socket = "Invalid, missing or undefined socket:";
  my $e_delay  = "$e_moi value: must be:0-6500 resolution:0.1:";
  my $e_alias  = "$e_moi alias name (no special characters allowed):";
  my $e_oldid  = "$e_moi PDU id name (not defined or connected?):";
  my $e_newid  = "$e_moi PDU id name (no special characters allowed):";
  my $e_usage  = "";

  if ($p[0] eq "?") {
  return "||";

  } elsif ($cmd =~ /^(statusRequest)$/) {
    return undef ;

  } elsif ($cmd eq "powerondelay") {
    return "$e_socket||'$p[0]'" if (not PM20_isSocketNameDefined($hash,$p[0]));
    return "$e_delay||'$p[1]'"  if (not PM20_isMinMax($p[1],0,6500));
    return "$e_tma||'$p[2]'"    if (int(@p) > 2);

  } elsif ($cmd =~ /^(on|off|lock|unlock)$/) {
    return "$e_socket||'$p[0]'" if (not PM20_isSocketNameDefined($hash,$p[0]));
    return "$e_tma||'$p[1]'"    if (int(@p) > 1);

  } elsif ($cmd eq "name") {
    return "$e_socket||'$p[0]'" if (not PM20_isSocketNameDefined($hash,$p[0]));
    return "$e_alias||'$p[1]'"  if (not PM20_isSocketAlias($p[1]));
    return "$e_tma||'$p[2]'"    if (int(@p) > 2);

  } elsif ($cmd eq "id") { #
    return "$e_oldid||'$p[0]'"  if (PM20_isPduNotDefined($hash,$p[0]));
    return "$e_newid||'$p[1]'"  if (not PM20_isSocketAlias($p[1]));
    return "$e_tma||'$p[2]'"    if (int(@p) > 2);

  } elsif ($cmd eq "help") {
    return "$e_cmd||'$p[0]'"    if (not PM20_isKnownCmd($p[0])); }

  return undef; #everything is fine...
}


# ------------------------------------------------------------------------------
# --- syntaxCheck helper functions ---------------------------------------------
# ------------------------------------------------------------------------------

#IPv6 regexp
#(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))

sub PM20_isSocketAlias($) {return if(!defined $_[0]); return 1 if($_[0] =~ /^[A-Za-z]+[A-Za-z0-9\._-]*$/)}
sub PM20_isOnOff($)       {return if(!defined $_[0]); return 1 if($_[0] =~ /^(on|off)$/)}
sub PM20_isIPv4($)        {return if(!defined $_[0]); return 1 if($_[0] =~ /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/)}
sub PM20_isIPv6($)        {return if(!defined $_[0]); return 1 if($_[0] =~ /^(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))$/)}
sub PM20_isFqdn($)        {return if(!defined $_[0]); return 1 if($_[0] =~ /^(?=^.{4,253}$)(^((?!-)[a-zA-Z0-9-]{1,63}(?<!-)\.)+[a-zA-Z]{2,63}$)$/)}

# ------------------------------------------------------------------------------
sub PM20_isMinMax($$$) {
  my ($val,$min,$max) = @_;
  return if (!defined $val);
  return if (not $val =~ /^([\d]*[\.]?+\d+)$/);
  return $val if ($val >= $min && $val <= $max);
}

# ------------------------------------------------------------------------------
sub PM20_isSocketNameDefined($$) {
  my ($hash,$socket) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami()."()");
#  no warnings 'experimental::smartmatch';

  my @pdus = keys %{$hash->{SOCKETS}{DEFINED}};
  my $pdus = join("|",@pdus);
  my @aliases = keys %{$hash->{ALIASES}};
  my $aliases = join("|",@aliases);
  my $names = $pdus."|".$aliases;
  
  $socket =~ s/,($names)/:$1/g;    #-> Prod[1,2,3]:Lab[4,5,6]:Lab[10-15]:TEST3
  my @s = split(":",$socket);

  foreach my $s (@s) {
    Log3 undef, 5, "Alias found: $s" if $s ~~ @aliases;
    next if $s ~~ @aliases;

    $s =~ m/(.*)\[([\d+,-]+)\]/;
    Log3 undef, 5, "unknown port: $s" if (not(defined $1) || not(defined $2));
    return if (not(defined $1) || not(defined $2));

    my $maxNum = PM20_maxVal(split(",",$hash->{SOCKETS}{CONNECTED}{$1}));
    my $minNum = PM20_minVal(split(",",$hash->{SOCKETS}{CONNECTED}{$1}));
    my $range = PM20_range2num($2,$minNum,$maxNum);
    Log3 $name, 5, "$name: out of range: $1\[$2\]" if !$range;
    return if !$range;                                    # mod here, test sub again.
    my @range = split(",",$range);

    my $defSockets = $hash->{SOCKETS}{DEFINED}{$1};
    return if !$defSockets; # Port is not on an defined PDU #-----------------
    my @defSockets = split(",",$defSockets);
    foreach my $r (@range) {
      Log3 undef, 5, "Port number not defined: $r" if not $r ~~  @defSockets;
      return if not $r ~~  @defSockets;
    }
  }

  return 1;
}

# ------------------------------------------------------------------------------
sub PM20_isKnownCmd($) {
  return if (!defined $_[0]);
  my $cmdsAvail = " ".join(" ", sort keys %PM20_setCmds)." ";
  return 1 if ($cmdsAvail =~ /\s$_[0]\s/ );
}

# ------------------------------------------------------------------------------
sub PM20_runningCmd($$)
{
  my ($hash,$param) = @_;
#  $param =~ s/pmCommand_//;
  $hash->{RUNNING_CMD} = $param;
}

# ##############################################################################
# --- queue related functions: -------------------------------------------------
# ##############################################################################

# ------------------------------------------------------------------------------
sub PM20_addQueue($$)
{
  my ($hash,$cmd) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami()."()");
  my $key = gettimeofday();

  Log3 $name, 5, "$name $self got: cmd:'$cmd'";
  
  if ($cmd =~ /statusRequest/) { #do not queue multiple statusRequests
    foreach my $queued (values %{$hash->{QUEUE}}) {
      if ($queued =~ /statusRequest/) {
        Log3 $name, 3, "$name: already in queue: 'set $cmd', cmd discarded";
        return undef if $queued =~ /statusRequest/;
      }
    }
  }
  $key -= 100 if ($cmd eq "statusRequest" && ReadingsVal($name,"state","") ne "initialized");
  $key += 100 if ($cmd eq "statusRequest" && ReadingsVal($name,"state","") eq "initialized");
  $hash->{QUEUE}{$key} = "$cmd";
  $hash->{QUEUE}{$key} =~ s/\s*$//;
  Log3 $name, 3, "$name: queued: 'set $cmd', ".scalar(keys(%{$hash->{QUEUE}}))." cmd(s) in queue";
  $hash->{QUEUE_CNT} = scalar keys %{$hash->{QUEUE}};
  DoTrigger($name, "QUEUE: queueing 'set $cmd' ($hash->{QUEUE_CNT})", 1);
  return undef;  
}

# ------------------------------------------------------------------------------
sub PM20_checkQueue($)
{
  my ($hash) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami()."()");
  if (!defined $hash->{QUEUE} || scalar keys %{$hash->{QUEUE}} == 0) {
    $hash->{QUEUE_CNT} = 0;
    return undef;
  }
  my @a = keys $hash->{QUEUE};

  my $oldest = PM20_minVal(@a);
  my @ret = split(" ",$hash->{QUEUE}{$oldest});
  delete $hash->{QUEUE}{$oldest};
  $hash->{QUEUE_CNT} = scalar keys $hash->{QUEUE};
  $hash->{helper}{QUEUE_NOW} = $oldest;
  DoTrigger($name, "QUEUE: finished", 1) if ($hash->{QUEUE_CNT} == 0);
  my $cmd = splice(@ret,0,1);
#  $ret[0] = "" if !$ret[0];
  PM20_Set($hash,$name,$cmd,@ret);
  return 1;
#  return ($cmd, @ret);
}


# ##############################################################################
# --- socket/aliases/reading related functions: --------------------------------
# ##############################################################################

# ------------------------------------------------------------------------------
sub PM20_isDefinedNotConnected($)
{
  my ($hash) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami()."()");
  my @dp = keys $hash->{SOCKETS}{DEFINED};
  my $err;
  foreach my $dp (@dp) {
    if (not defined $hash->{SOCKETS}{CONNECTED}{$dp}) {
      $hash->{SOCKETS}{DELETED}{$dp} = $hash->{SOCKETS}{DEFINED}{$dp};
      delete $hash->{SOCKETS}{DEFINED}{$dp};
      $err = "Error: PDU '$dp' defined but not connected -> will be ignored.";
      Log3 $name, 1, "$name: $err";
      next;
    }
    my @dpSockets = split(",",$hash->{SOCKETS}{DEFINED}{$dp});
    my @cs  = split(",",$hash->{SOCKETS}{CONNECTED}{$dp});
    foreach my $ds (@dpSockets) {
      if (not $ds ~~ @cs) { #test with: {$defs{"xx"}->{SOCKETS}{DEFINED}{Prod} = "1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,33"}
        $hash->{SOCKETS}{DELETED}{$dp} .= $ds.",";
        $hash->{SOCKETS}{DEFINED}{$dp} =~ s/,$ds$//;
        $hash->{SOCKETS}{DEFINED}{$dp} =~ s/,$ds,/,/;      
#        $err = 
        Log3 $name, 2, "$name: Error: Socket '$dp\[$ds\]' defined but not connected -> will be ignored";
      }
    }
  }
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_isSocketNotDefined($$;$)
{
  my ($hash,$socket,$logme) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami());

  $socket =~ /(.*)\[(\d+)\]/;
  Log3 $name, 2, "ERROR: PDU '$1' not defined" if (not(defined $hash->{SOCKETS}{DEFINED}{$1}) && defined $logme);
  return "ERROR: PDU '$1' not defined" if (!defined $hash->{SOCKETS}{DEFINED}{$1});

  my @s = split(",",$hash->{SOCKETS}{DEFINED}{$1});
  Log3 $name, 2, "ERROR: Socket $socket not defined" if (not($2 ~~ @s) && defined $logme);
  return "ERROR: Socket $socket not defined" if (not $2 ~~ @s);

  @s = split(",",$hash->{SOCKETS}{CONNECTED}{$1});
  Log3 $name, 2, "ERROR: Socket $socket not connected" if (not($2 ~~ @s) && defined $logme);
  return "ERROR: $socket not connected" if (not $2 ~~ @s);

  Log3 $name, 5, "$name: Socket $socket accepted";
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_isPduNotDefined($$;$)
{
  my ($hash,$pdu,$logme) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami());
#  use v5.10;
#  no warnings 'experimental::smartmatch';

  Log3 $name, 2, "ERROR: PDU '$pdu' not defined"   if (not(defined $hash->{SOCKETS}{DEFINED}{$pdu}) && defined $logme);
  return "ERROR: PDU '$pdu' not defined"           if (not defined $hash->{SOCKETS}{DEFINED}{$pdu});

  Log3 $name, 2, "ERROR: PDU '$pdu' not connected" if (not(defined $hash->{SOCKETS}{CONNECTED}{$pdu}) && defined $logme);
  return "ERROR: PDU '$pdu' not connected"         if (not defined $hash->{SOCKETS}{CONNECTED}{$pdu});

  Log3 $name, 5, "$name: PDU $pdu accepted";
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20C_isAutosaveEnabled($)
{
  my ($hash) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami()."()");

  my $module_enabled = AttrVal($name,"autosave",undef);
  my $global_enabled = AttrVal("global","autosave",undef);
  
  return 1 if (defined $module_enabled && $module_enabled eq "1");
  return 1 if (not(defined $module_enabled) 
                && ((not(defined $global_enabled)) || (defined $global_enabled && $global_enabled eq "1")) );

  Log3 $name, 5, "PM20C: $self autosave is disabled.";
  return 0;
}

# ------------------------------------------------------------------------------
sub PM20C_isAutocreateEnabled($)
{
  my ($hash) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami()."()");
  my $ret = 0;

  my $module_enabled = AttrVal($name,"autocreate",undef);
  my $global_enabled = AttrVal("global","autoload_undefined_devices",undef);
  
  $ret = 1 if (defined $module_enabled && $module_enabled eq "1");
  $ret = 1 if (not(defined $module_enabled)
              && ((not(defined $global_enabled)) || (defined $global_enabled  && $global_enabled eq "1") ));

  my $enDis = ($ret == 1) ? "en" : "dis";
  #Log3 $name, 5, "PM20C: $self autocreate is $enDis"."abled.";
  return $ret;
}

# ------------------------------------------------------------------------------
sub PM20_modifyReadingName($$)
{
  my ($hash,$reading) = @_;
  if ($hash->{READINGS_MODE} =~ /^multi/) {
    if ($reading =~ /(.+)\[(\d+)\]/) { # remove [] and format number to xx
      my $pn = $2;
      $pn = "0".$pn if (int($pn) < 10);
      return $1.$pn;
    }
  } #if multi
  else #single mode
  {
    $reading =~ /.*\[(\d+)\]/;
    $reading = $1;
    $reading = "0".$reading if (int($reading) < 10);
    $reading = "socket$reading";
  }
  return $reading;
}

# ------------------------------------------------------------------------------
sub PM20_modifyUserInput($$$)
{
  my ($hash,$cmd,$val) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami());
  $val = "" if (!defined $val);
  my $orgVal = $val;

  if ($cmd eq "powerondelay" && $val =~ /^([\d]*[\.]?+\d+)(m)$/) {
    $val = int(($1+0.5)*60);
#    $val = 6500 if $val > 6500; # will be check in PM20_syntaxCheck
    Log3 $name, 5, "$name: $self() cmd:'$cmd' orgVal:'$orgVal' newVal:'$val'";
  }
  if ($cmd eq "powerondelay" && $val =~ /^([\d]*[\.]?+\d+)(s)$/) {
    $val = $1
  }

  return $val;
}

# ------------------------------------------------------------------------------
sub PM20_modifyCommands($$@)
{
  my ($hash,$cmd,@params) = @_;;
  my $name = $hash->{NAME};
  my $p = join(" ",@params);
  my $op = $p;
  my $oc = $cmd;
  my $changed;
  my $a = $attr{$name}{socketsOnOff};
  
  # which sockets should be switched when cmd on|off
  if ($cmd =~ /^(on|off)/ && (!$p || $p eq "")) {
    if ($a && ($a eq "none" || $a eq "")) {
    }
    elsif ($a && $a ne "all") {
      $p = $a;  
      $changed = 1;
    } 
    else {
      foreach my $pdu (keys $hash->{SOCKETS}{DEFINED}) {
        $p .= "$pdu\[".PM20_num2range($hash->{SOCKETS}{DEFINED}{$pdu})."\],";
        $changed = 1;
      }
    }
    $p =~ s/,$//;
#    $op = "" if !$op;
  }
  Log3 $name, 4, "$name: modified command: 'set $name $oc $op' -> 'set $name $cmd $p'" if $changed;  
  return ($cmd,split(" ",$p));
}

# ------------------------------------------------------------------------------
sub PM20_modifyStateToLowerCase($)
{
  my ($state) = @_;
  return "on"  if (lc($state) eq "on");  # -> lowercase
  return "off" if (lc($state) eq "off"); # -> lowercase
  return $state;
}

# ------------------------------------------------------------------------------
sub PM20_internalSocketStates($)
{
  my ($hash) = @_;
  return undef if (!defined $hash->{SOCKETS}{CONNECTED});
  return undef if (!defined $hash->{SOCKETS}{DEFINED});
  my $name = $hash->{NAME};
  foreach my $pdu (keys $hash->{SOCKETS}{DEFINED}) {
    my @c;
    my $num = PM20_maxVal(split(",",$hash->{SOCKETS}{CONNECTED}{$pdu}));
    for(my $i = 0; $i < $num; $i++) {push(@c,"u")}
    my @d = split(",",$hash->{SOCKETS}{DEFINED}{$pdu});
    my $r = "";
    foreach my $p (@d) {
      if (defined $attr{$name}{standalone} && $attr{$name}{standalone} eq "1") {
        $r = $p < 10 ? "0".$p : $p;
        $r = $hash->{READINGS_MODE} eq "single" ? "socket$r"."_state" : $pdu."$r"."_state";
        $c[$p-1] = 1 if ReadingsVal($hash->{NAME},$r,"") eq "on"; #use Fn, so we dont have to care about defined or not
        $c[$p-1] = 0 if ReadingsVal($hash->{NAME},$r,"") eq "off";
        $c[$p-1] = "?" if not ReadingsVal($hash->{NAME},$r,"") =~ /^(on|off)$/;
      }
      else {
        $r = "$pdu\[$p\]";
        $c[$p-1] = "?" if not($hash->{helper}{pdus}{$pdu}{sockets}{$r}{state}) || $hash->{helper}{pdus}{$pdu}{sockets}{$r}{state} =~ /^(on|off)$/;
        $c[$p-1] = 0   if $hash->{helper}{pdus}{$pdu}{sockets}{$r}{state} && $hash->{helper}{pdus}{$pdu}{sockets}{$r}{state} eq "off";
        $c[$p-1] = 1   if $hash->{helper}{pdus}{$pdu}{sockets}{$r}{state} && $hash->{helper}{pdus}{$pdu}{sockets}{$r}{state} eq "on";
        #Log3 $hash, 1, "hash->{helper}{pdus}{$pdu}{sockets}{$r}{state}";
      }
    }
    $hash->{"SOCKETS_STATE_".uc($pdu)} = join(",",@c);
    $hash->{SOCKETS}{STATE}{$pdu} = join(",",@c);
  }
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_replaceAliases($$)
{
  my ($hash,$sockets) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami()."()");

  my @pdus = keys %{$hash->{SOCKETS}{DEFINED}};
  my $pdus = join("|",@pdus);
  my @aliases = keys %{$hash->{ALIASES}};
  my $aliases = join("|",@aliases);
  my $names = $pdus."|".$aliases;
  
  $sockets =~ s/,($names)/:$1/g;    #-> Prod[1,2,3]:Lab[4,5,6]:Lab[10-15]:TEST3
  my @sockets = split(":",$sockets);

  foreach my $socket (@sockets) {
    foreach my $alias (@aliases) {
      if ($socket eq $alias) {
        Log3 $name, 4, "$name: socket alias mapping: $alias -> $hash->{ALIASES}{$alias}";
        $sockets =~ s/$socket/$hash->{ALIASES}{$alias}/;
        last;
      }
    }
  }
  
  $sockets =~ s/:/,/g;
  return $sockets;
}

# ------------------------------------------------------------------------------
sub PM20_replaceGroups($$)
{
  my ($hash,$string) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami()."()");
  my @groups = keys %{$hash->{GROUPS}};
  return $string if !$groups[0];

  foreach my $group (@groups) {
    if ($group eq $string) {
      Log3 $name, 4, "$name: socket group mapping: $string -> $hash->{GROUPS}{$group}";
      return $hash->{GROUPS}{$group};
    }
  }

  return $string;
}

# ------------------------------------------------------------------------------
sub PM20_adjustReadingsMode($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my @unitsConnected = sort keys %{$hash->{SOCKETS}{CONNECTED}};
  my @unitsDefined   = sort keys %{$hash->{SOCKETS}{DEFINED}};
  if (scalar @unitsConnected > 1 && scalar @unitsDefined > 1) {
    if (defined $hash->{READINGS_MODE} && $hash->{READINGS_MODE} eq "single") {
      PM20_delReadings($hash);
#      delete $hash->{ALIASES} if (defined $hash->{ALIASES});
    } 
    $hash->{READINGS_MODE} = "multi (".scalar @unitsDefined." units)";
  } else { 
    if (defined $hash->{READINGS_MODE} && $hash->{READINGS_MODE} ne "single") {
      PM20_delReadings($hash);
#      delete $hash->{ALIASES} if (defined $hash->{ALIASES});
    }
    $hash->{READINGS_MODE} = "single";
  }
  # overwrite single mode
  if (defined $attr{$name}{multiPduMode} && $attr{$name}{multiPduMode} == 1) {
    $hash->{READINGS_MODE} = "multi (attr)";
  }
}

# ------------------------------------------------------------------------------
sub PM20_delReadings($;$)
{
  my ($hash,$silent) = @_;
  my ($name,$self) = ($hash->{NAME},PM20_whoami());

  foreach my $r (keys %{$hash->{READINGS}}) {
    delete $hash->{READINGS}{$r} if (not $r =~ /^state|_last/);
  }

  readingsSingleUpdate($hash,"state","???",1);
  PM20_log($name,"readings wiped out") if (not defined $silent);
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_BlockingKill($$;$)
{
  my ($hash,$h,$ll) = @_;
  $ll = 3 if !$ll;

  # MaxNr of concurrent forked processes @Win is 64, and must use wait as
  # $SIG{CHLD} = 'IGNORE' does not work.
  wait if($^O =~ m/Win/);

  if($^O !~ m/Win/) {
    if($h->{pid} && kill(9, $h->{pid})) {
#      Log 1, "Timeout for $h->{fn} reached, terminated process $h->{pid}";
      Log $ll, "forked process ($h->{pid}) terminated";
      if($h->{abortFn}) {
        no strict "refs";
        my $ret = &{$h->{abortFn}}($h->{abortArg});
        use strict "refs";

      } elsif($h->{finishFn}) {
        no strict "refs";
        my $ret = &{$h->{finishFn}}();
        use strict "refs";

      }
    }
  }
}



# ##############################################################################
# --- generel purpose helper functions: ----------------------------------------
# ##############################################################################

# ------------------------------------------------------------------------------
sub PM20_isPmInstalled($$)
{
  my ($hash,$pm) = @_;
  my $name = $hash->{NAME};
  if (not eval "use $pm;1")
  {
    PM20_log($name,"perl mudul missing: $pm");
    $hash->{MISSING_MODULES} .= "$pm ";
    return "failed: $pm";
  }
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_range2num($$$)
{
  my ($range,$min,$max) = @_;
  return undef if ($range =~ /[^\d,-]|^[,-]|[,-]$|,-|-,|[,-]{2,}/ 
               || ($range =~ /(\d+)-(\d+)/ && $1 >= $2));
  $range =~ s/\-/../g;
  my @a = ( eval $range );
  foreach (@a) {return undef if ($_ < $min || $_ > $max)}
  my %h = map { $_, 1 } @a; #remove duplicates
  @a = sort {$a <=> $b} keys %h;        #see: perldoc -q duplicate
  return join(",",@a)
}

# ------------------------------------------------------------------------------
sub PM20_num2range($) {
  local $_ = join ',' => @_;
  s/(?<!\d)(\d+)(?:,((??{$++1}))(?!\d))+/$1-$+/g;
  return $_;
}

# ------------------------------------------------------------------------------
sub PM20_maxVal(@)
{
  my (@a) = @_;
  my $max;
  for (@a) {$max = $_ if !$max || $_ > $max};
  return $max;
}

# ------------------------------------------------------------------------------
sub PM20_minVal(@)
{
  my (@a) = @_;
  my $min;
  for (@a) {$min = $_ if !$min || $_ < $min};
  return $min;
}

# ------------------------------------------------------------------------------
#sub PM20_getIP($)
#{
#  my ($hostname) = @_;
#
#  use Socket qw(:addrinfo SOCK_RAW);
#  my ($err, @res) = getaddrinfo($hostname, "", {socktype => SOCK_RAW});
##  print Dumper(@res);
#  return undef if $err;
#  while( my $ai = shift @res ) {
#    my ($err, $ipaddr) = getnameinfo($ai->{addr}, NI_NUMERICHOST, NIx_NOSERV);
#    return undef if $err;
#    return "$ipaddr";
#  }
#}

# ------------------------------------------------------------------------------
#sub PM20_getAFtype($)
#{
#  my ($host) = @_;
#  my $ip = PM20_getIP($host);
#  return "ipv4" if PM20_isIPv4($ip);
#  return "ipv6" if PM20_isIPv6($ip);
#  return undef;
#}

# ------------------------------------------------------------------------------
sub PM20_whoami()  { return (split('::',(caller(1))[3]))[1] || ''; }

# ------------------------------------------------------------------------------
sub PM20_reportToAuthor($$$)
{
  my ($hash,$self,$what) = @_;
  my ($name) = ($hash->{NAME});

  open (FH, ">./log/$name"."_DEBUG.txt");
  print FH "$name: ".'-' x 80 ."\n";
  print FH "$name: Please report to author IF ADVISED:\n";
  print FH "$name: date:   ".localtime()."\n";
  print FH "$name: where:  $self\n" if defined $self;
  print FH "$name: what:   $what\n" if defined $what;
  print FH "$name: perl:   $]\n";
  print FH "$name: os:     $^O\n";
  print FH "$name: os:     ".`uname -a` if $^O eq "linux";
  print FH "$name: PM20 v: $PM20_version\n";
  print FH Dumper([$hash], [qw(*$hash)]);
  foreach my $key (keys(%ENV)) {
    print FH "$key: $ENV{$key}\n"
  }
  close (FH); 
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20_log($$;$)
{
  my ($name,$log,$bulkupdate) =  @_;
  my $hash = $defs{$name};
  my $txtmsg = "";
  my $genEvent = "1";  # generate Events on default
  my $ll = 2;          # default verbose level

#  $bulkupdate = 0 if (!defined $bulkupdate);
#  my $errText = "ERROR: ";
  my $errText = "";

  if ($log =~ /^set $name statusRequest/) {
    $ll = 4;
    $genEvent = "0";
    $errText = "";
  } 

  elsif ($log =~ /^set $name/) {
    $ll = 3;
    $genEvent = "0";
    $errText = "";
  } 
  
  elsif ($log =~ /^set $name (on|off): failed/) {
    $ll = 2;
    $genEvent = "1";
  }
  
  if ($log =~ /^(Wrong syntax: '.*').*('.*')$/) {
    readingsSingleUpdate($hash,"_lastNotice","$1 =>$2",1) if ($genEvent eq "1" && !$bulkupdate);
    readingsBulkUpdate($hash,"_lastNotice","$1 =>$2")     if ($genEvent eq "1" && $bulkupdate);
  } else {
    readingsSingleUpdate($hash,"_lastNotice",$log,1) if ($genEvent eq "1" && !$bulkupdate); 
    readingsBulkUpdate($hash,"_lastNotice",$log)     if ($genEvent eq "1" && $bulkupdate);
  }

  Log3 $name, $ll, "$name: $errText$log $txtmsg";

  return $log;
}

# ##############################################################################
# --- unused: to be deleted: ---------------------------------------------------
# ##############################################################################



1;


=pod
=item device
=begin html

<a name="PM20"></a>
<h3>PM20</h3>
<ul>
<p>
    Provides access and control to Avocent's Power Distribution Unit 10/20
    Series (PM10/20 PDUs) in conjunction with Avocent's Advanced Console Server
    (ACS16/32 or ACS48) (see: <a href="http://bit.ly/1SQ4vL6">Avocent
    PM10/20</a>)
</p>

<b>Notes</b>
<ul>
<li>
Requirements: perl modul Net::Telnet
</li>
<li>
Devices for single sockets will automatically definedcan be defined with PM20C module.
</li><br>

</ul>


<a name="PM20define"></a>
<b>define</b>
<ul>

<code>
define &lt;name&gt; PM20 &lt;host&gt; [s:&lt;socket&gt; [s:&lt;socket&gt;]] [t:&lt;interval&gt;] [t:&lt;telnetPort&gt;] [u:&lt;username&gt;] [p:&lt;password&gt;]
</code><br>
<code>
<pre>
examples:
define myPM20 PM20 172.16.24.23 s:PDU1[1-20] s:PDU2[1,2,3,4,20] u:username p:password
define myPM20 PM20 2001:db8:4711:feed::1:123 s:PDU1[1,2,3-7,20] u:username2 p:pass2
define myPM10 PM20 pm20.example.com s:PDU1[1,2,3-7,10] i:600
define myPM10 PM20 10.1.2.3
</pre>
</code>

<li>&lt;name&gt;<br>
A name of your choice.
<br>
possible value: <code>&lt;string&gt;</code><br>
</li>
<br>

<li>PM20<br>
Module name, must be: PM20
<br>
</li>
<br>

<li>&lt;host&gt;<br>
ACS Host used to control PDUs
<br>
possible value: <code>IPv4|IPv6|FQDN</code><br>
default: none
</li>
<br>

<li>s:&lt;socket&gt; (optional)<br>
PDUs and Sockets to be used (argument can be used multiple times)
<br>
possible value: <code>PDU[sockets]</code>
<br>
default: all sockets on all connected PDUs
<br>
examples:
<code><br>
s:PDU1[1-20]<br>
s:PDU1[1-20] s:PDU2[1,3,5,10-20]<br>
s:PDU1[1,2] s:PDU2[10-20] s:PDU3[1-5,7,8,9]
</code><br>
</li>
<br>

<li>i:&lt;interval&gt;<br>
Interval used for statusRequests (optional)
<br>
possible value: <code>seconds &gt; 60</code><br>
default: <code>300</code><br>
</li>
<br>

<li>t:&lt;telnetPort&gt;<br>
Telnet port to be used. (optional)
<br>
possible value: <code>1-65535</code><br>
default: <code>
23
</code><br>
</li>
<br>

<li>u:&lt;username&gt;<br>
Username used to connect to Avocent ACS (optional)<br>
default: <code>admin</code><br>
</li>
<br>

<li>p:&lt;password&gt;<br>
Your password used to connect to Avocent ACS (optional)<br>
default: <code>admin</code><br>
</li>
<br>

</ul>


<a name="PM20set"></a>
<b>set</b>
<ul>

<li><code>alarm</code><br>
Set alarm threshold value in Ampere.<br>
possible value: <code>&lt;1-32&gt;</code><br>
example: <code>set myPM20 alarm PDU1 16</code><br>
</li><br>

<li><code>buzzer</code><br>
Set buzzer on or off.<br>
possible value: <code>&lt;on|off&gt;</code><br>
example: <code>set myPM20 buzzer on PDU1</code><br>
</li><br>

<li><code>currentprotection</code><br>
Set currentprotection on or off.<br>
example: <code>set myPM20 currentprotection on PDU1</code><br>
</li><br>

<li><code>cycle</code><br>
Set socket to off and on again.<br>
argument: <code>&lt;sockets&gt;</code><br>
example: <code>&lt;set myPM20 cycle PDU1[20]&gt;</code><br>
example: <code>&lt;set myPM20 cycle myRouter&gt;</code><br>
</li><br>

<li><code>display</code><br>
Set display orientation to 0 (normal) or 180 (upside down)<br>
possible value: <code>&lt;0|180&gt;</code><br>
example: <code>set myPM20 display PDU1 180</code><br>
</li><br>

<li>help<br>
Used to show syntax of set commands.
<br>
argument: <code>&lt; 
any set command
&gt;</code><br>
example: <code>set help unlock</code><br>
</li>
<br>

<li>id<br>
Used to set PDU ID (PDU name).
<br>
arguments: <code>&lt;oldname&gt; &lt;newname&gt;</code><br>
example: <code>&lt;set myPM20 id oldname newname&gt;</code><br>
note:
If there are attributes or PM20C devices that use this ID than they will updated, too.
Changes will automatically saved to your fhem.cfg if global autosave is enabled.
To prevent autosave, see: 'global autosave'
<br>
</li>
<br>

<li>lock<br>
Lock socket(s) to current state.
<br>
argument: <code>&lt;sockets&gt;</code><br>
example: <code>set myPM20 lock PDU1[1-2],PDU2[3,5,7]</code><br>
</li>
<br>

<li>name<br>
Used to set a socket alias name. Alias names could be used instead of sockets
names.
<br>
arguments: <code>&lt;socket&gt; &lt;name&gt;</code><br>
example: <code>set myPM20 PDU1[12] myRouter</code><br>
</li>
<br>

<li>on|off<br>
Switch a socket. All sockets will be switched if no argument (sockets) is added.
This behavior can be adjusted with socketsOnOff attribut.
<br>
optional argument: <code>&lt;sockets&gt;</code><br>
example: <code>&lt;set myPM20 on PDU1[20]&gt;</code><br>
example: <code>&lt;set myPM20 off myRouter&gt;</code><br>
</li>
<br>

<li>powerondelay<br>
Powerondelay for sockets in seconds, range:0-6500 resolution:0.1.
Be careful and do not set this value to high because PDUs react a little bit strange in some cases.
<br>
arguments: <code>&lt;socket(s)&gt; &lt;delay&gt;</code><br>
example: <code>set myPM20 powerondelay myRouter 0.1</code><br>
example: <code>set myPM20 powerondelay PDU1[1-20],PDU5[1,3,5-7] 0.1</code><br>
</li>
<br>

<li>reboot<br>
Reboot specified PDU, not the ACSxx console server.
<br>
argument: <code>&lt;PDU&gt;</code><br>
example: <code> set myPM20 reboot PDU3</code><br>
</li>
<br>

<li>statusRequest<br>
Trigger a statusRequest für all parameters.
<br>
argument: <code>n/a</code><br>
example: <code>set myPM20 statusRequest</code><br>
</li>
<br>

<li>unlock<br>
Oppsoite of lock (see lock)<br>
</li>
<br>

<li><a href="#setExtensions">setExtensions</a><br>
Note: Keep in mind that setExtensions do not allow an argument. All defined
sockets will be switched if on/off/setExtensions are used.<br>
Use PM20C Devices if you want to switch single sockets with setExtensions or set
attribut socketsOnOff to select sockets.
</li>
<br>

</ul>


<a name="PM20get"></a>
<b>get</b>
<ul>

<li>_lastNotice<br>
Last notices and errors are kept in this reading.<br>
</li>
<br>

<li>alarm | PDUx_alarm<br>
PDUs alarm threshold in Ampere. PDU default is 32A.
<br>
possible value: <code>&lt;Range is 0.1-32&gt;</code><br>
</li>
<br>

<li>aliases<br>
Show defined aliases that can be used in set commands instead of <sockets>.
<br>
possible value: <code>&lt;A list of your socket aliases&gt;</code><br>
</li>
<br>

<li>buzzer | PDUx_buzzer<br>
Shows PDUs buzzer state
<br>
possible value: <code>&lt;on|off&gt;</code><br>
</li>
<br>

<li>current_act | PDUx_current_act<br>
Shows PDUs actual current consumption. Unit is Ampere.
</li><br>

<li>current_avg | PDUx_current_avg<br>
Shows PDUs average current consumption. Unit is Ampere.
</li><br>
<br>

<li>current_max | PDUx_current_max<br>
Shows PDUs maximal current consumption since last PDU reboot. Unit is Ampere.
</li><br>
<br>

<li>current_min | PDUx_current_min<br>
Shows PDUs minimal current consumption since last PDU reboot. Unit is Ampere.
</li>
<br>

<li>currentprotection | PDUx_currentprotection<br>
Has currentprotection been triggered?
<br>
possible value: <code>&lt;yes|no&gt;</code><br>
</li>
<br>

<li>display | PDUx_display<br>
How to disply current on physical PDU?
<br>
possible values: <code>&lt;normal and cycle manually |
180° rotated and cycle automatically&gt;</code><br>
</li>
<br>

<li>power | PDUx_power<br>
Shows actual power consumption (evaluated by PDU)
<br>
possible value: <code>&lt;max. 32A x 230V = 7360W&gt;</code><br>
</li>
<br>

<li>powerfactor | PDUx_powerfactor<br>
Shows PDUs powerfactor.
</li>
<br>

<li>presence<br>
Shows if the last attempt to connect to ACS was successful.
<br>
possible value: <code>&lt;present|absent&gt;</code><br>
</li>
<br>

<li>socketX_alias | PDUx_alias<br>
Shows the alises name for this socket
<br>
possible value: <code>&lt;a name&gt;</code><br>
</li>
<br>

<li>socketX_delay | PDUx_delay<br>
Shows powerondelay for this socket
<br>
possible value: <code>&lt;0.1-6500&gt;</code><br>
</li>
<br>

<li>socketX_locked | PDUx_locked<br>
Shows if the socket is locked.
<br>
possible value: <code>&lt;lock|unlock&gt;</code><br>
</li>
<br>

<li>socketX_name | PDUx_name<br>
Shows the real socket name. Due to a restriction within FHEM it is not possible
use reading names with characters like [] recently.
<br>
possible value: <code>&lt;PDU1[x]&gt;</code><br>
</li>
<br>

<li>socketX_state | PDUx_state<br>
Shows if the sockets in switched on or off
<br>
possible value: <code>&lt;on|off&gt;</code><br>
</li>
<br>

<li>state<br>
Shows module state
<br>
possible value: <code>&lt;unknown|opened|initialized&gt;</code><br>
note: PDU und socket related readings will be deleted if in an unknown state.
<br>
</li>
<br>

<li>temperature_act | PDUx_temperature_act<br>
Shows PDUs actual temperature. Unit is degrees celsius.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

<li>temperature_avg | PDUx_temperature_avg<br>
Shows PDUs average temperature. Unit is degrees celsius.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

<li>temperature_max | PDUx_temperature_max<br>
Shows PDUs maximal temperature since last DPU reboot. Unit is degrees celsius.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

<li>temperature_min | PDUx_temperature_min<br>
Shows PDUs minimal temperature since last DPU reboot. Unit is degrees celsius.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

<li>ver | PDUx_ver<br>
Shows PDUs firmware version.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

<li>voltage | PDUx_voltage<br>
Shows PDUs actual input valtage. Unit: volt.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

<li>modul_version<br>
Shows the current FHEM PM20 modul version,
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

</ul>


<a name="PM20attr"></a>
<b>attr</b>
<ul>

<li>autocreate<br>
Autocreate is used to automatically define PM20C devices for each socket if not
in standalone mode. Default is 1 (true). You can deactivate this feature by
setting the value to 0.
<br>
possible value: <code>&lt;1,0&gt;</code><br>
</li>
<br>

<li>autosave<br>
Autosave is used to automatically trigger save after a configuration change,
e.g. after a new device was created. Default is 1 (true), you can deactivate
this feature by setting the value to 0.
<br>
possible value: <code>&lt;1,0&gt;</code><br>
</li>
<br>

<li>disable<br>
Disable frequently scheduled statusRequests and set commands.
<br>
possible value: <code>&lt;1,0&gt;</code><br>
</li>
<br>

<li>disable_fork<br>
Used to switch off the so called forking for non-blocking functionality,
in this case for telnet queries. It is not recommended to use this
attribute but some operating systems seem to have a problem due to
forking a FHEM process (Windows?).
<br>Possible values: <code>&lt;0,1&gt;</code><br>
</li>
<br>

<li>intervalPresent<br>
Used to set device polling interval in seconds when device is present.<br>
Possible value: <code>integer &gt;= 60</code><br>
</li><br>

<li>intervalAbsent<br>
Used to set device polling interval in seconds when device is absent.<br>
Possible value: <code> integer &gt;= 60</code><br>
</li><br>

<li>multiPduMode<br>
Used to overwrite "single PDU mode" if only 1 PDU is connected.<br>
There are two modes in which way reading names are generated for this modul.<br>
Single PDU mode: Only one PDU is connected to ACSxxx. Readings have no
additional PDU-prefix and socket readings are named is this form:
socket&lt;num&gt;_xxx<br>
example readings: socket01_state, power<br>
Multi PDU mode: There are multiple PDUs connected to ACS. PDU and socket related
readings will get an additional PDU-prefix in this form: PDUx_reading.<br>
example readings: PDUx01_state, PDUx02_delay, PDUx_power<br>
Note: All PDU and socket related readings will be deleted if you change between
single and multi PDU mode. A new statusRequest will be triggered immediately.
<br>
possible value: <code>&lt;1,0&gt;</code><br>
</li>
<br>

<li>socketGroups<br>
Used to define a space separated list of socket groups. You can use group names
instead of multiple sockets in commands.
<br>
possible value: <code>&lt;group1:socket01,socket04&gt;</code><br>
example: <code>attr myPM20 socketGroups
group1:socket01,socket03 group2:socket07,socket19</code> (single pdu mode)<br>
example: <code>attr myPM20 socketGroups
group1:PDU1[1,3,5-9],PDU2[10-15],PDU3[17]</code> (multi pdu mode)<br>
</li>
<br>

<li>socketsOnOff<br>
Which sockets should be switched if socket argument is omitted at the end of 
on/off/setExtensions commands? You can define it with this attribut (comma
separated and ranges).
<br>
possible value: <code>&lt;sockets&gt;</code><br>
example: <code> 
attr myPM20 socketsOnOff PDU[1,3,7-9],PDU2[19],alias1,alias2
</code><br>
default: <code> 
All defined sockets!!!
</code><br>
</li>
<br>

<li>standalone<br>
Standalone mode will work without client devices (PM20C). All readings and
events will be created within/from the defined PM20 device. Default is disabled.
Note: PM20C devices will be deleted if set to 1, PM20 readings will be deleted
if set to 0. A statusRequest is triggered immediately to update new
readings/devices.
<br>
possible value: <code>&lt;1,0&gt;</code><br>
</li>
<br>



</ul>
</ul>

=end html

=cut



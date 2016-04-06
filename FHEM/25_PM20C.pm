# $Id$
################################################################################
#
#  25_PM20C.pm is a FHEM perl module that presents a single socket/pdu from
#  24_PM20.pm as an own device. Normally autocreated by PM20
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
# PM20C change log:
#
# 2016-02-14  0.1    - initial release
# 2016-03-10  0.2.4  - removed PM20_getIP function
# 2016-03-12  0.2.5  - corrected attr creation on first run
#                    - timer workaround for readings*Update() within notifyFn.
#                    - scheduled startup statusRequest
#                    - reduced log entries
#                    - support both PM20 READING_MODES
# 2016-03-28  0.3.0  - use of IOWrite
#                    - autocreate
#                    - to: code cleanup
#
################################################################################

my $PM20C_version = "0.3.0";
my $PM20C_desc = 'Provides single socket/pdu access to PM20 devices.';


package main;

use v5.14; #smartmatch, splice
use strict;
use warnings;
use Data::Dumper;
use SetExtensions;

no warnings 'experimental::smartmatch';

#grep ^sub 25_PM20C.pm | awk '{print $1" "$2";"}'
sub PM20C_Initialize($);
sub PM20C_devStateIcon();
sub PM20C_Define($$);
sub PM20C_Undef($$);
sub PM20C_Delete($$);
sub PM20C_Rename();
sub PM20C_Shutdown($);
sub PM20C_Set($$@);
sub PM20C_Get($@);
sub PM20C_Attr(@);
sub PM20C_Notify($$);
sub PM20C_statusRequest($);
sub PM20C_startupRequest($);
sub PM20C_Parse($$$);
sub PM20C_autocreate($$$);
sub PM20C_IORead($$@);
sub PM20C_whoami();


# ------------------------------------------------------------------------------
sub PM20C_Initialize($)
{
  my ($hash) = @_;

  $hash->{SetFn}        = "PM20C_Set";
  $hash->{GetFn}        = "PM20C_Get";
  $hash->{DefFn}        = "PM20C_Define";
  $hash->{AttrFn}       = "PM20C_Attr";
  $hash->{NotifyFn}     = "PM20C_Notify";
#  $hash->{NOTIFYDEV}    = "PM20,global";
#  $hash->{NOTIFYDEV}    = "global" #moved to DefineFn
  
  $hash->{UndefFn}      = "PM20C_Undef";
  $hash->{ShutdownFn}	  =	"PM20C_Shutdown";
  $hash->{DeleteFn}	    = "PM20C_Delete";
	$hash->{RenameFn}	    =	"PM20C_Rename";

  $hash->{ParseFn}      = "PM20C_Parse";
#  $hash->{Match}        = $hash->{NAME};
  $hash->{Match}        = ".+";              
  
  $hash->{AttrList}     = "IODev ".
                          "do_not_notify:0,1 ".
                          "disable:1,0 ".
                          $readingFnAttributes;
}

sub PM20C_devStateIcon()
{
  return "on:ios-on-green:off off:ios-off:on set_on:ios-set_on:statusRequest set_off:ios-set_off-green:statusRequest unknown:ios-NACK:statusRequest set_statusRequest:ios-NACK:statusRequest startup:ios-NACK:statusRequest";
}

# ------------------------------------------------------------------------------
sub PM20C_Define($$)  # only called when defined, not on reload.
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  my $usg = "Use 'define <name> PM20C <subtype> <io_device> <master_socket>'";
  return "Wrong syntax: $usg" if(int(@a) < 4);
  if (defined $defs{$a[3]}{TYPE} && $defs{$a[3]}{TYPE} ne "PM20") {
    return "Wrong I/O device: $a[3] is not of type PM20" }
  if (!$defs{$a[3]}) {
    Log3 $a[1], 2, "Missing I/O device: '$a[3]'. Not defined, yet?" }

  my $name    = $a[0];
  my $type    = $a[1];
  my $subtype = $a[2];
  my $iodev   = $a[3];
  my $socket  = $a[4];

  # register socket, for use in _parse
  $modules{$type}{helper}{sockets}{$socket} = $name if $subtype eq "socket";

  AssignIoPort($hash,$iodev) if( !$hash->{IODev} );
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 5, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } 
  else {
    Log3 $name, 3, "$name: no I/O device";
  }

#  $hash->{NOTIFYDEV}    = "PM20,global";
  $hash->{NOTIFYDEV}    = "global";

  
  $hash->{SOCKET}  = $socket;
  $hash->{SUBTYPE} = $subtype;
  

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, 'state', "unknown");
  readingsBulkUpdate($hash, 'presence', "unknown");
  readingsEndUpdate($hash,1);

  if (!$modules{$type}{helper}{startup}) {
    Log3 $type, 2, "$type: client module PM20C loaded";
    $modules{$type}{helper}{startup} = "1st module done";
  }

#  if (ReadingsVal($master,"state","") ne "initialized") {
    Log3 $name, 4, "$type: device $name opened uninitialized";
    my $c = devspec2array("TYPE=$type");
#    InternalTimer(gettimeofday()+10+rand($c)/4,"PM20C_startupRequest", $hash, 0);
#    InternalTimer(gettimeofday()+10+rand($c)/4,"PM20C_statusRequest", $hash, 0);
#  } else {
#    PM20C_startupRequest($hash);
#  }

  return undef;
}

# ------------------------------------------------------------------------------
#UndefFn: called while deleting device (delete-command) (wrong: while rereadcfg)
sub PM20C_Undef($$)
{
  my ($hash, $arg) = @_;
  delete $hash->{helper} if (defined($hash->{helper}));
  return undef;
}

# ------------------------------------------------------------------------------
#DeleteFn: called while deleting device (delete-command) but after UndefFn
sub PM20C_Delete($$)
{
  my ($hash, $arg) = @_;
  Log3 $hash->{NAME}, 1, "$hash->{TYPE}: Device $hash->{NAME} deleted";
  return undef;
}

# ------------------------------------------------------------------------------
sub PM20C_Rename() {
	my ($new,$old) = @_;
	my $type = $defs{"$new"}->{TYPE};
	my $name = $defs{"$new"}->{NAME};
  Log3 $name, 1, "$type: Device $old renamed to $new";
	return undef;
}

# ------------------------------------------------------------------------------
#ShutdownFn: called before shutdown-cmd
sub PM20C_Shutdown($)
{
	my ($hash) = @_;
	my $type = $hash->{TYPE};
  delete $hash->{helper} if (defined($hash->{helper}));

  if (!$modules{$type}{helper}{shutdown}) {
    Log3 $type, 2, "$type: Client modules shutdown requested";
    $modules{$type}{helper}{shutdown} = "1st module done";
  }

	return undef;
}

# ------------------------------------------------------------------------------
sub PM20C_Set($$@)
{
  my ($hash, $name, $cmd, @params) = @_;
  my $self = PM20C_whoami();
  return undef if (IsDisabled $name);
  Log3 $hash->{NAME}, 5, "$name: $self() got: hash:$hash, name:$name, cmd:$cmd, ".
                         "params:".join(" ",@params) if ($cmd ne "?");

  my @cList;
  @cList = sort qw(on off cycle powerondelay lock unlock name status statusRequest) if $hash->{SUBTYPE} eq "socket";
  @cList = sort qw(alarm buzzer currentprotection display status statusRequest) if $hash->{SUBTYPE} eq "pdu";

  my $commands = join("|",@cList);
  if ($cmd =~ /^($commands)$/)
  {
    Log3 $name, 4, "$name: set $name $cmd";
   	readingsSingleUpdate($hash, 'state', "set_on",1) if $cmd eq "on";
   	readingsSingleUpdate($hash, 'state', "set_off",1) if $cmd eq "off";
    Log3 $name, 5, "$name: set $hash->{IODev} $cmd $hash->{SOCKET}";
    if ($hash->{SUBTYPE} eq "socket" || $cmd eq "alarm" || $cmd eq "display" || $cmd eq "status") {
      IOWrite($hash, $cmd, $hash->{SOCKET}, $params[0]);
    }
    else {
      IOWrite($hash, $cmd, $params[0], $hash->{SOCKET});
    }
    return undef;
    
  }

  return "Unknown argument ?, choose one of ".join(" ",@cList) if $hash->{SUBTYPE} eq "pdu";
  return SetExtensions($hash, join(" ", @cList), $name, $cmd, @params);
}


# ------------------------------------------------------------------------------
sub PM20C_Get($@)
{
  my ($hash, @a) = @_;
  return "argument is missing" if(int(@a) != 2);

  my $reading = $a[1];
  my $ret;

  if(exists($hash->{READINGS}{$reading})) {
    if(defined($hash->{READINGS}{$reading})) {
      return $hash->{READINGS}{$reading}{VAL};
    }
    else {
      return "no such reading: $reading";
    }
  }

  else {
    $ret = "unknown argument $reading, choose one of";
    foreach my $reading (sort keys %{$hash->{READINGS}}) {
      $ret .= " $reading:noArg" if ($reading ne "firmware");
    }
    return $ret;
  }
}

# ------------------------------------------------------------------------------
sub PM20C_Attr(@)
{
  my ($cmd,$name,$aName,$aVal) = @_;
  my $hash = $defs{$name};
  my $type = $hash->{TYPE};
  my $ret;
  
  # InternalTimer will be called from notifyFn if disabled = 0
  if ($aName eq "disable") {
    $ret="0,1" if ($cmd eq "set" && not $aVal =~ /^(0|1)$/);
    if ($cmd eq "set" && $aVal eq "1") {
      Log3 $name, 3, "$type: Device $name is disabled";
      readingsSingleUpdate($hash, "state", "disabled",1);
    }
    if (($cmd eq "set" && $aVal eq "0") || $cmd eq "del") {
      Log3 $name, 4, "$type: Device $name is enabled";
      PM20C_statusRequest($hash);
    }
  }

  if (defined $ret) {
    Log3 $name, 2, "$name: attr $aName $aVal != $ret";
    return "$aName must be: $ret";
  }

  return undef;
}


# ------------------------------------------------------------------------------
sub PM20C_Notify($$)
{
  my ($hash,$dev) = @_;
  my ($name,$self) = ($hash->{NAME},PM20C_whoami());
  return "" if(IsDisabled($name));

  my $events = deviceEvents($dev,1);
  return if( !$events );

  if ($defs{$hash->{IODev}} && $defs{$hash->{IODev}} eq $dev) {
    my $socket = $hash->{SOCKET};
    my $presence = "presence";
    
    if( defined $socket && grep(m/$socket/, @{$events}) ) {
###      InternalTimer(gettimeofday()+0.01,"PM20C_timedSetReading", "$name:state:$socket", 0);
       # readings*Update() did not work here. It prevents any further events from $dev ???
#      readingsSingleUpdate($hash,"state",$dev->{READINGS}{$reading}{VAL},1);
    }

    if( grep(m/$presence/, @{$events}) ) {
###      InternalTimer(gettimeofday()+0.01,"PM20C_timedSetReading", "$name:presence:$presence", 0);
    }

  }
  return "";
}

# ------------------------------------------------------------------------------
sub PM20C_statusRequest($)
{
  my ($hash) = @_;
  IOWrite($hash, "getSocketStatus", $hash->{SOCKET});
  return undef;
}

# ------------------------------------------------------------------------------
#sub PM20C_timedSetReading($)
#{
#  my ($name,$what,$reading) = split(":",$_[0]);
#  my $hash = $defs{$name};
#  my $mhash = $defs{$hash->{IODev}};
#  my $mval = $mhash->{READINGS}{$reading}{VAL};
#  my $self = PM20C_whoami()."()";
#  Log3 $name, 5, "$name: $self call: readingsSingleUpdate($hash,\"state\",$mval,1)";
#  readingsSingleUpdate($hash,$what,$mval,1);
#}

# ------------------------------------------------------------------------------
sub PM20C_startupRequest($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $type = $hash->{TYPE};
  my $master = $hash->{IODev};
  $hash->{INIT_RETRY} = 0 if !$hash->{INIT_RETRY};
  my $retry = $hash->{INIT_RETRY};
  my $myState = ReadingsVal($name,"state","unknown");
  
  unless(IsDisabled($name)) {
      return if $myState ne "unknown";
      PM20C_statusRequest($hash);

 #    	readingsSingleUpdate($hash, 'state', "startup",1);
      my $when = int(10+rand(10)-5)+$retry*10;
      $when = 900 if $when >900;
      Log3 $name, 4, "$type: Device $name opened, but not initialized (retry in ".$when."s)" if $retry >= 3;
      InternalTimer(gettimeofday()+$when,"PM20C_startupRequest", $hash, 0);
      $hash->{INIT_RETRY}++;

  }
}

# ------------------------------------------------------------------------------
sub PM20C_Parse($$$)
{
  # we are called from dispatch() from the PM20 device
  # we never come here if $msg does not match $hash->{MATCH} in the first place
  # NOTE: we will update all matching readings for all (logical) devices, not just the first!
  my ($IOhash, $msg) = @_;   # IOhash points to the PM20, not to this PM20C
  # 1:socket/pdu 2:autocreate 3:autosave 4:data
  my ($socket,$ac,$as,$v) = split(":",$msg);
  my ($self) = (PM20C_whoami()."()");
  Log3 undef, 5, "PM20C: $self got: $msg";
  return undef if !$socket || $socket eq "";

  my $name;
  my @v = split("\\|\\|",$v);
  # look in each $defs{$d}{SOCKET} for $socket to get device name.
  foreach my $d (keys %defs) {
    next if($defs{$d}{TYPE} ne "PM20C");
    if (InternalVal($defs{$d}{NAME},"SOCKET",undef) eq "$socket") {
      $name = $defs{$d}{NAME} ;
      last;
    }
  }

  # autocreate device if sockets has no device asigned.
  $name = PM20C_autocreate($IOhash,$socket,$as) if (!($name) && $ac eq "1");
  
  my $hash = $defs{$name};

  if (defined $hash && $hash->{TYPE} eq "PM20C") {
    foreach (@v) {
      my ($reading,$value) = split("\\|",$_);
      #Log3 undef, 3, "$name: $self readingsSingleUpdate(\$hash, $reading, $value, 1)";
      $reading =~ s/listipdus_//; #just cosmetically
      readingsSingleUpdate($hash, $reading, $value, 1);
    }
  }
  else {
    Log3 undef, 2, "PM20C: Device $name not defined";
  }
 
  return $name;  # must be != undef. else msg will processed further -> help me!
}

# ------------------------------------------------------------------------------
sub PM20C_autocreate($$$)
{
  my ($IOhash,$socket,$autosave) = @_;

  my ($pdu,$snum,$devname,$define,$subtype,$group);
  if ($socket =~ m/(.*)\[(\d+)\]/) { # Socket
    $pdu = uc($1);
    $pdu = $1;
    $pdu =~ s/[:-]/_/;
    $snum    = ($2 < 10) ? "0".$2 : $2;
    $devname = uc("PM20C_".$pdu."_".$snum);
    $subtype = "socket";
    $group   = "Socket";
    $define  = "$devname PM20C $subtype $IOhash->{NAME} $socket";
  }
  elsif ($socket =~ /(.*)/) { # PDU
#    $pdu = uc($1);
    $pdu = $1;
    $pdu =~ s/[:-]/_/;
    $devname = uc("PM20C_PDU_".$pdu);
    $subtype = "pdu";
    $group   = "PDU";
    $define  = "$devname PM20C $subtype $IOhash->{NAME} $pdu";
  }
  Log3 undef, 3, "PM20C: autocreate: $define";

  my $cmdret= CommandDefine(undef,$define);
  if(!$cmdret) {
    $cmdret= CommandAttr(undef, "$devname event-on-change-reading .*");
    $cmdret= CommandAttr(undef, "$devname webCmd :");
    $cmdret= CommandAttr(undef, "$devname room Avocent");
    $cmdret= CommandAttr(undef, "$devname group $group");
    $cmdret= CommandAttr(undef, "$devname devStateIcon {PM20C_devStateIcon()}") if $subtype eq "socket";
    CommandSave(undef,undef) if (defined $autosave && $autosave eq "1");
    Log3 undef, 4, "PM20C: autosave disabled: do not forget to save changes."
  }
  else {
    Log3 undef, 1, "PM20C: autocreate: an error occurred while creating device for socket $socket: $cmdret";
  } 

  return $devname;
}



###################################
# This could be IORead in fhem, But there is none.
# Read https://forum.fhem.de/index.php/topic,9670.msg54027.html#msg54027
# to find out why.
# ------------------------------------------------------------------------------
sub PM20C_IORead($$@)
{
  my ($hash,$what,@a) = @_;
  my $name = $hash->{NAME};

  my $iohash = $hash->{IODev};
  if(!$iohash ||
     !$iohash->{TYPE} ||
     !$modules{$iohash->{TYPE}} ||
     !$modules{$iohash->{TYPE}}{IOReadFn}) {
       Log3 $hash, 5, "No I/O device or IOReadFn found for $name";
       return;
  }

  no strict "refs";
  my $ret = &{$modules{$iohash->{TYPE}}{IOReadFn}}($iohash, $what, @a);
  use strict "refs";

  return $ret;
}




# ------------------------------------------------------------------------------
sub PM20C_whoami()  { return (split('::',(caller(1))[3]))[1] || ''; }



1;

=pod
=item device
=begin html

<a name="PM20C"></a>
<h3>PM20C</h3>

<ul>
<p>
Avocent Cyclade PM20C client module. It can only be use in context with the
<a href="#PM20">PM20 module</a>. It is used to provide access to a single socket
or PDU. Normally autocreated by PM20 device if not forbidden by autocreate
attribute.
</p>
<a name="PM20Cdefine"></a>
<b>define</b>
<ul>
<code>
define &lt;name&gt; PM20C &lt;subtype&gt; &lt;I/O device&gt; &lt;socket|pdu&gt;
</code><br><br>

<li><code>&lt;subtype&gt;</code><br>
Must be "socket" or "pdu" depending on if you want to define a socket or a PDU
device.
</li><br>

<li><code>&lt;name&gt;</code><br>
A device name of your choice.
</li><br>

<li><code>&lt;I/O device&gt;</code><br>
FHEM PM20 device that you want to use. Must already be defined.
</li><br>

<li><code>&lt;socket|pdu&gt;</code><br>
A single PM20 Socket or PDU that you want to use.<br>
possible value: <code>&lt;PDU1[17]|PDU1&gt;</code><br>
</li><br>
</ul>


<a name="PM20Cset"></a>
<b>set</b>

<ul>
<b>socket mode</b> (subtype socket)

<ul>
<li><code>cycle</code><br>
Switch socket off and on again.
</li><br>

<li><code>off</code><br>
Switch socket off.
</li><br>

<li><code>on</code><br>
Switch socket on.
</li><br>

<li><code>status</code><br>
Update status from PM20 I/O device.
</li><br>

<li><code>statusRequest</code><br>
Trigger PM20 I/O device to get all states from PDU and dispatch to clients.
</li><br>

<li><a href="#setExtensions">setExtensions</a>
</li><br>

</ul>
<b>pdu mode</b> (subtype pdu)
<ul>

<li><code>alarm</code><br>
Set alarm threshold value in Ampere.<br>
possible value: <code>&lt;1-32&gt;</code><br>
example: <code>set PDU1 alarm 16</code><br>
</li><br>

<li><code>buzzer</code><br>
Set buzzer on or off.<br>
possible value: <code>&lt;on|off&gt;</code><br>
example: <code>set PDU1 buzzer on</code><br>
</li><br>

<li><code>currentprotection</code><br>
Set currentprotection on or off.
example: <code>set PDU1 currentprotection on</code><br>
</li><br>

<li><code>display</code><br>
Set display orientation to 0 (normal) or 180 (upside down)<br>
possible value: <code>&lt;0|180&gt;</code><br>
example: <code>set PDU1 display 180</code><br>
</li><br>
</ul>
</ul>

<a name="PM20Cget"></a>
<b>get</b>

<ul>
<b>socket mode</b> (subtype socket)

<ul>
<li><code>presence</code><br>
Presence of Avocent Cylades ACSxx Console Server used to control PM20 PDUs.
<br>
possible value: <code>&lt;unknown|present|absent&gt;</code><br>
</li><br>

<li><code>state</code><br>
State of selected socket
<br>
possible value: <code>&lt;on|off|startup|disabled|unknown&gt;</code><br>
</li><br>

<li><code>locked</code><br>
Is socketed locked or not.
<br>
possible value: <code>&lt;yes|no&gt;</code><br>
</li><br>

<li><code>delay</code><br>
Powerondelay of socket in seconds.
<br>
possible value: <code>&lt;0.1-6500&gt;</code><br>
</li><br>

<li><code>alias</code><br>
Alias name of this socket.
<br>
possible value: <code>&lt;string;</code><br>
</li><br>

<li><code>pdu</code><br>
Name of PDU socket is connected to.
<br>
possible value: <code>&lt;string;</code><br>
</li><br>
</ul>

<b>pdu mode</b> (subtype pdu)
<ul>

<li>alarm<br>
PDUs alarm threshold in Ampere. PDU default is 32A.
<br>
possible value: <code>&lt;Range is 0.1-32&gt;</code><br>
</li>
<br>

<li>buzzer<br>
Shows PDUs buzzer state
<br>
possible value: <code>&lt;on|off&gt;</code><br>
</li>
<br>

<li>current_act<br>
Shows PDUs actual current consumption. Unit is Ampere.
</li><br>

<li>current_avg<br>
Shows PDUs average current consumption. Unit is Ampere.
</li><br>

<li>current_max<br>
Shows PDUs maximal current consumption since last PDU reboot. Unit is Ampere.
</li><br>

<li>current_min<br>
Shows PDUs minimal current consumption since last PDU reboot. Unit is Ampere.
</li>
<br>

<li>currentprotection<br>
Has currentprotection been triggered?
<br>
possible value: <code>&lt;yes|no&gt;</code><br>
</li>
<br>

<li>display<br>
How to disply current on physical PDU?
<br>
possible values: <code>&lt;normal|180 degrees rotated&gt;</code><br>
</li>
<br>

<li>power<br>
Shows actual power consumption (evaluated by PDU)
<br>
possible value: <code>&lt;max. 32A x 230V = 7360W&gt;</code><br>
</li>
<br>

<li>powerfactor<br>
Shows PDUs powerfactor.
</li>
<br>

<li><code>presence</code><br>
Presence of Avocent Cylades ACSxx Terminal Server used to control PM20 PDUs.
<br>
possible value: <code>&lt;unknown|present|absent&gt;</code><br>
</li><br>

<li><code>state</code><br>
State of selected socket
<br>
possible value: <code>&lt;startup|disabled|unknown&gt;</code><br>
</li><br>

<li>temperature_act<br>
Shows PDUs actual temperature. Unit is degrees celsius.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

<li>temperature_avg<br>
Shows PDUs average temperature. Unit is degrees celsius.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

<li>temperature_max<br>
Shows PDUs maximal temperature since last DPU reboot. Unit is degrees celsius.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

<li>temperature_min<br>
Shows PDUs minimal temperature since last DPU reboot. Unit is degrees celsius.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

<li>ver<br>
Shows PDUs firmware version.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>

<li>voltage<br>
Shows PDUs actual input valtage. Unit: volt.
<br>
possible value: <code>&lt;number&gt;</code><br>
</li>
<br>
</ul>
</ul>


<a name="PM20Cattr"></a>
<b>attr</b>

<ul>
<li>disable</a><br>
Disable device.<br>
possible value: <code>&lt;0|1&gt;</code><br>
</li><br>

<li>IODev</a><br>
IODev to be used.
</li><br>

<li><a href="#readingFnAttributes">readingFnAttributes</a><br>
Attributes like event-on-change-reading, event-on-update-reading,
event-min-interval, event-aggregator, stateFormat, userReadings, ...
are enabled.
</li><br>
</ul>
</ul>

=end html

=cut

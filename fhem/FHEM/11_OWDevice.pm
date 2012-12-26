# $Id: $
##############################################################################
#
#     11_OWDevice.pm
#     Copyright by Dr. Boris Neubert
#     e-mail: omega at online dot de
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################


package main;

use strict;
use warnings;


###################################
sub
OWDevice_Initialize($)
{
  my ($hash) = @_;

  $hash->{GetFn}     = "OWDevice_Get";
  $hash->{SetFn}     = "OWDevice_Set";
  $hash->{DefFn}     = "OWDevice_Define";

  $hash->{AttrList}  = "trimvalues loglevel:0,1,2,3,4,5";
}

###################################
# return array
# 1st element: interface
# 2nd element: array of getters/readings
# 3rd element: array of setters/readings
# 4th element: array of readings to be periodically updated
# the value of the first reading in getters is written to state
sub
OWDevice_GetDetails($) {

      my ($hash)= @_;
      my $interface= "";
      my @getters= qw(address alias family id power type);
      my @setters= qw(alias);
      my @polls;

      # below we use shift such that the potentially
      # more important values get listed first and
      # that the first reading in getters could be
      # defined (it is shown in the STATE).
            
      # http://owfs.sourceforge.net/family.html
      my $family= substr($hash->{fhem}{address}, 0, 2);
      if($family eq "10") {
        # 18S20 high precision digital thermometer
        unshift @getters, qw(temperature templow temphigh);
        unshift @setters, qw(templow temphigh);
        unshift @polls, qw(temperature);
        $interface= "temperature";
      } elsif($family eq "reserved") {
        # reserved for other devices
      };
      # http://perl-seiten.homepage.t-online.de/html/perl_array.html
      return ($interface, \@getters, \@setters, \@polls);
}

###################################
# This could be IORead in fhem, But there is none.
# Read http://forum.fhem.de/index.php?t=tree&goto=54027&rid=10#msg_54027
# to find out why.
sub
OWDevice_ReadFromServer($@)
{
  my ($hash, @a) = @_;

  my $dev = $hash->{NAME};
  return if(IsDummy($dev) || IsIgnored($dev));
  my $iohash = $hash->{IODev};
  if(!$iohash ||
     !$iohash->{TYPE} ||
     !$modules{$iohash->{TYPE}} ||
     !$modules{$iohash->{TYPE}}{ReadFn}) {
    Log 5, "No I/O device or ReadFn found for $dev";
    return;
  }

  no strict "refs";
  my $ret = &{$modules{$iohash->{TYPE}}{ReadFn}}($iohash, @a);
  use strict "refs";
  return $ret;
}

###################################
sub
OWDevice_ReadValue($$) {

        my ($hash,$reading)= @_;
        
        my $address= $hash->{fhem}{address};
        my $value= OWDevice_ReadFromServer($hash, "/$address/$reading");
        $value= trim($value) if(AttrVal($hash,"trimvalues",1));
        my @getters= @{$hash->{fhem}{getters}};
        Debug join(",", @getters);
        Debug $getters[0];
        $hash->{STATE}= $value if($reading eq $getters[0]);
        
        return $value;
}

###################################
sub
OWDevice_WriteValue($$$) {

        my ($hash,$reading,$value)= @_;

        my $address= $hash->{fhem}{address};
        IOWrite($hash, "/$address/$reading", $value);
        return $value;
}

###################################
sub
OWDevice_UpdateValues($) {

        my ($hash)= @_;

        my @polls= @{$hash->{fhem}{polls}};
        if($#polls>=0) {
          my $address= $hash->{fhem}{address};
          readingsBeginUpdate($hash);
          foreach my $reading (@polls) {
            my $value= OWDevice_ReadValue($hash,$reading);
            readingsBulkUpdate($hash,$reading,$value);
          }
          readingsEndUpdate($hash,1);
        }
        InternalTimer(gettimeofday()+$hash->{fhem}{interval}, "OWDevice_UpdateValues", $hash, 0)
          if(defined($hash->{fhem}{interval}));

}

###################################
sub
OWDevice_Get($@)
{
        my ($hash, @a)= @_;

        my $name= $hash->{NAME};
        return "get $name needs one argument" if(int(@a) != 2);
        my $cmdname= $a[1];
        my @getters= @{$hash->{fhem}{getters}};
        if($cmdname ~~ @getters) {
          my $value= OWDevice_ReadValue($hash, $cmdname);
          readingsSingleUpdate($hash,$cmdname,$value,1);
          return $value;
        } else {
          return "Unknown argument $cmdname, choose one of " . join(" ", @getters);
        }
}

#############################
sub
OWDevice_Set($@)
{
        my ($hash, @a)= @_;

        my $name= $hash->{NAME};
        my $cmdname= $a[1];
        my $value= $a[2];
        my @setters= @{$hash->{fhem}{setters}};
        if($cmdname ~~ @setters) {
          return "set $name needs two arguments" if(int(@a) != 3);
          OWDevice_WriteValue($hash,$cmdname,$value);
          readingsSingleUpdate($hash,$cmdname,$value,1);
          return undef;
        } else {
          return "Unknown argument $cmdname, choose one of " . join(" ", @setters);
        }
}

#############################
sub
OWDevice_Define($$)
{
        my ($hash, $def) = @_;
        my @a = split("[ \t]+", $def);

        return "Usage: define <name> OWDevice <address> [interval]"  if($#a < 3 || $#a > 4);
        my $name= $a[0];

        AssignIoPort($hash);
        if(defined($hash->{IODev}->{NAME})) {
          Log 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
        } else {
          Log 1, "$name: no I/O device";
        }

        $hash->{fhem}{address}= $a[2];
        if($#a == 3) {
          $hash->{fhem}{interval}= $a[3];
          Log 5, "$name: polling every $a[3] seconds";
        }
        my ($interface, $gettersref, $settersref, $pollsref)= OWDevice_GetDetails($hash);
        my @getters= @{$gettersref};
        my @setters= @{$settersref};
        my @polls= @{$pollsref};
        if($interface ne "") {
          $hash->{fhem}{interfaces}= $interface;
          Log 5, "$name: interfaces: $interface";
        }
        $hash->{fhem}{getters}= $gettersref;
        Log 5, "$name: getters: " . join(" ", @getters);
        $hash->{fhem}{setters}= $settersref;
        Log 5, "$name: setters: " . join(" ", @setters);
        $hash->{fhem}{polls}= $pollsref;
        Log 5, "$name: polls: " . join(" ", @polls);

        OWDevice_UpdateValues($hash) if(defined($hash->{fhem}{interval}));

        return undef;
}
###################################

1;

###################################
=pod
=begin html

<a name="OWDevice"></a>
<h3>OWDevice</h3>
<ul>
  <br>
  <a name="OWDevicedefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; OWDevice &lt;address&gt; [&lt;interval&gt;]</code>
    <br><br>

    Defines a 1-wire device. The 1-wire device is identified by its &lt;address&gt;. It is
    served by the most recently defined <a href="#OWServer">OWServer</a>.
    <br><br>

    If &lt;interval&gt; is given, the OWServer is polled every &lt;interval&gt; seconds for
    a subset of readings.
    <br><br>

    OWDevice is a generic device. Its characteristics are retrieved at the time of the device's
    definition. The available readings that you can get or set as well as those that are
    regularly retrieved by polling can be seen when issuing the
    <code><a href="#list">list</a> &lt;name&gt;</code> command.
    <br><br>
    This module is completely unrelated to the 1-wire modules with names all in uppercase.
    <br><br>

    Example:
    <ul>
      <code>
      define myOWServer localhost:4304<br><br>
      get myOWServer devices<br>
      10.487653020800 DS18S20<br><br>
      define myT1 10.487653020800<br><br>
      list myT1 10.487653020800<br>
      Internals:<br>
          ...<br>
        Readings:<br>
          2012-12-22 20:30:07   temperature     23.1875<br>
        Fhem:<br>
          ...<br>
          getters:<br>
            address<br>
            alias<br>
            family<br>
            id<br>
            power<br>
            type<br>
            temperature<br>
            templow<br>
            temphigh<br>
          polls:<br>
            temperature<br>
          setters:<br>
            alias<br>
            templow<br>
            temphigh<br>
        ...<br>
      </code>
    </ul>
    <br>
  </ul>

  <a name="OWDeviceset"></a>
  <b>Set</b>
  <ul>
    <code>set &lt;name&gt; &lt;reading&gt; &lt;value&gt;</code>
    <br><br>
    Sets &lt;reading&gt; to &lt;value&gt; for the 1-wire device &lt;name&gt;. The permitted values are defined by the underlying
    1-wire device type.
    <br><br>
    Example:
    <ul>
      <code>set myT1 templow 5</code><br>
    </ul>
    <br>
  </ul>


  <a name="OWDeviceget"></a>
  <b>Get</b>
  <ul>
    <code>get &lt;name&gt; &lt;reading&gt; &lt;value&gt;</code>
    <br><br>
    Gets &lt;reading&gt; for the 1-wire device &lt;name&gt;. The permitted values are defined by the underlying
    1-wire device type.
    <br><br>
    Example:
    <ul>
      <code>get myT1 temperature</code><br>
    </ul>
    <br>
  </ul>


  <a name="OWDeviceattr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#loglevel">loglevel</a></li>
    <li><a href="#eventMap">eventMap</a></li>
    <li><a href="#event-on-update-reading">event-on-update-reading</a></li>
    <li><a href="#event-on-change-reading">event-on-change-reading</a></li>
  </ul>
  <br><br>


</ul>




=end html
=cut
# zncslowvoice.pm v1.0 by Sven Roelse
# Copycat idea: https://github.com/solbu/eggdrop-scripts/tree/master/slowvoice
# Network module, moderates channel(s) where active and auto-voices users after random interval.
# (Between 60 and 90 seconds). This to prevent spam-on-join. See solbu's notes.

# 27-01-2020 - v1.0 first draft
# 28-01-2020 - fixed sub OnMode, $IsSVChannel regex(x2 - thanks Ouims!) 
#            - fixed error "can't call GetName on undefined object" 
#              when saving channel as argument in webpanel that you're not in. 


use 5.012;
use strict;
use warnings;
use diagnostics;
use utf8;

package zncslowvoice;
use base 'ZNC::Module';

sub description { 
  "ZNC module to voice users after random time interval."
}
sub has_args { 1 }

sub args_help_text { 
  "Whitelist channelnames; space delimited." 
}

sub module_types {
    $ZNC::CModInfo::NetworkModule
}
# set +m on all channels that are loaded in args if I'm op
sub OnLoad {
  my ($self, $args, $message) = @_;
  $self->{sv_channels} = $args;

  foreach my $svc (split /\s+/, $args) {
    my $objChan = $self->GetNetwork()->FindChan($svc);
    if ( defined ( $objChan ) ) {
      my $Chan = $objChan->GetName;
      my $bMyPerm = $objChan->HasPerm('@');
      my $ChanIsNotModerated = $objChan->GetModeString !~ /m/;

      $self->PutIRC("MODE $Chan +m") if ( $bMyPerm && $ChanIsNotModerated )
    }
  }
  return $ZNC::CONTINUE;
}

# On Join, if not me, start random interval timer if chan is slowvoiced
sub OnJoin {
  my ($self, $nickObj, $chanObj) = @_;
  my $nick = $nickObj->GetNick;
  my $chan = $chanObj->GetName;

  my $MyNick = $self->GetNetwork()->GetIRCSock->GetNick;

  my $bFlag = $self->{sv_channels} =~ /\B\Q$chan\E(?=\s|$)/ && $nick ne $MyNick;

  if ( $bFlag ) {
    my $interval = 60 + int(rand(31));
    my $timer = $self->CreateTimer(task=>'zncslowvoice::timer', interval=>$interval, cycles=>1, description=>'Slowvoices after random interval');
    $timer->{msg} = join " ", $nick, $chan;
  }
  return $ZNC::CONTINUE;
}

# If mode -m, and channel is slowvoiced and I'm op set +m
sub OnMode {
  my ($self, $OpNick, $ChanObj, $cMode, $sArg, $bAdded, $bNoChange) = @_;
  my $Chan = $ChanObj->GetName;
  $cMode = chr($cMode);
  my $bMyPerm = $ChanObj->HasPerm('@');
  my $IsSVChannel = $self->{sv_channels} =~ /\B\Q$Chan\E(?=\s|$)/;

  $self->PutIRC("MODE $Chan +m") if ( !$bAdded && !$bNoChange && $cMode eq "m" && $bMyPerm && $IsSVChannel);
  
}
# If I'm being opped and channel is slowvoiced, set +m
sub OnChanPermission {
  my $self = shift;
  my ( $OpNickObj, $NickObj, $ChanObj, $CharacterMode, $ModeIsAdded, $NoChange ) = @_;

  my $MyNick = $self->GetNetwork()->GetIRCSock->GetNick;
  my $Chan = $ChanObj->GetName;
  my $Subject = $NickObj->GetNick;
  
  my $IsSVChannel = $self->{sv_channels} =~ /\B\Q$Chan\E(?=\s|$)/;
  my $ChanIsNotModerated = $ChanObj->GetModeString !~ /m/;
  
  my $bFlag = $IsSVChannel && $ChanIsNotModerated && !$NoChange && $ModeIsAdded && chr($CharacterMode) eq "o" && $Subject eq $MyNick;

  if ( $bFlag ) {
    $self->PutIRC("MODE $Chan +m");
  }
}

package zncslowvoice::timer;
use base 'ZNC::Timer';
sub RunJob {
  my $self = shift;
  my @params = split /\s+/, $self->{msg};

  my $sv_nick = $self->GetModule->GetNetwork->FindChan($params[1])->FindNick($params[0])->GetNick;
  # Nick sill on channel? If so, continue
  if ( defined($sv_nick) ) {
    my $ChanObj = $self->GetModule->GetNetwork->FindChan($params[1]);
    
    my $bMyPerm = $ChanObj->HasPerm('@');
    my $sPermStr = $ChanObj->FindNick($sv_nick)->GetPermStr;
    my $Chan = $ChanObj->GetName;

    if ( $bMyPerm && $sPermStr !~ /v/ ) {
      $self->GetModule->PutIRC("MODE $Chan +v $sv_nick");
    }
  }
}
1;

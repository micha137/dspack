unit PauseFilter;

interface

uses
   BaseClass, DirectShow9;

type
  TPauseFilter = class(TBCTransInPlaceFilter)
    function Transform(Sample: IMediaSample): HRESULT; override;
    function CheckInputType(mtIn: PAMMediaType): HRESULT; override;
  protected
    FLastForwardedSampleTimeEnd, FPauseTimes: REFERENCE_TIME;
    FPause, FSwitchingPauseState: Boolean;
    FSkipped: Cardinal;
    procedure SetPause(const APause: Boolean);
  published
    property ForwardingPause: Boolean read FPause write SetPause stored False;
  end;


implementation

uses
  DXSUtil,
  SysUtils,
  Winapi.Windows;

function TPauseFilter.CheckInputType(mtIn: PAMMediaType): HRESULT;
begin
  Result := S_OK;
  FPauseTimes := 0;
end;

procedure TPauseFilter.SetPause(const APause: Boolean);
begin
  if FPause=APause then Exit;

  // We are entering or leaving a pause:
  // On entering, we will wait for the next keyframe.
  // On leaving, we will calculate the timestamp difference for the lenght of the last pause at the next key frame
  FSwitchingPauseState := True;

  FPause := APause;
end;

function TPauseFilter.Transform(Sample: IMediaSample): HRESULT;
var startTime, endTime, sampleDuration: REFERENCE_TIME;
label forwardit, skipit;
begin
  if FPause then begin
    if FSwitchingPauseState then begin
      if Sample.IsSyncPoint<>S_OK then goto forwardit;
      {$IFDEF DEBUG}
      DbgLog(self, Format('Entering pause at I-frame', [ ] ));
      {$ENDIF}
      FSkipped := 0;
      FSwitchingPauseState := False;
    end;

    skipit:
    Inc(FSkipped);
    Result := S_FALSE;// don't forward it
    Exit;
  end;

  forwardit:
  CheckDSError(Sample.GetTime(startTime, endTime));

  if FSwitchingPauseState and Not FPause then begin
    if Sample.IsSyncPoint<>S_OK then goto skipit;

    sampleDuration := endTime-startTime;
    FPauseTimes := FPauseTimes + FSkipped * sampleDuration;
    {$IFDEF DEBUG}
    DbgLog(self, Format('Pausetimes=%d ms (%f Samples, Dampleduration=%d ms skipped=%d samples, last pause duration=%d ms, skipped*SampleDuration=%d ms)',
      [ RefTimeToMiliSec(FPauseTimes), FPauseTimes/sampleDuration,
        RefTimeToMiliSec(sampleDuration), FSkipped,
        RefTimeToMiliSec(startTime - FLastForwardedSampleTimeEnd),
        FSkipped*RefTimeToMiliSec(sampleDuration) ] ));
    {$ENDIF}
    FSwitchingPauseState := False;
    Sample.SetDiscontinuity(True);
  end;
  FLastForwardedSampleTimeEnd := endTime;

  startTime := startTime-FPauseTimes;
  endTime := endTime-FPauseTimes;
  CheckDSError(Sample.SetTime(@startTime, @endTime));
  Result := S_OK;// forward the sample
end;

end.

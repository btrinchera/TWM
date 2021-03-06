function dataout = alg_wrapper(datain, calcset) %<<<1
% Part of QWTB. Wrapper script for algorithm ADEV.
%
% See also qwtb

% Format input data --------------------------- %<<<1
% ADEV definition is:
% [RETVAL, S, ERRORB, TAU] = ALLAN(DATA,TAU,NAME,VERBOSE)

if isfield(datain, 'fs')
    fs = datain.fs.v;
elseif isfield(datain, 'Ts')
    fs = 1/datain.Ts.v;
    if calcset.verbose
        disp('QWTB: ADEV wrapper: sampling frequency was calculated from sampling time')
    end
else
    fs = 1./mean(diff(datain.t.v));
    if calcset.verbose
        disp('QWTB: ADEV wrapper: sampling frequency was calculated from time series')
    end
end

% structure DATA required by Hopcroft's scripts:
DATA.rate = fs;
% values must be in row vectors:
DATA.freq = datain.y.v(:);

if isfield(datain, 'tau')
    % user supplied own tau values
    TAU = datain.tau.v;
else
    % generate all tau values:
    % calculation of tau must be in this form, otherwise rounding errors can occur:
    TAU = [1/DATA.rate : 1/DATA.rate : length(DATA.freq)./DATA.rate./2];
end % if isempty

% Call algorithm ---------------------------  %<<<1
[RETVAL, S, ERRORB, TAU] = allan(DATA, TAU, '', 0);

% Format output data:  --------------------------- %<<<1
% to prevent negative zeros sometimes generated by Hopcroft's scripts:
RETVAL = RETVAL + 0;
dataout.adev.v = RETVAL;
% should calculate uncertainty only if CS.unc = 'guf'!!  XXX 2DO
dataout.adev.u = ERRORB;
dataout.tau.v = TAU;

end % function

% vim settings modeline: vim: foldmarker=%<<<,%>>> fdm=marker fen ft=octave textwidth=80 tabstop=4 shiftwidth=4

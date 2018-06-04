function dataout = alg_wrapper(datain, calcset)
% Part of QWTB. Wrapper script for algorithm TWM-HCRMS.
%
% See also qwtb
%
% Format input data --------------------------- %<<<1
    
    % Restore orientations of the input vectors to originals (before passing via QWTB)
    % This is critical for the correction data! 
    [datain,cfg] = qwtb_restore_twm_input_dims(datain,1);

    % try to obtain sampling rate from alternative input quantities [Hz]
    if isfield(datain, 'fs')
        fs = datain.fs.v;
    elseif isfield(datain, 'Ts')
        fs = 1/datain.Ts.v;
    else
        fs = 1/mean(diff(datain.t.v));
    end
    
    % obtain nominal frequency value:
    if isfield(datain,'nom_f')
        nom_f = datain.nom_f.v;
    else
        % default:
        nom_f = NaN; 
    end
    
    % obtain nominal rms value:
    if isfield(datain,'nom_rms')
        nom_rms = datain.nom_rms.v;
    else    
        % default:
        nom_rms = 230.0; 
    end
    
    % obtain calculation mode:
    if isfield(datain,'mode')
        mode = datain.mode.v;
    else
        % default: A class 61000-3-40 
        mode = 'A';
    end
    if mode ~= 'A' && mode ~= 'S'
        error(sprintf('Calculation mode ''%s'' not supported!',mode));
    end
    
    % obtain tresholds:
    if isfield(datain,'sag_tres')
        sag_tres = datain.sag_tres.v;
    else
        sag_tres = 90;
    end
    if isfield(datain,'swell_tres')
        swell_tres = datain.swell_tres.v;
    else
        swell_tres = 110;
    end
    if isfield(datain,'int_tres')
        int_tres = datain.int_tres.v;
    else
        int_tres = 10;
    end
    % obtain hysteresis:
    if isfield(datain,'hyst')
        hyst = datain.hyst.v;
    else
        hyst = 2;
    end
    
    % --- get ADC LSB value
    if isfield(datain,'lsb')
        % get LSB value directly
        lsb = datain.lsb.v;
    elseif isfield(datain,'adc_nrng') && isfield(datain,'adc_bits')
        % get LSB value estimate from nominal range and resolution
        lsb = 2*datain.adc_nrng.v*2^(-datain.adc_bits.v);    
    else
        error('FPNLSF, corrections: Correction data contain no information about ADC resolution+range or LSB value!');
    end
         
    if cfg.y_is_diff
        % Input data 'y' is differential: if it is not allowed, put error message here
        error('Differential input data ''y'' not allowed!');     
    end
    
    if cfg.is_multi
        % Input data 'y' contains more than one record: if it is not allowed, put error message here
        error('Multiple input records in ''y'' not allowed!'); 
    end
    
    % timestamp phase compensation state:
    do_plots = isfield(datain, 'plot') && ((isnumeric(datain.plot.v) && datain.plot.v) || (ischar(datain.plot.v) && strcmpi(datain.plot.v,'on')));
    
    if ~isfield(calcset,'dbg_plots')
        calcset.dbg_plots = 0;
    end        
    
    % Rebuild TWM style correction tables:
    % This is not necessary but the TWM style tables are more comfortable to use then raw correction matrices
    tab = qwtb_restore_correction_tables(datain,cfg);
    
    
    % --------------------------------------------------------------------
    % Start of the algorithm
    % --------------------------------------------------------------------
    
    % fix timebase error:
    tb_corr = (1 + datain.adc_freq.v);
    u_tb_corr = datain.adc_freq.u;
    fs = fs/tb_corr;
    
    % get signal:
    y = datain.y.v;
    
    % sample count:
    N = size(y,1);
    
    
    % --- apply gain corrections
    fprintf('Scaling signal...\n');
    
    % remove digitizer DC offset error:
    y = y - datain.adc_offset.v;
    
    % average dc over the signal:    
    w = blackmanharris(N,'periodic');
    w = w(:);
    dc = mean(w.*y)/mean(w);
    
    % remove DC temporarily from the signal:
    y = y - dc;   
       
        
    % get initial guess of main component frequency:
    if isnan(nom_f)
        % estimate nominal frequency of not defined explicitly:
        f0_est = PSFE(y,1/fs);
    else
        f0_est = nom_f;
    end
    
    % create virtual list of frequencies including the nominal freq.:
    fh(:,1) = [0 logspace(log10(1),log10(0.5*fs),999) f0_est];
    [fh,fid] = sort(fh);
    % index of the f0_estiamte component:
    fid = find(fid == numel(fh));
    
    % -- now we will evaluate corrections for all the virtual frequencies
    
    % get digitizer gain/phase correction (independent to amplitude): 
    ag = correction_interp_table(tab.adc_gain, [], fh);
    ap = correction_interp_table(tab.adc_phi, [], fh);   
    % combine tfers for all amplitudes to mean amplitude, expand uncertainty: 
    g         = nanmean(ag.gain,2);
    ag.u_gain = (max(ag.u_gain,[],2).^2/3 + max([max(ag.gain,[],2) - g,g - min(ag.gain,[],2)],[],2).^2/3).^0.5;
    ag.gain   = g; 
    p        = nanmean(ap.phi,2);
    ap.u_phi = (max(ap.u_phi,[],2).^2/3 + max([max(ap.phi,[],2) - p,p - min(ap.phi,[],2)],[],2).^2/3).^0.5;
    ap.phi   = p;
        
    % apply aperture effect:
    ta = datain.adc_aper.v;
    if abs(ta) > 1e-12 && datain.adc_aper_corr.v
        % calculate aperture gain/phase correction (for f0):
        ap_gain = (pi*ta*fh)./sin(pi*ta*fh);
        ap_phi  =  pi*ta*fh;
        ap_gain(isnan(ap_gain)) = 1.0; % DC fix
        % combine with ADC tfer:
        ag.gain = ag.gain.*ap_gain;
        ag.u_gain = ag.u_gain.*ap_gain;
        ap.phi = ap.phi + ap_phi;
    end
    
        
    if isempty(datain.tr_type.v)
        % no transducer defined - apply plain tfer:
                
        % get transducer tfer (independent of rms):
        trg = correction_interp_table(tab.tr_gain, [], fh);
        trp = correction_interp_table(tab.tr_phi, [], fh);
        % combine tfers for all rms levels to find the worst case uncertainty: 
        g          = nanmean(trg.gain,2);
        trg.u_gain = (max(trg.u_gain,[],2).^2/3 + max([max(trg.gain,[],2) - g,g - min(trg.gain,[],2)],[],2).^2/3).^0.5;
        trg.gain   = g; 
        trp       = nanmean(trp.phi,2);
        trp.u_phi = (max(trp.u_phi,[],2).^2/3 + max([nanmax(trp.phi,[],2) - p;p - nanmin(trp.phi,[],2)],[],2).^2/3).^0.5;
        trp.phi   = p;
                
    else 
        % tran. type defined:       
        
        % calculate transducer transfer + loading effect:
        An = ones(size(fh)); 
        [gain,phi,u_gain,u_phi] = correction_transducer_loading(tab,datain.tr_type.v,fh,[], An,0,0,0);
        
        % get transducer tfer (independent of rms):
        trg = correction_interp_table(tab.tr_gain, [], fh);
        trp = correction_interp_table(tab.tr_phi, [], fh);
        % combine tfers for all rms levels to find the worst case uncertainty: 
        trg.u_gain = (max(trg.u_gain,[],2).^2/3 + max([max(trg.gain,[],2) - gain,gain - min(trg.gain,[],2)],[],2).^2/3).^0.5;
        trg.gain   = gain; 
        trp.u_phi = (max(trp.u_phi,[],2).^2/3 + max([max(trp.phi,[],2) - phi,phi - min(trp.phi,[],2)],[],2).^2/3).^0.5;
        trp.phi   = phi;
               
    end
    
    % combine gain/phase:
    trg.gain = trg.gain.*ag.gain;
    trg.u_gain = ((trg.u_gain.*ag.gain).^2 + (ag.u_gain.*trg.gain).^2).^0.5;
    trp.phi = trp.phi + ap.phi;
    trp.u_phi = (trp.u_phi.^2 + ap.u_phi.^2).^0.5;
        
    % --  apply the tfer:
    % note: apply only tfer based on the f0 component
    
    % get tfer for the f0_estimate:
    f0_gain = trg.gain(fid);
    f0_gain_u = trg.u_gain(fid);
    f0_phi = trp.phi(fid);
    f0_phi_u = trp.u_phi(fid);
            
    % apply gain tfer:
    y = y*f0_gain;
    
    % get dc gain:
    dc_gain = trg.gain(1);
    
    % apply dc gain and return DC offset back to the signal:
    y = y + dc*dc_gain;
    
    
    % time shift due to the signal path correction:
    dt_corr   = f0_phi/2/pi/f0_est;
    u_dt_corr = f0_phi_u/2/pi/f0_est;
    
    % time stamp of first sample:
    ts = dt_corr + datain.time_stamp.v*tb_corr;
    u_ts = u_dt_corr + datain.time_stamp.u*tb_corr;
          
    % calculate relative gain of frequency components to the f0 gain:
    gain = trg.gain/f0_gain;
    gain_u = trg.u_gain/f0_gain;
    gain_u = (gain_u.^2 + f0_gain_u^2).^0.5;
    
    
    % get combined SFDR of digitizer and transducer:
    adc_sfdr = correction_interp_table(tab.adc_sfdr, [], f0_est);
    tr_sfdr  = correction_interp_table(tab.tr_sfdr, [], f0_est);    
    adc_sfdr = max(adc_sfdr.sfdr);
    tr_sfdr = max(tr_sfdr.sfdr);    
    sfdr = -20*log10(10^-(adc_sfdr/20) + 10^-(tr_sfdr/20));
            
      
    cfg.f0_est = f0_est;
    cfg.nom_f = nom_f;
    cfg.nom_rms = nom_rms;
    cfg.mode = mode;
    cfg.do_plots = do_plots;    
    cfg.ev.hyst = hyst;
    cfg.ev.sag_tres = sag_tres;
    cfg.ev.swell_tres = swell_tres;
    cfg.ev.int_tres = int_tres;
    cfg.corr.gain.f = fh;
    cfg.corr.gain.gain = gain;
    cfg.corr.gain.unc = u_gain;
    cfg.corr.sfdr = sfdr;
        
    % generate empty results:
    dataout = struct();

    % calculate rms envelope, detect events:    
    [t,u_t,rms,u_rms,dataout] = hcrms_calc_pq(dataout,ts,u_ts,fs,y,cfg,calcset);
    
    % apply time scale uncertainty to the correction data:
    u_tb_corr = t*u_tb_corr*loc2covg(calcset.loc,50);       
    dataout.t.u = (dataout.t.u.^2 + u_tb_corr.^2).^0.5;
    
    % apply time scale uncertainty to the event times:
    dataout.sag_start.u = dataout.sag_start.u + interp1(t,u_tb_corr,dataout.sag_start.v,'linear','extrap');
    dataout.sag_dur.u   = dataout.sag_dur.u   + interp1(t,u_tb_corr,dataout.sag_start.v + 0.5*dataout.sag_dur.v,'linear','extrap');
    dataout.swell_start.u = dataout.swell_start.u + interp1(t,u_tb_corr,dataout.swell_start.v,'linear','extrap');
    dataout.swell_dur.u   = dataout.swell_dur.u   + interp1(t,u_tb_corr,dataout.swell_start.v + 0.5*dataout.swell_dur.v,'linear','extrap');
    dataout.int_start.u = dataout.int_start.u + interp1(t,u_tb_corr,dataout.int_start.v,'linear','extrap');
    dataout.int_dur.u   = dataout.int_dur.u   + interp1(t,u_tb_corr,dataout.int_start.v + 0.5*dataout.int_dur.v,'linear','extrap');
    
           
    
    % --- returning results ---    
    
           
    % --------------------------------------------------------------------
    % End of the algorithm.
    % --------------------------------------------------------------------


end % function



% vim settings modeline: vim: foldmarker=%<<<,%>>> fdm=marker fen ft=octave textwidth=80 tabstop=4 shiftwidth=4
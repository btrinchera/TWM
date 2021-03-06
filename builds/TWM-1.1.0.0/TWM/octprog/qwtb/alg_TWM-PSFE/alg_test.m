function alg_test(calcset) %<<<1
% Part of QWTB. Test script for algorithm TWM-PSFE.
%
% See also qwtb

    % samples count to synthesize:
    N = 1e5;
    
    % sampling rate [Hz]
    din.fs.v = 10000;
    
    % randomize uncertainties:
    rand_unc = 1;
    
    % harmonic amplitudes:
    A =    [1       0.1  0.02]';
    % harmonic phases:
    ph =   [0.1/pi -0.8  0.2]'*pi;
    % harmonic component index {1st, 2rd, ..., floor(N/2)}:
    fk =   [1000   5000  round(0.4*N)]';
    
    % current loop impedance (used for simulation of differential transducer):
    Zx = 0.1;
    
    % non-zero to generate differential input signal:
    is_diff = 0;
    
    % noise level:
    adc_std_noise = 0;
        
    
    
        
    
    % ADC aperture [s]:
    % note: non-zero value will simulate aperture gain/phase error 
    din.adc_aper.v = 20e-6;
    
    % ADC aperture correction enabled:
    % note: non-zero value will enable correction of the gain/phase error by alg.
    din.adc_aper_corr.v = 1;
    
    
    % generate some time-stamp of the digitizer channel:
    % note: the algorithm must 'unroll' the calculated phase accordingly,
    %       so whatever is put here should have no effect to the estimated phase         
    din.time_stamp.v = rand(1)*0.001; % random time-stamp
    
    % timestamp compensation:
    din.comp_timestamp.v = 1;
        
    % create some corretion table for the digitizer gain: 
    din.adc_gain_f.v = [0;1e3;1e6];
    din.adc_gain_a.v = [];
    din.adc_gain.v = [1.000; 1.100; 1.500];
    din.adc_gain.u = [0.001; 0.002; 0.003]*0.01; 
    % create some corretion table for the digitizer phase: 
    din.adc_phi_f.v = [0;1e3;1e6];
    din.adc_phi_a.v = [];
    din.adc_phi.v = [0.000; 0.100; 0.500]*pi;
    din.adc_phi.u = [0.001; 0.002; 0.005]*pi*0.01;
    % create corretion of the digitizer timebase:
    din.adc_freq.v = 0.001;
    din.adc_freq.u = 0.000005;
    
    
    % transducer type ('rvd' or 'shunt')
    din.tr_type.v = 'rvd';
        
    % create some corretion table for the transducer gain: 
    din.tr_gain_f.v = [0;1e3;1e6];
    din.tr_gain_a.v = [];
    din.tr_gain.v = [1.000; 0.800; 0.600]*5;
    din.tr_gain.u = [0.001; 0.002; 0.005]*0.01; 
    % create some corretion table for the transducer phase: 
    din.tr_phi_f.v = [0;1e3;1e6];
    din.tr_phi_a.v = [];
    din.tr_phi.v = [0.000; -0.200; -0.500]*pi;
    din.tr_phi.u = [0.001;  0.002;  0.005]*pi*0.01;
        
    % RVD low-side impedance:
    din.tr_Zlo_f.v = [];
    din.tr_Zlo_Rp.v = [200.00];
    din.tr_Zlo_Rp.u = [  0.05];
    din.tr_Zlo_Cp.v = [1e-12];
    din.tr_Zlo_Cp.u = [1e-12];
    
    
    % remember original input quantities:
    datain = din; 
    % Restore orientations of the input vectors to originals (before passing via QWTB)
    din.y.v = ones(10,1); % fake data vector just to make following function work!
    if is_diff, din.y_lo.v = din.y.v; end
    [din,cfg] = qwtb_restore_twm_input_dims(din,1);
    % Rebuild TWM style correction tables (just for more convenient calculations):
    tab = qwtb_restore_correction_tables(din,cfg);
    
    % calculate actual frequencies of the harmonics:
    fx = fk/N*din.fs.v;
    
    
    % apply transducer transfer:
    if rand_unc
        rand_str = 'rand';
    else
        rand_str = '';
    end
    A_syn = [];
    ph_syn = [];
    sctab = {};
    tsh = [];
    if is_diff
        % -- differential connection:
        [A_syn(:,1),ph_syn(:,1),A_syn(:,2),ph_syn(:,2)] = correction_transducer_sim(tab,din.tr_type.v,fx, A,ph,0*A,0*ph,rand_str,Zx);
        % subchannel correction tables:
        sctab{1}.adc_gain = tab.adc_gain;
        sctab{1}.adc_phi  = tab.adc_phi;
        sctab{2}.adc_gain = tab.lo_adc_gain;
        sctab{2}.adc_phi  = tab.lo_adc_phi;
        % subchannel timeshift:
        tsh(1) = 0; % high-side channel
        tsh(2) = din.time_shift_lo.v; % low-side channel
    else
        % -- single-ended connection:
        [A_syn(:,1),ph_syn(:,1)] = correction_transducer_sim(tab,din.tr_type.v,fx, A,ph,0*A,0*ph,rand_str);
        % subchannel correction tables:
        sctab{1}.adc_gain = tab.adc_gain;
        sctab{1}.adc_phi  = tab.adc_phi;
        % subchannel timeshift:
        tsh(1) = 0; % none for single-ended mode
    end
    
    % apply ADC aperture error:
    if din.adc_aper_corr.v && din.adc_aper.v > 1e-12
        % get ADC aperture value [s]:
        ta = abs(din.adc_aper.v);
    
        % calculate aperture gain/phase correction:
        ap_gain = sin(pi*ta*fx)./(pi*ta*fx);
        ap_phi  = -pi*ta*fx;        
        % apply it to subchannels:
        A_syn  = bsxfun(@times,ap_gain,A_syn);
        ph_syn = bsxfun(@plus, ap_phi, ph_syn);
    end
        
    % for each transducer subchannel:
    for c = 1:numel(sctab)
    
        % interpolate digitizer gain/phase to the measured frequencies and amplitudes:
        k_gain = correction_interp_table(sctab{c}.adc_gain,A_syn(:,c),fx,'f',1);    
        k_phi =  correction_interp_table(sctab{c}.adc_phi, A_syn(:,c),fx,'f',1);
        
        % apply digitizer gain:
        Ac  = A_syn(:,c)./k_gain.gain;
        phc = ph_syn(:,c) - k_phi.phi;
        
        % randomize ADC gain:
        if rand_unc
            Ac  = Ac.*(1 + k_gain.u_gain.*randn(size(Ac)));
            phc = phc + k_phi.u_phi.*randn(size(phc));
        end
        
        % generate relative time 2*pi*t:
        % note: include time-shift and timestamp delay and frequency error:        
        tstmp = din.time_stamp.v;       
        t = [];
        t(:,1) = ([0:N-1]/din.fs.v + tsh(c) + tstmp)*(1 + din.adc_freq.v)*2*pi;
        
        % synthesize waveform (crippled for Matlab < 2016b):
        % u = Ac.*sin(t.*fx + phc);
        u = bsxfun(@times, Ac', sin(bsxfun(@plus, bsxfun(@times, t, fx'), phc')));
        % sum the harmonic components to a single composite signal:
        u = sum(u,2);
        
        % add some noise:
        u = u + randn(N,1)*adc_std_noise;

        % store to the QWTB input list:
        datain = setfield(datain, cfg.ysub{c}, struct('v',u));
    
    end
        

    % --- execute the algorithm:
    calcset.unc = 'none';
    dout = qwtb('TWM-PSFE',datain,calcset);
    
    % get reference values:
    f0  = fx(1);
    Ar  = A(1);
    phr = ph(1);    
    
    % get calculated values and uncertainties:
    fx  = dout.f.v;
    Ax  = dout.A.v;
    phx = dout.phi.v;
    u_fx  = dout.f.u*2;
    u_Ax  = dout.A.u*2;
    u_phx = dout.phi.u*2;
    if ~rand_unc
        u_fx  = f0*1e-8;
        u_Ax  = Ar*1e-6;
        u_phx = 1e-6;
    end
    
    
    % print results:
    ref_list =  [f0, Ar, phr];    
    dut_list =  [fx, Ax, phx];
    unc_list =  [u_fx, u_Ax, u_phx];
    name_list = {'f','A','ph'};
    
    fprintf('   |     REF     |     DUT     |   ABS DEV   |  %%-DEV   |     UNC     |  %%-UNC \n');
    fprintf('---+-------------+-------------+-------------+----------+-------------+----------\n');
    for k = 1:numel(ref_list)
        
        ref = ref_list(k);
        dut = dut_list(k);
        unc = unc_list(k);
        name = name_list{k};
        
        fprintf('%-2s | %11.6f | %11.6f | %+11.6f | %+8.4f | %+11.6f | %5.0f\n',name,ref,dut,dut - ref,100*(dut - ref)/ref,unc,100*abs(dut - ref)/unc);
        
    end   
    
        
    % check frequency estimate:
    assert(abs(fx - f0) < u_fx, 'Estimated freq. does not match generated one.');
    
    if ~is_diff
    
        % check amplitude match     
        assert(abs(Ax - Ar) < u_Ax, 'Estimated amplitude does not match generated one.');
        
        % check phase match     
        assert(abs(phx - phr) < u_phx, 'Estimated phase does not match generated one.'); 
    end                                                     
    
end
   
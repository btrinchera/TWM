function alginfo = alg_info() %<<<1
% Part of QWTB. Info script for algorithm TWM-VALIDi1.
%
% See also qwtb

    alginfo.id = 'TWM-VALID';
    alginfo.name = 'Validation script for the TWM tool';
    alginfo.desc = 'Part of TWM self-test. Tests correctness of the passed parameters.';
    alginfo.citation = '';
    alginfo.remarks = '';
    alginfo.license = '';
    
  
    pid = 1;    
    % --- user parameters:
    % DFT bin to extract:
    alginfo.inputs(pid).name = 'scalar';
    alginfo.inputs(pid).desc = 'Real scalar';
    alginfo.inputs(pid).alternative = 0;
    alginfo.inputs(pid).optional = 0;
    alginfo.inputs(pid).parameter = 1;
    pid = pid + 1;
    
    alginfo.inputs(pid).name = 'vector';
    alginfo.inputs(pid).desc = 'Real vector';
    alginfo.inputs(pid).alternative = 0;
    alginfo.inputs(pid).optional = 0;
    alginfo.inputs(pid).parameter = 1;
    pid = pid + 1;
    
    alginfo.inputs(pid).name = 'matrix';
    alginfo.inputs(pid).desc = 'Real matrix';
    alginfo.inputs(pid).alternative = 0;
    alginfo.inputs(pid).optional = 0;
    alginfo.inputs(pid).parameter = 1;
    pid = pid + 1;
    
    alginfo.inputs(pid).name = 'string';
    alginfo.inputs(pid).desc = 'String of chars';
    alginfo.inputs(pid).alternative = 0;
    alginfo.inputs(pid).optional = 0;
    alginfo.inputs(pid).parameter = 1;
    pid = pid + 1;
    
    
    % --- flags:
    % note: presence of these parameters signalizes caller capabilities of the algoirthm
     
    alginfo.inputs(pid).name = 'support_diff';
    alginfo.inputs(pid).desc = 'Algorithm supports differential input data';
    alginfo.inputs(pid).alternative = 0;
    alginfo.inputs(pid).optional = 1;
    alginfo.inputs(pid).parameter = 0;
    pid = pid + 1;
    
    alginfo.inputs(pid).name = 'support_multi_inputs';
    alginfo.inputs(pid).desc = 'Algorithm supports processing of a multiple waveforms at once';
    alginfo.inputs(pid).alternative = 0;
    alginfo.inputs(pid).optional = 1;
    alginfo.inputs(pid).parameter = 0;
    pid = pid + 1;
    
    
    % list of parameters generated by TWM selftest function:
    global twm_selftest_control;
    
    
    
    % sample data
    alginfo.inputs(pid).name = 'fs';
    alginfo.inputs(pid).desc = 'Sampling frequency';
    alginfo.inputs(pid).alternative = 1;
    alginfo.inputs(pid).optional = 0;
    alginfo.inputs(pid).parameter = 0;
    pid = pid + 1;
    
    alginfo.inputs(pid).name = 'Ts';
    alginfo.inputs(pid).desc = 'Sampling time';
    alginfo.inputs(pid).alternative = 1;
    alginfo.inputs(pid).optional = 0;
    alginfo.inputs(pid).parameter = 0;
    pid = pid + 1;
    
    alginfo.inputs(pid).name = 't';
    alginfo.inputs(pid).desc = 'Time series';
    alginfo.inputs(pid).alternative = 1;
    alginfo.inputs(pid).optional = 0;
    alginfo.inputs(pid).parameter = 0;
    pid = pid + 1;
    
    % --- generate dynamic parameters:
    for k = 1:numel(twm_selftest_control.raw)
        if twm_selftest_control.raw{k}.auto_pass
            alginfo.inputs(pid).name = twm_selftest_control.raw{k}.name;
            alginfo.inputs(pid).desc = twm_selftest_control.raw{k}.desc;
            alginfo.inputs(pid).alternative = 0;
            alginfo.inputs(pid).optional = 0;
            alginfo.inputs(pid).parameter = twm_selftest_control.raw{k}.is_par;
            pid = pid + 1;
        end
    
    end
    for k = 1:numel(twm_selftest_control.t2d)         
        rec = twm_selftest_control.t2d{k};
        if rec.auto_pass        
            for q = 1:numel(rec.qu)
                if strcmpi(rec.qu{q}.sub,'v')
                    alginfo.inputs(pid).name = rec.qu{q}.name;
                    alginfo.inputs(pid).desc = rec.qu{q}.desc;
                    alginfo.inputs(pid).alternative = 0;
                    alginfo.inputs(pid).optional = 0;
                    alginfo.inputs(pid).parameter = 0;
                    pid = pid + 1;
                end
            end
        end
    end
    
    
    
    % --- outputs:
    pid = 1;
    % fixed special quantities:
    alginfo.outputs(pid).name = 'fs';
    alginfo.outputs(pid).desc = 'Sampling frequency';
    pid = pid + 1;
    
    % --- generate copy of all TWM input quantities:
    for k = 1:numel(twm_selftest_control.raw)    
        if twm_selftest_control.raw{k}.auto_pass
            alginfo.outputs(pid).name = twm_selftest_control.raw{k}.name;
            alginfo.outputs(pid).desc = twm_selftest_control.raw{k}.desc;
            pid = pid + 1;
        end    
    end
    for k = 1:numel(twm_selftest_control.t2d)
        rec = twm_selftest_control.t2d{k};
        if rec.auto_pass        
            for q = 1:numel(rec.qu)
                if strcmpi(rec.qu{q}.sub,'v')
                    alginfo.outputs(pid).name = rec.qu{q}.name;
                    alginfo.outputs(pid).desc = rec.qu{q}.desc;
                    pid = pid + 1;
                end
            end
        end
    end
    
    alginfo.providesGUF = 1;
    alginfo.providesMCM = 1;

end

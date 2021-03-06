%% -----------------------------------------------------------------------------
%% TracePQM: Loads record(s) from given path to memory.
%%
%% Inputs:
%%   header - absolute path to the measurement header file
%%   group_id - id of the measurement group (optional)
%%            - each measurement can contain multiple measurement groups with
%%              repeated measurements with identical setup. This parameter 
%%              selects the group.
%%            - note the value -1 means to load last group
%%   repetition_id - id of the measurement in the group (optional)
%%                 - note this parameter may be zero, then the loader
%%                   will load all repetitions in the group and merge them in
%%                   the single 2D matrix
%% 
%% Outputs:
%%   data - structure of results containing:
%%     data.groups_count - count of the measurement groups in the header
%%     data.repetitions_count - number of repetitions in the group
%%     data.channels_count - number of digitizer channels
%%     data.is_temperature - measurement has temperature measured
%%     data.sample_count - count of the samples per channel in the record
%%     data.y - 2D matrix of sample data, one column per channel
%%            - note if multiple repetition cycles are loaded, they are merged
%%              by columns, so the order will be [ch1,ch2,ch1,ch2,ch1,ch2,...]
%%     data.timestamp - relative timestamps in [s], row vector, one per channel
%%                    - note for multiple repet. they are merged as data.y
%%     data.Ts - sampling period [s]
%%     data.t - time vector [s], column vector 
%%     data.corr - structure of correction data containing:
%%       corr.phase_indexes - phase ID of each digitizer channel
%%                          - used to assign U and I channels to phases
%%       corr.tran - cell array of transducers containing:
%%         tran.type - string defining transducer type 'shunt', 'divider' 
%%         tran.name - string with transducer's name
%%         tran.sn - string with transducer's serial
%%         tran.nominal - transducer's nominal ratio (Ohms or Vin/Vout)
%%
%% Note the corrections are FAR from being done!!!! Just the phase indexes 
%% works now.
%% -----------------------------------------------------------------------------
function [data] = tpq_load_record(header, group_id, repetition_id);

  if nargin < 3
    % load last average cycle is not defined
    repetition_id = -1;
  end
  
  if nargin < 2
    % load last group if not defined 
    group_id = -1;
  end
  
  % try to load header file 
  inf = infoload(header);
     
  % get total groups count in the header file 
  data.groups_count = infogetnumber(inf,'groups count');
  
  if group_id < 1
    % select last available group if not speficified explicitly
    group_id = data.groups_count;
  end
  
  if group_id > data.groups_count
    error(sprintf('Measurement group #%d is out of range of available groups in the header!',group_id));
  end
  
  % fetch header section with desired group
  ginf = infogetsection(inf, sprintf('measurement group %d', group_id));
    
  % get available averages count in the group
  data.repetitions_count = infogetnumber(ginf, 'repetitions count');
  
  if repetition_id < 0
    % select last record in the average group
    repetition_id = data.repetitions_count;
  end
  
  if repetition_id > data.repetitions_count
    error(sprintf('Average cycle #%d is out of range of available records in the header!',repetition_id));
  end
  
  
  % get sample data format descriptor
  data_format = infogettext(inf, 'sample data format');
  
  if ~strcmpi(data_format,'mat-v4')
    error(sprintf('Format \"%s\" not supported!',data_format));
  end
  
  % get the data variable name 
  data_var_name = infogettext(inf, 'sample data variable name');
  
  % get channels count 
  data.channels_count = infogetnumber(inf, 'channels count');
  
  % is temperature available? 
  data.is_temperature = infogetnumber(inf, 'temperature available') > 0;
  
  
  
  % ====== GROUP SECTION ======
  
  % get preset sample counts
  data.sample_count = infogetnumber(ginf, 'samples count');
    
  % get measurement root folder
  meas_folder = fileparts(header);
  
  % get record file names
  record_names = infogetmatrixstr(ginf, 'record sample data files');
  
  % sample counts for each record in the average group
  sample_counts = infogetmatrix(ginf, 'record samples counts');
  
  % Ts for each record in the average group
  time_incerements = infogetmatrix(ginf, 'record time increments [s]');
  
  % record data gain for each record in the average group
  sample_gains = infogetmatrix(ginf, 'record sample data gains [V]');
  
  % record data offsets for each record in the average group
  sample_offsets = infogetmatrix(ginf, 'record sample data offsets [V]');
  
  % relative timestamps for each record in the average group
  relative_timestamps = infogetmatrix(ginf, 'record relative timestamps [s]');
  
  if data.is_temperature
    % relative timestamps for each record in the average group
    temperatures = infogetmatrix(ginf, 'record channel temperatures [deg C]');
  end
  
  
  % build list of average cycles to load
  if repetition_id
    ids = repetition_id;
  else
    ids = [1:data.repetitions_count];
  end
    
  if repetition_id && any(sample_counts(ids) ~= sample_counts(ids(1)))
    error('Sample counts in one of the loaded records does not match!');
  end
  
  % override samples count by actual samples count in the selected record
  data.sample_count = sample_counts(ids(1));
   
  % allocate sample data array
  data.y = zeros(data.sample_count, data.channels_count*numel(ids));

  % ====== FETCH SAMPLE DATA ====== 
  for r = 1:numel(ids)
  
    % sample data file path
    sample_data_file = [meas_folder filesep() record_names{ids(r)}];
    
    % store record file name
    [fld, data.record_filenames{r}] = fileparts(sample_data_file);
       
    
    if strcmpi(data_format,'mat-v4')      
      % load sample binary data
      smpl = load('-v4',sample_data_file,data_var_name);
      
      % store it into output array
      data.y(:,1 + (r-1)*data.channels_count:r*data.channels_count) = sample_offsets(ids(r),:) + sample_gains(ids(r),:).*getfield(smpl,data_var_name).';    
    end
  
  end
  
  % return relataive timestamps as 2D matrix (average cycle, channel) 
  data.timestamp = [relative_timestamps(ids)];
  
  % return sampling period
  data.Ts = mean(time_incerements(ids));
  
  % return time vector
  data.t(:,1) = [0:data.sample_count-1]*data.Ts;
  
  
  
  % ====== CORRECTIONS SECTION ======
  
  % load corrections section from meas. header
  cinf = infogetsection(inf, 'corrections');
  
  % get phase index for each channel
  corr.phase_idx = infogetmatrix(cinf, 'channel phase indexes');
   
  % get transducer paths
  transducer_paths = infogetmatrixstr(cinf, 'transducer paths');
  
  if numel(corr.phase_idx) && (numel(corr.phase_idx) ~= data.channels_count || numel(transducer_paths) ~= data.channels_count)
    error('Transducers count does not match channel count!');
  end
  
  % load tranducer correction files
  tran = {struct()};
  if numel(transducer_paths)
    for t = 1:numel(transducer_paths)
      
      % build absolute transducer correction path
      t_file = [meas_folder filesep() transducer_paths{t}];
      
      % try to load the correction
      tran{t} = correction_load_transducer(t_file);
      
    end
    corr.tran = tran;
  else
    % no transducers defined - fake some
    for t = 1:data.channels_count
      % fake phase order
      corr.phase_idx(t) = t;
      % fake some transducer data
      corr.tran{t}.type = 'divider';
      corr.tran{t}.name = 'dummy divider';
      corr.tran{t}.sn = 'n/a';
      corr.tran{t}.nominal = 1.0;
    end
    
  end

  % get digitizer path
  digitizer_path = infogettext(cinf, 'digitizer path');
  
  % TODO: digitizer loader
  
  %sinf = infogetsection(inf, 'corrections');  
  %cor_name = infogettext(sinf, 'digitizer path');  
  %cor_path = [records_folder filesep() cor_name];  
  %cinf = infoload(cor_path);
  %correction_parse_section(fileparts(cor_path), cinf, inf, 'interchannel timeshift',2)
    
  
  % return corrections
  data.corr = corr;
    
  
  

end
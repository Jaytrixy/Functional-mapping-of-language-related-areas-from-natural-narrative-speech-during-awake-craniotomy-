%% Recording data from Brain vision Recorder and Save to files
function Simtan_Record(SubName,duration)
% global definitions of controls for easy use in other functions
%  PsychPortAudio('Close')
if nargin<1
    SubName = 'test';
end
finish = false;
%% serial port
config_io;
%% prepare sound recording
InitializePsychSound(1);
PsychPortAudio('Verbosity', 4);
freq = 44100;
pahandlein = PsychPortAudio('Open', [], 2, 2, freq, 2, [], 0);
PsychPortAudio('GetAudioData', pahandlein, 10);

button = questdlg('Connect to the RDA of BP recording system?','Setup Connection','Connect','Cancel','Connect');
if strcmp(button,'Connect')
    OpenConnection(SubName,duration);
else
    disp('Abondoned.');
    CloseConnection;
    return;
end

%% Connection opening
    function OpenConnection(SubName,duration)
        WaitSecs(1);
        recorderip = 'localhost';
        
        % Establish connection to BrainVision Recorder Software 32Bit RDA-Port
        % (use 51234 to connect with 16Bit Port)
        con=pnet('tcpconnect', recorderip, 51244);
        
        % Check established connection and display a message
        stat=pnet(con,'status');
        if stat > 0
            disp('connection established');
        else
            error('?')
        end
    %% --- Main reading loop ---
       h = waitbar(0,'0','Name','Recording Data',...
            'CreateCancelBtn',...
            'setappdata(gcbf,''canceling'',1)');
        setappdata(h,'canceling',0);
        RecordData = struct('blockID',[],'data',[],'Markers',[],'Audio',[],'Audio_starttime',[]);
        TimeTag = [];
        try
            while ~finish
                % check for existing data in socket buffer
                tryheader = pnet(con, 'read',24, 'byte', 'network', 'view', 'noblock');
                while ~isempty(tryheader)
                    % Read header of RDA message
                    hdr = ReadHeader(con);
                    
                    % Perform some action depending of the type of the data package
                    switch hdr.type
                        case 1       
                            % Start, Setup information like EEG properties
                            disp('Start');
                            % Read and display EEG properties
                            props = ReadStartMessage(con, hdr);
                            % Reset block counter to check overflows
                            lastBlock = -1;
                            % set data buffer to empty
                            PsychPortAudio('Start', pahandlein, 0, 0, 1);
                        case 4       % 32Bit Data block
                            % Read data and markers from message
                            [datahdr, data, markers] = ReadDataMessage(con, props);
                            % check tcpip buffer overflow
                            if lastBlock == -1 && datahdr.block ~= lastBlock
                                startBlock = datahdr.block;
                            elseif lastBlock ~= -1 &&  datahdr.block > lastBlock + 1
                                disp(['******* Overflow with ' int2str(data_info(1)  - lastBlock) ' blocks ******',int2str(data_info(1)),' - ' ,int2str(lastBlock)]);
                            end
                            lastBlock = datahdr.block ;
                            
                            if double(lastBlock-startBlock)>=3000*duration || getappdata(h,'canceling')
                                disp('pass');
                                finish = 1;
                                delete(h);
                                disp('Recording finished');
                                RecordData(1)=[];
                                save([pwd,'/',SubName],'RecordData','TimeTag')
                                break;
                            end
                            
                            waitbar(double(datahdr.block-startBlock)/(60*50*duration),h,...
                                sprintf('%1.0f seconds',double(datahdr.block-startBlock)/50));
                            RecordData(length(RecordData)+1).blockID = datahdr.block;
                            RecordData(end).data = data;
                            RecordData(end).Markers = markers;
                            [RecordData(end).Audio, ~,~,RecordData(end).Audio_starttime] = PsychPortAudio('GetAudioData', pahandlein);
                           
                            if rem(lastBlock-startBlock,3000) == 0 && (lastBlock-startBlock)/3000>0
                                sendsignal(round((lastBlock-startBlock)/3000));
                                TimeTag = [TimeTag; (double(lastBlock-startBlock))/3000,GetSecs];
                            end
                            
                        case 3       % Stop message
                            pnet(con, 'read', hdr.size - 24);
                            delete(h);
                            disp('Recording somehow stopped');
                            RecordData(1)=[];
                            save([pwd,SubName],'RecordData','TimeTag');
                            break;
                        otherwise    % ignore all unknown types, but read the package from buffer
                            pnet(con, 'read', hdr.size - 24);
                    end % switch hdr.type
                    WaitSecs(.01);
                    tryheader = pnet(con, 'read',24, 'byte', 'network', 'view', 'noblock');
                end
            end
            CloseConnection( );
        catch
            CloseConnection( );
            error('sorry for this')
        end  
    end

%% ********************************************************************
% Close function
    function CloseConnection()
        % Close all open socket connections
        pnet('closeall');
        PsychPortAudio('Close',pahandlein)
        % Display a message
        disp('connection closed');
        clear mex;
        set(groot,'ShowHiddenHandles','on')
        delete(get(groot,'Children'))
    end
%% ***********************************************************************
% Read the message header
    function hdr = ReadHeader(con)
        % con    tcpip connection object
        
        % define a struct for the header
        hdr = struct('uid',[],'size',[],'type',[]);
        
        % read id, size and type of the message
        % swapbytes is important for correct byte order of MATLAB variables
        % pnet behaves somehow strange with byte order option
        hdr.uid = pnet(con,'read', 16);
        hdr.size = swapbytes(pnet(con,'read', 1, 'uint32', 'network'));
        hdr.type = swapbytes(pnet(con,'read', 1, 'uint32', 'network'));
    end

%% ***********************************************************************
% Read the start message
    function props = ReadStartMessage(con, hdr)
        % con    tcpip connection object
        % hdr    message header
        % props  returned eeg pyroperties
        
        % define a struct for the EEG properties
        props = struct('channelCount',[],'samplingInterval',[],'resolutions',[],'channelNames',[]);
        
        % read EEG properties
        props.channelCount = swapbytes(pnet(con,'read', 1, 'uint32', 'network'));
        props.samplingInterval = swapbytes(pnet(con,'read', 1, 'double', 'network'));
        props.resolutions = swapbytes(pnet(con,'read', props.channelCount, 'double', 'network'));
        allChannelNames = pnet(con,'read', hdr.size - 36 - props.channelCount * 8);
        props.channelNames = [];
    end

%% ***********************************************************************
% Read a data message
    function [datahdr, data, markers] = ReadDataMessage(con, props)
        % con       tcpip connection object
        % hdr       message header
        % datahdr   data header with information on datalength and number of markers
        % data      data as one dimensional arry
        % markers   markers as array of marker structs
        
        
        % Define data header struct and read data header
        datahdr = struct('block',[],'points',[],'markerCount',[]);
        
        datahdr.block = swapbytes(pnet(con,'read', 1, 'uint32', 'network'));
        datahdr.points = swapbytes(pnet(con,'read', 1, 'uint32', 'network'));
        datahdr.markerCount = swapbytes(pnet(con,'read', 1, 'uint32', 'network'));
        
        % Read data in float format
        data = swapbytes(pnet(con,'read', props.channelCount * datahdr.points, 'single', 'network'));
        
        % Define markers struct and read markers
        markers = struct('size',[],'position',[],'points',[],'channel',[],'type',[],'description',[]);
        for m = 1:datahdr.markerCount
            marker = struct('size',[],'position',[],'points',[],'channel',[],'type',[],'description',[]);
            
            % Read integer information of markers
            marker.size = swapbytes(pnet(con,'read', 1, 'uint32', 'network'));
            marker.position = swapbytes(pnet(con,'read', 1, 'uint32', 'network'));
            marker.points = swapbytes(pnet(con,'read', 1, 'uint32', 'network'));
            marker.channel = swapbytes(pnet(con,'read', 1, 'int32', 'network'));
            
            % type and description of markers are zero-terminated char arrays
            % of unknown length
            c = pnet(con,'read', 1);
            while c ~= 0
                marker.type = [marker.type c];
                c = pnet(con,'read', 1);
            end
            
            c = pnet(con,'read', 1);
            while c ~= 0
                marker.description = [marker.description c];
                c = pnet(con,'read', 1);
            end
            
            % Add marker to array
            markers(m) = marker;
        end
    end

%% ***********************************************************************
%Send signal to serial port
    function sendsignal(marker_signal)
        outp(888,marker_signal);
        pause(0.001);
        outp(888,0);
    end

end

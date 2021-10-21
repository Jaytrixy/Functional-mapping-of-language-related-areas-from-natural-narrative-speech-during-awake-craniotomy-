clear
close all
[file,path] = uigetfile('.mat','Choose Data file.');
% load ('E:\ECoG\offline_processing/RF_Move.mat');
tic;
load([path,file]);
EEG = zeros(64,length(RecordData)*50);
Markers = cell(0);
h = waitbar(0,'loading data...');
fid  =  fopen('temp.aud','w');
%% Reconstruct Data

for sN = 1:length(RecordData)
EEG(:,sN*50-49 : sN*50) = reshape(RecordData(sN).data,[64 50]);
if ~isempty(RecordData(sN).Markers(1).size)
    Markers(end+1,:) = {RecordData(sN).Markers,sN};
end
if ~isempty(RecordData(sN).Audio)
    fwrite(fid,RecordData(sN).Audio(1,:),'double');
end
waitbar(sN/length(RecordData),h);
end
fclose(fid);
fid  =  fopen('temp.aud','r')
audio = fread(fid,[1,length(RecordData)/50*44100],'double');
fclose(fid);
delete (h);
delete('temp.aud');
toc
%% processes audio data
tic
audio_res = resample(audio,40,441);
% outliers = find((abs(zscore(audio_res)))>=15);
% for oN = 1:length(outliers)
%     audio_res((outliers(oN)+[-800:3000]))=rand(3801,1)*std(audio_res)/4;
% end

bp2 = fir1(floor(0.22*4000),[20 1900]/(4000/2));
audio_F = filter(bp2,1,audio_res);
seg = buffer(zscore(audio_F),800,760,'nodelay');
env = rms(seg); % 100 Hz samplng rate, with start point at 800/4000 = 200ms 
env = [zeros(1,10),env];
env = double(env>1);
env = smooth(env,40);

%% processes ECoG

choosen_channels = inputdlg('Active Channels','Input',1,{'1:64'});
activeChannels = str2num(choosen_channels{1});
EEG = EEG(activeChannels,:);
chN = size(EEG,1);
pntN = size(EEG,2);
% fre = 60:2:90;
EEG_sr=2500;
EEG = EEG*.5; %% resolution = 0.5 uv
eeglab_hg = eeglabfilt(EEG,48,52,1);
eeglab_hg = eeglabfilt(eeglab_hg,1,90,0);
% eeglab_hg = (downsample(eeglab_hg',25));
for i=1:size(eeglab_hg,1)
eeglab_rs(i,:) = (resample(eeglab_hg(i,:),250,2500)); %downsample
end

%% Time-Freq transform
fs = 250;    % Sampling Rate
fL=5;  %% low cutoff frequency of interest
fH=90;   %% high cutoff frequency of interest
fb=0.5;  %% frequency bin resolution
freqIndex = fL:fb:fH;

TFR=[];
for i=1:size(eeglab_rs,1)

        EEG_data=eeglab_rs(i,:)';
        scale=fs*1.5./freqIndex;%和频率成反比
        COEFS = cwt ( EEG_data ,scale,'cmor1-1.5');
        TFR(:,:,i) = abs(COEFS).^2;
end

%% tensor decomposed
% Select Num

data=reshape(TFR,[size(TFR,1) size(TFR,2)*size(TFR,3)]);
[coeff, latent]= pca(data');
Ratio=[];
for NumComp = 1:20
   Ratio(NumComp) = sum(coeff(1:NumComp))/sum(coeff)*100; 
end

figure;plot(Ratio,'ok','linewidth',2);grid on
xlabel('Number of component #','fontsize',14);
ylabel('Explain variance /%','fontsize',14);

NumberOfComp = inputdlg('Number of Component','Input',1,{'10'});
NComp = str2num(NumberOfComp{1});


[TFR_approx_ks,Uinit,output] = cp_als(tensor(TFR),NComp,'tol',1.0e-4,'maxiters',100, 'init','random');
% ncp(X,R,'method','hals');
freq_Comp=TFR_approx_ks.U{1};
Temp_Comp=TFR_approx_ks.U{2};
Spatial_Comp=TFR_approx_ks.U{3};

% Calculate index

Temp_Comp_rs=[];
for compID = 1:NComp
    Temp_Comp(:,compID) = (abs(hilbert(Temp_Comp(:,compID)')))';
    Temp_Comp_rs(:,compID) = resample(Temp_Comp(:,compID)',100,250)';
    Temp_Comp_rs(:,compID) = smooth(Temp_Comp_rs(:,compID),40); %% smooth as before
end

nsurrogate = 1000;
[Index]= my_Get_Tensor_Temporal_index(Temp_Comp,env,nsurrogate);

%% Display results
figure
barh(Index(:,1),'r');axis ij; ylim([0.5 R+0.5]);xlabel('Mean Index','FontSize',14,'FontWeight','bold');title('maximum activation','FontSize',14,'FontWeight','bold');
ylabel('Component #','FontSize',14,'FontWeight','bold'); 
set(gca,'FontSize',14,'FontWeight','bold');

SignificantComp = inputdlg('Significant Component','Input',1,{'[]'});
Sig_Comp = str2num(SignificantComp{1});

for  Sig_Comp
figure
subplot(1,2,1);plot(freqIndex,freq_Comp(:,Sig_Comp));xlabel('Frequency/Hz');
subplot(1,2,2);barh(1:size(EEG,1),Spatial_Comp(:,Sig_Comp),'r');axis ij;ylim([0 size(EEG,1)]);xlabel('Mean Index');title('spatial activation');

end






























function [Index] = Get_Tensor_Temporal_index(Y,x,lag)

if nargin<3
    lag = 5;
end

if size(x,2)>size(x,1)
    x = x';
end
if size(Y,2)>size(Y,1)
    Y = Y';
end

chN = size(Y,2);
Index = zeros(chN,201);
if length(x)>=length(Y) % realign the data
    x(length(Y)+1:end) = [];
else
    Y(length(x)+1:end,:)  =[];
end

h = waitbar(0,'Get activation index...');
x = x((lag*100+1):(end-lag*100));
delay_period = -lag*100:1:lag*100; % -2000ms to +2000ms of delay
for delay = 1:length(delay_period)
    Index(:,length(delay_period)-delay+1) = corr(Y((lag*200+2-delay*1):(end+1-delay*1),:),x);
    waitbar(delay/length(delay_period),h);
end
Index = abs(Index);
delete(h);

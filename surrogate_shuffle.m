
function surrogate_x=surrogate_shuffle(x)

% 
% Surrogate data must be generated from an original time series 
% and must be consisten with H0 (Null Hypothesis) and otherwise by typical of the data
% Current surrogate generation algorithms are only capable of testing
% linear hypothesis

% Shuffle method:
% 
% Test: independent and identically distributed noise;

% Surrogate algorithm: Shullf data to produce surrogates;

% Preserve PDF, destroy temporal correlation

% function y=surrogat_shuffle(x);
%
% The time series x is shuffled randomly, result in a surrogate time series y; 
% x is uncorrelated to y.
%
%
% 1/5/2005, Xiaoli Li

y=randn(size(x));
[y,i]=sort(y);
surrogate_x=x(i);

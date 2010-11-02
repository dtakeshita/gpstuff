function p = prior_normal(varargin)
%PRIOR_NORMAL  Normal prior structure     
%       
%  Description
%    P = PRIOR_NORMAL('PARAM1', VALUE1, 'PARAM2', VALUE2, ...) 
%    creates Normal prior structure in which the named
%    parameters have the specified values. Any unspecified
%    parameters are set to default values.
%    
%    P = PRIOR_NORMAL(P, 'PARAM1', VALUE1, 'PARAM2', VALUE2, ...)
%    modify a prior structure with the named parameters altered
%    with the specified values.
%
%    Parameters for Normal prior [default]
%      mu       - location [0]
%      s2       - scale squared (variance) [1]
%      mu_prior - prior for mu [prior_fixed]
%      s2_prior - prior for s2 [prior_fixed]
%
%  See also
%    PRIOR_*

% Copyright (c) 2000-2001,2010 Aki Vehtari
% Copyright (c) 2010 Jaakko Riihim�ki

% This software is distributed under the GNU General Public
% License (version 2 or later); please refer to the file
% License.txt, included with the software, for details.

  if nargin < 1
    do='init';
  elseif ischar(varargin{1})
    switch varargin{1}
      case 'init'
        do='init';varargin(1)=[];
      case 'set'
        do='set';varargin(1)=[];
      otherwise
        do='init';
    end
  elseif isstruct(varargin{1})
    do='set';
  else
    error('Unknown first argument');
  end

  switch do 
    case 'init'
      % Initialize the prior structure
      p.type = 'Normal';
      
      % set functions
      p.fh.pak = @prior_normal_pak;
      p.fh.unpak = @prior_normal_unpak;
      p.fh.e = @prior_normal_e;
      p.fh.g = @prior_normal_g;
      p.fh.recappend = @prior_normal_recappend;
      
      % set parameters
      p.mu = 0;
      p.s2 = 1;
      
      % set parameter priors
      p.p.mu = [];
      p.p.s2 = [];
      
      if numel(varargin) > 0 & mod(numel(varargin),2) ~=0
        error('Wrong number of arguments')
      end
      % Loop through all the parameter values that are changed
      for i=1:2:numel(varargin)-1
        switch varargin{i}
          case 'mu'
            p.mu = varargin{i+1};
          case 's2'
            p.s2 = varargin{i+1};
          case 'mu_prior'
            p.p.mu = varargin{i+1};
          case 's2_prior'
            p.p.s2 = varargin{i+1};                    
          otherwise
            error('Wrong parameter name!')
        end
      end

    case 'set'
      % Set the parameter values of the prior
      if numel(varargin)~=1 & mod(numel(varargin),2) ~=1
        error('Wrong number of arguments')
      end
      p = varargin{1};
      % Loop through all the parameter values that are changed
      for i=2:2:numel(varargin)-1
        switch varargin{i}
          case 'mu'
            p.mu = varargin{i+1};
          case 's2'
            p.s2 = varargin{i+1};
          otherwise
            error('Wrong parameter name!')
        end
      end
  end

  
  function w = prior_normal_pak(p)
    
    w = [];
    if ~isempty(p.p.mu)
      w = p.mu;
    end
    if ~isempty(p.p.s2)
      w = [w log(p.s2)];
    end
  end
  
  function [p, w] = prior_normal_unpak(p, w)

    if ~isempty(p.p.mu)
      i1=1;
      p.mu = w(i1);
      w = w(i1+1:end);
    end
    if ~isempty(p.p.s2)
      i1=1;
      p.s2 = exp(w(i1));
      w = w(i1+1:end);
    end
  end
  
  function e = prior_normal_e(x, p)
    
    e = 0.5*sum(log(2*pi) + log(p.s2)+ 1./p.s2 .* sum((x-p.mu).^2,1));
    
    if ~isempty(p.p.mu)
      e = e + feval(p.p.mu.fh.e, p.mu, p.p.mu);
    end
    if ~isempty(p.p.s2)
      e = e + feval(p.p.s2.fh.e, p.s2, p.p.s2)  - log(p.s2);
    end
  end
  
  function g = prior_normal_g(x, p)
    
    g = (1./p.s2).*(x-p.mu);
    
    if ~isempty(p.p.mu)
      gmu = sum(-(1./p.s2).*(x-p.mu)) + feval(p.p.mu.fh.g, p.mu, p.p.mu);
      g = [g gmu];
    end
    if ~isempty(p.p.s2)
      gs2 = (sum( 0.5*(1./p.s2-1./p.s2.^2.*(x-p.mu).^2 )) + feval(p.p.s2.fh.g, p.s2, p.p.s2)).*p.s2 - 1;
      g = [g gs2];
    end
  end
  
  function rec = prior_normal_recappend(rec, ri, p)
  % The parameters are not sampled in any case.
    rec = rec;
    if ~isempty(p.p.mu)
      rec.mu(ri) = p.mu;
    end
    if ~isempty(p.p.s2)
      rec.s2(ri) = p.s2;
    end
  end    
end